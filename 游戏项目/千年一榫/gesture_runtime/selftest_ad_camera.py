#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AD 批次二专项自测：真实摄像头生命周期重构（spec §4.2）。

零摄像头纪律（摄像头红线）：全程 mock——`cv.VideoCapture` 一律
`mock.patch.object` 打桩、WMI 枚举桩化、UDPSender/选择器替身；**绝不真实构造
VideoCapture、绝不枚举真实设备、绝不 bind 真实端口**。红线护栏断言内建
（E 段：VideoCapture 构造调用次数=桩计数，真机路径恒受门）。

断言口径（spec §4.2.1/§4.2.2/§4.2.3）：
  A. 黑名单硬编码彻底移除：`camera_selector` 无 `VIRTUAL_OR_PHONE_CAMERA_KEYWORDS`/
     `is_virtual_or_phone_camera`/`pick_auto_camera`/`AUTO_CAM_KEYWORDS`，且源码不含
     手机/虚拟关键词字面量；`hand_tracking_server` 无黑名单引用；`gesture_bridge.gd`
     无 `VIRTUAL_OR_PHONE_KEYWORDS`/`is_virtual_or_phone_camera_name`/
     `_pick_non_phone_camera_id`。
  B. 冷启动只枚举零开镜：`start()` 前序完成时 `cap is None`、`current_camera_id is None`、
     句柄开镜入口（`_acquire_camera_handle`）零调用；init#1 `current_camera == -1`。
  C. 查名直启：`pick_camera_by_name` 纯函数（命中忽略大小写/首尾空格 → 命中 id；
     未命中/空名 → 首项 id；空列表 → None 保持未启动）；server 侧命令
     `START_CAMERA_BY_NAME:<名>` 命中目标 id 直启、未命中降级首项、列表空回传 0 摄像头
     状态且零开镜；旧命令 `SET_PREFERRED_CAMERA:<名>` 兼容同路（协议零破坏）。
  D. 单一稳定后端：`_open_camera` 仅 `cv.CAP_DSHOW` 单后端一次性直启（零 MSMF/零重复
     open）、MJPG + BUFFERSIZE=1 配置在位；`rotate_backend_chain` 退役。
  E. 红线门：启动桩/懒探测桩默认零开镜（AA_ALLOW_REAL_CAMERA 未设），且本测试全段
     真 VideoCapture 构造计数恒为 0。

判绿：末行输出 SELFTEST PASSED，退出码 0。
"""
import socket
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

_GESTURE_DIR = Path(__file__).resolve().parent
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


def make_server(cameras=None):
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    if cameras is not None:
        server._cameras = list(cameras)
    return server


def typed_packets(server, msg_type):
    return [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                        if c.args and isinstance(c.args[0], dict))
            if isinstance(p, dict) and p.get("type") == msg_type]


ENTRIES = [{"id": 0, "name": "荣耀Magic7 跨屏互联"},
           {"id": 2, "name": "HD Camera"},
           {"id": 3, "name": "USB Cam"}]


def code_only(source: str) -> str:
    """剥整行注释后再断语句（留痕注释会引用被退役标识符/关键词——`test_ac_batch2_camera`
    的 `_code_only` 同款口径）。"""
    return "\n".join(ln for ln in source.split("\n")
                     if not ln.strip().startswith("#"))


# ----------------------------------------------------------------------
# A. 黑名单硬编码彻底移除（spec §4.2.1）
# ----------------------------------------------------------------------

class BlacklistRemovedTest(unittest.TestCase):
    """批次 AD（spec §4.2.1）：`is_virtual_or_phone_camera` 与
    `VIRTUAL_OR_PHONE_CAMERA_KEYWORDS` 及其全部消费者（黑名单自动选择）彻底退役——
    不再靠名称字符串猜测设备类型，严格遵循用户配置与时序驱动。"""

    def test_selector_blacklist_symbols_gone(self):
        for sym in ("VIRTUAL_OR_PHONE_CAMERA_KEYWORDS", "is_virtual_or_phone_camera",
                    "pick_auto_camera", "AUTO_CAM_KEYWORDS", "rotate_backend_chain"):
            self.assertFalse(hasattr(cs, sym),
                             f"AD：camera_selector.{sym} 必须彻底退役（红态=仍在位）")

    def test_selector_source_has_no_blacklist_literals(self):
        """源码断言只断**可执行代码行**（留痕注释会引用被退役关键词，与
        `test_ac_batch2_camera._code_only` 同口径）。"""
        src = code_only((_GESTURE_DIR / "camera_selector.py").read_text(encoding="utf-8"))
        for kw in ("magic", "荣耀", "honor", "obs", "vcam", "droidcam", "iriun",
                   "link to windows", "跨屏", "互联"):
            self.assertNotIn(kw, src.lower(),
                             f"AD：camera_selector 代码行不得再含黑名单关键词「{kw}」")

    def test_server_source_has_no_blacklist_consumer(self):
        src = code_only((_GESTURE_DIR / "hand_tracking_server.py").read_text(encoding="utf-8"))
        for sym in ("is_virtual_or_phone_camera", "pick_auto_camera",
                    "VIRTUAL_OR_PHONE_CAMERA_KEYWORDS"):
            self.assertNotIn(sym, src, f"AD：server 代码行不得再引用黑名单符号 {sym}")

    def test_bridge_source_has_no_blacklist(self):
        br = code_only((_GESTURE_DIR.parent / "autoload" / "gesture_bridge.gd").read_text(
            encoding="utf-8"))
        for sym in ("VIRTUAL_OR_PHONE_KEYWORDS", "is_virtual_or_phone_camera_name",
                    "_pick_non_phone_camera_id"):
            self.assertNotIn(sym, br, f"AD：gesture_bridge.gd 代码行不得再含黑名单符号 {sym}")


# ----------------------------------------------------------------------
# B. 冷启动只枚举零开镜（spec §4.2.2-1）
# ----------------------------------------------------------------------

class ColdStartNoOpenTest(unittest.TestCase):
    """启动期只枚举物理设备列表；绝不调用 `_acquire_camera_handle`；保持
    `cap = None`、`current_camera_id = None`；init#1 `current_camera = -1`。"""

    def _run_start(self, server, cameras=None):
        names = {0: "HD Camera", 2: "USB Cam"} if cameras is None else cameras
        with mock.patch.object(server, "_start_watchdog"), \
             mock.patch.object(server, "_bind_control_socket", return_value=True), \
             mock.patch.object(server, "_start_control_recv_thread"), \
             mock.patch.object(server, "_get_all_camera_names", return_value=names), \
             mock.patch.object(server, "_acquire_camera_handle") as fake_acquire, \
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
        if getattr(server, "frame_socket", None) is not None:
            try:
                server.frame_socket.close()
            except OSError:
                pass
            server.frame_socket = None
        return fake_acquire

    def test_start_leaves_camera_closed(self):
        server = make_server()
        fake_acquire = self._run_start(server)
        self.assertIsNone(server.cap, "AD：冷启动结束 cap 必须恒为 None（零开镜）")
        self.assertIsNone(server.current_camera_id,
                          "AD：冷启动结束 current_camera_id 必须恒为 None（未启动）")
        fake_acquire.assert_not_called()
        server.camera_selector._open_camera.assert_not_called()
        server.camera_selector.select_camera.assert_not_called()

    def test_init1_reports_not_started_sentinel(self):
        server = make_server()
        self._run_start(server)
        inits = [p for p in typed_packets(server, "init") if "cameras" in p]
        self.assertTrue(inits, "冷启动必发 init#1（含 cameras 列表）")
        self.assertEqual(inits[0]["current_camera"], -1,
                         "AD：未启动设备时 init#1 必须报告 current_camera=-1")
        self.assertEqual([c["name"] for c in inits[0]["cameras"]], ["HD Camera", "USB Cam"],
                         "AD：init#1 候选列表=物理设备枚举（零开镜构建）")

    def test_start_with_empty_device_list_sends_zero_camera_state(self):
        server = make_server()
        fake_acquire = self._run_start(server, cameras={})
        self.assertEqual(server._cameras, [], "无物理设备 → 候选列表空")
        inits = [p for p in typed_packets(server, "init") if "cameras" in p]
        self.assertTrue(inits)
        self.assertEqual(inits[0]["cameras"], [], "0 摄像头状态：cameras=[]")
        self.assertEqual(inits[0]["current_camera"], -1, "0 摄像头状态：current_camera=-1")
        fake_acquire.assert_not_called()
        self.assertIsNone(server.cap)


# ----------------------------------------------------------------------
# C. 查名直启（spec §4.2.2-3/4）
# ----------------------------------------------------------------------

class PickCameraByNamePureTest(unittest.TestCase):
    """`pick_camera_by_name` 纯函数（无副作用，绝不打开设备）。"""

    def test_hit_ignores_case_and_spaces(self):
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, "hd camera"), 2)
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, "  USB CAM  "), 3)
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, "荣耀magic7 跨屏互联"), 0,
                         "AD：手机设备名同样按名称精确命中（黑名单退役，不再按类型猜测）")

    def test_miss_or_empty_falls_back_to_first_entry(self):
        self.assertIsNone(cs.match_camera_by_name(ENTRIES, "Ghost Cam"),
                          "前置：纯匹配函数未命中返回 None")
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, "Ghost Cam"), 0,
                         "AD：未命中 → 降级首项物理设备")
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, ""), 0, "AD：空名 → 降级首项")
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, None), 0, "AD：None 名 → 降级首项")
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, "   "), 0, "AD：纯空格 → 降级首项")

    def test_numeric_residual_is_not_a_cap_index(self):
        self.assertIsNone(cs.match_camera_by_name(ENTRIES, "2"),
                          "AD：数字残留不再按 CAP 索引解释（禁止依赖 CAP 索引）")
        self.assertEqual(cs.pick_camera_by_name(ENTRIES, "2"), 0,
                         "AD：数字残留视同未命中 → 降级首项（不盲开索引 2）")

    def test_empty_list_returns_none(self):
        self.assertIsNone(cs.pick_camera_by_name([], "HD Camera"))
        self.assertIsNone(cs.pick_camera_by_name(None, "HD Camera"))
        self.assertIsNone(cs.pick_camera_by_name([], ""), "空列表 → None（保持未启动）")

    def test_dirty_entries_defensive(self):
        entries = [{"name": "No Id"}, {"id": 2, "name": "HD Camera"}]
        self.assertEqual(cs.pick_camera_by_name(entries, "Ghost"), 2,
                         "脏条目（无 id）跳过，降级取首个可解析条目")
        self.assertIsNone(cs.pick_camera_by_name([{"name": "No Id"}], "Ghost"),
                          "全部条目无有效 id → None（防御）")


class StartCameraByNameCommandTest(unittest.TestCase):
    """server 级：`START_CAMERA_BY_NAME:<名>` 查名直启/降级/0 摄像头三态。"""

    def _server_with_entries(self, entries=ENTRIES):
        server = make_server(cameras=entries)
        return server

    def test_hit_starts_matched_device(self):
        server = self._server_with_entries()
        with mock.patch.object(server, "_switch_camera") as fake_switch:
            server._execute_control_command("START_CAMERA_BY_NAME:hd camera")
        fake_switch.assert_called_once_with(2)
        self.assertTrue(server._handshake_received, "握手已达状态位置真（等待窗唤醒语义）")
        self.assertEqual(server._preferred_camera_name, "hd camera")

    def test_miss_starts_first_device(self):
        server = self._server_with_entries()
        with mock.patch.object(server, "_switch_camera") as fake_switch:
            server._execute_control_command("START_CAMERA_BY_NAME:不存在的相机")
        fake_switch.assert_called_once_with(0, )
        self.assertEqual(int(fake_switch.call_args.args[0]), 0, "未命中 → 首项物理设备 id=0")

    def test_empty_name_starts_first_device(self):
        server = self._server_with_entries()
        with mock.patch.object(server, "_switch_camera") as fake_switch:
            server._execute_control_command("START_CAMERA_BY_NAME:")
        fake_switch.assert_called_once()
        self.assertEqual(int(fake_switch.call_args.args[0]), 0, "空名 → 首项物理设备")

    def test_empty_list_reports_zero_camera_and_no_open(self):
        server = make_server(cameras=[])
        server.udp_sender.reset_mock()
        with mock.patch.object(server, "_switch_camera") as fake_switch, \
             mock.patch.object(server, "_acquire_camera_handle") as fake_acquire:
            server._execute_control_command("START_CAMERA_BY_NAME:HD Camera")
        fake_switch.assert_not_called()
        fake_acquire.assert_not_called()
        self.assertIsNone(server.cap, "列表空 → 保持未启动（cap 恒 None）")
        inits = [p for p in typed_packets(server, "init") if "cameras" in p]
        self.assertTrue(inits, "列表空 → 必回传 0 摄像头状态（init 报文）")
        self.assertEqual(inits[-1]["cameras"], [])
        self.assertEqual(inits[-1]["current_camera"], -1)

    def test_legacy_preferred_command_still_routed(self):
        server = self._server_with_entries()
        with mock.patch.object(server, "_switch_camera") as fake_switch:
            server._execute_control_command("SET_PREFERRED_CAMERA: USB Cam")
        fake_switch.assert_called_once()
        self.assertEqual(int(fake_switch.call_args.args[0]), 3,
                         "AD：旧命令格式兼容同一查名直启路径（协议零破坏）")

    def test_already_open_same_device_is_noop(self):
        server = self._server_with_entries()
        server.current_camera_id = 2
        server.cap = make_open_cap()
        with mock.patch.object(server, "_switch_camera") as fake_switch:
            server._execute_control_command("START_CAMERA_BY_NAME:HD Camera")
        fake_switch.assert_not_called()
        self.assertTrue(server.cap is not None, "同设备已开 → 零 release/零 reopen")


# ----------------------------------------------------------------------
# D. 单一稳定后端直启（spec §4.2.3）
# ----------------------------------------------------------------------

class SingleBackendOpenTest(unittest.TestCase):
    """Windows 单后端 `cv.CAP_DSHOW` 一次性直启 + MJPG + BUFFERSIZE=1；
    `CAP_MSMF` 轮换与 `rotate_backend_chain` 彻底退役。全段 VideoCapture 为 mock。"""

    def test_open_camera_uses_single_dshow_backend_once(self):
        with mock.patch.object(cs.cv, "VideoCapture") as fake_vc:
            fake_vc.return_value.isOpened.return_value = True
            fake_vc.return_value.read.return_value = (True, mock.MagicMock())
            cap = cs.CameraSelector._open_camera(2, 640, 480)
        self.assertIsNotNone(cap, "单后端成功即返回句柄")
        self.assertEqual(fake_vc.call_count, 1, "AD：一次性直启（零后端轮换）")
        backend = fake_vc.call_args.args[1] if len(fake_vc.call_args.args) > 1 else None
        self.assertEqual(backend, cs.cv.CAP_DSHOW, "AD：Windows 恒 CAP_DSHOW 单后端")
        ms = [c for c in fake_vc.call_args_list
              if len(c.args) > 1 and c.args[1] == cs.cv.CAP_MSMF]
        self.assertEqual(ms, [], "AD：CAP_MSMF 轮换彻底退役")

    def test_open_camera_sets_mjpg_and_buffersize(self):
        with mock.patch.object(cs.cv, "VideoCapture") as fake_vc:
            fake_vc.return_value.isOpened.return_value = True
            fake_vc.return_value.read.return_value = (True, mock.MagicMock())
            cap = cs.CameraSelector._open_camera(1, 640, 480)
        sets = [c.args[0] for c in cap.set.call_args_list if c.args]
        self.assertIn(cs.cv.CAP_PROP_FOURCC, sets, "AD：MJPG 配置在位")
        self.assertIn(cs.cv.CAP_PROP_BUFFERSIZE, sets, "AD：BUFFERSIZE=1 配置在位")
        buf_calls = [c.args for c in cap.set.call_args_list
                     if c.args and c.args[0] == cs.cv.CAP_PROP_BUFFERSIZE]
        self.assertEqual(buf_calls[0][1], 1, "AD：BUFFERSIZE 恒为 1（消除排队延迟）")

    def test_open_camera_failure_returns_none_single_attempt(self):
        with mock.patch.object(cs.cv, "VideoCapture") as fake_vc:
            fake_vc.return_value.isOpened.return_value = False
            cap = cs.CameraSelector._open_camera(3, 640, 480)
            calls = fake_vc.call_count
        self.assertIsNone(cap)
        self.assertEqual(calls, 1, "AD：失败不换后端重开（一次性直启，零指示灯闪烁）")

    def test_probe_open_single_backend(self):
        with mock.patch.object(cs.cv, "VideoCapture") as fake_vc:
            fake_vc.return_value.isOpened.return_value = True
            cs._probe_open_backends(2)
            calls = fake_vc.call_count
        self.assertEqual(calls, 1, "AD：探测开镜同为单后端一次（无 MSMF 轮换）")
        self.assertEqual(fake_vc.call_args.args[1], cs.cv.CAP_DSHOW)


# ----------------------------------------------------------------------
# E. 红线护栏
# ----------------------------------------------------------------------

class RedlineGateTest(unittest.TestCase):
    """默认零开镜桩恒返回 None；本测试真 VideoCapture 构造恒 0 次。"""

    def test_startup_probe_stub_gated_by_default(self):
        server = make_server()
        server._acquire_probe_open = mock.MagicMock(name="probe_open")
        with mock.patch.dict("os.environ", {}, clear=False):
            import os as _os
            saved = _os.environ.pop("AA_ALLOW_REAL_CAMERA", None)
            try:
                self.assertIsNone(server._startup_probe_open(0),
                                  "红线：默认零开镜桩恒 None")
                self.assertIsNone(server._lazy_probe_open(1),
                                  "红线：懒探测桩同门恒 None")
            finally:
                if saved is not None:
                    _os.environ["AA_ALLOW_REAL_CAMERA"] = saved
        server._acquire_probe_open.assert_not_called()
        server._acquire_camera_handle = mock.MagicMock(name="acquire")
        self.assertIsNone(server._startup_probe_open(2))
        server._acquire_camera_handle.assert_not_called()

    def test_no_real_videocapture_constructed_in_suite(self):
        """整段自测的真 VideoCapture 构造计数恒 0（全 mock 隔离证明）。"""
        with mock.patch.object(cs.cv, "VideoCapture") as spy:
            cs.pick_camera_by_name(ENTRIES, "HD Camera")
            cs.build_camera_entries([(0, True)], {0: "HD Camera"})
            self.assertEqual(spy.call_count, 0,
                             "红线：纯函数路径不得构造任何 VideoCapture")


def main():
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for cls in (BlacklistRemovedTest, ColdStartNoOpenTest, PickCameraByNamePureTest,
                StartCameraByNameCommandTest, SingleBackendOpenTest, RedlineGateTest):
        suite.addTests(loader.loadTestsFromTestCase(cls))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    if result.wasSuccessful():
        print("SELFTEST PASSED")
        return 0
    print("SELFTEST FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
