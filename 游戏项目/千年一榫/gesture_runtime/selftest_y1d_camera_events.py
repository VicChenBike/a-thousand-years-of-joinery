#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Y1 selftest 第 3 件（Y-A17 camera_opened/closed 真值事件 + 设备启动指令 python 侧）。

批次 AD（spec §4.2）等价改写：等待窗/首开选择退役，改为「`START_CAMERA_BY_NAME:<名>`
查名直启」；match_camera_by_name 口径升级为忽略大小写与首尾空格、数字残留不再按 CAP 索引。

零摄像头纪律：CameraSelector/UDPSender/cap 全 mock，不打开真实设备、不占用真实端口。

断言口径（spec §3.2 + 批次 AD §4.2.2）：
  ① match_camera_by_name 纯函数：strip/大小写不敏感精确匹配、未命中 None、空名 None、
     纯数字残留**不再**按 CAP 索引解释（AD：禁止依赖 CAP 索引）；
  ② START_CAMERA_BY_NAME:<设备名> 解析（首个冒号后整行剩余、允许空格）与旧命令兼容；
  ③ 查名直启：命中→目标 id；失配/空名→降级列表首项；列表空→保持未启动；
  ④ camera_opened/camera_closed 事件：边沿触发（不重复发），载荷 {type,id,name,width,height,fps}/
     {type,id,reason}；RELEASE→reason="release"、切换释放→"switch"；
  ⑤ 心跳/空包新增 camera_open 电平字段（流实际开启时 true）。
判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import socket
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import camera_selector  # noqa: E402
import hand_tracking_server as hts  # noqa: E402
from camera_selector import match_camera_by_name  # noqa: E402


ENTRIES = [{"id": 0, "name": "HD WebCam"}, {"id": 2, "name": "USB Cam"}]


class FakeCtrlSock:
    """控制口打桩：recvfrom 逐条返回预置命令，取尽后 socket.timeout（非阻塞语义）。"""

    def __init__(self, cmds):
        self._cmds = list(cmds)

    def recvfrom(self, _n):
        if self._cmds:
            return self._cmds.pop(0), ("127.0.0.1", 55555)
        raise socket.timeout()

    def close(self):
        pass  # server._cleanup 兼容（真实 socket 关闭语义无）


def make_open_cap(w=640, h=480, fps=30.0):
    """「已打开」mock cap：isOpened True，get 回读与期望一致。"""
    cap = mock.MagicMock(name="cap")
    cap.isOpened.return_value = True

    def _get(prop):
        if prop == hts.cv.CAP_PROP_FRAME_WIDTH:
            return w
        if prop == hts.cv.CAP_PROP_FRAME_HEIGHT:
            return h
        if prop == hts.cv.CAP_PROP_FPS:
            return fps
        return 0

    cap.get.side_effect = _get
    return cap


def make_server():
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    return server


def typed_packets(server, msg_type):
    return [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                        if c.args and isinstance(c.args[0], dict))
            if isinstance(p, dict) and p.get("type") == msg_type]


def feed_command(server, cmd: bytes):
    server.control_socket = mock.MagicMock(name="control_socket")
    server.control_socket.recvfrom.return_value = (cmd, ("127.0.0.1", 55555))
    server._check_control_commands()


class TestMatchCameraByName(unittest.TestCase):

    def test_exact_match_after_strip(self):
        self.assertEqual(match_camera_by_name(ENTRIES, " USB Cam "), 2)
        self.assertEqual(match_camera_by_name(ENTRIES, "HD WebCam"), 0)

    def test_no_match_returns_none(self):
        self.assertIsNone(match_camera_by_name(ENTRIES, "不存在的相机"))
        self.assertIsNone(match_camera_by_name(ENTRIES, "USB Cams"))

    def test_case_insensitive_match(self):
        """批次 AD（spec §4.2.2-4）：忽略大小写差异（旧「严格精确」口径升级）。"""
        self.assertEqual(match_camera_by_name(ENTRIES, "usb cam"), 2)
        self.assertEqual(match_camera_by_name(ENTRIES, "hd webcam"), 0)
        self.assertEqual(match_camera_by_name(ENTRIES, "  USB CAM  "), 2)

    def test_empty_name_returns_none(self):
        self.assertIsNone(match_camera_by_name(ENTRIES, ""))
        self.assertIsNone(match_camera_by_name(ENTRIES, "   "))
        self.assertIsNone(match_camera_by_name(ENTRIES, None))

    def test_legacy_numeric_residual_no_longer_a_cap_index(self):
        """批次 AD（spec §4.2.2-2）：禁止存储或依赖 CAP 索引——纯数字串不再按
        旧 CAP 索引语义解释（视同未命中 → 调用方降级列表首项）。"""
        self.assertIsNone(match_camera_by_name(ENTRIES, "2"))
        self.assertEqual(camera_selector.pick_camera_by_name(ENTRIES, "2"), 0,
                         "AD：数字残留 → 未命中 → 降级列表首项 0")


class TestPreferredCameraCommand(unittest.TestCase):

    def test_parse_command_keeps_spaces(self):
        server = make_server()
        feed_command(server, "START_CAMERA_BY_NAME: USB Cam Pro".encode("utf-8"))
        self.assertEqual(server._preferred_camera_name, "USB Cam Pro")

    def test_legacy_command_parsed_same_way(self):
        """批次 AD：旧 `SET_PREFERRED_CAMERA:` 兼容同路（协议零破坏）。"""
        server = make_server()
        feed_command(server, "SET_PREFERRED_CAMERA: USB Cam Pro".encode("utf-8"))
        self.assertEqual(server._preferred_camera_name, "USB Cam Pro")

    def test_unknown_command_stays_silent(self):
        server = make_server()
        feed_command(server, b"START_CAMERA_BY_NAME_NO_COLON")
        self.assertEqual(server._preferred_camera_name, "")


class TestInitialCameraChoice(unittest.TestCase):
    """批次 AD：首开选择函数退役，改为「启动指令 → 查名直启」三态（命中/降级/空列表）。"""

    def _dispatch(self, server, name):
        cfg = server._switch_camera
        server._switch_camera = mock.MagicMock()
        try:
            server._start_camera_by_name(name)
            return server._switch_camera
        finally:
            server._switch_camera = cfg

    def test_name_hit_selects_target(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        spy = self._dispatch(server, "USB Cam")
        spy.assert_called_once_with(2)

    def test_name_miss_falls_back_to_first_entry(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        spy = self._dispatch(server, "不存在的相机")
        spy.assert_called_once_with(0)
        spy = self._dispatch(server, "2")
        spy.assert_called_once_with(0, )

    def test_empty_name_falls_back_to_first_entry(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        spy = self._dispatch(server, "")
        spy.assert_called_once_with(0)

    def test_empty_list_stays_unstarted(self):
        server = make_server()
        server._cameras = []
        spy = self._dispatch(server, "USB Cam")
        spy.assert_not_called()
        self.assertIsNone(server.cap)
        inits = [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                             if c.args and isinstance(c.args[0], dict))
                 if isinstance(p, dict) and "cameras" in p]
        self.assertTrue(inits, "AD：空列表 → 回传 0 摄像头状态")
        self.assertEqual(inits[-1]["cameras"], [])


class TestPreferredWaitWindow(unittest.TestCase):
    """批次 AD：等待窗机制**彻底退役**（启动零阻塞，设备启停等 Godot 指令）。

    历史口径留痕：Y1 审查① P1-2 曾要求 deadline 锚定「进入等待时」；AC 将窗上限
    调至 5.0s。批次 AD 拍板整体删除——`_wait_for_preference`/`PREFERRED_WAIT_SEC`
    不再存在，冷启动枚举完成即发 init#1（current_camera=-1）并进主循环。
    """

    def test_wait_window_api_retired(self):
        self.assertFalse(hasattr(hts.HandTrackingServer, "_wait_for_preference"),
                         "AD：等待窗函数必须彻底退役（启动零阻塞）")
        self.assertFalse(hasattr(hts, "PREFERRED_WAIT_SEC"),
                         "AD：等待窗常量必须彻底退役（启动零阻塞）")

    def test_start_command_consumed_by_control_loop(self):
        """替代口径：设备启动指令经控制口在**主循环**即时消费（零阻塞等待）。"""
        server = make_server()
        server._cameras = list(ENTRIES)
        server._switch_camera = mock.MagicMock()
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME: USB Cam"])
        served = []
        for _ in range(5):
            server._check_control_commands()
            served.append(server._preferred_camera_name)
            if server._preferred_camera_name:
                break
        self.assertEqual(server._preferred_camera_name, "USB Cam",
                         "主循环下一轮即消费启动指令（无等待窗）")
        server._switch_camera.assert_called_once_with(2)

    def test_returns_after_window_when_no_command(self):
        """替代口径：无指令时控制口轮询不阻塞（recvfrom 超时即返，零 sleep 等待）。"""
        server = make_server()
        server.control_socket = FakeCtrlSock([])
        t0 = time.monotonic()
        server._check_control_commands()
        self.assertLess(time.monotonic() - t0, 0.5,
                        "无指令时控制口轮询必须立即返回（不得阻塞等待）")
        self.assertEqual(server._preferred_camera_name, "")


class TestStartupSequence(unittest.TestCase):
    """审查① P1-2②（批次 AD 等价改写）：控制口 bind 前移至枚举之前——接住桥早期下发的
    设备启动指令（UDP 无接收者时命令被内核丢弃，启动序收不到）。
    抽取 _startup_sequence 供真实构造路径直调断言顺序；等待窗已退役（AD §4.2.2-1）。"""

    def test_control_bind_precedes_enumeration(self):
        server = make_server()
        order = []
        with mock.patch.object(server, "_bind_control_socket",
                               side_effect=lambda: (order.append("bind"), True)[1]), \
             mock.patch.object(server, "_enumerate_cameras_step",
                               side_effect=lambda: (order.append("enum"), ([], None))[1]):
            server._startup_sequence()
        self.assertEqual(order[:2], ["bind", "enum"],
                         f"控制口 bind 必须先于枚举（实测顺序 {order}）")
        self.assertNotIn("wait", order, "AD：启动前序不得再含等待窗（零阻塞）")


class TestCameraOpenCloseEvents(unittest.TestCase):

    def test_opened_event_payload_and_edge(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        server.current_camera_id = 2
        server.cap = make_open_cap()
        server._emit_camera_opened()
        server._emit_camera_opened()  # 边沿去重：重复调用不再发
        events = typed_packets(server, "camera_opened")
        self.assertEqual(len(events), 1, f"opened 事件应恰好一次: {events}")
        ev = events[0]
        self.assertEqual(ev["id"], 2)
        self.assertEqual(ev["name"], "USB Cam")
        self.assertEqual(ev["width"], 640)
        self.assertEqual(ev["height"], 480)
        self.assertEqual(ev["fps"], 30)
        self.assertTrue(server._camera_stream_open)

    def test_closed_event_payload_and_edge(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        server.current_camera_id = 2
        server.cap = make_open_cap()
        server._emit_camera_opened()
        server._emit_camera_closed("release")
        server._emit_camera_closed("release")  # 未开启状态下不再发
        closed = typed_packets(server, "camera_closed")
        self.assertEqual(len(closed), 1)
        self.assertEqual(closed[0]["id"], 2)
        self.assertEqual(closed[0]["reason"], "release")
        self.assertFalse(server._camera_stream_open)

    def test_release_camera_only_emits_closed(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        server.current_camera_id = 2
        server.cap = make_open_cap()
        server._emit_camera_opened()
        server._release_camera_only()
        closed = typed_packets(server, "camera_closed")
        self.assertEqual(len(closed), 1)
        self.assertEqual(closed[0]["reason"], "release")
        self.assertTrue(server._camera_intentionally_released)

    def test_switch_camera_emits_closed_then_opened(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        server.current_camera_id = 0
        server.cap = make_open_cap()
        server._emit_camera_opened()
        self.server = server
        new_cap = make_open_cap()
        server.camera_selector.select_camera.return_value = new_cap
        server.udp_sender.send.reset_mock()
        server._switch_camera(2)
        closed = typed_packets(server, "camera_closed")
        opened = typed_packets(server, "camera_opened")
        self.assertEqual(len(closed), 1, f"切换释放应发一次 closed: {closed}")
        self.assertEqual(closed[0]["reason"], "switch")
        self.assertEqual(len(opened), 1, f"切换成功应发一次 opened: {opened}")
        self.assertEqual(opened[0]["id"], 2)
        self.assertTrue(server._camera_stream_open)

    def test_switch_all_fail_emits_closed_not_opened(self):
        server = make_server()
        server._cameras = list(ENTRIES)
        server.current_camera_id = 0
        server.cap = make_open_cap()
        server._emit_camera_opened()
        server.udp_sender.send.reset_mock()
        server.camera_selector.select_camera.side_effect = RuntimeError("无法打开摄像头 [2]")
        server._switch_camera(2)
        opened = typed_packets(server, "camera_opened")
        closed = typed_packets(server, "camera_closed")
        errors = [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                              if c.args and isinstance(c.args[0], dict))
                  if isinstance(p, dict) and p.get("type") == "camera_error"]
        self.assertEqual(len(opened), 0, "切换全失败不应发 opened")
        self.assertEqual(len(closed), 1)
        self.assertEqual(len(errors), 1, "切换全失败必回传 camera_error（既有契约）")

    def test_heartbeat_empty_packet_carries_camera_open_level(self):
        server = make_server()
        server.cap = None
        server._latest_frame = None
        server._last_heartbeat = 0.0
        with mock.patch.object(server, "_attempt_reconnect"), \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        pkts = [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                            if c.args and isinstance(c.args[0], dict))
                if isinstance(p, dict) and p.get("left", "X") is None and "left" in p]
        self.assertTrue(pkts, "无帧分支应发心跳空包")
        self.assertIn("camera_open", pkts[-1])
        self.assertIs(pkts[-1]["camera_open"], False)
        # 流开启态：电平翻 true（重置 1Hz 心跳节流计时，允许本帧再发）
        server._camera_stream_open = True
        server._last_heartbeat = 0.0
        server.udp_sender.send.reset_mock()
        with mock.patch.object(server, "_attempt_reconnect"), \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        pkts2 = [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                             if c.args and isinstance(c.args[0], dict))
                 if isinstance(p, dict) and "left" in p]
        self.assertTrue(pkts2)
        self.assertIs(pkts2[-1]["camera_open"], True)


class TestBackwardCompatCommands(unittest.TestCase):

    def test_existing_commands_still_accepted(self):
        """老命令回归：RELEASE_CAMERA/GET_CAMERAS/SET_RESOLUTION 老式 2 参不炸（静默容错）。"""
        server = make_server()
        server.cap = None
        feed_command(server, b"RELEASE_CAMERA")
        self.assertTrue(server._camera_intentionally_released)
        feed_command(server, b"GET_CAMERAS")  # 幂等无状态，不抛即过
        feed_command(server, b"SET_RESOLUTION:1280x720")  # cap None：走异常兜底不抛
        feed_command(server, b"TOTALLY_UNKNOWN_CMD")  # 未知命令静默


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
