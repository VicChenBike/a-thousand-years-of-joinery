#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Z（Z-B 波，spec §4-验收③④ python 侧）——摄像头生命周期自测。

零摄像头纪律：CameraSelector/UDPSender/cv 全 mock、不打开真实设备；控制口走本机
高位回环（端口由内核分配，不占 9876/9878）。

断言口径（spec §4）：
  ③ 首开阻塞期命令接收与执行解耦（Z4-③）——收线程独立于主循环：注入 RELEASE_CAMERA
     → ≤1s 内实际释放（camera_closed 事件 + cap.release + 流真值翻 false）；
     RELEASE 清空在积命令队列（先行未执行命令作废，顺序语义确定）。
  ④ 句柄获取单入口（Z4-④）——_acquire_camera_handle 唯一入口在位；切换到设备 1 后
     重连/回退路径对旧设备 0 的 open 调用数 == 0（旧 range(3) 扫开红态锚）；
     SWITCH 在飞期间晚到的 RELEASE 于打开完成后就地释放（_release_latch）。
  ① 支撑件——父/宿主进程看门狗纯函数 _watchdog_should_exit（owner 优先、父兜底）
     与 _pid_alive（Windows OpenProcess 语义；禁用 os.kill(pid,0) 族防误杀）。

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import os
import socket
import subprocess
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import hand_tracking_server as hts  # noqa: E402


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
    return cap


def make_server():
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


class ReleaseDuringFirstOpenTest(unittest.TestCase):
    """③ 命令接收与首开解耦：收线程独立，RELEASE ≤1s 实际生效。"""

    def _has_recv_thread(self, test) -> bool:
        if not hasattr(hts.HandTrackingServer, "_start_control_recv_thread"):
            test.fail("Z4-③：收线程入口 _start_control_recv_thread 缺失（红态）")
            return False
        return True

    def test_release_takes_effect_within_1s(self):
        if not self._has_recv_thread(self):
            return
        server = make_server()
        ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ctrl.bind(("127.0.0.1", 0))   # 高位回环：不占 9878
        server.control_socket = ctrl
        server.control_port = ctrl.getsockname()[1]
        server._start_control_recv_thread()
        try:
            # 首开阻塞期形态：cap 已开 + camera_opened 已发（start() 中段语义）
            cap = make_open_cap()
            server.current_camera_id = 0
            server.cap = cap
            server._emit_camera_opened()
            self.assertTrue(server._camera_stream_open, "前置：流已开启")
            t0 = time.monotonic()
            sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sender.sendto(b"RELEASE_CAMERA", ("127.0.0.1", server.control_port))
            sender.close()
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline and server._camera_stream_open:
                time.sleep(0.02)
            elapsed = time.monotonic() - t0
            self.assertFalse(server._camera_stream_open,
                             "RELEASE 后流真值必须翻 false（实际仍 open）")
            self.assertLessEqual(elapsed, 1.0,
                                 f"RELEASE 须 ≤1s 实际生效（实测 {elapsed:.3f}s）")
            closed = typed_packets(server.udp_sender, "camera_closed")
            self.assertEqual(len(closed), 1, f"camera_closed 恰一次: {closed}")
            self.assertEqual(closed[0]["reason"], "release")
            cap.release.assert_called()
            self.assertTrue(server._camera_intentionally_released)
            self.assertTrue(server._release_latch,
                            "RELEASE 置闩：在飞 SWITCH 完成后须就地释放")
        finally:
            server._control_recv_stop = True
            try:
                ctrl.close()
            except OSError:
                pass
            if getattr(server, "_control_thread", None) is not None:
                server._control_thread.join(timeout=2.0)

    def test_release_clears_pending_queue(self):
        """RELEASE 到达即清空在积命令队列（先行未执行命令作废）。"""
        if not self._has_recv_thread(self):
            return
        server = make_server()
        ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ctrl.bind(("127.0.0.1", 0))
        server.control_socket = ctrl
        server.control_port = ctrl.getsockname()[1]
        server._start_control_recv_thread()
        try:
            server.current_camera_id = 0
            server.cap = make_open_cap()
            server._emit_camera_opened()   # 流开启 → 可等待 RELEASE 生效边沿
            sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            dest = ("127.0.0.1", server.control_port)
            sender.sendto(b"GET_CAMERAS", dest)
            time.sleep(0.15)   # 让收线程把 GET_CAMERAS 落入队列（模拟首开阻塞期积压）
            server.udp_sender.send.reset_mock()
            sender.sendto(b"RELEASE_CAMERA", dest)
            sender.close()
            deadline = time.monotonic() + 1.0
            while time.monotonic() < deadline and server._camera_stream_open:
                time.sleep(0.02)
            # 主循环随后到达：清队后 drain 不得执行被作废的 GET_CAMERAS
            sends_before = server.udp_sender.send.call_count
            server._check_control_commands()
            self.assertEqual(len(server._cmd_queue), 0, "RELEASE 后队列必须为空")
            self.assertEqual(server.udp_sender.send.call_count, sends_before,
                             "被 RELEASE 作废的在积命令不得再被执行")
        finally:
            server._control_recv_stop = True
            try:
                ctrl.close()
            except OSError:
                pass
            if getattr(server, "_control_thread", None) is not None:
                server._control_thread.join(timeout=2.0)


class SwitchLatchTest(unittest.TestCase):
    """④ SWITCH 在飞期间晚到的 RELEASE：打开完成后就地释放（不残留新设备句柄）。"""

    def test_release_latch_honored_after_switch_open(self):
        if not hasattr(hts.HandTrackingServer, "_acquire_camera_handle"):
            self.fail("Z4-④：句柄单入口 _acquire_camera_handle 缺失（红态）")
            return
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
        good = make_open_cap()

        def open_and_release_arrives(camera_id, backend_shift=0):
            # 打开完成瞬间 RELEASE 到达（收线程置闩——模拟命令交错）
            server._release_latch = True
            return good

        server.camera_selector.select_camera.side_effect = open_and_release_arrives
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertIsNone(server.cap, "闩生效：打开完成后必须就地释放（cap 归零）")
        good.release.assert_called()
        self.assertFalse(server._camera_stream_open,
                         "闩生效期间不得发 camera_opened（流真值保持 false）")


class SingleEntryNoOldDeviceOpenTest(unittest.TestCase):
    """④ 切换到设备 1 后：重连/回退路径对旧设备 0 的 open 调用数 == 0。"""

    def test_no_old_device_open_after_switch_then_reconnect(self):
        if not hasattr(hts.HandTrackingServer, "_acquire_camera_handle"):
            self.fail("Z4-④：句柄单入口 _acquire_camera_handle 缺失（红态）")
            return
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
        opened_switch = []
        good = make_open_cap()
        server.camera_selector.select_camera.side_effect = \
            lambda camera_id, backend_shift=0: (opened_switch.append(camera_id), good)[1]
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertEqual(server.current_camera_id, 1, "前置：已切换到设备 1")
        self.assertEqual(opened_switch, [1], "前置：切换只 open 目标设备 1")
        # 断电重连路径：全部打开失败 → 旧实现 range(3) 回退扫开 0/1/2（红态=0 出现）
        opened_reconnect = []
        server.camera_selector._open_camera.side_effect = \
            lambda *a, **k: (opened_reconnect.append(a[0]), None)[1]
        with mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        self.assertNotIn(0, opened_reconnect,
                         f"切换到设备 1 后，重连/回退路径不得 open 旧设备 0（实际 {opened_reconnect}）")
        self.assertTrue(all(i == 1 for i in opened_reconnect),
                        f"重连只允许对当前设备 1 发起（实际 {opened_reconnect}）")
        self.assertTrue(len(opened_reconnect) >= 1, "同设备重连尝试保留（单入口内建）")


class LatchReassertTest(unittest.TestCase):
    """③ 自查回修：在飞窗口（重连/SET_RESOLUTION）内晚到的 RELEASE → 主循环下一帧复查就地释放。"""

    def test_latch_reassert_in_process_frame(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
        server.current_camera_id = 1
        server.cap = make_open_cap()
        server._emit_camera_opened()
        self.assertTrue(server._camera_stream_open, "前置：流已开启（在飞开镜落位形态）")
        server._release_latch = True   # 收线程在无 cap 窗口内置闩（重连/重开期间 RELEASE 晚到）
        with mock.patch.object(server, "_attempt_reconnect"):
            server._process_frame()
        self.assertIsNone(server.cap, "闩复查：主循环下一帧必须释放落位的在飞开镜")
        self.assertFalse(server._camera_stream_open, "闩复查：流真值翻 false（camera_closed 边沿）")
        closed = typed_packets(server.udp_sender, "camera_closed")
        self.assertTrue(closed and closed[-1]["reason"] == "release",
                        f"闩复查须发 camera_closed(reason=release)：{closed}")


class WatchdogTest(unittest.TestCase):
    """① 父/宿主进程看门狗纯函数 + pid 存活判定。"""

    def test_watchdog_should_exit_pure(self):
        if not hasattr(hts.HandTrackingServer, "_watchdog_should_exit"):
            self.fail("Z4-①：看门狗纯函数 _watchdog_should_exit 缺失（红态）")
            return
        alive_table = {10, 999}
        alive = lambda p: p in alive_table  # noqa: E731
        sw = hts.HandTrackingServer._watchdog_should_exit
        self.assertTrue(sw(10, 5555, alive), "owner 已死 → 退出（编辑器硬杀主判据）")
        self.assertFalse(sw(9999, 999, alive), "owner 存活 → 不退（父状态不否决）")
        self.assertTrue(sw(9999, None, alive), "无 owner + 父已死 → 退出（父兜底）")
        self.assertFalse(sw(10, None, alive), "无 owner + 父存活 → 不退")

    def test_pid_alive(self):
        if not hasattr(hts, "_pid_alive"):
            self.fail("Z4-①：_pid_alive 缺失（红态；Windows 须走 OpenProcess 语义）")
            return
        self.assertTrue(hts._pid_alive(os.getpid()), "自身进程恒存活")
        proc = subprocess.Popen([sys.executable, "-c", "pass"])
        proc.wait(timeout=15)
        self.assertFalse(hts._pid_alive(proc.pid), "已收割子进程判死")


class CleanupOrderTest(unittest.TestCase):
    """Z-B 回修 P2-b：退出序——running=False → join 读取线程(≈1.5s) → 再释放摄像头。

    旧形态：看门狗路径先 _release_camera_only() 再 _cleanup()（join 在释放后）——
    读取线程持旧 cap 引用的 ~1s 窄窗（spec §4 回修 P2-b）。
    """

    def test_shutdown_release_joins_before_release(self):
        if not hasattr(hts.HandTrackingServer, "_shutdown_release"):
            self.fail("P2-b：退出序入口 _shutdown_release 缺失（红态）")
            return
        server = make_server()
        events = []

        class FakeThread:
            def __init__(self, tag):
                self._tag = tag

            def is_alive(self):
                return True

            def join(self, timeout=None):
                events.append(("join_" + self._tag, timeout))

        server._stream_thread = FakeThread("stream")
        server._read_thread = FakeThread("read")
        server.cap = make_open_cap()
        orig_release = server._release_camera_only

        def wrapped_release():
            self.assertTrue(any(e[0].startswith("join") for e in events),
                            "P2-b：释放摄像头之前必须先 join 工作线程（读取线程持旧 cap 窄窗根除）")
            events.append(("release", None))
            orig_release()

        server._release_camera_only = wrapped_release
        server._shutdown_release()
        order = [e[0] for e in events]
        self.assertEqual(order, ["join_stream", "join_read", "release"],
                         f"P2-b：退出序=停循环→join(stream/read)→release（实际 {order}）")
        read_join = [e for e in events if e[0] == "join_read"]
        self.assertTrue(read_join and read_join[0][1] is not None
                        and read_join[0][1] >= 1.5,
                        f"P2-b：读取线程 join 超时 ≥1.5s（实际 {read_join}）")
        self.assertFalse(server.running, "P2-b：退出序先停 running 循环")

    def test_watchdog_uses_shutdown_release(self):
        """读码断言：看门狗退出路径经 _shutdown_release（先 join 后释放），不再裸 release。"""
        if not hasattr(hts.HandTrackingServer, "_watchdog_loop"):
            self.fail("看门狗 _watchdog_loop 缺失（红态）")
            return
        import inspect
        src = inspect.getsource(hts.HandTrackingServer._watchdog_loop)
        self.assertIn("_shutdown_release", src,
                      "P2-b：看门狗退出路径走 _shutdown_release（join→release→cleanup）")
        self.assertNotIn("self._release_camera_only()", src,
                         "P2-b：看门狗不再在 join 之前裸调 _release_camera_only")

    def test_cleanup_joins_before_camera_release(self):
        """SHUTDOWN 常规路径：_cleanup 内 join（stream/read）先于 _cleanup_camera。"""
        import inspect
        src = inspect.getsource(hts.HandTrackingServer._cleanup)
        self.assertLess(src.index("_read_thread.join"), src.index("_cleanup_camera()"),
                        "P2-b：_cleanup 顺序=先 join 读取线程、后 _cleanup_camera（规范序）")


class SwitchProbeRaceGuardTest(unittest.TestCase):
    """Z-B 回修 P3-c：_switch_camera 探测段 self.cap 并发置 None → 早退不抛 AttributeError。"""

    def test_probe_section_guard_when_cap_released(self):
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
        good = make_open_cap()
        server.camera_selector.select_camera.side_effect = \
            lambda camera_id, backend_shift=0: good

        def release_during_open(*_a, **_k):
            # 模拟收线程并发 RELEASE：_emit_camera_opened 调用点（探测段之前）cap 被置 None
            server.cap = None

        server._emit_camera_opened = release_during_open
        with mock.patch.object(hts.time, "sleep"):
            try:
                server._switch_camera(1)
            except AttributeError as e:
                self.fail(f"P3-c：探测段对 None cap 调 set/get 抛 AttributeError（被命令层静默吞）：{e}")
        self.assertIsNone(server.cap, "并发释放语义保持（cap 为 None 不复活）")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
