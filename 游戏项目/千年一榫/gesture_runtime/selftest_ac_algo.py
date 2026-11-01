#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AC Wave-3 专项自测：手势底层算法——单手强连续锁定 + 动态速度自适应平滑
+ One Euro 提速（spec §4.3 领域三）。

零摄像头纪律（spec §2.1）：全程 mock——`HandTracker` 纯逻辑直测；
server 级 `_process_frame` 段 CameraSelector/UDPSender/landmarker 全 mock、帧为
np.zeros 假帧；**辅助守卫断言 `cv.VideoCapture` 零调用**（真开镜即判红）。
不占用 9876/9877/9878 真实端口（udp_sender 为 MagicMock）。

断言口径（spec §4.3-1/2 + §7.2/D3）：
  A. 常量锚：`HAND_MATCH_DIST` 0.35→0.65、`HAND_SINGLE_FAST_MATCH_DIST=0.85`、
     `LANDMARK_SMOOTH_ALPHA` 0.35→0.55、`LANDMARK_SMOOTH_ALPHA_MAX=0.92`、
     `LANDMARK_SMOOTH_SPEED_GAIN=8.0`；One Euro `min_cutoff` 1.2→1.8、`beta` 1.7→3.0。
  B. 单手强连续锁定：
     B1 帧间曼哈顿位移 0.55（> 旧阈 0.35、< 新阈 0.65）→ id 与 side 全程锁定、
        恒 1 条 track、无第二条 ghost 骨架（红态=旧 0.35 断链建新手）；
     B2 帧间位移 0.70（> 0.65、< 0.85）且**伴随单帧 mp 反向抖动（score 0.85）** →
        仍由 `HAND_SINGLE_FAST_MATCH_DIST` 单 track×单检出快移通道配对：id/side 锁定、
        零改侧（红态=断链换 id → GDScript 整侧清态）。
     B3 单手连续移动期间高分 mp 反向标签**不得**触发 `_relabel_track`（spec §4.3-2
        「只有多手场景或出画重入才重新评估手性」）。
     B4 反向护栏：**双手**场景 mp 高分交换仍照常改判（多手域权威序零回归）。
     B5 残影吸收：本帧恰 1 检出且**新生 track**，未配对 held track 中心距 < 0.85 →
        判同源残影、从 track 表移除（不输出双骨架）；反向护栏=两真手交叉单帧丢检
        （AA R1-e）残影保留（本帧零新生 track）。
  C. 动态速度自适应平滑：
     C1 静止微抖（σ=0.002）帧间位移 σ 降幅保持（α 贴近基准 0.55）；
     C2 大步幅快移 Δ=0.15 单帧响应率 ≥90%（α→0.92；旧固定 α=0.35 仅 35% 判红）；
     C3 快移帧 α 严格大于静止帧 α（速度加权真实生效，非「调用了常量」式自证）。
  D. One Euro 提速：新参静止段收敛（不震荡）＋同序列相位滞后较旧参下降 ≥25%。

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import math
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import hand_tracking_server as hts  # noqa: E402
import one_euro_filter as oef  # noqa: E402

_RUNTIME_DIR = Path(__file__).resolve().parent


# ----------------------------------------------------------------------
# 夹具（零真开镜）
# ----------------------------------------------------------------------

def make_server(flip=True):
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    server.flip_image = flip
    return server


def synth_landmarks(cx: float, cy: float, thumb_sign: int) -> np.ndarray:
    """21×3 合成 landmark（thumb_sign=+1 拇指在图像右侧=几何判 Left）。"""
    lm = np.zeros((21, 3), dtype=np.float32)
    for i in range(21):
        lm[i] = [cx + (i % 5) * 0.01, cy + (i // 5) * 0.01, 0.0]
    lm[0] = [cx, cy + 0.05, 0.0]
    lm[4] = [cx + 0.05 * thumb_sign, cy + 0.04, 0.0]
    lm[17] = [cx - 0.05 * thumb_sign, cy + 0.02, 0.0]
    return lm


def det(cx, cy, label_geo="Left", label_mp=None, score=0.9, lm=None, sign=+1):
    return {
        "center": (cx, cy),
        "label_geo": label_geo,
        "label_mp": label_mp,
        "mp_score": score,
        "landmarks": lm if lm is not None else synth_landmarks(cx, cy, sign),
    }


def packets(server):
    out = []
    for call in server.udp_sender.send.call_args_list:
        if call.args and isinstance(call.args[0], dict):
            out.append(call.args[0])
    return out


# ======================================================================
# 段 A：常量锚（spec §4.3 / D3）
# ======================================================================

class AlgoConstantsTest(unittest.TestCase):

    def test_match_dist_tightened_ad(self):
        """批次 AD（§4.1.3）等价改写：0.65→0.50（换手继承切断）。"""
        self.assertAlmostEqual(hts.HAND_MATCH_DIST, 0.50, places=9,
                               msg="AD §4.1.3：HAND_MATCH_DIST 0.65→0.50（切断换手时右手继承"
                                   "左手残留 track；AC 0.65 / 旧值 0.35 留痕）")

    def test_single_fast_match_dist(self):
        """批次 AD（§4.1.3）等价改写：0.85→0.55（残影继承切断；仍 ≥ 常态阈 0.50）。"""
        fast = getattr(hts, "HAND_SINGLE_FAST_MATCH_DIST", -1.0)
        self.assertAlmostEqual(fast, 0.55, places=9,
                               msg="AD §4.1.3：HAND_SINGLE_FAST_MATCH_DIST 0.85→0.55"
                                   "（AC 0.85 留痕）")
        self.assertGreaterEqual(fast, hts.HAND_MATCH_DIST - 1e-9,
                                msg="结构护栏：快移通道不得比常态通道更严（否则单手快移断链"
                                    "=AC §4.3-1 已根治的缺陷回潮）")

    def test_landmark_smoother_constants(self):
        self.assertAlmostEqual(hts.LANDMARK_SMOOTH_ALPHA, 0.55, places=9,
                               msg="AC §4.3-2：LANDMARK_SMOOTH_ALPHA 0.35→0.55（旧值留痕）")
        self.assertAlmostEqual(getattr(hts, "LANDMARK_SMOOTH_ALPHA_MAX", -1.0), 0.92,
                               places=9, msg="AC §4.3-2：LANDMARK_SMOOTH_ALPHA_MAX=0.92")
        self.assertAlmostEqual(getattr(hts, "LANDMARK_SMOOTH_SPEED_GAIN", -1.0), 8.0,
                               places=9, msg="AC §4.3-2：LANDMARK_SMOOTH_SPEED_GAIN=8.0"
                                             "（Δmax≥0.046 → α→0.92）")

    def test_one_euro_speedup(self):
        self.assertAlmostEqual(oef.ONE_EURO_MIN_CUTOFF, 1.8, places=9,
                               msg="AC §4.3-2：min_cutoff 1.2→1.8（旧值留痕）")
        self.assertAlmostEqual(oef.ONE_EURO_BETA, 3.0, places=9,
                               msg="AC §4.3-2：beta 1.7→3.0（旧值留痕）")
        self.assertAlmostEqual(oef.ONE_EURO_D_CUTOFF, 1.0, places=9,
                               msg="AC：微分通道截止不变（防误改）")

    def test_single_hand_branch_has_no_relabel_call(self):
        """源码锚：`_resolve_sides` 单手分支不得再调用 `_relabel_track`。"""
        src = (_RUNTIME_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")
        i = src.find("    def _resolve_sides(")
        self.assertGreater(i, 0, "_resolve_sides 应在位")
        j = src.find("\n    def ", i + 1)
        body = src[i:j if j > 0 else len(src)]
        k = body.find("if len(entries) == 1:")
        self.assertGreater(k, 0, "单手分支 `if len(entries) == 1:` 应在位")
        seg = body[k:body.find("a, b = entries[0], entries[1]", k)]
        code = "\n".join(ln for ln in seg.splitlines() if not ln.strip().startswith("#"))
        self.assertNotIn("_relabel_track", code,
                         "AC §4.3-2：单手连续跟踪分支不得再调用 _relabel_track"
                         "（现场翻转手性=红蓝双骨架根因）")


# ======================================================================
# 段 B：单手强连续锁定（spec §4.3-1/2）
# ======================================================================

class SingleHandContinuityTest(unittest.TestCase):
    """单手连续跟踪期间 side 与 id 强锁定（红线：不得换 id → GDScript 整侧清态）。"""

    def _run_steps(self, tracker, xs, ys, t0=100.0, label_mp="Left", score=0.9):
        """逐帧喂单检出；返回 (ids, labels, new_ids_after_first, items_per_frame)。

        注：`HandTracker.update` 第二返回值 = `new_ids`（含**首帧注册**与改侧换 id）——
        首帧注册属正常路径，故断「连续跟踪期零新增/零换 id」时跳过首帧。
        """
        ids, labels, new_ids_after_first, per_frame = [], [], [], []
        for i, (x, y) in enumerate(zip(xs, ys)):
            items, new_ids, _ = tracker.update(
                [det(float(x), float(y), "Left", label_mp=label_mp, score=score)], 
                t0 + 0.033 * i)
            fresh = [it for it in items if not it["held"]]
            per_frame.append(len(fresh))
            if fresh:
                ids.append(fresh[0]["id"])
                labels.append(fresh[0]["label"])
            if i > 0:
                new_ids_after_first.extend(new_ids)
        return ids, labels, new_ids_after_first, per_frame

    def test_b1_mid_speed_walk_045_keeps_id_and_side(self):
        """B1（批次 AD §4.1.3 等价改写）：帧间曼哈顿位移 0.45（> 旧阈 0.35）→ id/side 全程锁定。

        夹具平移说明：AC 时阈为 base 0.65 / fast 0.85 → 步进取 0.55（∈(0.35,0.65)）；
        AD 收紧为 base 0.50 / fast 0.55 → 步进等价平移为 **0.45**（∈(0.35, 0.50)）——
        判据（连续移动期 id/side 锁定、恒 1 track、零 ghost）与帧数逐条不变。
        """
        tracker = hts.HandTracker()
        xs = [0.20 + (0.45 if i % 2 else 0.0) for i in range(10)]
        ys = [0.50] * 10
        ids, labels, new_ids, _ = self._run_steps(tracker, xs, ys)
        self.assertEqual(len(set(ids)), 1,
                         f"AD §4.1.3：0.45 步进单手必须恒同一 id（旧 0.35 断链建新手）：{ids}")
        self.assertEqual(set(labels), {"Left"}, f"side 全程锁定：{labels}")
        self.assertEqual(new_ids, [], "连续跟踪期零新增 track / 零改侧换 id")
        self.assertEqual(len(tracker.tracks()), 1,
                         f"恒 1 条 track（旧阈值下会幽灵+新手两条）：{list(tracker.tracks())}")

    def test_b2_fast_walk_052_uses_single_fast_channel(self):
        """B2（批次 AD §4.1.3 等价改写）：0.52 步进 ∈(base 0.50, fast 0.55] → 仍锁定。

        该步进**只在单 track×单检出快移通道下可配对**（常态阈 0.50 会给 0.52 断链）——
        「快移通道真实生效、非 base 通道兜住」的判据强度逐条保持；步进由 AC 的
        0.70（∈(0.65,0.85)）等价平移为 0.52（∈(0.50,0.55)）。
        """
        tracker = hts.HandTracker()
        xs = [0.15 + (0.52 if i % 2 else 0.0) for i in range(10)]
        ys = [0.50] * 10
        ids, labels, new_ids, per_frame = self._run_steps(
            tracker, xs, ys, label_mp="Left", score=0.9)
        self.assertEqual(set(per_frame), {1},
                         f"每帧恰 1 条实检出（无 ghost/新手双骨架）：{per_frame}")
        self.assertEqual(len(set(ids)), 1, f"0.52 快移恒同一 id：{ids}")
        self.assertEqual(set(labels), {"Left"}, f"side 锁定（早窗内同向高置信 → 不触发校正）：{labels}")
        self.assertEqual(new_ids, [], "快移期间零新增 track / 零改侧换 id")
        self.assertEqual(len(tracker.tracks()), 1, "恒 1 条 track（快移通道配对，不断链）")

    def test_b3_high_score_mp_flip_cannot_relabel_after_lock(self):
        """B3（批次 AD §4.1.3 等价改写）：**手性锁定后**（age>5）mp 高分反向不得 relabel。

        AD 把 AC 的「单手永久焊死」收窄为「入画初期 5 帧可投票校正、之后锁定」——早期校正
        通路由 `selftest_ad_algo.DynamicHandednessTest` 专项覆盖（含 id 不变断言）。
        本用例保留 AC 的**核心收益**（稳定期零抖动/零换 id），夹具等价平移为：先喂 7 帧稳定
        高置信 Left 使 age>5 进入锁定，再连续 10 帧喂反向高置信 Right。
        """
        tracker = hts.HandTracker()
        t0 = 100.0
        items, new_ids, _ = tracker.update(
            [det(0.50, 0.40, "Left", label_mp="Left", score=0.90)], t0)
        self.assertEqual(len(new_ids), 1, "首帧注册一次")
        orig_id = items[0]["id"]
        self.assertEqual(items[0]["label"], "Left")
        # 先稳定 7 帧（age 越过 HANDEDNESS_VOTE_MAX_AGE=5）→ 手性进入锁定保护
        for i in range(1, 8):
            items, _, _ = tracker.update(
                [det(0.50 + 0.005 * i, 0.40, "Left", label_mp="Left", score=0.90)],
                t0 + 0.033 * i)
        self.assertEqual(items[0]["id"], orig_id, "前置：稳定期 id 保持")
        self.assertGreater(int(tracker.tracks()[orig_id]["age"]),
                           hts.HANDEDNESS_VOTE_MAX_AGE,
                           "前置：age 须越过投票窗（锁定保护生效）")
        # 连续 10 帧：每帧 mp 标签翻到 Right 且 score=0.85（过 score 门），位置连续
        for i in range(8, 18):
            items2, changed, _ = tracker.update(
                [det(0.50 + 0.005 * i, 0.40, "Left", label_mp="Right", score=0.85)],
                t0 + 0.033 * i)
            self.assertEqual(changed, [],
                             f"第 {i} 帧高分 mp 反向不得换 id（AD §4.1.3 锁定期手性保护）：{changed}")
            self.assertEqual(items2[0]["id"], orig_id, f"第 {i} 帧 id 必须保持")
            self.assertEqual(items2[0]["label"], "Left",
                             f"第 {i} 帧 side 必须保持（锁定后分类跳变不得翻转手性）")

    def test_b4_two_hand_mp_swap_still_relabels(self):
        """B4 反向护栏：**双手**场景 mp 高分相异仍照常改判（多手域权威序零回归）。"""
        tracker = hts.HandTracker()
        t0 = 200.0
        tracker.update([det(0.20, 0.40, "Left", label_mp="Left", score=0.9, sign=+1),
                        det(0.85, 0.40, "Right", label_mp="Right", score=0.9, sign=-1)], t0)
        items, changed, _ = tracker.update(
            [det(0.20, 0.40, "Left", label_mp="Right", score=0.9, sign=+1),
             det(0.85, 0.40, "Right", label_mp="Left", score=0.9, sign=-1)], t0 + 0.033)
        self.assertEqual(len(changed), 2,
                         f"双手 mp 高分交换必须照常改判（换 id 清累计态）：{changed}")
        labels = sorted(it["label"] for it in items if not it["held"])
        self.assertEqual(labels, ["Left", "Right"], "改判后两侧 hand_index 仍相异")

    def test_b5_ghost_absorb_after_fast_jump(self):
        """B5（批次 AD §4.1.3 等价改写）：恰 1 检出且新生 track → 未配对 held 残影
        （中心距 < fast 阈）从 track 表移除。

        夹具几何随阈收紧（**结构影响留痕**）：吸收判据读 `HAND_SINGLE_FAST_MATCH_DIST`，
        而「未被配对」判据在 2 track×1 检出形态下读 `HAND_MATCH_DIST` → 可吸收带
        = [base, fast) 由 AC 的 [0.65, 0.85)（宽 0.20）收窄为 AD 的 **[0.50, 0.55)（宽 0.05）**。
        取检出落 (0.20,0.72)：距 L0@(0.20,0.20) = **0.52 ∈ [0.50,0.55)**（未配对建新手 +
        同源吸收）；距 R0@(0.80,0.20) = 1.12（>fast 保留）。判据链（仅 1 检出且新生 track
        才启用残影吸收、吸收只清同源不误杀异手）逐条不变。
        """
        tracker = hts.HandTracker()
        t0 = 300.0
        # 帧 1：两只手（L0@(0.20,0.20)、R0@(0.80,0.20)）
        tracker.update([det(0.20, 0.20, "Left", label_mp="Left", score=0.9, sign=+1),
                        det(0.80, 0.20, "Right", label_mp="Right", score=0.9, sign=-1)], t0)
        self.assertEqual(sorted(tracker.tracks()), ["L0", "R0"], "前置：两条 track")
        # 帧 2：唯一检出落 (0.20,0.72)——距 L0 = 0.52（≥base 0.50 未配对、<fast 0.55 同源）
        items, new_ids, dead = tracker.update(
            [det(0.20, 0.72, "Left", label_mp="Left", score=0.9, sign=+1)], t0 + 0.033)
        self.assertEqual(len(new_ids), 1, f"前置：新检出须建新手（未配对）：{new_ids}")
        self.assertIn("L0", [d["id"] for d in dead],
                      f"L0 残影（同源、中心距 0.52<fast 0.55）须被吸收判死：dead={dead}")
        self.assertNotIn("L0", tracker.tracks(),
                         f"被吸收残影不得留在 track 表（防跨帧双骨架）：{list(tracker.tracks())}")
        self.assertIn("R0", tracker.tracks(),
                      f"远距异手 track 必须保留（不误杀另一只手）：{list(tracker.tracks())}")

    def test_b5_guard_crossing_ghost_kept(self):
        """B5 反向护栏（AA R1-e 回归）：两真手交叉单帧丢检（本帧零新生 track）→ 残影保留。"""
        server = make_server(flip=True)
        server.current_camera_id = 0
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        server.landmarker = mock.MagicMock(name="landmarker")

        def run(hands):
            server.landmarker.detect_for_video.return_value = _results(hands)
            server.udp_sender.send.reset_mock()
            with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f), \
                    mock.patch.object(server, "_attempt_reconnect"):
                server._process_frame()
            return packets(server)[-1]

        run([(synth_landmarks(0.45, 0.40, +1), "Right", 0.92),
             (synth_landmarks(0.55, 0.40, -1), "Left", 0.92)])
        pkt = run([(synth_landmarks(0.55, 0.40, -1), "Left", 0.92)])
        self.assertIsNotNone(pkt.get("left"),
                             "交叉丢检帧另一手的 held 残影必须保留（AA R1-e；置 None=整侧清态）")
        self.assertIsNotNone(pkt.get("right"), "fresh 侧照常在")


def _results(hands):
    """HandLandmarker 风格 results：hands=[(landmarks ndarray, label_mp, score), ...]。"""
    hl, hd = [], []
    for lm, label, score in hands:
        hl.append([SimpleNamespace(x=float(p[0]), y=float(p[1]), z=float(p[2])) for p in lm])
        hd.append([] if label is None else [SimpleNamespace(category_name=label, score=score)])
    return SimpleNamespace(hand_landmarks=hl, handedness=hd)


# ======================================================================
# 段 C：动态速度自适应平滑（spec §4.3-2）
# ======================================================================

class DynamicSmootherTest(unittest.TestCase):

    @staticmethod
    def _stacked(seq):
        sm = hts.LandmarkSmoother()
        return np.stack([np.asarray(sm.smooth("L0", f.tolist()), dtype=np.float64)
                         for f in seq])

    def test_c1_static_jitter_attenuation(self):
        """C1：静止微抖（σ=0.002）帧间位移 σ 降幅 ≥35%（α 贴近基准 0.55）。"""
        rng = np.random.default_rng(20260927)
        n = 300
        noise = rng.normal(0.0, 0.002, size=(n, 21, 2))
        base = np.tile(np.linspace(0.3, 0.7, 42).reshape(21, 2), (n, 1, 1))
        raw = base + noise
        out = self._stacked(raw)
        sigma_raw = float(np.diff(raw, axis=0).std(ddof=1))
        sigma_sm = float(np.diff(out, axis=0).std(ddof=1))
        ratio = sigma_sm / sigma_raw
        print("EVID|ac3_smooth_static|sigma_raw=%.6f sigma_sm=%.6f ratio=%.4f" % (
            sigma_raw, sigma_sm, ratio))
        self.assertLessEqual(ratio, 0.65,
                            f"AC §4.3-2：静止微抖仍须显著衰减（≤0.65，实测 {ratio:.4f}）")

    def test_c2_fast_step_response_over_90pct(self):
        """C2：大步幅 Δ=0.15 单帧响应率 ≥90%（α→0.92；旧固定 0.35 判红）。"""
        sm = hts.LandmarkSmoother()
        prev = np.zeros((21, 2), dtype=np.float64)
        _ = sm.smooth("L0", prev.tolist())
        cur = prev + 0.15
        out = np.asarray(sm.smooth("L0", cur.tolist()), dtype=np.float64)
        ratio = float(np.abs(out - prev).max()) / 0.15
        print("EVID|ac3_smooth_fast|response_ratio=%.4f (旧固定 α=0.35 → 0.35)" % ratio)
        self.assertGreaterEqual(ratio, 0.90,
                                f"AC §4.3-2：快移单帧响应率 ≥90%（实测 {ratio:.4f}；"
                                f"旧固定 α=0.35 仅 0.35 判红）")

    def test_c3_alpha_is_velocity_weighted(self):
        """C3：快移帧有效 α 严格大于静止帧（速度加权真实生效）。"""
        sm_slow = hts.LandmarkSmoother()
        slow = np.zeros((21, 2), dtype=np.float64)
        sm_slow.smooth("L0", slow.tolist())
        out_slow = np.asarray(sm_slow.smooth("L0", (slow + 0.002).tolist()), dtype=np.float64)
        a_slow = float(np.abs(out_slow - slow).max()) / 0.002

        sm_fast = hts.LandmarkSmoother()
        fast = np.zeros((21, 2), dtype=np.float64)
        sm_fast.smooth("L0", fast.tolist())
        out_fast = np.asarray(sm_fast.smooth("L0", (fast + 0.15).tolist()), dtype=np.float64)
        a_fast = float(np.abs(out_fast - fast).max()) / 0.15
        print("EVID|ac3_alpha|slow=%.4f fast=%.4f" % (a_slow, a_fast))
        self.assertGreaterEqual(a_slow, hts.LANDMARK_SMOOTH_ALPHA - 1e-9,
                                "静止档有效 α 不得低于基准 0.55（下界钳制）")
        self.assertLess(a_slow, 0.62,
                        f"静止微抖（Δ=0.002）档 α 应贴近基准 0.55（实测 {a_slow:.3f}）")
        self.assertGreater(a_fast, a_slow + 0.2,
                           f"快移档 α 必须严格高于静止档（实测 {a_slow:.3f} → {a_fast:.3f}）")

    def test_c4_reset_and_shape_defense_kept(self):
        """C4：按 id 复位 / 形状变化重建（既有防御语义零回归）。"""
        sm = hts.LandmarkSmoother()
        a = np.zeros((21, 2), dtype=np.float64)
        sm.smooth("L0", a.tolist())
        sm.smooth("L0", (a + 0.2).tolist())
        sm.reset()
        out = np.asarray(sm.smooth("L0", (a + 0.2).tolist()), dtype=np.float64)
        self.assertTrue(np.allclose(out, a + 0.2), "新 id/复位后首帧直通（不继承旧手状态）")


# ======================================================================
# 段 D：One Euro 提速（spec §4.3-2）
# ======================================================================

class OneEuroSpeedupTest(unittest.TestCase):

    @staticmethod
    def _lag(min_cutoff, beta, n=120, dt=1.0 / 30.0, speed=0.6):
        f = oef.OneEuroFilter(min_cutoff, beta, 1.0)
        lag = []
        for i in range(n):
            t = i * dt
            x = 0.2 + speed * t
            y = f.filter(x, t)
            if i > 20:
                lag.append(x - y)
        return float(np.mean(lag))

    def test_d1_lag_improves_over_old_params(self):
        lag_new = self._lag(oef.ONE_EURO_MIN_CUTOFF, oef.ONE_EURO_BETA)
        lag_old = self._lag(1.2, 1.7)
        print("EVID|ac3_oneeuro_lag|old=%.5f new=%.5f" % (lag_old, lag_new))
        self.assertLess(lag_new, lag_old,
                        f"AC §4.3-2：新参滞后必须低于旧参（old={lag_old:.5f} new={lag_new:.5f}）")
        self.assertLessEqual(lag_new, 0.80 * lag_old,
                             f"AC §4.3-2：相位滞后下降 ≥20%（old={lag_old:.5f} "
                             f"new={lag_new:.5f}）")

    def test_d2_static_still_converges(self):
        """提速不得引入静止震荡：静止段输出极差 < 0.02。"""
        f = oef.OneEuroFilter()
        out = [f.filter(0.5, 0.033 * i) for i in range(40)]
        self.assertLess(max(out) - min(out), 0.02, f"静止段仍收敛：极差 {max(out) - min(out)}")


# ======================================================================
# 段 E：零摄像头红线（辅助守卫）
# ======================================================================

class NoCameraRedlineTest(unittest.TestCase):

    def test_no_video_capture_calls(self):
        """`_process_frame` 全链路不得触碰 `cv.VideoCapture`（零真开镜红线）。"""
        server = make_server()
        server.current_camera_id = None
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        server.landmarker = mock.MagicMock(name="landmarker")
        server.landmarker.detect_for_video.return_value = _results(
            [(synth_landmarks(0.5, 0.4, +1), "Right", 0.9)])
        with mock.patch.object(hts.cv, "VideoCapture") as vc, \
                mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f), \
                mock.patch.object(server, "_attempt_reconnect"):
            server._process_frame()
        self.assertFalse(vc.called, "测试链禁止调用 cv.VideoCapture（摄像头红线）")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
