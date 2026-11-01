#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AA（W4 摄像头生命周期域，spec §7）——python 侧红测（全 mock 零真摄像头）。

零摄像头纪律（spec §2.1 红线）：CameraSelector / UDPSender / cv.VideoCapture / 枚举 /
WMI 查询全部 mock 或桩接——**不打开、不枚举任何真实设备**；控制口只用本机高位回环
（端口由内核分配，不占 9876/9877/9878）。**绝不设 AA_ALLOW_REAL_CAMERA**（本文件
无任何真实枚举路径）。

断言口径（spec §7.4/§7.5）：
  R4-a2 / W4-8：启动期开镜次数上界 = 1（仅记忆设备首开；启动枚举零 CAP 探测开镜）
  R4-a     ：bind 先于枚举 + 偏好命令 bind 后被消费 → 记忆设备被选中（python 半侧；
              「bind 前不发」的桥侧半测在 tests/test_aa_camera_lifecycle.gd）
  R4-c     ：_attempt_reconnect 有界（预算 ≤10）+ 指数退避单调不减 ≤5s +
              达预算转 FAILED 上报 camera_error（恰一条）+ 冷却按实际重连目标 id 登记
  R4-d     ：SWITCH 取消语义——排队中被取代的旧 SWITCH 零 open；在飞 SWITCH 遇新
              代际立即中止并 release 已开句柄
  R4-e     ：同 id SWITCH no-op（零 release / 零 reopen）
  R4-f     ：无帧看门狗——读帧时间戳老化 → 超时释放旧句柄 + 触发重连（根治永久冻结）
             回修2（W4-P2-2）：按窗口计数——同窗高频自旋不触发，跨 3 个真实超阈窗才触发
  回修3    ：懒探测线程 open_fn 受门桩 _lazy_probe_open（与启动桩同一把 AA_ALLOW_REAL_CAMERA
             门；默认态零开镜、worker 注入受门桩）——全程计数假体，绝不真枚举/真开镜
  R4-g     ：SET_RESOLUTION/SET_FPS 3 参式先切后设（res/fps 只落到目标设备）
  R4-h     ：~/.hand_tracking/camera_config.json 生产路径零写入（save_camera_id 停写）
  W4-11    ：_open_camera 每后端单次超时（坏设备单后端不挂数秒）

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import os
import socket
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import camera_selector  # noqa: E402
import hand_tracking_server as hts  # noqa: E402


# ======================================================================
# 夹具（selftest_z_camera_release / test_server_camera_logic 同款风格）
# ======================================================================

def make_open_cap(w=640, h=480, fps=30.0):
    """「已打开」mock cap：isOpened True、get 回读一致、release 记录调用。"""
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
    cap.read.return_value = (True, mock.MagicMock(name="frame"))
    return cap


def make_server():
    """被测服务器：CameraSelector/UDPSender 打桩（不触真实设备与端口）。"""
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    return server


def typed_packets(sender_mock, msg_type):
    return [p for p in (c.args[0] for c in sender_mock.send.call_args_list
                        if c.args and isinstance(c.args[0], dict))
            if isinstance(p, dict) and p.get("type") == msg_type]


def camera_errors(sender_mock):
    return typed_packets(sender_mock, "camera_error")


class _NoopThread:
    """线程替身：不真起线程（start() 全链 mock 用；target 不执行）。"""

    def __init__(self, *a, **k):
        pass

    def start(self):
        pass

    def is_alive(self):
        return False

    def join(self, timeout=None):
        pass


# ======================================================================
# 批次 AD（spec §4.2.2-1）：启动期开镜次数上界 = 0（冷启动只枚举零开镜）
# ======================================================================

class StartupOpenBoundTest(unittest.TestCase):
    """start() 全链 mock：断言**启动期开镜恰 0 次**（冷启动只枚举物理设备、
    绝不打开任何摄像头），cap/current_camera_id 恒 None，init#1 current_camera=-1。

    历史口径留痕：R4-a2/W4-8 上界=1（仅记忆设备首开）；AC 上界=1（非黑名单缺省）。
    批次 AD 拍板降为 0——设备启停一律等 Godot 下发 START_CAMERA_BY_NAME 指令。
    """

    def _run_start(self, server, preferred_name=""):
        """把 start() 除「开镜」外全部桩接，返回 open 调用记录。"""
        open_calls = []

        def _fake_open(camera_id, width=640, height=480, backend_shift=0, **kw):
            open_calls.append(int(camera_id))
            return make_open_cap()

        server.camera_selector._open_camera.side_effect = _fake_open
        server._preferred_camera_name = preferred_name
        with mock.patch.object(server, "_start_watchdog"), \
             mock.patch.object(server, "_bind_control_socket", return_value=True), \
             mock.patch.object(server, "_start_control_recv_thread"), \
             mock.patch.object(server, "_get_all_camera_names",
                               return_value={0: "Magic Phone", 1: "HD"}), \
             mock.patch.object(server, "_acquire_camera_handle") as fake_acquire, \
             mock.patch.object(hts.threading, "Thread", _NoopThread), \
             mock.patch.object(hts.time, "sleep"), \
             mock.patch("mediapipe.tasks.python.BaseOptions",
                        mock.MagicMock()), \
             mock.patch("mediapipe.tasks.python.vision.HandLandmarkerOptions",
                        mock.MagicMock()), \
             mock.patch("mediapipe.tasks.python.vision.HandLandmarker.create_from_options",
                        mock.MagicMock(return_value=mock.MagicMock())), \
             mock.patch.object(server, "_main_loop"), \
             mock.patch.object(server, "_cleanup"):
            server.start()
            fake_acquire.assert_not_called()
        if getattr(server, "frame_socket", None) is not None:
            try:
                server.frame_socket.close()
            except OSError:
                pass
            server.frame_socket = None
        # AD 判据：open_calls 即**全进程开镜计数**（枚举探测桩零开镜 + 冷启动零首开）
        return open_calls

    def test_startup_opens_nothing_memory_device_pending(self):
        """记忆设备名在档也不得启动期自开——等 Godot 指令（AD §4.2.2-1）。"""
        server = make_server()
        open_calls = self._run_start(server, preferred_name="HD")
        self.assertEqual(open_calls, [],
                         f"AD：启动期开镜必须恰 0 次（实际 {open_calls}）")
        self.assertIsNone(server.current_camera_id,
                          "AD：启动后 current_camera_id 恒 None（未启动设备）")
        self.assertIsNone(server.cap, "AD：启动后 cap 恒 None（零开镜）")
        inits = [p for p in typed_packets(server.udp_sender, "init") if "cameras" in p]
        self.assertTrue(inits, "启动必发 init#1")
        self.assertEqual(inits[0]["current_camera"], -1,
                         "AD：init#1 current_camera=-1（未启动哨兵）")

    def test_startup_enumeration_zero_probe_opens(self):
        """启动枚举零真实开镜——enumerate 协议调用保留，但 open 桩零次：
        候选条目回落 WMI 显示名合成（零设备激活）。

        批次 AD 等价改写：返回值第二项（旧 auto 缺省）恒 None——「自动缺省设备」
        概念随黑名单一并退役（设备名一律由 Godot 下发）；断言条数只增不减。
        """
        server = make_server()
        server._get_all_camera_names = mock.MagicMock(
            return_value={0: "Magic Phone", 1: "HD"})
        cameras, auto = server._enumerate_cameras_step()
        server.camera_selector._open_camera.assert_not_called()
        self.assertEqual([c["name"] for c in cameras], ["Magic Phone", "HD"],
                         "启动候选名单=WMI 显示名合成（零开镜构建）")
        self.assertIsNone(auto,
                          "AD：auto 缺省退役恒 None（等价自选设备路径不存在）")
        # 手机名单同样照常入列（黑名单退役，不再按类型猜测）
        server3 = make_server()
        server3._get_all_camera_names = mock.MagicMock(
            return_value={0: "荣耀Magic7 前置摄像头"})
        cameras3, auto3 = server3._enumerate_cameras_step()
        self.assertEqual([c["id"] for c in cameras3], [0],
                         "AD：手机摄像头照常入候选名单（黑名单退役）")
        self.assertIsNone(auto3, "AD：auto 恒 None（不再有自动开镜候选）")
        server3.camera_selector._open_camera.assert_not_called()
        # WMI 空 → 懒探测挂起（GET_CAMERAS 独立线程补全）
        server2 = make_server()
        server2._get_all_camera_names = mock.MagicMock(return_value={})
        cameras2, _auto2 = server2._enumerate_cameras_step()
        self.assertEqual(cameras2, [], "WMI 空 → 启动候选空")
        self.assertTrue(getattr(server2, "_enum_probe_pending", False),
                        "WMI 空 → 懒探测挂起标志在位（红态=缺失）")
        server2.camera_selector._open_camera.assert_not_called()

    def test_no_preference_still_opens_nothing(self):
        """无记忆（存档空）同样零开镜——绝无「缺省候选自动开」通路。"""
        server = make_server()
        open_calls = self._run_start(server, preferred_name="")
        self.assertEqual(open_calls, [],
                         f"AD：无记忆时启动期仍零开镜（实际 {open_calls}）")
        self.assertIsNone(server.current_camera_id)

    def test_startup_sequence_has_no_wait_window(self):
        """读码锚：启动前序已无握手等待窗/首开选择（AD §4.2.2-1）。"""
        import inspect
        self.assertFalse(hasattr(hts.HandTrackingServer, "_wait_for_preference"),
                         "AD：5.0s 握手等待窗函数必须彻底退役（启动零阻塞）")
        self.assertFalse(hasattr(hts.HandTrackingServer, "_choose_initial_camera_id"),
                         "AD：首开选择函数必须彻底退役（设备启动等 Godot 指令）")
        src = inspect.getsource(hts.HandTrackingServer._startup_sequence)
        self.assertNotIn("self._wait_for_preference(", src,
                         "AD：启动前序不得再调用握手等待窗")
        self.assertNotIn("self._choose_initial_camera_id(", src,
                         "AD：启动前序不得再调用首开选择")
        self.assertIn('"current_camera": -1', src,
                      "AD：init#1 current_camera 恒发 -1 未启动哨兵")
        self.assertIn("return None", src, "AD：启动前序返回恒为 None（无首开目标）")


# ======================================================================
# R4-a（python 半侧）：bind 先于枚举 + 偏好命令 bind 后被消费 → 记忆设备选中
# ======================================================================

class PreferredAfterBindTest(unittest.TestCase):
    """bind 前移（读码锚）+ bind 后经真实回环送达的设备启动指令立即查名直启。

    批次 AD（spec §4.2.2-3/4）等价改写：等待窗 `_wait_for_preference` 与首开选择
    `_choose_initial_camera_id` 已退役——设备启停改由 9878 控制命令
    `START_CAMERA_BY_NAME:<名>` 直达 `_start_camera_by_name` → `_switch_camera`。
    断言口径迁移为「bind 后命令被消费 → 直启记忆设备 CAP」（断言数不减）。

    桥侧「bind 前不发」半测见 tests/test_aa_camera_lifecycle.gd 段 A（三档
    8s/15s/35s 启动耗时注入）。
    """

    def test_bind_precedes_enumeration_in_startup_sequence(self):
        import inspect
        src = inspect.getsource(hts.HandTrackingServer._startup_sequence)
        i_bind = src.index("_bind_control_socket")
        i_enum = src.index("_enumerate_cameras_step")
        self.assertLess(i_bind, i_enum,
                        "bind 必须前移至枚举之前（接住桥早期下发的设备启动指令）")
        self.assertIn("_start_control_recv_thread", src[:i_enum],
                      "bind 即起收线程（启动期命令照收）")

    def test_preference_consumed_after_bind_selects_memory_device(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "Magic Phone"}, {"id": 1, "name": "HD"}]
        opened = []

        def _select(camera_id, backend_shift=0):
            opened.append(int(camera_id))
            return make_open_cap()

        server.camera_selector.select_camera.side_effect = _select
        ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ctrl.bind(("127.0.0.1", 0))   # 高位回环：不占 9878
        server.control_socket = ctrl
        server.control_port = ctrl.getsockname()[1]
        server._start_control_recv_thread()
        try:
            sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sender.sendto("START_CAMERA_BY_NAME:HD".encode("utf-8"),
                          ("127.0.0.1", server.control_port))
            sender.close()
            # 等收线程入队 + drain 执行（等价于「bind 后命令被消费」）
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline and not server._preferred_camera_name:
                server._check_control_commands()
                time.sleep(0.02)
            self.assertEqual(server._preferred_camera_name, "HD",
                             "bind 后设备启动指令必须被消费")
            with mock.patch.object(hts.time, "sleep"):
                server._check_control_commands()
            self.assertEqual(opened, [1],
                             f"记忆设备命中：直启 CAP 1（id 1），非缺省 0（实际 {opened}）")
            self.assertEqual(server.current_camera_id, 1, "前置：当前设备即记忆设备")
        finally:
            server._control_recv_stop = True
            try:
                ctrl.close()
            except OSError:
                pass
            if getattr(server, "_control_thread", None) is not None:
                server._control_thread.join(timeout=2.0)


# ======================================================================
# R4-c：_attempt_reconnect 有界（预算 + 退避 + FAILED 上报 + 冷却按目标 id）
# ======================================================================

class ReconnectBudgetTest(unittest.TestCase):
    """恒失败 open_fn → 重连调用有界、退避单调 ≤5s、恰一条 camera_error、
    冷却表键=实际重连目标 id。"""

    def _drain(self, server, loops=20):
        """循环调用重连；每次注入「速率门/冷却已过期」以测预算本身。"""
        delays = []
        for _ in range(loops):
            server._reconnect_next_at = 0.0          # 测试注入：速率门到期
            server._switch_fail_cooldown.clear()     # 测试注入：冷却到期
            before = time.time()
            server._attempt_reconnect()
            nxt = getattr(server, "_reconnect_next_at", 0.0)
            if nxt > before:
                delays.append(nxt - before)
        return delays

    def test_reconnect_attempts_bounded_and_reports_camera_error(self):
        server = make_server()
        server.current_camera_id = 1
        server.cap = None
        server._latest_frame = None
        server.camera_selector._open_camera.return_value = None   # 恒失败
        with mock.patch.object(hts.time, "sleep"):
            delays = self._drain(server, loops=20)
        budget = getattr(hts, "RECONNECT_BUDGET", None)
        self.assertIsNotNone(budget, "RECONNECT_BUDGET 常量缺失（红态）")
        max_calls = budget * hts.RECONNECT_MAX_RETRIES
        calls = server.camera_selector._open_camera.call_count
        self.assertLessEqual(
            calls, max_calls,
            f"重连开镜次数必须有界（预算 {budget} 次调用 × {hts.RECONNECT_MAX_RETRIES} 内轮；"
            f"实际 {calls} 次——旧实现无界风暴）")
        errs = camera_errors(server.udp_sender)
        self.assertEqual(len(errs), 1,
                         f"达预算必须上报 camera_error 恰一条（实际 {len(errs)}）")
        self.assertIn("预算", str(errs[0].get("reason", "")) if errs else "")
        self.assertTrue(getattr(server, "_reconnect_failed", False),
                        "达预算转 FAILED 态（_reconnect_failed）")

    def test_reconnect_backoff_monotonic_and_capped(self):
        server = make_server()
        server.current_camera_id = 1
        server.cap = None
        server._latest_frame = None
        server.camera_selector._open_camera.return_value = None
        with mock.patch.object(hts.time, "sleep"):
            delays = self._drain(server, loops=12)
        self.assertGreaterEqual(len(delays), 3, "至少产生 3 次退避延迟")
        cap_s = float(getattr(hts, "RECONNECT_BACKOFF_MAX_SEC", 0.0))
        self.assertGreater(cap_s, 0.0, "RECONNECT_BACKOFF_MAX_SEC 常量缺失（红态）")
        prev = 0.0
        for i, d in enumerate(delays):
            self.assertGreaterEqual(d, prev - 0.05,
                                    f"退避须单调不减（第 {i} 次 {d:.2f} < {prev:.2f}）")
            self.assertLessEqual(d, cap_s + 0.5,
                                 f"退避上限 ≤{cap_s}s（第 {i} 次 {d:.2f}s）")
            prev = d

    def test_cooldown_registered_by_actual_reconnect_target(self):
        server = make_server()
        server.current_camera_id = 7   # 实际重连目标
        server.cap = None
        server._latest_frame = None
        server.camera_selector._open_camera.return_value = None
        with mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        self.assertIn(7, server._switch_fail_cooldown,
                      "重连失败冷却必须按**实际重连目标 id** 登记（修 :1833 错位）")


# ======================================================================
# R4-d：SWITCH 取消语义（目标 id 单一真值 + 代际号）
# ======================================================================

class SwitchCancelTest(unittest.TestCase):
    def test_queued_superseded_switch_zero_open(self):
        """收线程先到 SWITCH:1 后到 SWITCH:2 → 旧目标 id=1 零 open，最终设备=2。"""
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"},
                           {"id": 2, "name": "C"}]
        server.current_camera_id = 0
        server.cap = make_open_cap()
        opened = []

        def _select(camera_id, backend_shift=0):
            opened.append(int(camera_id))
            return make_open_cap()

        server.camera_selector.select_camera.side_effect = _select
        ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ctrl.bind(("127.0.0.1", 0))
        server.control_socket = ctrl
        server.control_port = ctrl.getsockname()[1]
        server._start_control_recv_thread()
        try:
            sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            dest = ("127.0.0.1", server.control_port)
            sender.sendto(b"SWITCH_CAMERA:1", dest)
            sender.sendto(b"SWITCH_CAMERA:2", dest)
            sender.close()
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline and len(server._cmd_queue) < 2:
                time.sleep(0.02)
            self.assertEqual(len(server._cmd_queue), 2, "前置：两条 SWITCH 均已入队")
            with mock.patch.object(hts.time, "sleep"):
                server._check_control_commands()
            self.assertNotIn(1, opened,
                             f"被取代的旧目标 id=1 必须零 open（实际 {opened}）")
            self.assertIn(2, opened, "最新目标 id=2 必须被执行")
            self.assertEqual(server.current_camera_id, 2, "最终设备==id 2")
        finally:
            server._control_recv_stop = True
            try:
                ctrl.close()
            except OSError:
                pass
            if getattr(server, "_control_thread", None) is not None:
                server._control_thread.join(timeout=2.0)

    def test_inflight_switch_aborts_on_new_generation_and_releases(self):
        """在飞 SWITCH 期间新 SWITCH 到达（代际递增）→ 旧 SWITCH 立即中止、
        已开句柄被 release、不采纳为当前设备。"""
        server = make_server()
        if not hasattr(server, "_note_switch_target"):
            self.fail("W4-3：目标 id 单一真值登记 _note_switch_target 缺失（红态）")
            return
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"},
                           {"id": 2, "name": "C"}]
        server.current_camera_id = 0
        server.cap = None
        inflight_cap = make_open_cap()
        server._note_switch_target(1)

        def _select(camera_id, backend_shift=0):
            # 模拟打开期间新 SWITCH:2 到达（收线程在接收点递增代际）
            server._note_switch_target(2)
            return inflight_cap

        server.camera_selector.select_camera.side_effect = _select
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertIsNone(server.cap,
                          "代际过期：在飞开关取的句柄必须被 release（cap 归零）")
        inflight_cap.release.assert_called()
        self.assertNotEqual(server.current_camera_id, 1,
                            "代际过期的 SWITCH 不得被采纳为当前设备")
        opened_events = typed_packets(server.udp_sender, "camera_opened")
        self.assertEqual(opened_events, [], "中止路径不得发 camera_opened")


class SameIdNoopTest(unittest.TestCase):
    """R4-e：同 id SWITCH → 零 release / 零 reopen。"""

    def test_same_id_switch_is_noop(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
        cap0 = make_open_cap()
        server.current_camera_id = 1
        server.cap = cap0
        server._camera_stream_open = True
        server.camera_selector.select_camera.return_value = make_open_cap()   # 旧实现误走 reopen 的干净红
        server._switch_camera(1)
        server.camera_selector.select_camera.assert_not_called()
        server.camera_selector._open_camera.assert_not_called()
        cap0.release.assert_not_called()
        self.assertIs(server.cap, cap0, "同 id no-op：句柄对象不变")
        self.assertEqual(typed_packets(server.udp_sender, "camera_closed"), [],
                         "同 id no-op：零 camera_closed（零 release 语义）")


# ======================================================================
# R4-f：无帧看门狗（读帧时间戳老化 → 释放 + 重连）
# ======================================================================

class FrameWatchdogTest(unittest.TestCase):
    def _stale_server(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}]
        server.current_camera_id = 0
        server.cap = make_open_cap()
        # 真 ndarray：红态（旧实现）走完整处理路径不崩，红在「看门狗不动作」
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        server._last_camera_read_time = time.time() - 60.0   # 读帧线程挂死形态
        server._no_frame_count = 0
        server._cap_configuring = False
        server.landmarker = mock.MagicMock(name="landmarker")   # detect 返回可安全迭代
        server.landmarker.detect_for_video.return_value = \
            mock.Mock(hand_landmarks=None, handedness=None)
        server.flip_image = False
        server._camera_stream_open = True   # 冻结真实形态：画面卡死时流真值为开
        return server

    def test_stale_frame_triggers_release_and_reconnect(self):
        # 批次 AA 回修2（W4-P2-2）等价改写：语义由「连续 n_trip 次主循环迭代」修正为
        # 「连续 n_trip 个超阈窗各计 1」——本测以 _no_frame_last_mark 回退注入逐窗推进
        #（旧实现不读该成员，注入无害；触发判据与期望值零弱化）。
        server = self._stale_server()
        old_cap = server.cap
        n_trip = int(getattr(hts, "NO_FRAME_TRIP_COUNT", 0) or 0)
        self.assertGreater(n_trip, 0, "NO_FRAME_TRIP_COUNT 常量缺失（红态）")
        with mock.patch.object(server, "_attempt_reconnect") as fake_re:
            # 阈值（默认 3 窗）内不动作
            for i in range(n_trip):
                if i > 0:
                    server._no_frame_last_mark = \
                        getattr(server, "_no_frame_last_mark", 0.0) - hts.CAMERA_TIMEOUT_SECONDS
                server._process_frame()
                if i < n_trip - 1:
                    self.assertFalse(old_cap.release.called,
                                     f"第 {i + 1} 个超阈窗内不得释放（防低帧率误判）")
        self.assertTrue(old_cap.release.called,
                        "看门狗超时必须 release 旧句柄（根治永久冻结）")
        self.assertIsNone(server.cap, "释放后 cap 归零")
        self.assertIsNone(server._latest_frame, "陈旧帧清除（不再喂旧帧）")
        self.assertTrue(fake_re.called,
                        "看门狗触发后必须发起重连（不再「零重连冻结」）")
        closed = typed_packets(server.udp_sender, "camera_closed")
        self.assertTrue(closed and closed[-1]["reason"] == "device_lost",
                        f"看门狗须发 camera_closed(device_lost)：{closed}")

    def test_high_freq_spin_does_not_trip_watchdog(self):
        """回修2（W4-P2-2）红测：冻结期主循环高速自旋——同一超阈窗内 n_trip 次迭代
        只计 1（距上次计数 ≥CAMERA_TIMEOUT_SECONDS 才 +1），不得触发。
        红态锚（旧实现）：逐迭代 +1 → 第 n_trip 次迭代即 trip（实际触发阈 ≈3s 而非 9s）。"""
        server = self._stale_server()
        old_cap = server.cap
        n_trip = int(hts.NO_FRAME_TRIP_COUNT)
        with mock.patch.object(server, "_attempt_reconnect") as fake_re:
            for _ in range(n_trip + 2):   # 高频自旋：同窗内连打 n_trip+2 次主循环
                server._process_frame()
                self.assertFalse(old_cap.release.called,
                                 "同一超阈窗内高频自旋不得触发看门狗（按窗计数；红态=逐迭代计数已 trip）")
        self.assertFalse(fake_re.called, "同窗自旋零重连（误杀慢启动/瞬时停帧设备的根因）")

    def test_watchdog_trips_only_after_three_real_windows(self):
        """回修2（W4-P2-2）：缩窗真时钟（CAMERA_TIMEOUT_SECONDS=0.05s）——同窗两次迭代
        只计 1；跨 3 个真实超阈窗才触发；第 2 窗末不触发。"""
        server = self._stale_server()
        old_cap = server.cap
        with mock.patch.object(hts, "CAMERA_TIMEOUT_SECONDS", 0.05), \
                mock.patch.object(server, "_attempt_reconnect") as fake_re:
            server._process_frame()   # 窗1 计 1
            server._process_frame()   # 窗1 自旋（同窗不重复计数）
            self.assertFalse(old_cap.release.called,
                             "窗1 内自旋第二次不得计数（红态=旧实现已 trip）")
            time.sleep(0.06)          # 跨窗2
            server._process_frame()
            self.assertFalse(old_cap.release.called,
                             "第 2 个超阈窗末不得触发（需连续 3 窗；红态=旧实现此处已 trip）")
            time.sleep(0.06)          # 跨窗3
            server._process_frame()
        self.assertTrue(old_cap.release.called, "跨 3 个真实超阈窗后才触发看门狗")
        self.assertTrue(fake_re.called, "触发后按预算发起重连")

    def test_fresh_frame_does_not_trip_watchdog(self):
        server = self._stale_server()
        server._last_camera_read_time = time.time()   # 读帧新鲜
        cap = server.cap
        with mock.patch.object(server, "_attempt_reconnect") as fake_re:
            server._process_frame()
        self.assertFalse(cap.release.called, "新鲜帧零看门狗动作")
        self.assertFalse(fake_re.called, "新鲜帧零重连")


# ======================================================================
# R4-g：res/fps 仅落到目标设备（3 参式先切后设）
# ======================================================================

class ResFpsTargetTest(unittest.TestCase):
    def test_set_resolution_switches_before_applying(self):
        server = make_server()
        server.current_camera_id = 1
        server.cap = make_open_cap(640, 480)
        events = []

        def _select(camera_id, backend_shift=0):
            events.append(("switch", int(camera_id)))
            new_cap = make_open_cap(800, 600)
            orig_set = new_cap.set
            new_cap.set = lambda prop, val: (
                events.append(("set", prop)), orig_set(prop, val))[1]
            return new_cap

        server.camera_selector.select_camera.side_effect = _select
        with mock.patch.object(hts.time, "sleep"):
            server.control_socket = mock.MagicMock()
            server.control_socket.recvfrom.return_value = \
                (b"SET_RESOLUTION:2:800x600", ("127.0.0.1", 1))
            server._check_control_commands()
        kinds = [e[0] for e in events]
        self.assertIn("switch", kinds, "3 参式 id≠当前必须先切到目标设备")
        self.assertIn("set", kinds, "切换完成后 res 必须落到目标设备 cap")
        self.assertLess(kinds.index("switch"), kinds.index("set"),
                        "res 必须在切换完成后才落到（目标）设备 cap")


# ======================================================================
# R4-h：camera_config.json 生产路径零写入
# ======================================================================

class CameraConfigNoWriteTest(unittest.TestCase):
    def test_select_camera_does_not_write_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "camera_config.json"
            sel = camera_selector.CameraSelector(config_file=str(cfg))
            with mock.patch.object(sel, "_open_camera",
                                   return_value=make_open_cap()):
                sel.select_camera(1)
            self.assertFalse(cfg.exists(),
                             "生产路径不得写 camera_config.json（CAP 索引记忆停写）")
            sel.save_camera_id(3)
            self.assertFalse(cfg.exists(),
                             "save_camera_id 必须为停写 no-op（脏状态根除）")

    def test_get_saved_camera_id_read_path_preserved(self):
        """读取路径保留（兼容旧档）：手工落旧档 → 仍可读。"""
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "camera_config.json"
            cfg.write_text('{"camera_id": 2}', encoding="utf-8")
            sel = camera_selector.CameraSelector(config_file=str(cfg))
            self.assertEqual(sel.get_saved_camera_id(), 2, "旧档读取路径保留")


# ======================================================================
# W4-11：_open_camera 每后端单次超时
# ======================================================================

class OpenBackendTimeoutTest(unittest.TestCase):
    def test_slow_backend_aborted_at_timeout(self):
        """坏设备单后端挂数秒 → 超时放弃该后端，_open_camera 整体不挂数秒。"""
        if not hasattr(camera_selector, "OPEN_BACKEND_TIMEOUT_SEC"):
            self.fail("W4-11：OPEN_BACKEND_TIMEOUT_SEC 常量缺失（红态：单后端无超时）")
            return
        timeout = 0.5
        slow_opened = []

        def slow_vc(*args, **kwargs):
            time.sleep(2.5)          # 模拟坏设备构造挂死
            cap = make_open_cap()
            slow_opened.append(cap)
            return cap

        with mock.patch.object(camera_selector, "OPEN_BACKEND_TIMEOUT_SEC",
                               timeout), \
             mock.patch.object(camera_selector.cv, "VideoCapture",
                               side_effect=slow_vc):
            t0 = time.monotonic()
            cap = camera_selector.CameraSelector._open_camera(3, 640, 480)
            elapsed = time.monotonic() - t0
        self.assertLess(elapsed, 2.0,
                        f"单后端超时必须截断（实测 {elapsed:.2f}s——旧实现无超时挂数秒）")
        self.assertIsNone(cap, "超时后端视为失败（不返回未验证句柄）")
        # 等迟到线程自弃（abandoned 标志 → 迟到成功句柄自行 release）
        time.sleep(2.6)
        for c in slow_opened:
            self.assertTrue(c.release.called,
                            "超时被弃的句柄迟到打开必须自行 release（零泄漏）")


# ======================================================================
# 回修3（W4-P2-3）：懒探测线程 open_fn 红线门（与启动桩同一把 AA_ALLOW_REAL_CAMERA 门）
# ======================================================================

class LazyProbeGateTest(unittest.TestCase):
    """W4-P2-3：_enum_probe_worker 的 open_fn 必须是受门桩 _lazy_probe_open（默认态零开镜），
    旧实现直注 _acquire_probe_open（无门）→ 退化机器 GET_CAMERAS 懒探测线程无门真开 CAP 0..3。
    全程计数假体：_acquire_probe_open 被 mock，**绝不真枚举/真开镜**。"""

    def test_lazy_probe_open_default_returns_none_without_open(self):
        server = make_server()
        server._acquire_probe_open = mock.MagicMock(name="probe_open")
        with mock.patch.dict(os.environ, {}):
            os.environ.pop("AA_ALLOW_REAL_CAMERA", None)
            if not hasattr(server, "_lazy_probe_open"):
                self.fail("回修3：_lazy_probe_open 受门桩缺失（红态：懒探测 open_fn 无门直开 CAP）")
            self.assertIsNone(server._lazy_probe_open(0),
                              "默认态（未设 AA_ALLOW_REAL_CAMERA）受门桩返回 None（零开镜）")
        server._acquire_probe_open.assert_not_called()

    def test_lazy_probe_open_gate_set_passes_through(self):
        """设门路径在位（只断言代码路径：_acquire_probe_open 已 mock，不执行真开镜）。"""
        server = make_server()
        sentinel = object()
        server._acquire_probe_open = mock.MagicMock(name="probe_open", return_value=sentinel)
        with mock.patch.dict(os.environ, {"AA_ALLOW_REAL_CAMERA": "1"}):
            self.assertIs(server._lazy_probe_open(2), sentinel,
                          "AA_ALLOW_REAL_CAMERA=1 时受门桩经 _acquire_probe_open 放行（真机复验路径）")
        server._acquire_probe_open.assert_called_once_with(2)

    def test_enum_probe_worker_wires_gated_open_fn(self):
        """worker 注入面：enumerate_cameras 收到的 open_fn 必须是受门桩；默认态零真实开镜。"""
        server = make_server()
        captured = {}

        def _fake_enum(max_index=3, open_fn=None, **kw):
            captured["open_fn"] = open_fn
            return [(i, False) for i in range(max_index + 1)]

        with mock.patch.object(hts, "enumerate_cameras", side_effect=_fake_enum), \
                mock.patch.dict(os.environ, {}):
            os.environ.pop("AA_ALLOW_REAL_CAMERA", None)
            server._acquire_probe_open = mock.MagicMock(name="probe_open")
            server._enum_probe_worker()
        self.assertEqual(captured.get("open_fn"), getattr(server, "_lazy_probe_open", None),
                         "懒探测 worker 注入的 open_fn 必须是受门桩 _lazy_probe_open"
                         "（红态=无门 _acquire_probe_open 直注）")
        server._acquire_probe_open.assert_not_called()


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
