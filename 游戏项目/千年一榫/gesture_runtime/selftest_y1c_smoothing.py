#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Y1 selftest 第 2 件（Y-A7 roll/pitch/yaw 与 fingers 输出平滑）。

零摄像头纪律：纯 GestureEngine 逻辑直测（合成 landmarks），不触任何设备。

断言口径（spec §3.1 值语义升级/§2 Y-A7/§4-4 常量集中）：
  ① 新增常量 ROTATION_EMA_ALPHA / FINGERS_EMA_ALPHA 存在、∈(0,1]、集中可调；
  ② 抖动序列下输出 fingers/rotation 无单帧跳变（输出帧差有界）；
  ③ 恒定输入 N 帧后输出收敛到输入（平滑不引入稳态偏差）；
  ④ roll wrap-around（359°→3°）平滑走短弧不爆 180° 跳变；
  ⑤ reset() 清空全部时序状态（Y-A6 新手进入该侧防历史污染的前提）；
  ⑥ 手势/置信度既有 EMA+滑窗不受影响（常量锚 + 分类输出回归）。
判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import math
import sys
import unittest
from pathlib import Path

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import gesture_engine as ge  # noqa: E402
from gesture_engine import GestureEngine  # noqa: E402


def make_flat_palm(angle_deg: float = 0.0, center=(0.5, 0.5), curl: float = 0.0):
    """合成张开掌 21 点：指向上伸展，可整体绕腕旋转 angle_deg（度）、可按 curl 收拢。"""
    lm = np.zeros((21, 3), dtype=np.float32)
    cx, cy = center
    a = math.radians(angle_deg)

    def rot(dx, dy):
        return np.array([cx + dx * math.cos(a) - dy * math.sin(a),
                         cy + dx * math.sin(a) + dy * math.cos(a),
                         0.0], dtype=np.float32)

    lm[0] = rot(0.0, 0.06)  # 腕（掌心下方）
    # 拇指 1..4：横向展开
    for i in range(1, 5):
        lm[i] = rot(-0.08 - 0.02 * i * (1.0 - curl), 0.03 - 0.006 * i)
    # 四指 5..20：向上伸展（curl=1 时收拢到掌心）
    fingers = {5: -0.04, 9: 0.0, 13: 0.04, 17: 0.08}
    for base_idx, dx in fingers.items():
        for k in range(4):
            t = k / 3.0
            x = dx * (1.0 - curl)
            y = 0.02 - (0.02 + 0.16 * t) * (1.0 - 0.8 * curl)
            lm[base_idx + k] = rot(x, y)
    return lm


class TestSmoothingConstants(unittest.TestCase):

    def test_constants_exist_and_bounded(self):
        self.assertTrue(0.0 < ge.ROTATION_EMA_ALPHA <= 1.0,
                        f"ROTATION_EMA_ALPHA 越界: {ge.ROTATION_EMA_ALPHA}")
        self.assertTrue(0.0 < ge.FINGERS_EMA_ALPHA <= 1.0,
                        f"FINGERS_EMA_ALPHA 越界: {ge.FINGERS_EMA_ALPHA}")

    def test_existing_temporal_constants_untouched(self):
        """既有 gesture/confidence EMA+滑窗口径不受本批影响（批次 U 锚延续）。"""
        self.assertEqual(ge.SMOOTH_WINDOW_SIZE, 5)
        self.assertAlmostEqual(ge.CONFIDENCE_ENTER, 0.55)
        self.assertAlmostEqual(ge.CONFIDENCE_EXIT, 0.40)
        self.assertAlmostEqual(ge.EMA_ALPHA, 0.3)


class TestFingersSmoothing(unittest.TestCase):

    def test_no_single_frame_jump_under_jitter(self):
        """伸直↔收拢单帧交替抖动：输出 fingers 相邻帧差有界（无 0↔1 直接跳变）。"""
        engine = GestureEngine()
        prev = None
        max_step = 0.0
        for i in range(24):
            curl = 1.0 if i % 2 == 0 else 0.0
            result = engine.process(make_flat_palm(curl=curl), "Right")
            cur = float(result["fingers"][2])  # 中指
            if prev is not None:
                max_step = max(max_step, abs(cur - prev))
            prev = cur
        self.assertLess(max_step, 0.75,
                        f"输出单帧跳变过大: {max_step:.3f}（未平滑应≈1.0）")

    def test_converges_to_constant_input(self):
        engine = GestureEngine()
        out = None
        for _ in range(40):
            out = engine.process(make_flat_palm(curl=0.0), "Right")
        for v in out["fingers"]:
            self.assertGreater(float(v), 0.6, f"恒定伸直输入 40 帧后未收敛: {out['fingers']}")

    def test_output_keys_unchanged(self):
        engine = GestureEngine()
        result = engine.process(make_flat_palm(), "Right")
        self.assertEqual(len(result["fingers"]), 5)
        for key in ("hand_rotation_x", "hand_rotation_y", "hand_rotation_z"):
            self.assertIn(key, result)
        self.assertIsInstance(result["fingers"][0], float)


class TestRotationSmoothing(unittest.TestCase):

    def test_no_single_frame_jump_under_jitter(self):
        engine = GestureEngine()
        prev = None
        max_step = 0.0
        for i in range(24):
            angle = 30.0 if i % 2 == 0 else 60.0
            result = engine.process(make_flat_palm(angle_deg=angle), "Right")
            cur = float(result["hand_rotation_x"])  # roll
            if prev is not None:
                max_step = max(max_step, abs(((cur - prev + 180.0) % 360.0) - 180.0))
            prev = cur
        self.assertLess(max_step, 25.0,
                        f"roll 输出单帧跳变过大: {max_step:.1f}°（30° 抖动直通应≈30°）")

    def test_roll_wrap_takes_short_arc(self):
        """roll 359°→3° 平滑输出走短弧（~0°/360° 附近），不产生 180° 级跳变。"""
        engine = GestureEngine()
        engine._smooth_rotation({"roll": 359.0, "pitch": 0.0, "yaw": 0.0})
        out = engine._smooth_rotation({"roll": 3.0, "pitch": 0.0, "yaw": 0.0})
        self.assertLess(out["roll"], 357.0,
                        f"wrap 后输出应接近 0°/360° 短弧侧: {out['roll']}")

    def test_converges(self):
        engine = GestureEngine()
        out = None
        for _ in range(40):
            out = engine._smooth_rotation({"roll": 10.0, "pitch": -20.0, "yaw": 30.0})
        self.assertAlmostEqual(out["roll"], 10.0, delta=0.5)
        self.assertAlmostEqual(out["pitch"], -20.0, delta=0.5)
        self.assertAlmostEqual(out["yaw"], 30.0, delta=0.5)

    def test_pitch_yaw_ranges_preserved(self):
        engine = GestureEngine()
        for angle in (0.0, 45.0, -45.0):
            out = engine.process(make_flat_palm(angle_deg=angle), "Right")
            self.assertTrue(-90.0 <= out["hand_rotation_y"] <= 90.0,
                            f"pitch 越界: {out['hand_rotation_y']}")
            self.assertTrue(-180.0 <= out["hand_rotation_z"] <= 180.0,
                            f"yaw 越界: {out['hand_rotation_z']}")


class TestEngineReset(unittest.TestCase):

    def test_reset_clears_temporal_state(self):
        engine = GestureEngine()
        for _ in range(10):
            engine.process(make_flat_palm(), "Right")
        engine.reset()
        self.assertEqual(len(engine._gesture_history), 0)
        self.assertEqual(len(engine._confidence_history), 0)
        self.assertEqual(engine._ema_confidence, 0.0)
        self.assertEqual(engine._smoothed_gesture_id, 21)
        self.assertEqual(len(engine._rotation_ema), 0)
        self.assertIsNone(engine._fingers_ema)
        self.assertIsNone(engine._last_result)

    def test_gesture_classification_regression(self):
        """既有滑窗投票路径回归：稳定张开掌 10 帧后输出 Open_Palm。"""
        engine = GestureEngine()
        out = None
        for _ in range(10):
            out = engine.process(make_flat_palm(), "Right")
        self.assertEqual(out["gesture"], "Open_Palm", f"分类回归: {out['gesture']}")
        self.assertGreater(out["confidence"], 0.4)


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
