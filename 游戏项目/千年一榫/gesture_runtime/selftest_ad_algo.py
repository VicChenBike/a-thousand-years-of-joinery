#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AD 批次一专项自测（2026-09-27，spec §4.1.3）：动态手性校正 + 换手门限收紧。

零摄像头纪律（spec §2.1）：全程 mock——`HandTracker` 纯逻辑直测，
不触 UDP/端口/设备（真开镜即判红）。

断言口径（spec §4.1.3 逐条）：
  A. 常量锚：
     A1 `HAND_MATCH_DIST` 0.65→0.50（换手继承被切断；AC 0.65 / 旧值 0.35 留痕）；
     A2 `HAND_SINGLE_FAST_MATCH_DIST` 0.85→0.55（AC 0.85 留痕）；
     A3 **结构护栏**：`HAND_SINGLE_FAST_MATCH_DIST >= HAND_MATCH_DIST`——否则单人单检出
        形态下快移通道反比常态通道更严（单手比双手更易断链=AC §4.3-1 已根治的缺陷回潮）；
     A4 投票四参在位（WINDOW=5 / MIN_FRAMES=3 / MIN_SCORE=0.70 / MAX_AGE=5）。
  B. 动态手性校正（**红态=AC 的 `return changed` 永久焊死**）：
     B1 入画误判纠正：首帧 low-score mp 误判为 Left（几何亦 Left）→ Track=L0；
        随后连续 3 帧高置信 Right（0.9≥0.70）→ 手性校正为 Right，
        **id 不变、new_ids 零新增、tracks 表恒 1 条**（严禁重置 ID / 销毁过滤器）。
     B2 校正后 hand_index / label 同步翻转到真实手性（组包槽位随之一致）。
     B3 反向护栏（非假绿）：单帧高分反向**不足 3 帧连续** → 不得校正；
        低分（0.30 < 0.70）连发亦不得校正。
     B4 超窗锁定：`age > HANDEDNESS_VOTE_MAX_AGE` 后面对连续高置信反向噪声
        **保持锁定**（AC 零抖动收益保留——只把「永久焊死」收窄为「初期可纠」）。
     B5 连续段语义：反向票之间夹一帧同向/低分 → 连续段中断，不校正
        （「连续 3 帧」而非「5 帧内累计 3 帧」）。
     B6 held 帧不污染判据：丢帧 hold 期间 age 照常递增（防锁定保护被无限期推迟），
        但无 mp 观测入窗——回帧后「连续 3 帧」仍需新的连续观测。
  C. 换手门限收紧（0.50）行为锚：
     C1 单 track×单检出、帧间位移 0.70（> 0.55 快移阈）→ **断链**（旧 0.85 通道下会
        被配对继承：右手继承刚放下的左手残留 Track 的根因）；
     C2 反向护栏：帧间位移 0.40（< 0.50 常态阈）→ 恒同一 id、零 ghost（常态快移零回归）。

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import sys
import unittest
from pathlib import Path

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import hand_tracking_server as hts  # noqa: E402


# ----------------------------------------------------------------------
# 夹具（零真开镜：HandTracker 纯逻辑直测，无 server/无设备/无端口）
# ----------------------------------------------------------------------

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


class TrackHandednessTestBase(unittest.TestCase):
    T0 = 5000.0

    def _single(self, tracker, t, cx=0.50, cy=0.40, label_mp="Left", score=0.9,
                label_geo="Left", sign=+1):
        """喂单检出；返回 (items, changed/new_ids, dead)。"""
        return tracker.update(
            [det(cx, cy, label_geo, label_mp=label_mp, score=score, sign=sign)],
            t)

    def _labels(self, items):
        return sorted(it["label"] for it in items if not it["held"])


# ======================================================================
# 段 A：常量锚（spec §4.1.3）
# ======================================================================

class AlgoConstantsTest(unittest.TestCase):

    def test_a1_match_dist_tightened(self):
        self.assertAlmostEqual(hts.HAND_MATCH_DIST, 0.50, places=9,
                               msg="AD §4.1.3：HAND_MATCH_DIST 0.65→0.50（换手继承切断；"
                                   "AC 0.65 / 旧值 0.35 留痕）")

    def test_a2_single_fast_match_dist_tightened(self):
        self.assertAlmostEqual(
            getattr(hts, "HAND_SINGLE_FAST_MATCH_DIST", -1.0), 0.55, places=9,
            msg="AD §4.1.3：HAND_SINGLE_FAST_MATCH_DIST 0.85→0.55（AC 0.85 留痕）")

    def test_a3_single_fast_not_stricter_than_base(self):
        """结构护栏：快移通道**不得比常态通道更严**（否则单手比双手更易断链）。"""
        fast = float(getattr(hts, "HAND_SINGLE_FAST_MATCH_DIST", -1.0))
        base = float(hts.HAND_MATCH_DIST)
        print("EVID|ad1_match_dists|base=%.2f fast=%.2f" % (base, fast))
        self.assertGreaterEqual(
            fast, base,
            f"HAND_SINGLE_FAST_MATCH_DIST({fast}) 必须 ≥ HAND_MATCH_DIST({base})——"
            f"否则单人单检出形态下快移通道反比常态通道更严，单手快移断链（held 幽灵 + "
            f"换 id → GDScript 整侧清态）=AC §4.3-1 已根治的缺陷回潮")

    def test_a4_vote_params_in_place(self):
        self.assertEqual(getattr(hts, "HANDEDNESS_VOTE_WINDOW", -1), 5,
                         "AD §4.1.3：入画初期滑窗长度=5 帧")
        self.assertEqual(getattr(hts, "HANDEDNESS_VOTE_MIN_FRAMES", -1), 3,
                         "AD §4.1.3：连续相反手性帧数下限=3")
        self.assertAlmostEqual(getattr(hts, "HANDEDNESS_VOTE_MIN_SCORE", -1.0), 0.70,
                               places=9, msg="AD §4.1.3：计入票数的 mp_score 下限=0.70")
        self.assertEqual(getattr(hts, "HANDEDNESS_VOTE_MAX_AGE", -1), 5,
                         "AD §4.1.3：仅 age ≤5（入画初期）允许校正，之后锁定")


# ======================================================================
# 段 B：动态手性校正（spec §4.1.3）
# ======================================================================

class DynamicHandednessTest(TrackHandednessTestBase):
    """入画初期多帧滑窗投票动态校正 track 手性（严禁重置 ID / 销毁过滤器）。"""

    def test_b1_early_frames_correct_handedness_without_id_reset(self):
        """B1：首帧误判 Left + 随后连续 3 帧高置信 Right → 校正为 Right，id 不变。"""
        tracker = hts.HandTracker()
        # 帧 1：边缘入画误判——mp 低分（0.30，几何兜底）判 Left
        items, new_ids, _ = self._single(
            tracker, self.T0, label_mp="Left", score=0.30, label_geo="Left", sign=+1)
        self.assertEqual(len(new_ids), 1, "前置：首帧注册一次")
        orig_id = items[0]["id"]
        self.assertEqual(items[0]["label"], "Left", "前置：首帧手性=Left（误判）")
        self.assertEqual(orig_id, "L0", f"前置：id 前缀随初始侧（实测 {orig_id}）")
        # 帧 2~4：MediaPipe 稳定高置信 Right（0.90 ≥ 0.70）→ 连续 3 帧触发校正
        changed_last = None
        for i in range(1, 4):
            items, changed, _ = self._single(
                tracker, self.T0 + 0.033 * i, cx=0.50 + 0.005 * i,
                label_mp="Right", score=0.90, label_geo="Left", sign=+1)
            changed_last = changed
        self.assertEqual(changed_last, [],
                         "AD §4.1.3：校正**严禁换 id**——不得出现在 new_ids "
                         "（GDScript 据 id 变化 teardown 整侧累计态）："
                         f"{changed_last}")
        self.assertEqual(items[0]["id"], orig_id,
                         f"AD §4.1.3：校正后 id 必须不变（实测 {items[0]['id']}）")
        self.assertEqual(items[0]["label"], "Right",
                         f"AD §4.1.3：入画初期 3 帧高置信反向 → 手性须校正为 Right"
                         f"（实测 {items[0]['label']}；AC 永久焊死=红）")
        self.assertEqual(len(tracker.tracks()), 1,
                         f"AD §4.1.3：校正只改标签，track 表恒 1 条（不得拆/建）："
                         f"{list(tracker.tracks())}")

    def test_b2_hand_index_follows_corrected_side(self):
        """B2：校正后 hand_index/label 同步翻转到真实手性（组包槽位一致）。"""
        tracker = hts.HandTracker()
        self._single(tracker, self.T0, label_mp="Left", score=0.30, sign=+1)
        for i in range(1, 4):
            items, _, _ = self._single(
                tracker, self.T0 + 0.033 * i, cx=0.50 + 0.005 * i,
                label_mp="Right", score=0.90, sign=+1)
        self.assertEqual(items[0]["label"], "Right", "前置：已校正为 Right")
        self.assertEqual(items[0]["hand_index"], 1,
                         "AD §4.1.3：校正后 hand_index 必须随侧别变（Right→1）")
        trk = tracker.tracks()[[k for k in tracker.tracks()][0]]
        self.assertEqual(trk["label"], "Right", "track['label'] 同步")
        self.assertEqual(trk["side"], "R", "track['side'] 同步")

    def test_b3_single_frame_or_low_score_no_correction(self):
        """B3 反向护栏：单帧高分反向 / 连续低分反向均**不得**校正（非假绿）。"""
        # B3a：仅 1 帧高分反向（不足 3 帧连续）
        tracker = hts.HandTracker()
        self._single(tracker, self.T0, label_mp="Left", score=0.9, sign=+1)
        items, changed, _ = self._single(
            tracker, self.T0 + 0.033, cx=0.505, label_mp="Right", score=0.95, sign=+1)
        self.assertEqual(changed, [], "单帧反向零换 id")
        self.assertEqual(items[0]["label"], "Left",
                         "AD §4.1.3：单帧高分反向（1<3 连续）不得校正——"
                         "AC 抗单帧抖动收益保留")
        # B3b：连续 4 帧**低分**反向（0.30 < 0.70 阈）
        tracker2 = hts.HandTracker()
        self._single(tracker2, self.T0, label_mp="Left", score=0.9, sign=+1)
        for i in range(1, 5):
            items2, changed2, _ = self._single(
                tracker2, self.T0 + 0.033 * i, cx=0.50 + 0.005 * i,
                label_mp="Right", score=0.30, sign=+1)
        self.assertEqual(changed2, [], "低分反向零换 id")
        self.assertEqual(items2[0]["label"], "Left",
                         "AD §4.1.3：连续低分反向（0.30<0.70）不得校正——"
                         "低置信噪声视同无证据")

    def test_b4_locked_after_vote_window(self):
        """B4：`age > 5` 后面对连续高置信反向噪声**保持锁定**（AC 零抖动收益保留）。"""
        tracker = hts.HandTracker()
        # 前 6 帧稳定 Left（高置信，同向）→ age 越过 5，手性进入锁定保护
        #（注册帧 age=0，其后每在场帧 +1 → 第 6 帧末 age=5；再喂 1 帧到 age=6 以严格过阈）
        for i in range(7):
            items, _, _ = self._single(
                tracker, self.T0 + 0.033 * i, cx=0.50 + 0.005 * i,
                label_mp="Left", score=0.90, sign=+1)
        self.assertEqual(items[0]["label"], "Left", "前置：7 帧稳定 Left")
        self.assertGreater(int(tracker.tracks()["L0"]["age"]), 5,
                           f"前置：age 须 > {hts.HANDEDNESS_VOTE_MAX_AGE}"
                           f"（实测 {tracker.tracks()['L0']['age']}）")
        # 之后连续 5 帧高分反向 → 锁定期内不得校正
        for i in range(7, 12):
            items, changed, _ = self._single(
                tracker, self.T0 + 0.033 * i, cx=0.50 + 0.005 * i,
                label_mp="Right", score=0.95, sign=+1)
            self.assertEqual(changed, [], f"锁定期第 {i} 帧零换 id")
        self.assertEqual(items[0]["label"], "Left",
                         "AD §4.1.3：age > 5 后手性锁定保护——单帧/多帧侧立姿态噪声"
                         "不再翻转手性（AC「单手强连续锁定」零抖动收益保留）")

    def test_b5_run_must_be_consecutive(self):
        """B5：反向票之间夹一帧同向 → 连续段中断，不得校正（「连续 3 帧」语义）。"""
        tracker = hts.HandTracker()
        self._single(tracker, self.T0, label_mp="Left", score=0.9, sign=+1)
        seq = [("Right", 0.9), ("Left", 0.9), ("Right", 0.9), ("Right", 0.9)]
        for i, (lab, sc) in enumerate(seq, start=1):
            items, changed, _ = self._single(
                tracker, self.T0 + 0.033 * i, cx=0.50 + 0.005 * i,
                label_mp=lab, score=sc, sign=+1)
            self.assertEqual(changed, [], f"第 {i} 帧零换 id")
        self.assertEqual(items[0]["label"], "Left",
                         "AD §4.1.3：反向票序列 [R, L, R, R] 的尾部连续段仅 2 帧"
                         "（<3）→ 不得校正（判据是**连续**而非窗内累计）")

    def test_b6_held_frames_do_not_pollute_run(self):
        """B6：held（丢帧）帧不追加 mp 观测，但 age 照常递增。"""
        tracker = hts.HandTracker()
        self._single(tracker, self.T0, label_mp="Left", score=0.9, sign=+1)
        # 连续 2 帧高分反向（尚不足 3）
        for i in (1, 2):
            tracker.update([det(0.50 + 0.005 * i, 0.40, "Left",
                                label_mp="Right", score=0.9, sign=+1)],
                           self.T0 + 0.033 * i)
        age_before = int(tracker.tracks()["L0"]["age"])
        # 帧 4：丢帧（held 窗内零检出）→ age 递增、观测零追加
        items, _, dead = tracker.update([], self.T0 + 0.099)
        self.assertEqual(dead, [], "hold 窗内不判死")
        held = [it for it in items if it["held"]]
        self.assertEqual(len(held), 1, "前置：残影按 hold 语义保留（1 条 held）")
        age_after = int(tracker.tracks()["L0"]["age"])
        self.assertEqual(age_after, age_before + 1,
                         f"AD §4.1.3：held 帧 age 亦须递增（防反复短丢帧无限推迟锁定）："
                         f"{age_before} → {age_after}")
        self.assertEqual(len(tracker.tracks()["L0"]["mp_labels"]), 3,
                         "AD §4.1.3：held 帧不得追加 mp 观测（窗口仅含真分类帧）")
        # 回帧 1 帧高分反向 → 连续段=3（2 帧旧 + 本帧）→ 校正触发（证 held 未截断已有票）
        items2, changed2, _ = self._single(
            tracker, self.T0 + 0.132, cx=0.53, label_mp="Right", score=0.9, sign=+1)
        self.assertEqual(items2[0]["label"], "Right",
                         "AD §4.1.3：held 帧后回帧补齐第 3 连续票 → 校正照常触发"
                         "（丢帧不销毁已有证据，也不伪造新证据）")

    def test_b7_new_track_starts_with_age_zero(self):
        """B7：新手 track age 初值 0（spec 字面「初始为 0」）且首帧观测即入窗。"""
        tracker = hts.HandTracker()
        self._single(tracker, self.T0, label_mp="Left", score=0.9, sign=+1)
        trk = tracker.tracks()["L0"]
        self.assertEqual(int(trk["age"]), 0,
                         "AD §4.1.3：注册帧 age 初值 = 0（spec「初始为 0」；"
                         "其后每在场帧 +1）")
        self.assertEqual(len(trk["mp_labels"]), 1,
                         "AD §4.1.3：注册帧的 mp 观测即入窗（入画首帧分类亦是投票证据）")
        # 下一帧（配对帧）age 递增为 1，观测入窗为第 2 条
        self._single(tracker, self.T0 + 0.033, cx=0.505, label_mp="Left", score=0.9,
                     sign=+1)
        trk2 = tracker.tracks()["L0"]
        self.assertEqual(int(trk2["age"]), 1, "AD §4.1.3：配对帧 age 递增（0 → 1）")
        self.assertEqual(len(trk2["mp_labels"]), 2, "配对帧观测入窗（1 → 2）")


# ======================================================================
# 段 C：换手门限收紧行为锚（spec §4.1.3）
# ======================================================================

class HandSwapThresholdTest(TrackHandednessTestBase):

    def test_c1_swap_gap_now_breaks_chain(self):
        """C1：单 track×单检出、帧间位移 0.70 > 快移阈 0.55 → 断链建新手。

        红态对照：AC 0.85 通道下 0.70 被配对继承——即用户实机反馈的「右手伸入时误匹配
        并继承刚放下的左手残留 Track」（手别/累计态全部错位）。
        """
        tracker = hts.HandTracker()
        items, _, _ = self._single(tracker, self.T0, cx=0.20, cy=0.40,
                                   label_mp="Left", score=0.9, sign=+1)
        orig_id = items[0]["id"]
        self.assertEqual(orig_id, "L0", "前置：初始 Left")
        items2, new_ids2, _ = self._single(
            tracker, self.T0 + 0.033, cx=0.90, cy=0.40,
            label_mp="Right", score=0.9, label_geo="Right", sign=-1)
        self.assertTrue(
            len(new_ids2) >= 1,
            f"AD §4.1.3：0.70 位移（>0.55 快移阈）须断链建新手"
            f"（旧 0.85 通道下被配对继承=换手错继承根因）：new_ids={new_ids2}")
        self.assertNotEqual(items2[0]["id"], orig_id,
                            "AD §4.1.3：断链后 id 必须更新（不继承残留 track 的 id）")
        labels = self._labels(items2)
        self.assertIn("Right", labels,
                      f"AD §4.1.3：新手按 mp 主判为 Right（真实手性不再被残留 Left 焊死）："
                      f"{labels}")

    def test_c2_normal_fast_move_still_continuous(self):
        """C2 反向护栏：帧间位移 0.40（< 0.50 常态阈）→ 恒同一 id、零 ghost。"""
        tracker = hts.HandTracker()
        ids = []
        for i in range(8):
            cx = 0.20 + (0.40 if i % 2 else 0.0)
            items, new_ids, _ = self._single(
                tracker, self.T0 + 0.033 * i, cx=cx, cy=0.40,
                label_mp="Left", score=0.9, sign=+1)
            if i > 0:
                self.assertEqual(new_ids, [], f"第 {i} 帧零新增 track（常态快移零回归）")
            ids.append(items[0]["id"])
        self.assertEqual(len(set(ids)), 1, f"AD §4.1.3：0.40 步进单手恒同一 id：{ids}")
        self.assertEqual(len(tracker.tracks()), 1,
                         f"恒 1 条 track（0.50 阈下 0.40 步进零断链）："
                         f"{list(tracker.tracks())}")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
