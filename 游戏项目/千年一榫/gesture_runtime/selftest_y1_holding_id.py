#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Y1 selftest 第 1 件（Y-A6 per-hand 稳定 id + Y-A4 丢帧容忍 hold-last）。

零摄像头纪律：HandTracker 纯逻辑直测；server 集成段 CameraSelector/UDPSender/
landmarker 全 mock、帧为 np.zeros 假帧，不打开真实设备、不占用真实端口。

断言口径（spec §3.1/§2 Y-A6/Y-A4）：
  ① 手 dict 新增键仅 id/held 两个，既有键全保留（引擎键 + server 注入键）；
  ② id 格式 "L0"/"R0"，同侧重分配递增尾号，跨帧稳定不互换（含双手交叉）；
  ③ 双手最近邻关联：标签随 track 延续，几何误判不串手；
  ④ hold-last：手丢失 ≤0.3s（HAND_HOLD_TTL_SEC）时输出上一帧完整数据 + held:true，
     超窗才消失（server 组包为 null）；
  ⑤ 单手丢失不影响另一手的标签与数据连续性；
  ⑥ 整帧 0 手：各手独立走 hold 后按实际组包（held 数据仍随包发出）。
判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import hand_tracking_server as hts  # noqa: E402
from hand_tracking_server import HandTracker, HAND_HOLD_TTL_SEC  # noqa: E402


# ======================================================================
# 合成数据
# ======================================================================

def make_hand_landmarks(cx: float, cy: float, label: str):
    """构造 21 个 MediaPipe 风格关键点（.x/.y/.z 属性）。

    thumb_tip(4) 与 pinky_mcp(17) 的 x 关系与镜像口径 label 一致
    （Right: thumb.x < pinky.x）；center 均值 ≈ (cx, cy)。
    """
    sign = 1.0 if label == "Right" else -1.0  # Right：拇指在图像 x 负方向
    pts = []

    def lm(x, y, z=0.0):
        class _P:
            pass
        p = _P()
        p.x, p.y, p.z = float(x), float(y), float(z)
        return p

    # 腕(0)
    pts.append(lm(cx, cy + 0.05))
    # 拇指链 1..4：向 sign 负方向展开
    for i in range(1, 5):
        pts.append(lm(cx - sign * (0.02 + 0.02 * i), cy + 0.04 - 0.015 * i))
    # 食指 5..8、中指 9..12（x 居中偏 sign 正向小量，向上伸展）
    for i, base in ((5, 0.03), (9, 0.01)):
        for k in range(4):
            pts.append(lm(cx + sign * base, cy + 0.02 + 0.045 * k + (0.01 if base > 0.02 else 0)))
    # 无名指 13..16、小指 17..20：向 sign 正方向展开
    for i, base in ((13, -0.01), (17, -0.04)):
        for k in range(4):
            pts.append(lm(cx - sign * base, cy + 0.02 + 0.04 * k))
    assert len(pts) == 21, f"合成手点数错误: {len(pts)}"
    return pts


def _mirror_landmarks(cx, cy, label):
    """21×3 合成 landmark（镜像口径：Right 拇指在图像 x 负方向）。

    批次 AC（2026-09-27）等价改写：`HAND_MATCH_DIST` 0.35→0.65（spec §4.3-1）后，
    `_is_same_hand` 的 **D1 第二档**（landmark 缺失/退化 → 中心距兜底）会把中心距
    <0.65 的两个**无 landmark 夹具**判成同一只手并合并。本文件历史夹具
    `landmarks=None` 属「无形状信息」形态，故自本批起一律携带**镜像 landmark**：
    D1 第一档（逐点最大偏差 <0.02）成为唯一判据，两只真手（左右镜形）即便中心重合
    也判异手（与 `selftest_aa_handedness` 的 `synth_landmarks` 同口径）。
    """
    sign = 1.0 if label == "Right" else -1.0
    lm = np.zeros((21, 3), dtype=np.float32)
    for i in range(21):
        lm[i] = [cx + sign * (i % 5) * 0.01, cy + (i // 5) * 0.01, 0.0]
    lm[0] = [cx, cy + 0.05, 0.0]
    lm[4] = [cx - sign * 0.06, cy + 0.04, 0.0]
    lm[17] = [cx + sign * 0.06, cy + 0.02, 0.0]
    return lm


def detection(cx, cy, label):
    return {"center": (cx, cy), "label_geo": label,
            "landmarks": _mirror_landmarks(cx, cy, label)}


# ======================================================================
# HandTracker 纯逻辑测试
# ======================================================================

class TestHandTracker(unittest.TestCase):

    def setUp(self):
        self.tracker = HandTracker()

    def test_partial_match_keeps_ids_and_holds_other(self):
        """审查① P1-1：部分匹配——仅一对 track×detection 在阈值内时，
        该对保持原 id 正常匹配；另一 track 进 hold；未消费 detection 才建新手。

        场景（审查指定推演）：R0@(0.28,0.5)、L0@(0.02,0.5) 两 track；
        新帧 D0@(0.28,0.5)（与 R0 距 0 合法）、D1@(1.00,0.5)（与两 track 距均 ≥0.65）。
        缺陷行为：整组匹配判无效返回 [] → R0/L0 双双 held、D0/D1 建新手——
        同一物理手（D0）被新 id 顶替、right 槽被覆盖。

        批次 AC（2026-09-27，spec §4.3-1）等价改写：`HAND_MATCH_DIST` 0.35→0.65，
        原夹具 D1@(0.9,0.5) 距 R0@(0.5,0.5) 仅 0.4（新阈内）→ 变成**满配**场景，
        断言前提（部分匹配）失效。故把两条 track 分别移到 0.28/0.02、D1 移到 1.00：
        d(R0,D0)=0 ✓、d(L0,D0)=0.26 ✓、d(R0,D1)=0.72 ≥0.65 ✗、d(L0,D1)=0.98 ✗ →
        基数 2 不可能、最优配对恒 (R0,D0)，原断言逐条语义保持（tests only 夹具平移）。

        批次 Z（Z5-2，spec §5-2）等价改写：D1 的 label_geo 与 R0 同标 "Right"——旧码建
        **同侧新手 R1**（两只 active track 同 hand_index → server 后写覆盖前写=「只出一只
        手」根因）；现为同侧冲突修正域（mp 缺失 → 既有粘性优先、新手让位）→ D1 改侧建
        **L1**，R0 保持原 id。核心契约（部分匹配不整组作废 / 未配对进 hold / 未消费
        detection 建新手不偷 D0）逐字不变，断言数 6→9（增：L1 侧别、R1 反例、活跃两侧
        hand_index 相异）。
        """
        self.tracker.update([detection(0.28, 0.5, "Right"),
                             detection(0.02, 0.5, "Left")], 100.0)
        items, new_ids, dead = self.tracker.update(
            [detection(0.28, 0.5, "Right"), detection(1.00, 0.5, "Right")], 100.033)
        by_id = {it["id"]: it for it in items}
        # R0 与 D0 匹配保持原 id、正常帧（不得进 held）
        self.assertIn("R0", by_id)
        self.assertFalse(by_id["R0"]["held"],
                         "同物理手应保持原 id 正常匹配（部分匹配不得整组作废）")
        self.assertIsNotNone(by_id["R0"]["detection"])
        self.assertAlmostEqual(by_id["R0"]["detection"]["center"][0], 0.28)
        # L0 无合法配对 → hold（不得建新手顶替）
        self.assertIn("L0", by_id)
        self.assertTrue(by_id["L0"]["held"], "无配对的旧 track 应进 hold")
        # D1 未被消费 → 新手（Z5-2 同侧冲突修正：geo 同标 Right → 新手让位改侧 L1）
        self.assertIn("L1", by_id, "未消费的 detection 应建新手（Z5-2 修正后 side=L）")
        self.assertAlmostEqual(by_id["L1"]["detection"]["center"][0], 1.00)
        self.assertEqual([i for i in new_ids if i == "L1"], ["L1"])
        self.assertNotIn("R1", by_id,
                         "Z5-2 反例锁：不得再建同侧新手 R1（两手同标覆盖=只出一只手根因）")
        self.assertEqual([i for i in new_ids if i == "R1"], [],
                         "Z5-2 反例锁：new_ids 不含同侧 R1")
        self.assertNotEqual(by_id["R0"]["hand_index"], by_id["L1"]["hand_index"],
                            "Z5-2：两只 active track hand_index 必须相异（0/1）")
        self.assertEqual(dead, [])

    def test_id_format_and_side_prefix(self):
        items, new_ids, dead = self.tracker.update([detection(0.3, 0.5, "Left")], 100.0)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["id"], "L0")
        self.assertEqual(items[0]["hand_index"], 0)
        self.assertEqual(items[0]["label"], "Left")
        self.assertFalse(items[0]["held"])
        self.assertEqual(new_ids, ["L0"])
        self.assertEqual(dead, [])

        tracker2 = HandTracker()
        items2, _, _ = tracker2.update([detection(0.7, 0.5, "Right")], 100.0)
        self.assertEqual(items2[0]["id"], "R0")
        self.assertEqual(items2[0]["hand_index"], 1)

    def test_id_stable_across_frames(self):
        ids = []
        for i in range(6):
            items, _, _ = self.tracker.update(
                [detection(0.5 + 0.01 * i, 0.5, "Right")], 100.0 + 0.033 * i)
            self.assertEqual(len(items), 1)
            ids.append(items[0]["id"])
        self.assertEqual(len(set(ids)), 1, f"id 漂移: {ids}")
        self.assertEqual(ids[0], "R0")

    def test_hold_within_ttl(self):
        _, _, _ = self.tracker.update([detection(0.5, 0.5, "Right")], 100.0)
        # server 侧回写上一帧完整数据（模拟 process 常驻回路）
        track = self.tracker.tracks().get("R0")
        self.assertIsNotNone(track)
        track["last_result"] = {"hand_x": 0.5, "hand_y": 0.5, "gesture": "Open_Palm"}
        # 丢手 0.1s / 0.29s：仍在 hold 窗内
        for dt in (0.1, 0.29):
            items, _, dead = self.tracker.update([], 100.0 + dt)
            self.assertEqual(dead, [], f"dt={dt} 不应判死")
            self.assertEqual(len(items), 1)
            self.assertTrue(items[0]["held"], f"dt={dt} 应 held=True")
            self.assertEqual(items[0]["id"], "R0")

    def test_hold_expires_after_ttl(self):
        self.tracker.update([detection(0.5, 0.5, "Right")], 100.0)
        items, _, dead = self.tracker.update([], 100.0 + HAND_HOLD_TTL_SEC + 0.01)
        self.assertEqual(items, [], "超窗后不应再输出 hold 数据")
        self.assertEqual([d["id"] for d in dead], ["R0"])

    def test_two_hands_crossing_ids_stable(self):
        """双手交叉运动：id 稳定不互换（Y-A6 验收口径）。"""
        tracker = HandTracker()
        n = 20
        ids_a, ids_b = [], []
        for i in range(n):
            t = i / (n - 1)
            ax = 0.3 + 0.4 * t      # A: 0.3 → 0.7
            bx = 0.7 - 0.4 * t      # B: 0.7 → 0.3
            items, _, _ = tracker.update(
                [detection(ax, 0.5, "Right"), detection(bx, 0.5, "Left")],
                200.0 + 0.033 * i)
            self.assertEqual(len(items), 2, f"帧{i} 应有两手输出")
            by_id = {it["id"]: it for it in items}
            if i == 0:
                id_a = "R0"
                id_b = "L0"
                self.assertIn(id_a, by_id)
                self.assertIn(id_b, by_id)
            ids_a.append(by_id.get("R0", {}).get("label"))
            ids_b.append(by_id.get("L0", {}).get("label"))
        self.assertTrue(all(x == "Right" for x in ids_a),
                        f"R0 标签漂移/互换: {ids_a}")
        self.assertTrue(all(x == "Left" for x in ids_b),
                        f"L0 标签漂移/互换: {ids_b}")

    def test_single_hand_loss_does_not_affect_other(self):
        tracker = HandTracker()
        items, _, _ = tracker.update(
            [detection(0.3, 0.5, "Left"), detection(0.7, 0.5, "Right")], 300.0)
        self.assertEqual({it["id"] for it in items}, {"L0", "R0"})
        # 左手消失（右手仍在）：左手 held、右手正常
        items, _, _ = tracker.update([detection(0.7, 0.5, "Right")], 300.1)
        self.assertEqual(len(items), 2)
        left = next(it for it in items if it["id"] == "L0")
        right = next(it for it in items if it["id"] == "R0")
        self.assertTrue(left["held"])
        self.assertFalse(right["held"])
        self.assertIsNotNone(right["detection"])

    def test_new_hand_same_side_increments_suffix(self):
        tracker = HandTracker()
        tracker.update([detection(0.5, 0.5, "Right")], 400.0)
        # 超窗判死
        tracker.update([], 400.0 + HAND_HOLD_TTL_SEC + 0.05)
        # 同侧新手进入：尾号递增（不复用 R0，GDScript 侧 id 变化=新手）
        items, new_ids, _ = tracker.update([detection(0.5, 0.5, "Right")], 401.0)
        self.assertEqual(new_ids, ["R1"])
        self.assertEqual(items[0]["id"], "R1")

    def test_label_persists_despite_geometry_flip(self):
        """标签随 track 延续：后续帧几何误判（label_geo 翻转）不改变标签与 id。"""
        tracker = HandTracker()
        tracker.update([detection(0.5, 0.5, "Right")], 500.0)
        items, _, _ = tracker.update([detection(0.51, 0.5, "Left")], 500.033)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["id"], "R0")
        self.assertEqual(items[0]["label"], "Right")
        self.assertEqual(items[0]["hand_index"], 1)


# ======================================================================
# server 集成测试（mock landmarker / udp_sender / camera_selector）
# ======================================================================

def make_server():
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.landmarker = mock.MagicMock(name="landmarker")
    server.headless = True
    return server


def set_detections(server, hands):
    """mock landmarker 输出：hands=[(label, cx, cy), ...]。"""
    class _Result:
        pass
    r = _Result()
    r.hand_landmarks = [make_hand_landmarks(cx, cy, label) for label, cx, cy in hands]
    server.landmarker.detect_for_video.return_value = r


def last_packet(server):
    calls = server.udp_sender.send.call_args_list
    assert calls, "udp_sender.send 未被调用"
    return calls[-1].args[0]


def sent_packets(server):
    return [c.args[0] for c in server.udp_sender.send.call_args_list
            if c.args and isinstance(c.args[0], dict)]


# spec §3.1 手 dict 既有键（引擎键 + server 注入键；landmarks 为 server 注入）
# _raw_gesture_id/_raw_confidence 为 gesture_engine 既有附加调试键（spec §3.1 明列 _raw_*）
ENGINE_KEYS = {"gesture", "gesture_id", "confidence", "hand_x", "hand_y", "hand_z",
               "hand_rotation_x", "hand_rotation_y", "hand_rotation_z",
               "fingers", "pinch_distance", "handedness", "fps",
               "is_detected", "timestamp", "palm_size",
               "_raw_gesture_id", "_raw_confidence"}
SERVER_KEYS = {"hand_index", "landmarks", "tip_x", "tip_y"}
EXPECTED_NEW_KEYS = {"id", "held"}
# 批次 AA（W1-8，spec §4.3）：诊断三字段（gesture_map GAME_GESTURE_DEBUG 日志消费）——
# 协议**只增不改**（spec §1.2.1「本批仅新增诊断/心跳类字段」），并入白名单后仍以
# 封闭集合减法卡「除这些之外不得新增键」（断言强度不降）。
DIAG_KEYS = {"label_mp", "mp_score", "label_geo"}


class TestServerFrameIntegration(unittest.TestCase):

    def setUp(self):
        self.server = make_server()
        self.server._latest_frame = np.zeros((48, 64, 3), dtype=np.uint8)

    def test_packet_structure_and_new_keys(self):
        set_detections(self.server, [("Right", 0.7, 0.5)])
        self.server._process_frame()
        pkt = last_packet(self.server)
        self.assertEqual(set(pkt.keys()),
                         {"left", "right", "timestamp", "camera_open"},
                         f"顶层键漂移: {sorted(pkt.keys())}")
        self.assertIsNone(pkt["left"])
        hand = pkt["right"]
        self.assertIsNotNone(hand)
        # 既有键全保留
        missing = (ENGINE_KEYS | SERVER_KEYS) - set(hand.keys())
        self.assertFalse(missing, f"既有键缺失: {sorted(missing)}")
        # 新增键仅 id/held + 批次 AA 诊断三字段（封闭集合减法，越权仍判红）
        extra = set(hand.keys()) - (ENGINE_KEYS | SERVER_KEYS | EXPECTED_NEW_KEYS | DIAG_KEYS)
        self.assertFalse(extra, f"越权新增键: {sorted(extra)}")
        self.assertEqual(hand["id"], "R0")
        self.assertIs(hand["held"], False)

    def test_hold_packet_within_ttl(self):
        # 帧1：检出右手
        set_detections(self.server, [("Right", 0.7, 0.5)])
        self.server._process_frame()
        held_x = last_packet(self.server)["right"]["hand_x"]
        # 帧2：0 检出（紧随，真实时钟差 << 0.3s）→ right=held 数据
        set_detections(self.server, [])
        self.server._process_frame()
        pkt = last_packet(self.server)
        self.assertIsNone(pkt["left"])
        hand = pkt["right"]
        self.assertIsNotNone(hand, "hold 窗内不应发 null")
        self.assertIs(hand["held"], True)
        self.assertEqual(hand["hand_x"], held_x, "held 帧应沿用上一帧值")
        self.assertEqual(hand["id"], "R0")

    def test_hold_expires_to_null(self):
        set_detections(self.server, [("Right", 0.7, 0.5)])
        self.server._process_frame()
        # 把该 track 的 last_seen 拨后超窗（免真睡 0.3s）
        tracks = self.server._hand_tracker.tracks()
        self.assertEqual(len(tracks), 1)
        for tr in tracks.values():
            tr["last_seen"] -= (HAND_HOLD_TTL_SEC + 0.05)
        set_detections(self.server, [])
        self.server._process_frame()
        pkt = last_packet(self.server)
        self.assertIsNone(pkt["right"], "超窗后应发 null")
        self.assertIsNone(pkt["left"])

    def test_two_hands_each_slot_and_ids(self):
        set_detections(self.server, [("Left", 0.3, 0.5), ("Right", 0.7, 0.5)])
        self.server._process_frame()
        pkt = last_packet(self.server)
        self.assertIsNotNone(pkt["left"])
        self.assertIsNotNone(pkt["right"])
        self.assertEqual(pkt["left"]["id"], "L0")
        self.assertEqual(pkt["right"]["id"], "R0")
        self.assertEqual(pkt["left"]["hand_index"], 0)
        self.assertEqual(pkt["right"]["hand_index"], 1)

    def test_crossing_integration_ids_stable(self):
        n = 12
        for i in range(n):
            t = i / (n - 1)
            set_detections(self.server, [("Left", 0.3 + 0.4 * t, 0.5),
                                         ("Right", 0.7 - 0.4 * t, 0.5)])
            self.server._process_frame()
            pkt = last_packet(self.server)
            self.assertEqual(pkt["left"]["id"], "L0", f"帧{i} 左手 id 漂移")
            self.assertEqual(pkt["right"]["id"], "R0", f"帧{i} 右手 id 漂移")

    def test_camera_open_field_present_in_empty_packet(self):
        # 假帧在 → 0 手空包也应带 camera_open 电平字段
        set_detections(self.server, [])
        self.server._process_frame()
        pkt = last_packet(self.server)
        self.assertIn("camera_open", pkt)
        self.assertIs(pkt["camera_open"], False)


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
