#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AA（W2 域，spec §5）python 侧红测——分指阈值 / 小指泄漏守卫 / 全 landmark 平滑 /
One Euro dt 钳制。

TDD 口径：本件全部断言在 W2 实现落地前**应判红**（红态证据
AI工作记录/批次AA_走查_20260925/w2_red_python.txt），实现后转绿。

判定锚（spec §5.5 红测清单 R2-e/h/g + §5.3 W2-6/8/9）：
  A. 分指阈值——`_compute_finger_states` 支持每指独立 extend 阈（无名指 0.45）：
     合成「无名指中等伸展」链（curl_ratio≈0.635）旧公式 extend≈0.284（<0.55 →
     GDScript 判不了 three）→ 期望 ≥0.55（新公式 (0.635−0.45)/0.30≈0.618）。
  B. 小指泄漏守卫——三指形+小指泄漏 extend≈0.633（∈(0.55,0.70] 泄漏带）：
     旧 `_classify_gesture` 在 Open_Palm（`all(s>0.6)` 含小指）先行命中返回 0=palm；
     期望 palm/Four 要求小指 >0.70、泄漏带回落 Three(7)（与 GDScript PALM_PINKY_TH
     同口径；GDScript 侧语义守卫 red→green 见 tests/test_aa_gesture_stability.gd 段 9）。
  C. 全 landmark 平滑（W2-8）——`LandmarkSmoother` 对下发 21 点做 EMA（α=0.35），
     σ=0.005 合成抖动帧间位移 σ 降幅 ≥50%；结构断言锁死「判定内核
     `engine.process(landmarks_3d` 读原始值、平滑只落 `result["landmarks"]` 下发字段」
     （判定内核零改动断言，spec §5.4-9）。
  D. One Euro dt 钳制（W2-9）——卡顿帧 dt=1.0s → 输出跳变被钳（≤0.40，旧 0.462 判红）；
     极小 dt=1e-6 → 抬到下限仍有响应（≥0.003，旧 ≈1.4e-6 判红）。
  E. 【回修1・P2-2】`tr["last_landmarks"]` 必须赋**原始** landmarks 切片（非平滑输出）
     ——W1-6 ghost 裁决 D1 判据（逐点偏差 <0.02）的源数据，写入平滑值会静默劣化
     「异手近距 → 误判同手」，全量回归不判红。
  F. 【回修3・P3-3】分指阈值**跨语言一致性**——`gesture_map.gd` 数组（extend 输出进入阈）
     与 `gesture_engine.py` dict（curl 基线）**语义不同**，生效切点 =
     py_th + 0.30×gd_th，必须落在 0.585±0.02 且两侧登记值各锁 0.45（联动调参护栏）。

零摄像头纪律：全程合成 landmark/mock，不 import cv2 设备路径、不触真实端口。
判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import re
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
_RUNTIME_DIR = Path(__file__).resolve().parent   # 源码同目录（selftest_* 与被测 .py 同层）
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import gesture_engine as ge  # noqa: E402
import hand_tracking_server as hts  # noqa: E402
import one_euro_filter as oef  # noqa: E402


# ---------------------------------------------------------------------
# 合成 landmark 夹具（features["normalized"] 21×3；坐标与计算口径：
# extend = clamp((curl_ratio − th) / 0.30, 0, 1)，curl_ratio = |MCP−TIP| / 骨骼链长）
# ---------------------------------------------------------------------

def _straight_chain(origin):
    """三段共线伸直链：curl_ratio = 1.0。返回 (mcp, pip, dip, tip)。"""
    o = np.asarray(origin, dtype=np.float64)
    return (o, o + np.array([1.0, 0.0, 0.0]), o + np.array([2.0, 0.0, 0.0]),
            o + np.array([3.0, 0.0, 0.0]))


def _ring_chain(curl_ratio):
    """无名指链：MCP/PIP/DIP 共线，TIP 折返使 |MCP−TIP| = 3×curl_ratio。
    折返点取单位圆（|DIP−TIP| = 1）：|TIP|² = 5 + 4cosφ = (3r)² → cosφ = ((3r)² − 5)/4。"""
    r2 = (3.0 * curl_ratio) ** 2
    cos_phi = (r2 - 5.0) / 4.0
    if abs(cos_phi) > 1.0:
        raise ValueError(f"curl_ratio={curl_ratio} 超出单位圆折返可解域")
    sin_phi = np.sqrt(max(0.0, 1.0 - cos_phi * cos_phi))
    return (np.array([0.0, 0.0, 0.0]), np.array([1.0, 0.0, 0.0]),
            np.array([2.0, 0.0, 0.0]), np.array([2.0 + cos_phi, sin_phi, 0.0]))


def _hand_features(ring_chain, pinky_chain, index_chain=None, middle_chain=None,
                   thumb_straight=True):
    """构造 21×3 normalized 手。未指定指默认伸直链（offset 互不重叠防Peace im_dist等
    几何分支干扰；同指判定只依赖自身四个点，互不干扰）。"""
    nlm = np.zeros((21, 3), dtype=np.float64)
    index_chain = index_chain or _straight_chain([0.1, 0.3, 0.0])
    middle_chain = middle_chain or _straight_chain([0.2, 0.3, 0.0])
    thumb = _straight_chain([0.0, -0.1, 0.0]) if thumb_straight else (
        np.zeros(3), np.zeros(3), np.zeros(3), np.zeros(3))
    for idx, pt in zip((1, 2, 3, 4), thumb):
        nlm[idx] = pt
    for idx, pt in zip((5, 6, 7, 8), index_chain):
        nlm[idx] = pt
    for idx, pt in zip((9, 10, 11, 12), middle_chain):
        nlm[idx] = pt
    for idx, pt in zip((13, 14, 15, 16), ring_chain):
        nlm[idx] = pt
    for idx, pt in zip((17, 18, 19, 20), pinky_chain):
        nlm[idx] = pt
    return {"normalized": nlm}


class TestPerFingerThreshold(unittest.TestCase):
    """A. 分指阈值：中指 0.55 / 无名指 0.48（批次 AD §4.1.4；W2-6 → AC §4.5-1 → AD 三级留痕）。"""

    def test_ring_reachability(self):
        # 无名指 curl_ratio≈0.635（真手「半伸无名指」量级；旧共用 0.55 时 extend≈0.284 不可达）
        # 批次 AD（§4.1.4）：ring 阈 0.48 不变 → extend = (0.635276−0.48)/0.30 ≈ 0.5176
        # （W2-6 的 0.45 时 ≈0.618；旧共用阈 0.55 时 ≈0.284 不可达）——本批无名指侧零变化。
        chain = _ring_chain(0.635276)
        feats = _hand_features(ring_chain=chain,
                               pinky_chain=_straight_chain([0.3, 0.3, 0.0]))
        engine = ge.GestureEngine()
        states = engine._compute_finger_states(None, feats)
        self.assertGreaterEqual(
            states[3], 0.50,
            f"无名指 curl=0.635 的 extend 应 ≥0.50（AD §4.1.4：分指阈 0.48 维持后 ≈0.518；"
            f"旧共用阈 0.55 时 ≈0.284 不可达）实测 {states[3]:.4f}")
        # 同链食指（伸直）不受分指阈值影响 → 仍满值（回归锚）
        self.assertGreaterEqual(states[1], 0.9,
                                f"伸直食指 extend 应 ≥0.9（共用阈 0.55 未动）实测 {states[1]:.4f}")
        self.assertGreaterEqual(states[2], 0.9,
                                f"伸直中指 extend 应 ≥0.9 实测 {states[2]:.4f}")

    def test_finger_extend_threshold_constant(self):
        """批次 AD（§4.1.4）：中指 0.48→0.55（收回安全区间）、无名指 0.48 维持（与 gd 侧同源同值）。"""
        th = getattr(ge, "FINGER_EXTEND_TH", None)
        self.assertIsNotNone(th, "gesture_engine 应暴露分指阈值表 FINGER_EXTEND_TH（W2-6）")
        self.assertAlmostEqual(float(th.get("ring", -1.0)), 0.48, places=6,
                               msg="AD §4.1.4：无名指分指阈值 0.48 维持（AC §4.5-1 值零变化）")
        self.assertAlmostEqual(float(th.get("middle", -1.0)), 0.55, places=6,
                               msg="AD §4.1.4：中指分指阈值 0.48→0.55（收回安全区间，防瞄准期中指"
                                   "连带误判二指；旧 0.48=AC §4.5-1、0.55=W2-6 留痕）")
        self.assertAlmostEqual(float(th.get("index", -1.0)), 0.55, places=6,
                               msg="食指分指阈值维持 0.55")
        self.assertAlmostEqual(float(th.get("pinky", -1.0)), 0.55, places=6,
                               msg="小指分指阈值维持 0.55")
        # 结构护栏：中指阈必须 **≥ 无名指阈**——真手无名指恒不领先中指，反序会让
        # 「竖中指单击」与「三指删除」的判定区间互相矛盾（AD 把中指收回 0.55 的隐含前提）。
        self.assertGreaterEqual(
            float(th.get("middle", 0.0)), float(th.get("ring", 1.0)),
            f"中指分指阈 {th.get('middle')} 必须 ≥ 无名指阈 {th.get('ring')}"
            f"（反序=两指判定区间矛盾，AD §4.1.4 结构前提）")


class TestPinkyLeakGuard(unittest.TestCase):
    """B. 小指泄漏守卫：泄漏带 (0.55,0.70] 不判 palm/Four，回落 Three（W2-6）。"""

    def _leak_states(self):
        feats = _hand_features(
            ring_chain=_straight_chain([0.2, 0.3, 0.0]),
            pinky_chain=_ring_chain(0.74),   # curl 0.74 → extend (0.74−0.55)/0.30 ≈0.633
        )
        engine = ge.GestureEngine()
        return engine, feats, engine._compute_finger_states(None, feats)

    def test_leak_band_value(self):
        _, _, states = self._leak_states()
        self.assertGreater(states[4], 0.55,
                           f"小指泄漏 extend 应 >0.55 实测 {states[4]:.4f}")
        self.assertLessEqual(states[4], 0.70,
                             f"小指泄漏 extend 应 ≤0.70（泄漏带上界=PALM_PINKY_TH）实测 {states[4]:.4f}")

    def test_leaky_three_classifies_as_three(self):
        engine, feats, states = self._leak_states()
        gid, _conf = engine._classify_gesture(None, feats, states)
        self.assertNotIn(gid, (0, 8),
                         f"三指形+小指泄漏不得判 Open_Palm(0)/Four(8)（小指泄漏致 palm "
                         f"守卫）实测 gesture_id={gid}")
        self.assertEqual(gid, 7,
                         f"三指形+小指泄漏应判 Three(7)（泄漏带 ≤0.70 视为三指；旧 Open_Palm "
                         f"先行命中判红）实测 gesture_id={gid}")


class TestLandmarkSmoothing(unittest.TestCase):
    """C. W2-8：全 21 landmark 下发平滑 + 判定内核读原始值（结构断言）。

    批次 AC（§4.3-2）等价改写：平滑由**固定 α=0.35** 升级为**动态速度自适应加权**
    α_eff = clamp(0.55 + 8.0×Δmax, 0.55, 0.92)——噪声帧内的大位移会把 α 推高（这正是
    「消除 3~5 帧滞后」的设计代价），故 σ 降幅判据由「≥50%」等价平移为「≥35%」
    （同一夹具实测 0.5044，见 EVID；静态微抖档的强衰减判据见新增
    `selftest_ac_algo.DynamicSmootherTest`）。
    """

    def test_smooth_reduces_frame_diff_sigma(self):
        self.assertTrue(hasattr(hts, "LandmarkSmoother"),
                        "hand_tracking_server 应提供 LandmarkSmoother（W2-8 全 landmark 平滑）")
        rng = np.random.default_rng(20260925)
        n_frames = 300
        noise = rng.normal(0.0, 0.005, size=(n_frames, 21, 2))
        base = np.tile(np.linspace(0.3, 0.7, 21 * 2).reshape(21, 2), (n_frames, 1, 1))
        raw = base + noise
        sm = hts.LandmarkSmoother()
        smoothed = np.stack([sm.smooth("L0", frame.tolist()) for frame in raw])
        sigma_raw = float(np.diff(raw, axis=0).std(ddof=1))
        sigma_sm = float(np.diff(smoothed, axis=0).std(ddof=1))
        ratio = sigma_sm / sigma_raw
        print("EVID|w2fix_smooth_sigma|raw=%.6f smoothed=%.6f ratio=%.4f" % (
            sigma_raw, sigma_sm, ratio))
        self.assertGreater(sigma_raw, 1e-6, "原始抖动非空（夹具自检）")
        self.assertLessEqual(
            ratio, 0.65,
            f"下发 landmark 帧间位移 σ 降幅应 ≥35%（AC 动态 α∈[0.55,0.92] 后的等价判据；"
            f"W2-8 固定 α=0.35 时降幅 ≥50%）：raw={sigma_raw:.6f} "
            f"smoothed={sigma_sm:.6f}（ratio={ratio:.4f}）")

    def test_smoothing_only_touches_outgoing_field(self):
        src = (_RUNTIME_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")
        i_process = src.find("engine.process(landmarks_3d")
        self.assertGreaterEqual(i_process, 0,
                                "判定内核调用点 engine.process(landmarks_3d 应在位（读原始检测值）")
        apply_lines = [ln for ln in src.splitlines()
                       if 'result["landmarks"]' in ln and "smooth" in ln]
        self.assertTrue(apply_lines,
                        "平滑结果只应赋给下发字段 result[\"landmarks\"]（W2-8 落点）")
        i_apply = src.find(apply_lines[0])
        self.assertGreater(i_apply, i_process,
                           "结构序：engine.process（判定内核，原始值）先于平滑赋值——"
                           "滤波不得进入判定路径（spec §5.4-9 判定内核零改动断言）")
        ge_src = (_RUNTIME_DIR / "gesture_engine.py").read_text(encoding="utf-8")
        self.assertNotIn("LandmarkSmoother", ge_src,
                         "gesture_engine.py 不得引用平滑器（判定内核零改动）")
        self.assertNotIn("LANDMARK_SMOOTH", ge_src,
                         "gesture_engine.py 不得引用平滑常量（判定内核零改动）")


class TestOneEuroDtClamp(unittest.TestCase):
    """D. W2-9：dt 上下限钳制（spec §5.3 W2-9、§15 #8：[1/120, 1/15]）。"""

    def test_dt_constants_present(self):
        dt_min = getattr(oef, "ONE_EURO_DT_MIN", None)
        dt_max = getattr(oef, "ONE_EURO_DT_MAX", None)
        self.assertIsNotNone(dt_min, "one_euro_filter 应暴露 ONE_EURO_DT_MIN（W2-9）")
        self.assertIsNotNone(dt_max, "one_euro_filter 应暴露 ONE_EURO_DT_MAX（W2-9）")
        self.assertAlmostEqual(float(dt_min), 1.0 / 120.0, places=9,
                               msg="ONE_EURO_DT_MIN=1/120（暂定值·待用户复验）")
        self.assertAlmostEqual(float(dt_max), 1.0 / 15.0, places=9,
                               msg="ONE_EURO_DT_MAX=1/15（暂定值·待用户复验）")

    def test_stall_frame_jump_clamped(self):
        f = oef.OneEuroFilter()
        f.filter(0.5, 0.0)
        jump = f.filter(1.0, 1.0) - 0.5   # 卡顿 1.0s：旧 dt 无上限 → alpha→1 → 跳变 0.462
        self.assertLessEqual(
            jump, 0.40,
            f"卡顿帧（dt=1.0s）输出跳变应被钳制 ≤0.40（旧无上限实测 ≈0.462 直通判红）"
            f"实测 {jump:.4f}")

    def test_tiny_dt_still_responds(self):
        f = oef.OneEuroFilter()
        f.filter(0.5, 0.0)
        jump = f.filter(0.6, 1e-6) - 0.5   # 同帧级微步：旧 dt=1e-6 → alpha≈0 → 假死
        self.assertGreaterEqual(
            jump, 0.003,
            f"极小 dt（1e-6）应抬到下限 1/120 保持响应 ≥0.003（旧 alpha≈0 输出假死 ≈1.4e-6 判红）"
            f"实测 {jump:.6f}")


class TestLastLandmarksStaysRaw(unittest.TestCase):
    """回修1（审查 P2-2）：`hand_tracking_server.py` 的 `tr["last_landmarks"]` 赋值必须来自
    **原始** landmarks 切片（不是 `LandmarkSmoother` 输出）。

    为什么锁它：该字段是 W1-6 ghost 裁决 **D1 判据**（`_lm_pair_dev` 逐点最大偏差 <
    `HAND_SAME_HAND_LM_TOL`=0.02）的**源数据**。若有人把**平滑值**写进来，ghost 与 fresh
    的逐点偏差会被平滑抹小 → 异手近距可能误判同手 → 对侧第二只手被当「重复框」丢弃
    （直接放大用户症状「两只手在屏只识别出一只」），而且**全量回归不会判红**（静默劣化）。
    此前本件只有「engine.process 先于平滑赋值 + gesture_engine 不引用平滑器」半边锁，
    `grep -rn "last_landmarks"` 在测试中零命中（审查实锤）。

    断言口径 = **源结构断言（两层）+ 对真实 RHS 的行为求值（第三层）**：
    ①纯行为断言要求把 `HandTrackingServer._process_frame` 整条跑起来（MediaPipe results
      mock + self 半初始化 + 检出/track 组装链），成本与脆性过高 → 按任务书允许**退化为
      源结构断言**；
    ②但纯源文本匹配「重构即碎」，故再加一层**行为求值**：把源里那条**真实赋值语句**抽出来
      在受控命名空间里 exec（`landmarks_3d`=原始、`sm`=真 `LandmarkSmoother`、
      `result["landmarks"]`=平滑值），断言 `tr["last_landmarks"]` **逐点等于原始切片**
      且 **≠ 平滑输出**——RHS 一旦改成平滑输出，本层立即判红（即「故意把平滑值写进
      last_landmarks」的红测）。
    """

    _ASSIGN_RE = re.compile(r'^tr\["last_landmarks"\]\s*=(?!=)')
    _FORBIDDEN = ("smooth", "_lm_smoother", "landmarkssmooth",
                  'result["landmarks"]', "lmsmoother")

    @classmethod
    def _src(cls):
        return (_RUNTIME_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")

    @classmethod
    def _assignments(cls, src):
        """(行号, 语句) 列表——只认非注释的 `tr["last_landmarks"] = ...` 真赋值。"""
        out = []
        for no, ln in enumerate(src.splitlines(), 1):
            s = ln.strip()
            if s.startswith("#"):
                continue
            if cls._ASSIGN_RE.match(s):
                out.append((no, s))
        return out

    @classmethod
    def _smooth_assignments(cls, src):
        """`result["landmarks"] = ...smooth...` 下发平滑赋值行。"""
        out = []
        for no, ln in enumerate(src.splitlines(), 1):
            s = ln.strip()
            if s.startswith("#"):
                continue
            if 'result["landmarks"]' in s and "smooth" in s:
                out.append((no, s))
        return out

    def test_single_raw_assignment(self):
        src = self._src()
        assigns = self._assignments(src)
        self.assertEqual(
            len(assigns), 1,
            f'hand_tracking_server.py 应**恰有一处** `tr["last_landmarks"] = ...` 赋值'
            f'（实测 {len(assigns)} 处：{assigns}）——新增旁路赋值即判红，防止'
            f'平滑值从第二处赋值口溜进来')
        # 结构序：判定内核 engine.process（读原始检测值）先于该赋值（同一次组包循环内）
        i_process = src.find("engine.process(landmarks_3d")
        self.assertGreaterEqual(i_process, 0,
                                "判定内核调用点 engine.process(landmarks_3d 应在位")
        lines = src.splitlines(keepends=True)
        i_assign = sum(len(ln) for ln in lines[:assigns[0][0] - 1])   # 精确到该行行首
        self.assertGreater(i_assign, i_process,
                           "结构序：engine.process（判定内核，原始值）先于 "
                           'tr["last_landmarks"] 赋值（同帧同源，均为原始 landmarks_3d）')

    def test_rhs_is_not_smoothing_output(self):
        src = self._src()
        assigns = self._assignments(src)
        self.assertTrue(assigns, '未找到 `tr["last_landmarks"] = ...` 赋值（护栏失效）')
        _, stmt = assigns[0]
        rhs = stmt.split("=", 1)[1].strip().lower()
        for bad in self._FORBIDDEN:
            self.assertNotIn(
                bad, rhs,
                f'`tr["last_landmarks"]` 的赋值右侧不得引用平滑产物（命中 {bad!r}）：'
                f'{stmt}——W1-6 ghost 裁决源必须是**原始** landmarks 切片，'
                f'写平滑值会让逐点偏差判据（<0.02）静默劣化')
        # 与 `result["landmarks"]` 的平滑赋值必须是**不同语句**，且平滑下发路径仍在位
        smooth = self._smooth_assignments(src)
        self.assertTrue(smooth,
                        '应存在 `result["landmarks"] = ...smooth...` 下发平滑赋值'
                        '（W2-8 落点；缺失则「≠平滑值」的对照失去意义）')
        self.assertNotEqual(
            assigns[0][0], smooth[0][0],
            'tr["last_landmarks"] 与 result["landmarks"] 的平滑赋值不得是同一条语句')

    def test_assignment_behavior_keeps_raw_and_differs_from_smoothed(self):
        """行为层：对源里**真实那条赋值语句**在受控命名空间求值。"""
        src = self._src()
        assigns = self._assignments(src)
        self.assertTrue(assigns, '未找到赋值语句（护栏失效）')
        _, stmt = assigns[0]

        # 造一组「原始 vs 平滑」必然不同的输入：上一帧与本帧差 0.05，α=0.35
        raw3d = np.zeros((21, 3), dtype=np.float64)
        raw3d[:, 0] = np.linspace(0.30, 0.70, 21)
        raw3d[:, 1] = np.linspace(0.40, 0.80, 21)
        prev = (raw3d[:, :2] - 0.05).tolist()
        cur = raw3d[:, :2].tolist()
        sm = hts.LandmarkSmoother()
        sm.smooth("L0", prev)            # 播种平滑状态
        smoothed = sm.smooth("L0", cur)  # α=0.35 部分跟进 → 必然 ≠ cur
        self.assertFalse(
            np.allclose(np.asarray(smoothed, dtype=np.float64), raw3d[:, :2]),
            "夹具自检：平滑输出必须与原始值不同，否则本行为断言空转（假绿）")

        ns = {
            "np": np,
            "landmarks_3d": raw3d,                       # 原始检测值
            "tr": {"id": "L0", "hand_index": 0},
            "result": {"landmarks": smoothed,            # 平滑后的下发字段
                       "fingers": [], "held": False},
            "sm": sm,                                    # W2-8 平滑器实例
            "_lm_smoother": {0: sm, 1: sm},
            "LandmarkSmoother": hts.LandmarkSmoother,
            "self": SimpleNamespace(_lm_smoother={0: sm, 1: sm}),
            "landmarks_2d": None, "engine": None, "fps": 30.0, "t_sec": 0.0,
        }
        # ---- B4（2026-09-25）exec 输入边界留痕——Mimosa 门禁 high「代码注入」处置=保留+注释 ----
        # 输入来源 = 本仓库自身源文件 `hand_tracking_server.py`（与本测试同目录、git 受控）里
        #   由 `_assignments()` 抽出的**单一** `tr["last_landmarks"] = ...` 赋值语句：
        #   正则 `^tr\["last_landmarks"\]\s*=(?!=)` 且跳过 `#` 注释行；`test_single_raw_assignment`
        #   另断言全文件**恰有 1 条**该赋值（多一条即判红），故 stmt 不可能是任意外部串。
        # 非外部输入 = 无 env / argv / 网络 / 用户输入 / 日志等任何外部通道内容进入 stmt；
        #   能改变 stmt 的只有能提交本仓库的人（与能改本测试文件同一权限级别），
        #   本 exec 不引入超出「改代码即可改测试」的额外攻击面。
        # 仅测试用 = globals 传空字典、locals 为本测试逐键构造的受控命名空间 ns；
        #   替换为纯文本比对会丢掉「对真实 RHS 行为求值」这层（平滑值写入 last_landmarks
        #   的红测判据）→ 断言强度下降，故**保留 exec 不替换**。
        try:
            exec(stmt, {}, ns)   # noqa: S102 —— 受控命名空间求值被测源语句（输入边界见上）
        except Exception as exc:  # noqa: BLE001
            self.fail(
                "`tr[\"last_landmarks\"]` 赋值语句无法在受控命名空间求值"
                f"（RHS 依赖了未纳入护栏的符号，请同步更新护栏）：{exc!r}\n语句：{stmt}")
        got = np.asarray(ns["tr"]["last_landmarks"], dtype=np.float64)
        self.assertEqual(got.shape, (21, 2),
                         f'tr["last_landmarks"] 应为 21×2（xy 下发裁剪）实测 {got.shape}')
        self.assertTrue(
            np.allclose(got, raw3d[:, :2]),
            f'tr["last_landmarks"] 必须**逐点等于原始输入切片**，实测首点 '
            f'{got[0].tolist()} vs 原始 {raw3d[0, :2].tolist()}（语句：{stmt}）')
        self.assertFalse(
            np.allclose(got, np.asarray(smoothed, dtype=np.float64)),
            f'tr["last_landmarks"] 与平滑输出 result["landmarks"] 相等 → 赋值了**平滑值**'
            f'（语句：{stmt}）——W1-6 ghost 逐点偏差判据（<0.02）会被平滑抹小，'
            f'异手近距可能误判同手')


class TestCrossLanguageFingerThreshold(unittest.TestCase):
    """回修3（审查 P3-3）：分指阈值**跨语言一致性护栏**。

    两常量**同名不同义**、必须联动调参：
      · `gesture_engine.py FINGER_EXTEND_TH[ring]` 是 **curl 基线**——
        `extend = clamp((curl_ratio − th)/0.30, 0, 1)` 的减数；
      · `scripts/gesture_map.gd FINGER_EXTEND_TH[ring]` 是 **extend 输出值的
        进入阈**（`fv[i] >= FINGER_EXTEND_TH[i]` 才置伸直）。
    生效切点 = py_th + 0.30×gd_th。

    批次 AC（§4.5-1，2026-09-27）等价改写：中指/无名指两侧**同批**下调至 0.48
    （旧中 0.55/环 0.45）→ 生效切点由 0.585 平移为
      中/环 = 0.48 + 0.30×0.48 = **0.624**
      拇/食/小 = 0.55 + 0.30×0.55 = **0.715**（未动）
    批次 AD（§4.1.4，2026-09-27）再改写：中指两侧**同批**收回 0.55（防瞄准期中指连带
    误判二指）、无名指 0.48 不动 → 生效切点再平移为
      中指 = 0.55 + 0.30×0.55 = **0.715**（与拇/食/小 同带）
      无名指 = 0.48 + 0.30×0.48 = **0.624**（未动）
    **注意中指与无名指的切点带已分离**（0.715 vs 0.624）——护栏随之按指分带，且新增
    「中指切点 ≥ 无名指切点」的序护栏（AD 收回中指阈的结构前提：真手无名指不领先中指）。
    本护栏三层判红语义逐条保持：
      层1（分带切点）：抓任一侧单独改动；
      层2（两侧登记值逐一锁 0.55/0.48）：抓「即使切点仍在带内」的单侧偷改；
      层3（序护栏）：抓中指/无名指阈值反序（两指判定区间矛盾）。
    """

    GD_TH_RE = re.compile(r"const\s+FINGER_EXTEND_TH\s*:=\s*\[([^\]]*)\]", re.S)
    RING_IDX = 3          # [thumb, index, middle, ring, pinky]
    MIDDLE_IDX = 2
    CUTOFF_RING = 0.624   # 无名指生效切点（AD 未动；AC 值）
    CUTOFF_MIDDLE = 0.715  # 中指生效切点（AD 由 0.624 平移回 0.715）
    CUTOFF_DEFAULT = 0.715
    PY_TH = {"thumb": 0.55, "index": 0.55, "middle": 0.55, "ring": 0.48, "pinky": 0.55}
    GD_TH = [0.55, 0.55, 0.55, 0.48, 0.55]
    NAMES = ("thumb", "index", "middle", "ring", "pinky")

    @classmethod
    def _gd_values(cls):
        src = (_GESTURE_DIR / "scripts" / "gesture_map.gd").read_text(encoding="utf-8")
        hits = cls.GD_TH_RE.findall(src)
        return [float(x) for x in hits[0].split(",")] if hits else []

    def test_effective_cutoff_in_band(self):
        gd = self._gd_values()
        self.assertEqual(len(gd), 5,
                         f"gesture_map.gd FINGER_EXTEND_TH 应为 5 元素数组，实测 {gd}")
        py_th = dict(ge.FINGER_EXTEND_TH)
        cutoffs = {}
        for i, name in enumerate(self.NAMES):
            py_v = float(py_th.get(name, 0.55))   # python 缺省项=0.55（thumb 走缺省）
            cutoffs[name] = py_v + 0.30 * gd[i]
        print("EVID|ad1_finger_cutoff|middle=%.4f ring=%.4f | others=%s" % (
            cutoffs["middle"], cutoffs["ring"],
            {k: round(v, 4) for k, v in cutoffs.items()
             if k not in ("middle", "ring")}))
        # 中指带（AD：0.715，与拇/食/小 同带）
        self.assertTrue(
            self.CUTOFF_MIDDLE - 0.02 <= cutoffs["middle"] <= self.CUTOFF_MIDDLE + 0.02,
            f"middle 生效切点应落 [{self.CUTOFF_MIDDLE - 0.02:.3f}, {self.CUTOFF_MIDDLE + 0.02:.3f}]"
            f"（{self.CUTOFF_MIDDLE}±0.02，AD §4.1.4 中指两侧同批收回 0.55），实测 "
            f"{cutoffs['middle']:.4f}——两常量语义不同（py=curl 基线 / gd=extend 进入阈），"
            f"**须联动调参**，任何一侧单独改动都会静默平移切点")
        # 序护栏（AD 新增）：中指切点必须 ≥ 无名指切点
        self.assertGreaterEqual(
            cutoffs["middle"], cutoffs["ring"] - 1e-9,
            f"中指切点 {cutoffs['middle']:.4f} 必须 ≥ 无名指切点 {cutoffs['ring']:.4f}"
            f"（AD §4.1.4 结构前提：真手无名指不领先中指，反序会令二指/三指判定区间矛盾）")
        # 无名指带（AD：0.624，AC 值未动）
        self.assertTrue(
            self.CUTOFF_RING - 0.02 <= cutoffs["ring"] <= self.CUTOFF_RING + 0.02,
            f"ring 生效切点应落 [{self.CUTOFF_RING - 0.02:.3f}, {self.CUTOFF_RING + 0.02:.3f}]"
            f"（{self.CUTOFF_RING}±0.02，AD §4.1.4 无名指 0.48 维持），实测 "
            f"{cutoffs['ring']:.4f}——两侧须联动调参")
        for name in ("thumb", "index", "pinky"):
            self.assertTrue(
                self.CUTOFF_DEFAULT - 0.02 <= cutoffs[name] <= self.CUTOFF_DEFAULT + 0.02,
                f"{name} 生效切点应保持 {self.CUTOFF_DEFAULT}±0.02（两侧 0.55 未动），"
                f"实测 {cutoffs[name]:.4f}——同名常量两侧被单独改动")

    def test_registered_values_per_side(self):
        """层2：两侧登记值逐一锁定（gd 侧单改 0.51 时切点仍在带内，
        本层是它的**唯一**判红来源）。"""
        gd = self._gd_values()
        self.assertEqual(len(gd), 5, f"gesture_map.gd 未解析到 5 元素阈值数组：{gd}")
        for i, name in enumerate(self.NAMES):
            self.assertAlmostEqual(
                float(ge.FINGER_EXTEND_TH.get(name, 0.55)), self.PY_TH[name], places=9,
                msg=f"gesture_engine.py {name}（curl 基线）应={self.PY_TH[name]}"
                    f"（AD §4.1.4 登记值；单独改动会使生效切点漂移判红）")
            self.assertAlmostEqual(
                gd[i], self.GD_TH[i], places=9,
                msg=f"gesture_map.gd {name}（extend 进入阈）应={self.GD_TH[i]}"
                    f"（AD §4.1.4 登记值；两侧须联动调参）")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
