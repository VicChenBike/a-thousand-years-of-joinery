#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Y1 补派 selftest（Y-A5 空间先验：侧立盲区 roll 稳定化/外推）。

零摄像头纪律：纯 GestureEngine 逻辑直测（合成 21 点手）；server 集成段
CameraSelector/UDPSender/landmarker 全 mock、帧为 np.zeros 假帧。

背景：roll=atan2(palm_vec.y, palm_vec.x)（palm_vec=lm9−lm0）。侧立/朝向镜头
位姿下 palm_vec 的 XY 投影模长≈0，atan2(≈0,≈0) 输出由噪声决定——roll 随机
跳变（spec §1 域二根因）。Y-A5 要求盲区期间按空间位置+运动方向外推，使翻转
全程 roll 轨迹连续可判（GDScript FlipDetector 1.0s 窗 |Δroll|>90° 依赖连续轨迹）。

断言口径（补派要求 + spec §2 Y-A5）：
  ① 盲区门限/外推参数常量集中（BLIND_ZONE_*）；
  ② 合成侧立穿越序列（roll ~270° 竖掌 → 模长塌缩盲区 → 背面 ~90°）：
     输出 roll 无 ±180° 级跳变（相邻帧 wrap-aware 差有界）；
  ③ 盲区段外推沿运动方向延续（符号与盲区前角速度一致）、每帧变化受限幅约束；
  ④ 全程按运动方向累计翻转进度（unwrap 净位移绝对值 ≥180°，足以触发判定）；
  ⑤ 盲区帧=正常检出帧：is_detected=True，server 包中 held=False——盲区数值
     稳定化与丢帧 hold-last（Y-A4）语义不冲突；
  ⑥ 不新增协议键：手 dict 键集仍=既有键 ∪ {id, held}（§3.1 契约）；
  ⑦ 冷启动即盲区：无锚点透传不炸；reset() 清盲区状态。
判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import math
import sys
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import gesture_engine as ge  # noqa: E402
from gesture_engine import GestureEngine  # noqa: E402
import hand_tracking_server as hts  # noqa: E402


# ======================================================================
# 合成数据
# ======================================================================

def make_side_hand(angle_deg: float, palm_len: float):
    """合成 21 点手：palm_vec=lm9−lm0 方向=angle_deg（度，atan2 口径）、XY 模长=palm_len。

    其余关键点沿 palm 反方向排开成指状；angle=270°（指向上方）时 thumb/pinky 的
    x 关系满足镜像口径 Right（thumb.x < pinky.x）。
    """
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = 0.5, 0.5

    def pt(along, side):
        # along：沿 palm 方向偏移；side：垂直 palm 方向偏移
        return (cx + along * ca - side * sa,
                cy + along * sa + side * ca, 0.0)

    raw = []
    for i in range(21):
        if i == 0:      # 腕：palm 负方向端
            raw.append(pt(-palm_len / 2.0, 0.0))
        elif i == 9:    # 中指根：palm 正方向端（palm_vec=lm9−lm0 指向 angle）
            raw.append(pt(palm_len / 2.0, 0.0))
        else:
            t = (i % 4) / 4.0
            lateral = ((i // 4) - 2) * 0.02
            raw.append(pt(-palm_len / 2.0 - 0.02 - 0.15 * t, lateral))

    class _P:
        pass

    out = []
    for x, y, z in raw:
        p = _P()
        p.x, p.y, p.z = float(x), float(y), float(z)
        out.append(p)
    return out


def as_lm(hand):
    """合成手（属性点列）→ process 同款 (21,3) np.ndarray。"""
    return np.array([[p.x, p.y, p.z] for p in hand], dtype=np.float32)


def wrap180(diff: float) -> float:
    """角度差归一到 [-180, 180)。"""
    return ((diff + 180.0) % 360.0) - 180.0


# 穿越序列（30fps，dt=0.033s）：
#   有效 5 帧：roll 方向 300→279→258→237→216（−21°/帧，模长 0.2=竖掌清晰）
#   盲区 4 帧：palm_len=0.015（XY 模长塌缩进盲区），方向给乱序噪声
#   恢复 4 帧：方向 132→111→90→69（延续 −21°/帧 节奏，衔接外推预期值 ≈154→132）
VALID_ANGLES = [300.0, 279.0, 258.0, 237.0, 216.0]
BLIND_ANGLES = [10.0, 200.0, 80.0, 170.0]
RECOVER_ANGLES = [132.0, 111.0, 90.0, 69.0]
DT = 0.033
PALM_LEN_VALID = 0.2
PALM_LEN_BLIND = 0.015


def make_engine_with_clock():
    """engine + 可控时钟（实例属性遮蔽 _get_timestamp，帧间 dt=DT）。"""
    engine = GestureEngine()
    clock = {"t": 1000.0}
    engine._get_timestamp = lambda: clock["t"]

    def tick():
        clock["t"] += DT

    return engine, tick


# ======================================================================
# 常量与状态
# ======================================================================

class TestBlindZoneConstants(unittest.TestCase):

    def test_constants_exist_and_bounded(self):
        self.assertTrue(0.0 < ge.BLIND_ZONE_XY_MIN <= 0.2,
                        f"盲区门限越界: {ge.BLIND_ZONE_XY_MIN}")
        self.assertGreater(ge.BLIND_ZONE_MAX_RATE_DPS, 0.0,
                           "外推角速度限幅必须为正")
        self.assertTrue(0.0 < ge.BLIND_ZONE_RATE_ALPHA <= 1.0,
                        f"角速度 EMA 系数越界: {ge.BLIND_ZONE_RATE_ALPHA}")

    def test_reset_clears_blind_state(self):
        engine, tick = make_engine_with_clock()
        for ang in VALID_ANGLES[:3]:
            engine.process(as_lm(make_side_hand(ang, PALM_LEN_VALID)), "Right")
            tick()
        engine.reset()
        self.assertIsNone(engine._roll_last_valid)
        self.assertIsNone(engine._roll_last_t)
        self.assertEqual(engine._roll_rate_dps, 0.0)


# ======================================================================
# 侧立穿越序列（engine 层）
# ======================================================================

class TestBlindZoneCrossing(unittest.TestCase):

    def setUp(self):
        self.engine, self.tick = make_engine_with_clock()
        self.outs = []
        for ang in VALID_ANGLES:                       # 有效段
            self.outs.append(self.engine.process(
                as_lm(make_side_hand(ang, PALM_LEN_VALID)), "Right"))
            self.tick()
        self.blind_start = len(self.outs)
        for ang in BLIND_ANGLES:                       # 盲区段
            self.outs.append(self.engine.process(
                as_lm(make_side_hand(ang, PALM_LEN_BLIND)), "Right"))
            self.tick()
        self.blind_end = len(self.outs)
        for ang in RECOVER_ANGLES:                      # 恢复段
            self.outs.append(self.engine.process(
                as_lm(make_side_hand(ang, PALM_LEN_VALID)), "Right"))
            self.tick()
        self.rolls = [float(o["hand_rotation_x"]) for o in self.outs]

    def test_no_half_turn_jump(self):
        """①②全程无 ±180° 级跳变：相邻帧 wrap-aware 差 < 90°。"""
        steps = [wrap180(b - a) for a, b in zip(self.rolls, self.rolls[1:])]
        worst = max(abs(s) for s in steps)
        self.assertLess(worst, 90.0,
                        f"出现大跳变 {worst:.1f}°（steps={['%.1f' % s for s in steps]}）；"
                        f"rolls={['%.1f' % r for r in self.rolls]}")

    def test_blind_segment_extrapolates_along_motion(self):
        """③盲区段沿运动方向外推：进入前角速度为负 → 盲区段每帧 Δ 亦为负。"""
        blind_steps = [wrap180(b - a) for a, b in
                       zip(self.rolls[self.blind_start - 1:self.blind_end],
                           self.rolls[self.blind_start:self.blind_end])]
        self.assertTrue(all(s < 0.0 for s in blind_steps),
                        f"盲区段外推未沿运动方向（应为负）: "
                        f"{['%.1f' % s for s in blind_steps]}")

    def test_blind_segment_bounded_by_rate_limit(self):
        """③盲区段每帧变化受外推限幅约束（|Δ| ≤ rate_max×dt + EMA 余量）。"""
        bound = ge.BLIND_ZONE_MAX_RATE_DPS * DT + 5.0
        blind_steps = [wrap180(b - a) for a, b in
                       zip(self.rolls[self.blind_start - 1:self.blind_end],
                           self.rolls[self.blind_start:self.blind_end])]
        for s in blind_steps:
            self.assertLessEqual(abs(s), bound,
                                 f"盲区段帧差 {s:.1f}° 超限幅界 {bound:.1f}°")

    def test_progress_accumulates_along_motion(self):
        """④全程按运动方向累计翻转进度：unwrap 净位移 ≤ −180°（300°→~69° 穿越）。"""
        total = self.rolls[-1] - self.rolls[0]  # 300→69 不跨界，直接差即净位移
        self.assertLessEqual(total, -180.0,
                             f"净位移 {total:.1f}° 不足以累计翻转进度 "
                             f"（rolls={['%.1f' % r for r in self.rolls]}）")

    def test_valid_segment_follows_input_direction(self):
        """非盲区段输出随输入方向递减（EMA 收敛方向与 raw 一致）。"""
        valid_rolls = self.rolls[:self.blind_start]
        self.assertTrue(all(b <= a for a, b in zip(valid_rolls, valid_rolls[1:])),
                        f"有效段输出非递减: {['%.1f' % r for r in valid_rolls]}")

    def test_all_frames_detected(self):
        """盲区帧仍是正常检出帧（is_detected=True），非空包语义。"""
        for o in self.outs:
            self.assertTrue(o["is_detected"])
            self.assertIn("hand_rotation_x", o)


class TestBlindZoneColdStart(unittest.TestCase):

    def test_first_frame_blind_zone_passthrough(self):
        """⑦冷启动即盲区（无锚点）：透传不炸、输出有限数值。"""
        engine = GestureEngine()
        out = engine.process(as_lm(make_side_hand(45.0, PALM_LEN_BLIND)), "Right")
        self.assertTrue(out["is_detected"])
        self.assertTrue(math.isfinite(float(out["hand_rotation_x"])))

    def test_blind_zone_after_reset_uses_fresh_anchor(self):
        """reset 后盲区状态清零：再次进入序列按新锚点重建（无陈旧速度污染）。"""
        engine, tick = make_engine_with_clock()
        for ang in VALID_ANGLES:
            engine.process(as_lm(make_side_hand(ang, PALM_LEN_VALID)), "Right")
            tick()
        engine.reset()
        out = engine.process(as_lm(make_side_hand(120.0, PALM_LEN_BLIND)), "Right")
        self.assertTrue(math.isfinite(float(out["hand_rotation_x"])))


# ======================================================================
# 批次 Y 扫描回修 P2-5：有效帧角速度估计进 EMA 前限幅
# ======================================================================

class TestRateEstimateClamped(unittest.TestCase):
    """P2-5：xy 门限边界抖动序列下（帧在模长门限上下交替、roll 噪声差 ~180° 级，
    单帧 rate≈5400dps），有效帧差分估计进 EMA（α=0.3）前必须先按
    ±BLIND_ZONE_MAX_RATE_DPS 限幅——否则单帧噪声污染估计，盲区外推沿错误方向漂移。
    （治本在源头；外推侧既有二次限幅保留，符号方向不受损。）"""

    def test_rate_estimate_bounded_on_xy_boundary_jitter(self):
        engine, tick = make_engine_with_clock()
        for ang in VALID_ANGLES[:2]:                   # 锚定段：有效帧建立 roll 锚点
            engine.process(as_lm(make_side_hand(ang, PALM_LEN_VALID)), "Right")
            tick()
        # 门限边界抖动段：模长在门限上下交替，roll 逐帧 ±179° 级噪声跳变
        seq = [(98.0, PALM_LEN_VALID), (277.0, PALM_LEN_BLIND), (98.0, PALM_LEN_VALID),
               (277.0, PALM_LEN_VALID), (98.0, PALM_LEN_BLIND), (277.0, PALM_LEN_VALID)]
        for ang, plen in seq:
            engine.process(as_lm(make_side_hand(ang, plen)), "Right")
            self.assertLessEqual(
                abs(engine._roll_rate_dps), ge.BLIND_ZONE_MAX_RATE_DPS + 1e-6,
                f"角速度估计超限幅（EMA 前未限幅）: {engine._roll_rate_dps:.1f}dps "
                f"@ang={ang} plen={plen}")
            tick()

    def test_rate_limit_keeps_last_diff_sign(self):
        """限幅治本在源头：大噪声差帧后估计保持最后差分符号（外推方向不翻转）。"""
        engine, tick = make_engine_with_clock()
        for ang in VALID_ANGLES[:2]:
            engine.process(as_lm(make_side_hand(ang, PALM_LEN_VALID)), "Right")
            tick()
        engine.process(as_lm(make_side_hand(98.0, PALM_LEN_VALID)), "Right")   # +179° 噪声差
        self.assertGreater(engine._roll_rate_dps, 0.0,
                           f"限幅后估计应保持最后差分符号（正）: {engine._roll_rate_dps:.1f}")
        self.assertLessEqual(engine._roll_rate_dps, ge.BLIND_ZONE_MAX_RATE_DPS,
                             "估计不超上限")


# ======================================================================
# server 集成（mock landmarker / udp_sender / camera_selector）
# ======================================================================

class _LM:
    def __init__(self, x, y, z=0.0):
        self.x, self.y, self.z = x, y, z


class _Result:
    pass


def make_server():
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.landmarker = mock.MagicMock(name="landmarker")
    server.headless = True
    return server


class TestBlindZoneServerIntegration(unittest.TestCase):

    def _run_sequence(self):
        server = make_server()
        server._latest_frame = np.zeros((48, 64, 3), dtype=np.uint8)
        hands = ([make_side_hand(a, PALM_LEN_VALID) for a in VALID_ANGLES]
                 + [make_side_hand(a, PALM_LEN_BLIND) for a in BLIND_ANGLES]
                 + [make_side_hand(a, PALM_LEN_VALID) for a in RECOVER_ANGLES])
        results = []
        for h in hands:
            r = _Result()
            r.hand_landmarks = [h]   # MediaPipe 语义：list of hands（每手 21 点）
            server.landmarker.detect_for_video.return_value = r
            server._process_frame()
            pkt = server.udp_sender.send.call_args_list[-1].args[0]
            hand = pkt["right"] if pkt["right"] is not None else pkt["left"]
            results.append((pkt, hand))
        return server, results

    def test_blind_frames_are_normal_frames_not_held(self):
        """⑤盲区数值稳定化 ≠ 丢帧 hold：全程帧帧检出，held 恒 False（语义不冲突）。"""
        _, results = self._run_sequence()
        self.assertEqual(len(results), len(VALID_ANGLES) + len(BLIND_ANGLES)
                         + len(RECOVER_ANGLES))
        for pkt, hand in results:
            self.assertIsNotNone(hand)
            self.assertIs(hand["held"], False,
                          "盲区帧应=正常帧（held=False），不得误触发 hold 语义")
            self.assertTrue(hand["is_detected"])

    def test_keys_contract_unchanged(self):
        """⑥不新增协议键：手 dict 键集仍=既有键 ∪ {id, held} ∪ 批次 AA 诊断三字段。"""
        _, results = self._run_sequence()
        known = {"gesture", "gesture_id", "confidence", "hand_x", "hand_y",
                 "hand_z", "hand_rotation_x", "hand_rotation_y",
                 "hand_rotation_z", "fingers", "pinch_distance", "handedness",
                 "fps", "is_detected", "timestamp", "palm_size",
                 "_raw_gesture_id", "_raw_confidence", "hand_index",
                 "landmarks", "tip_x", "tip_y", "id", "held",
                 # 批次 AA（W1-8，spec §4.3 / §1.2.1 诊断类字段只增）：gesture_map 日志消费
                 "label_mp", "mp_score", "label_geo"}
        for _, hand in results:
            extra = set(hand.keys()) - known
            self.assertFalse(extra, f"越权新增键: {sorted(extra)}")

    def test_roll_trajectory_continuous_in_packets(self):
        """包中 roll 轨迹连续：相邻帧 wrap-aware 差 < 120°（无 ±180° 级跳变）。"""
        _, results = self._run_sequence()
        rolls = [float(hand["hand_rotation_x"]) for _, hand in results]
        steps = [wrap180(b - a) for a, b in zip(rolls, rolls[1:])]
        worst = max(abs(s) for s in steps)
        self.assertLess(worst, 120.0,
                        f"包轨迹出现大跳变 {worst:.1f}°；"
                        f"rolls={['%.1f' % r for r in rolls]}")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
