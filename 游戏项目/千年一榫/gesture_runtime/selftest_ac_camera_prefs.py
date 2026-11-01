#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AC Wave 2 专项自测：摄像头生命周期与首选握手（spec §4.2 领域二）。

零摄像头纪律：全程 mock——CameraSelector/UDPSender/cap 全打桩，
**绝不调用 cv.VideoCapture 真开镜**，也不占用 9876/9877/9878 真实端口。

断言口径（spec §4.2/D2）：
  A. `is_virtual_or_phone_camera` 纯函数：黑名单关键词逐个命中（大小写不敏感）、
     荣耀/Magic 真机名命中、正常物理设备不误杀、None/空/非串防御；
  B. `pick_auto_camera` 重构：空列表/全手机/全虚拟 → **None**（废除「空列表兜底 0」
     与「盲开索引 0」）；混合时取非黑名单最低 CAP 索引；防御未知名；
  C. 握手状态机（server 级）：PREFERRED_WAIT_SEC=5.0；`_handshake_received` 置位点
     （SET_PREFERRED_CAMERA 空载荷/SWITCH_CAMERA）；空载荷即时结束等待窗；
     `_choose_initial_camera_id(None)` → None（不盲开）；偏好命中优先；迟到握手
     动态切换（未开流/开错设备，首开段已收口）与窗内只记偏好/RELEASE/失配零切换；
  D. 启动待命：`chosen_id is None` → start() 不打开任何摄像头，init#1 current_camera=-1；
  E. GET_CAMERAS 空名单重扫（热插拔）：重调 `_enumerate_cameras_step`；仍空则复位
     `_enum_probe_started` 并重起懒探测线程；
  F. 红线门：默认零开镜桩（AA_ALLOW_REAL_CAMERA 未设）恒返回 None。

判绿：末行输出 SELFTEST PASSED，退出码 0。
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

import camera_selector as cs  # noqa: E402
import hand_tracking_server as hts  # noqa: E402


# ----------------------------------------------------------------------
# 夹具（零真开镜：selector/sender/cap 全 mock）
# ----------------------------------------------------------------------

class FakeCtrlSock:
    """控制口打桩：recvfrom 逐条返回预置命令，取尽后 socket.timeout（非阻塞语义）。"""

    def __init__(self, cmds):
        self._cmds = list(cmds)

    def recvfrom(self, _n):
        if self._cmds:
            return self._cmds.pop(0), ("127.0.0.1", 55555)
        raise socket.timeout()

    def close(self):
        pass


def make_open_cap(w=640, h=480, fps=30.0):
    """「已打开」mock cap（绝不触真实设备）。"""
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


class _NoopThread:
    """线程替身：start() 全链 mock 用（不真起线程）。"""

    def __init__(self, *a, **k):
        pass

    def start(self):
        pass

    def is_alive(self):
        return False

    def join(self, timeout=None):
        pass


# ----------------------------------------------------------------------
# A. 黑名单硬编码彻底退役（批次 AD 等价改写：旧黑名单断言口径迁移）
# ----------------------------------------------------------------------

class VirtualPhoneFilterTest(unittest.TestCase):
    """批次 AD（spec §4.2.1）：`VIRTUAL_OR_PHONE_CAMERA_KEYWORDS` 与
    `is_virtual_or_phone_camera` 及其消费者 `pick_auto_camera`、`AUTO_CAM_KEYWORDS`
    全部退役——不再靠名称字符串猜测设备类型，严格遵循用户配置与时序驱动。
    断言口径由「黑名单命中/不误杀」迁移为「符号与关键词彻底不在位」，条数不减。
    """

    def test_keywords_tuple_is_retired(self):
        for sym in ("VIRTUAL_OR_PHONE_CAMERA_KEYWORDS", "is_virtual_or_phone_camera",
                    "pick_auto_camera", "AUTO_CAM_KEYWORDS", "rotate_backend_chain"):
            self.assertFalse(hasattr(cs, sym),
                             f"AD：{sym} 必须彻底退役（重命名为黑名单硬编码移除）")

    def test_phone_and_virtual_keywords_absent_from_source(self):
        csrc = Path(cs.__file__).read_text(encoding="utf-8")
        code = "\n".join(ln for ln in csrc.split("\n")
                         if not ln.strip().startswith("#"))
        for kw in ("magic", "荣耀", "honor", "virtual", "obs", "vcam",
                   "link to windows", "跨屏", "互联", "droidcam", "iriun"):
            self.assertNotIn(kw, code.lower(),
                             f"AD：代码行不得再含黑名单关键词「{kw}」")

    def test_physical_names_are_kept(self):
        """AD 反向护栏：物理设备名照常可被查名直启命中（黑名单退役≠选择失效）。"""
        cases = ["HD Camera", "Integrated Camera", "FaceTime HD Camera",
                 "USB2.0 HD UVC WebCam", "HD WebCam", "笔记本内置摄像头"]
        entries = [{"id": i, "name": nm} for i, nm in enumerate(cases)]
        for i, name in enumerate(cases):
            self.assertEqual(cs.match_camera_by_name(entries, name), i,
                             f"AD：物理设备名应可被查名直启命中（{name!r}）")

    def test_case_insensitive_and_defensive(self):
        """AD：查名匹配忽略大小写与首尾空格；空/None/非串防御不崩。"""
        entries = [{"id": 7, "name": "HD Camera"}]
        self.assertEqual(cs.match_camera_by_name(entries, "hD cAmErA"), 7)
        self.assertEqual(cs.match_camera_by_name(entries, "  HD Camera  "), 7)
        self.assertIsNone(cs.match_camera_by_name(entries, ""))
        self.assertIsNone(cs.match_camera_by_name(entries, None))
        self.assertIsNone(cs.match_camera_by_name(entries, "   "))


# ----------------------------------------------------------------------
# B. pick_camera_by_name：查名直启 / 未命中降级首项 / 空列表保持未启动（AD）
# ----------------------------------------------------------------------

class PickAutoCameraTest(unittest.TestCase):

    def test_empty_returns_none(self):
        self.assertIsNone(cs.pick_camera_by_name([], "HD Camera"),
                          "AD：空列表必须返回 None（保持未启动，绝不盲开）")
        self.assertIsNone(cs.pick_camera_by_name(None, "HD Camera"))

    def test_phone_named_device_matches_by_name_not_type(self):
        """AD：手机设备名同样按**名称精确匹配**（黑名单退役后不再按类型排除）。"""
        entries = [{"id": 0, "name": "荣耀Magic7 前置摄像头"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "荣耀Magic7 前置摄像头"), 0,
                         "AD：命中手机设备名 → 精准启动该设备（用户配置优先）")
        entries = [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
                   {"id": 1, "name": "荣耀Magic7 后置摄像头"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "荣耀Magic7 后置摄像头"), 1,
                         "AD：前后摄按名区分，命中的那颗被启动")

    def test_virtual_named_device_matches_by_name(self):
        entries = [{"id": 0, "name": "OBS Virtual Camera"},
                   {"id": 1, "name": "Virtual Camera"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "OBS Virtual Camera"), 0,
                         "AD：虚拟设备名照名命中（不再按类型过滤）")

    def test_miss_falls_back_to_first_entry(self):
        entries = [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
                   {"id": 1, "name": "HD Camera"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "不存在的相机"), 0,
                         "AD：未命中 → 降级列表首项（id=0）")

    def test_mixed_order_first_entry_wins_on_miss(self):
        entries = [{"id": 3, "name": "Integrated Camera"},
                   {"id": 0, "name": "Magic Camera"},
                   {"id": 2, "name": "USB Camera"}]
        self.assertEqual(cs.pick_camera_by_name(entries, ""), 3,
                         "AD：空名 → 列表首项（3，非最低索引 0）")

    def test_keyword_priority_retired_name_match_only(self):
        """AD：旧「内置关键词优先」排序依据随黑名单一并退役——只有名称命中或首项。"""
        entries = [{"id": 5, "name": "USB Camera"},
                   {"id": 4, "name": "HD Camera"},
                   {"id": 2, "name": "Integrated Camera"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "HD Camera"), 4,
                         "AD：按名命中 HD Camera（4）——不再有关键词优先/最低索引语义")
        self.assertEqual(cs.pick_camera_by_name(entries, "ghost"), 5,
                         "AD：未命中 → 列表首项 5")

    def test_unnamed_entries_are_handled(self):
        entries = [{"id": 2, "name": "摄像头 2"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "摄像头 2"), 2,
                         "AD：缺省显示名照名命中")
        entries = [{"id": 1}, {"id": 0, "name": None}]
        self.assertEqual(cs.pick_camera_by_name(entries, "Ghost"), 1,
                         "AD：name 缺失/None 条目不崩，降级首项 id=1")

    def test_reverse_guard_all_physical_keeps_first(self):
        entries = [{"id": 4, "name": "Camera B"}, {"id": 2, "name": "Camera A"}]
        self.assertEqual(cs.pick_camera_by_name(entries, ""), 4,
                         "AD 反向护栏：全物理设备 → 未命中降级取列表首项（非最低索引）")
        entries = [{"id": 2, "name": "Camera A"}, {"id": 4, "name": "Camera B"}]
        self.assertEqual(cs.pick_camera_by_name(entries, ""), 2,
                         "AD：首项 id 随列表序（不排序取最小）")


# ----------------------------------------------------------------------
# C. 设备启动指令状态机（server 级；零真开镜）
# ----------------------------------------------------------------------

class HandshakeStateMachineTest(unittest.TestCase):

    def test_wait_constant_retired(self):
        self.assertFalse(hasattr(hts, "PREFERRED_WAIT_SEC"),
                         "AD：PREFERRED_WAIT_SEC 等待窗常量必须彻底退役（启动零阻塞）")

    def test_handshake_flag_initial_and_set_by_commands(self):
        server = make_server()
        self.assertIs(bool(getattr(server, "_handshake_received", False)), False,
                      "AD：_handshake_received 初值 False（成员缺失=红态）")
        server._cameras = []
        server.udp_sender.reset_mock()
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:"])
        server._check_control_commands()
        self.assertTrue(bool(getattr(server, "_handshake_received", False)),
                        "AD：空名启动指令即刻置握手已达")
        self.assertEqual(server._preferred_camera_name, "",
                         "AD：空名不写入偏好名（语义=无记忆设备名）")

        server2 = make_server()
        server2.control_socket = FakeCtrlSock([b"SWITCH_CAMERA:2"])
        server2._switch_camera = mock.MagicMock()
        server2._check_control_commands()
        self.assertTrue(bool(getattr(server2, "_handshake_received", False)),
                        "AD：SWITCH_CAMERA:<id> 亦视为握手已达")

    def test_empty_list_reports_zero_camera_immediately(self):
        server = make_server()
        server._cameras = []
        server.udp_sender.reset_mock()
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:"])
        server._check_control_commands()
        inits = typed_packets(server, "init")
        self.assertTrue(inits, "AD：列表空 → 即刻回传 0 摄像头状态（init 报文）")
        self.assertEqual(inits[-1]["cameras"], [])
        self.assertEqual(int(inits[-1]["current_camera"]), -1)
        self.assertIsNone(server.cap, "AD：0 摄像头状态保持未启动（cap 恒 None）")

    def test_named_payload_starts_matched_device(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
                           {"id": 1, "name": "HD Camera"}]
        server._note_switch_target = mock.MagicMock()
        server._switch_camera = mock.MagicMock()
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:hd camera"])
        server._check_control_commands()
        server._note_switch_target.assert_called_once_with(1)
        server._switch_camera.assert_called_once_with(1)
        self.assertEqual(server._preferred_camera_name, "hd camera")

    def test_miss_and_empty_name_degrade_to_first_entry(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
                           {"id": 1, "name": "HD Camera"}]
        server._note_switch_target = mock.MagicMock()
        server._switch_camera = mock.MagicMock()
        server.control_socket = FakeCtrlSock(
            ["START_CAMERA_BY_NAME:不存在的相机".encode("utf-8")])
        server._check_control_commands()
        server._switch_camera.assert_called_once_with(0)

        server2 = make_server()
        server2._cameras = [{"id": 3, "name": "USB Cam"}]
        server2._note_switch_target = mock.MagicMock()
        server2._switch_camera = mock.MagicMock()
        server2.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:"])
        server2._check_control_commands()
        server2._switch_camera.assert_called_once_with(3)

    def test_legacy_command_routed_same_way(self):
        """AD：旧 `SET_PREFERRED_CAMERA:<名>` 兼容同路（协议零破坏）。"""
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 2, "name": "HD Camera"}]
        server._note_switch_target = mock.MagicMock()
        server._switch_camera = mock.MagicMock()
        server.control_socket = FakeCtrlSock([b"SET_PREFERRED_CAMERA:HD Camera"])
        server._check_control_commands()
        server._switch_camera.assert_called_once_with(2)
        self.assertTrue(server._handshake_received)

    def test_already_open_same_device_is_noop(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 2, "name": "HD Camera"}]
        server.current_camera_id = 2
        server.cap = make_open_cap()
        server._note_switch_target = mock.MagicMock()
        server._switch_camera = mock.MagicMock()
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:HD Camera"])
        server._check_control_commands()
        server._switch_camera.assert_not_called()
        self.assertTrue(server._handshake_received)

    def test_released_state_still_opens_on_explicit_command(self):
        """AD：命令即显式开启意图——RELEASE 粘滞标志只抑制自动重连，**永不阻断**显式启动指令
        （与 `_switch_camera` 的「粘滞标志不阻断显式 SWITCH」同一条项目铁律）。AC 的 release
        拦截已上提到桥侧 `_camera_release_intent`（自动补发路径短路），用户显式再开照发。"""
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 2, "name": "HD Camera"}]
        server.current_camera_id = 0
        server.cap = None
        server._camera_intentionally_released = True
        server._note_switch_target = mock.MagicMock()
        server._switch_camera = mock.MagicMock()
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:HD Camera"])
        server._check_control_commands()
        server._switch_camera.assert_called_once_with(2)
        self.assertTrue(server._handshake_received,
                        "AD：显式启动指令仍记握手已达（命令优先，锁存只管自动重连）")

    def test_reconnect_still_suppressed_after_release(self):
        """AD 反向护栏：RELEASE 粘滞标志**照旧抑制自动重连**（语义不扩体、零弱化）。"""
        server = make_server()
        server.current_camera_id = 2
        server.cap = None
        server._camera_intentionally_released = True
        with mock.patch.object(server.camera_selector, "_open_camera") as fake_open:
            server._attempt_reconnect()
        fake_open.assert_not_called()

    def test_start_command_opens_switch_path(self):
        """端到端：目标不同 → 直达 _switch_camera（含代际登记）。"""
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "HD Camera"}]
        server.current_camera_id = 0
        server.cap = make_open_cap()
        opened = []

        def _select(camera_id, backend_shift=0):
            opened.append(int(camera_id))
            return make_open_cap()

        server.camera_selector.select_camera.side_effect = _select
        server.control_socket = FakeCtrlSock([b"START_CAMERA_BY_NAME:HD Camera"])
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        self.assertEqual(opened, [1], "AD：启动指令查名直启目标设备 1")
        self.assertEqual(server.current_camera_id, 1)


# ----------------------------------------------------------------------
# D. 启动待命：chosen_id=None → 不打开任何摄像头
# ----------------------------------------------------------------------

class StandbyStartupTest(unittest.TestCase):
    """AD 等价改写：启动期恒零开镜（不再有首开/待命两态之分）——设备启动一律等
    Godot 的 `START_CAMERA_BY_NAME` 指令经主循环消费。本类保留「启动后零开镜 +
    0 摄像头状态回传 + 指令到达才开镜」三条主链断言。"""

    def _run_start(self, server, cmds, wmi_names=None):
        """start() 全链 mock；返回**开镜计数**（_acquire_camera_handle 入口被调用即计）。

        AD：设备启动指令经 `_start_camera_by_name` → `_switch_camera` →
        `_acquire_camera_handle(remember=True)` → `select_camera`，故两条获取路径
        （select_camera / _open_camera）都打桩并记账，覆盖全部分支。
        """
        open_calls = []

        def _record_and_open(*a, **kw):
            if a:
                open_calls.append(int(a[0]))
            return make_open_cap()

        server.camera_selector._open_camera.side_effect = _record_and_open
        server.camera_selector.select_camera.side_effect = _record_and_open
        server.control_socket = FakeCtrlSock(cmds)
        server._control_thread = None   # 无收线程：直接喂队列语义（FakeCtrlSock 直收）
        if wmi_names is None:
            wmi_names = {0: "荣耀Magic7 前置摄像头", 1: "荣耀Magic7 后置摄像头"}
        with mock.patch.object(server, "_start_watchdog"), \
             mock.patch.object(server, "_bind_control_socket", return_value=True), \
             mock.patch.object(server, "_start_control_recv_thread"), \
             mock.patch.object(server, "_get_all_camera_names",
                               return_value=wmi_names), \
             mock.patch.object(hts.threading, "Thread", _NoopThread), \
             mock.patch.object(hts.time, "sleep"), \
             mock.patch("mediapipe.tasks.python.BaseOptions", mock.MagicMock()), \
             mock.patch("mediapipe.tasks.python.vision.HandLandmarkerOptions",
                        mock.MagicMock()), \
             mock.patch("mediapipe.tasks.python.vision.HandLandmarker.create_from_options",
                        mock.MagicMock(return_value=mock.MagicMock())), \
             mock.patch.object(server, "_main_loop"), \
             mock.patch.object(server, "_cleanup"):
            server.start()
            # AD：启动序不再阻塞等指令——主循环首轮消费设备启动指令（_main_loop 已桩接，
            # 此处显式补一次 drain 等价表达）
            server._check_control_commands()
        if getattr(server, "frame_socket", None) is not None:
            try:
                server.frame_socket.close()
            except OSError:
                pass
            server.frame_socket = None
        return open_calls

    def test_all_phone_machine_starts_in_standby(self):
        """启动期**无任何指令**→ 零开镜（设备启停等 Godot 下发）。"""
        server = make_server()
        open_calls = self._run_start(server, [])
        self.assertEqual(open_calls, [],
                         f"AD：启动期必须零开镜（实测 {open_calls}；红态=[0] 盲开手机）")
        self.assertIsNone(server.current_camera_id,
                          "AD：启动后 current_camera_id=None（未启动设备）")
        self.assertIsNone(server.cap, "AD：启动后 cap=None（零设备占用）")
        inits = typed_packets(server, "init")
        self.assertTrue(inits, "AD：启动仍发 init#1（Godot 侧需要名单）")
        self.assertEqual(int(inits[0].get("current_camera")), -1,
                         "AD：init#1 current_camera=-1（未启动哨兵）")
        # 反向护栏：待命态 watchdog 轮询不得借重连打开任何设备
        with mock.patch.object(server, "_attempt_reconnect") as fake_reconnect, \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        fake_reconnect.assert_not_called()

    def test_phone_plus_hd_opens_hd_only(self):
        """AD 等价改写：名命中 HD Camera → 精准直启 id=1（手机设备不再被类型排除，
        而是因为**没被指定**才不开启）。"""
        server = make_server()
        open_calls = self._run_start(
            server, [b"START_CAMERA_BY_NAME:HD Camera"],
            wmi_names={0: "荣耀Magic7 前置摄像头", 1: "HD Camera"})
        self.assertEqual(open_calls, [1],
                         f"AD：名命中 HD → 只开 HD（实测 {open_calls}；红态=盲开 [0]）")
        self.assertEqual(server.current_camera_id, 1, "AD：启动设备=HD（非索引 0 手机）")


    def test_no_reconnect_when_no_camera_chosen(self):
        server = make_server()
        server.current_camera_id = None
        server.cap = None
        server._latest_frame = None
        with mock.patch.object(server, "_attempt_reconnect") as fake_reconnect, \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        fake_reconnect.assert_not_called()
        self.assertEqual(len(server.udp_sender.send.call_args_list), 1,
                         "AC：待命态 1Hz 心跳照发（camera_open=false 电平）")
        pkt = server.udp_sender.send.call_args_list[0].args[0]
        self.assertIs(pkt.get("camera_open"), False,
                      "AC：待命态心跳 camera_open=false")


# ----------------------------------------------------------------------
# E. GET_CAMERAS 空名单重扫（热插拔）
# ----------------------------------------------------------------------

class GetCamerasRescanTest(unittest.TestCase):

    def test_empty_rescan_calls_enumerate_step_and_sends_init(self):
        server = make_server()
        server._cameras = []
        fresh = [{"id": 1, "name": "HD Camera"}]
        server._enumerate_cameras_step = mock.MagicMock(return_value=(fresh, 1))
        server.current_camera_id = None
        server.control_socket = FakeCtrlSock([b"GET_CAMERAS"])
        server._check_control_commands()
        server._enumerate_cameras_step.assert_called_once()
        self.assertEqual(server._cameras, fresh,
                         "AC：空名单 GET_CAMERAS → 重扫刷新名单（热插拔识别）")
        inits = typed_packets(server, "init")
        self.assertTrue(inits, "AC：重扫后必发最新 init#1")

    def test_still_empty_resets_probe_and_respawns(self):
        server = make_server()
        server._cameras = []
        server._enum_probe_started = True      # 启动期已跑过一次的形态
        server._enumerate_cameras_step = mock.MagicMock(return_value=([], None))
        server._spawn_enum_probe_thread = mock.MagicMock(return_value=True)
        server.control_socket = FakeCtrlSock([b"GET_CAMERAS"])
        server._check_control_commands()
        self.assertFalse(server._enum_probe_started,
                         "AC：仍为空 → 复位一次性门（旧的「跑过一次不再扫」=热插拔失效根因）")
        server._spawn_enum_probe_thread.assert_called_once()

    def test_nonempty_cache_keeps_legacy_path(self):
        server = make_server()
        server._cameras = [{"id": 2, "name": "USB Cam"}]
        server.current_camera_id = 2
        server.cap = None
        server._enumerate_cameras_step = mock.MagicMock(
            side_effect=AssertionError("非空名单不得重扫"))
        server.control_socket = FakeCtrlSock([b"GET_CAMERAS"])
        server._check_control_commands()
        inits = typed_packets(server, "init")
        self.assertTrue(inits, "AC 反向护栏：非空名单照发既有 init（零重扫，语义不扩体）")
        self.assertEqual([c["id"] for c in inits[0]["cameras"]], [2])


# ----------------------------------------------------------------------
# F. 红线门：默认零开镜桩
# ----------------------------------------------------------------------

class RedlineProbeGateTest(unittest.TestCase):

    def test_startup_and_lazy_probe_open_default_none(self):
        server = make_server()
        import os
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("AA_ALLOW_REAL_CAMERA", None)
            self.assertIsNone(server._startup_probe_open(0),
                              "AC 红线：默认启动枚举桩零开镜")
            self.assertIsNone(server._lazy_probe_open(0),
                              "AC 红线：默认懒探测桩零开镜")

    def test_source_anchors(self):
        src = (_GESTURE_DIR / "gesture_runtime" / "hand_tracking_server.py").read_text(
            encoding="utf-8") if (_GESTURE_DIR / "gesture_runtime").exists() else \
            (_GESTURE_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")
        self.assertIn("_handshake_received", src, "AD：源码锚——握手已达状态位")
        self.assertIn("START_CAMERA_BY_NAME:", src,
                      "AD：源码锚——查名直启主协议命令")
        self.assertIn("pick_camera_by_name", src,
                      "AD：源码锚——查名直启纯函数调用")
        # 代码行判定（留痕注释会引用退役标识符——项目既有 `_code_only` 同款口径）
        code = "\n".join(ln for ln in src.split("\n")
                         if not ln.strip().startswith("#"))
        self.assertNotIn("PREFERRED_WAIT_SEC", code,
                         "AD：源码锚——等待窗常量必须退役（启动不再阻塞）")
        self.assertNotIn("pick_auto_camera", code,
                         "AD：源码锚——黑名单自动选择必须退役")
        csrc = Path(cs.__file__).read_text(encoding="utf-8")
        self.assertIn("def pick_camera_by_name(", csrc,
                      "AD：源码锚——查名直启纯函数在位")
        ccode = "\n".join(ln for ln in csrc.split("\n")
                          if not ln.strip().startswith("#"))
        self.assertNotIn("is_virtual_or_phone_camera", ccode,
                         "AD：源码锚——黑名单判定纯函数必须退役")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
