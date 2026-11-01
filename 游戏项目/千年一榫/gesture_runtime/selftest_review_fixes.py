#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""独立审查修复批（python 手势域）——自测（2026-09-26）。

零摄像头纪律：全 mock/桩，不枚举 CAP 设备，不设 AA_ALLOW_REAL_CAMERA；
控制口走本机高位回环（内核分配端口，不占 9876/9878）。

断言口径（审查确认 5 项 bug）：
  ① P0 建线唯一：`_ensure_capture_threads` 幂等（flag 守卫，两次调用只建一次；
     未进运行态不落线）；start 成功段 / _switch_camera 成功段 /
     _attempt_reconnect 成功段三处统一调用——首开失败后经 SWITCH/重连打开成功
     不再漏建线（`_latest_frame` 恒 None → 看门狗 3×3s 释放/重开永动循环根除）。
  ② P1 cap 读写竞态：读线程每次 `cap.read()` 持 `_camera_lock`（锁外 read vs
     锁内 release 竞态根除；读线程持锁期不取其他锁，无死锁面；release 等待
     read 完成有界）。
  ③ P3 吞异常：`_execute_control_command` 的 `except Exception` 记一行日志
     后继续（不再 pass 静默）。
  ④ P2 心跳停发：收线程兼职周期心跳 `_maybe_send_heartbeat`（不新建线程）——
     主循环被 SWITCH/重连阻塞 >5s 时桥 NO_PACKET_TIMEOUT_SEC=5.0 不再误判
     UNAVAILABLE；包格式与现心跳完全一致；主循环刚发过包则不重复补发。
  ⑤ P3 launcher kill 无 wait：`reap_server` = wait → 超时 kill → 再 wait →
     仍超时再 kill 兜底（防句柄泄漏）；main 游戏退出后收割改走该函数。

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import contextlib
import inspect
import io
import socket
import subprocess
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import hand_tracking_server as hts  # noqa: E402
import launcher  # noqa: E402


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


def _close_frame_socket(server):
    if getattr(server, "frame_socket", None) is not None:
        try:
            server.frame_socket.close()
        except OSError:
            pass
        server.frame_socket = None


# ======================================================================
# ① P0 建线唯一：_ensure_capture_threads 幂等 + 三成功段统一调用
# ======================================================================

class EnsureCaptureThreadsTest(unittest.TestCase):

    def test_ensure_capture_threads_exists_and_idempotent(self):
        if not hasattr(hts.HandTrackingServer, "_ensure_capture_threads"):
            self.fail("P0：_ensure_capture_threads 缺失（红态）")
            return
        server = make_server()
        server.running = True
        try:
            created1 = server._ensure_capture_threads()
            t_stream, t_read = server._stream_thread, server._read_thread
            self.assertTrue(created1, "首次调用必须建线（返回 True）")
            self.assertIsNotNone(t_stream, "流线程必须被创建")
            self.assertIsNotNone(t_read, "读线程必须被创建")
            self.assertTrue(server._capture_threads_started,
                            "flag 必须置位（幂等守卫）")
            # 第二次调用：flag 守卫 → no-op，线程对象不得被替换/重建
            created2 = server._ensure_capture_threads()
            self.assertFalse(created2, "第二次调用必须 no-op（返回 False）")
            self.assertIs(server._stream_thread, t_stream,
                          "流线程对象不得被替换（只建一次）")
            self.assertIs(server._read_thread, t_read,
                          "读线程对象不得被替换（只建一次）")
        finally:
            server.running = False
            for t in (server._stream_thread, server._read_thread):
                if t is not None:
                    t.join(timeout=2.0)
            _close_frame_socket(server)

    def test_ensure_noop_when_not_running(self):
        """未进运行态不建线（selftest 直调 switch/reconnect 不落真实线程）。"""
        if not hasattr(hts.HandTrackingServer, "_ensure_capture_threads"):
            self.fail("P0：_ensure_capture_threads 缺失（红态）")
            return
        server = make_server()
        server.running = False
        created = server._ensure_capture_threads()
        self.assertFalse(created, "running=False 时不建线（返回 False）")
        self.assertIsNone(server._read_thread, "running=False 不落读线程")
        self.assertIsNone(server._stream_thread, "running=False 不落流线程")
        self.assertFalse(server._capture_threads_started,
                         "未建线则 flag 不置位（下次运行态可再建）")
        _close_frame_socket(server)

    def test_switch_success_calls_ensure(self):
        """_switch_camera 成功段统一经 _ensure_capture_threads（P0 三落点之一）。"""
        server = make_server()
        server._cameras = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
        server.camera_selector.select_camera.side_effect = \
            lambda camera_id, backend_shift=0: make_open_cap()
        spy = mock.MagicMock(name="ensure_spy")
        server._ensure_capture_threads = spy   # 挂桩：修复前 switch 不调用 → 红
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        spy.assert_called_with()
        self.assertEqual(server.current_camera_id, 1, "前置：切换成功")

    def test_reconnect_success_calls_ensure(self):
        """_attempt_reconnect 成功段统一经 _ensure_capture_threads（P0 三落点之二）。"""
        server = make_server()
        server.current_camera_id = 0
        server.camera_selector._open_camera.side_effect = \
            lambda *a, **k: make_open_cap()
        spy = mock.MagicMock(name="ensure_spy")
        server._ensure_capture_threads = spy
        with mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        spy.assert_called_with()
        self.assertIsNotNone(server.cap, "前置：重连成功")

    def test_start_success_segment_calls_ensure(self):
        """start 的成功开启段收敛经 _ensure_capture_threads（P0 建线唯一，读码锚）。

        批次 AD（spec §4.2.2-1）等价改写：冷启动零开镜后 start() 自身已无「成功段」
        （不打开任何摄像头），建线唯一落点在开启成功段 `_switch_camera`（设备启动指令
        `START_CAMERA_BY_NAME` 直达同一漏斗）。断言口径由「start 源码含 ensure」迁移为
        「start 零内联建线 ∧ 冷启动显式零开镜」，并补开启段同源锚，断言数只增不减。
        """
        src = inspect.getsource(hts.HandTrackingServer.start)
        self.assertNotIn("target=self._camera_stream_thread", src,
                         "P0：start 不再内联建流线程（收敛至 _ensure_capture_threads）")
        self.assertNotIn("target=self._camera_read_thread", src,
                         "P0：start 不再内联建读线程（收敛至 _ensure_capture_threads）")
        self.assertIn("self.cap = None", src, "AD：start 冷启动显式置 cap=None（零开镜）")
        self.assertIn("_startup_sequence", src, "AD：启动前序仍先于设备阶段执行")
        sw_src = inspect.getsource(hts.HandTrackingServer._switch_camera)
        self.assertIn("_ensure_capture_threads", sw_src,
                      "P0：开启成功段（_switch_camera）仍经 _ensure_capture_threads")


# ======================================================================
# ② P1 cap 读写竞态：读线程 read 持 _camera_lock
# ======================================================================

class ReadThreadLockTest(unittest.TestCase):

    def _run_read_thread(self, server, min_reads=5, timeout=2.0):
        """起真实读线程，采集 min_reads 次 read 的锁状态后停线。"""
        states = []
        cap = mock.MagicMock(name="cap")
        cap.isOpened.return_value = True
        frame = object()

        def _read():
            states.append(server._camera_lock.locked())
            return (True, frame)

        cap.read.side_effect = _read
        server.cap = cap
        server.flip_image = False          # 跳过 cv.flip（frame 为通用对象）
        server.running = True
        t = threading.Thread(target=server._camera_read_thread, daemon=True)
        t.start()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and len(states) < min_reads:
            time.sleep(0.01)
        server.running = False
        t.join(timeout=2.0)
        return states, t

    def test_read_holds_camera_lock(self):
        server = make_server()
        states, t = self._run_read_thread(server, min_reads=5)
        self.assertGreaterEqual(len(states), 5,
                                "读线程必须持续读帧（持锁不构成死锁）")
        self.assertTrue(all(states),
                        f"P1：cap.read() 必须持 _camera_lock（实测 locked={states}）")
        self.assertFalse(t.is_alive(), "读线程停机正常（无死锁残留）")

    def test_release_during_read_is_bounded(self):
        """读帧进行中 release：等待 read 完成、有界返回（无死锁）。"""
        server = make_server()
        server.flip_image = False
        cap = mock.MagicMock(name="cap")
        cap.isOpened.return_value = True

        def _read():
            time.sleep(0.05)                # 模拟毫秒级~数十毫秒读帧
            return (True, object())

        cap.read.side_effect = _read
        server.cap = cap
        server.running = True
        t = threading.Thread(target=server._camera_read_thread, daemon=True)
        t.start()
        time.sleep(0.02)                    # 让读线程先进入 read（持锁窗内）
        rel = threading.Thread(target=server._release_camera_only, daemon=True)
        rel.start()
        rel.join(timeout=2.0)
        server.running = False
        t.join(timeout=2.0)
        self.assertFalse(rel.is_alive(),
                         "P1：锁内 release 等待 read 完成必须有界（2s 内返回，无死锁）")
        cap.release.assert_called()
        self.assertIsNone(server.cap, "释放语义保持（cap 归零）")
        self.assertFalse(t.is_alive(), "读线程退出正常")


# ======================================================================
# ③ P3 吞异常：_execute_control_command 的 except Exception 记日志
# ======================================================================

class CommandExceptionLogTest(unittest.TestCase):

    def test_execute_command_logs_exception(self):
        server = make_server()
        server._enum_probe_pending = False
        server._enum_probe_started = False
        # 注入故障：GET_CAMERAS else 分支必调 _send_camera_list_init → 抛
        server._send_camera_list_init = mock.MagicMock(
            side_effect=RuntimeError("boom-inject"))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            server._execute_control_command("GET_CAMERAS")   # 异常必须被吞但记日志
        out = buf.getvalue()
        self.assertIn("命令执行异常", out,
                      f"P3：except Exception 不得 pass 静默，须记一行日志（实际输出={out!r}）")
        self.assertIn("boom-inject", out, "日志须含异常摘要（排障可用）")


# ======================================================================
# ④ P2 心跳停发：收线程兼职周期心跳 _maybe_send_heartbeat
# ======================================================================

class HeartbeatSupplementTest(unittest.TestCase):

    def test_maybe_send_heartbeat_sends_and_throttles(self):
        if not hasattr(hts.HandTrackingServer, "_maybe_send_heartbeat"):
            self.fail("P2：_maybe_send_heartbeat 缺失（红态）")
            return
        server = make_server()
        server.udp_sender.last_send_time = 0.0      # 此后零发包（>1s 前）
        server.udp_sender.send.reset_mock()
        server._last_heartbeat = 0.0
        sent = server._maybe_send_heartbeat()
        self.assertTrue(sent, "距上次发包 >1s → 必须补发心跳（返回 True）")
        self.assertEqual(server.udp_sender.send.call_count, 1, "恰补发一次")
        pkt = server.udp_sender.send.call_args.args[0]
        # 包格式与现心跳完全一致（主循环 _process_frame 无帧分支同款）
        self.assertEqual(set(pkt.keys()),
                         {"left", "right", "stale", "timestamp", "camera_open"},
                         f"心跳包键集与现心跳一致（实际 {sorted(pkt.keys())}）")
        self.assertIsNone(pkt["left"], "心跳=双手空包 left=None")
        self.assertIsNone(pkt["right"], "心跳=双手空包 right=None")
        self.assertTrue(pkt["stale"], "无帧期心跳须带 stale=true")
        # 1s 节流：立即再调 → 不发
        self.assertFalse(server._maybe_send_heartbeat(), "1s 内再次调用必须节流")
        self.assertEqual(server.udp_sender.send.call_count, 1, "节流期零重复发包")

    def test_skips_when_main_loop_just_sent(self):
        if not hasattr(hts.HandTrackingServer, "_maybe_send_heartbeat"):
            self.fail("P2：_maybe_send_heartbeat 缺失（红态）")
            return
        server = make_server()
        server.udp_sender.last_send_time = time.time()   # 主循环/正常帧刚发过
        server.udp_sender.send.reset_mock()
        server._last_heartbeat = 0.0                     # 自身节拍已过期（唯一门=发包时间）
        sent = server._maybe_send_heartbeat()
        self.assertFalse(sent, "主循环刚发过包 → 不重复补发")
        server.udp_sender.send.assert_not_called()

    def test_skips_when_sender_has_no_timestamp(self):
        """测试桩发送端无数值 last_send_time → 不越权补发（存量 selftest 零影响）。"""
        if not hasattr(hts.HandTrackingServer, "_maybe_send_heartbeat"):
            self.fail("P2：_maybe_send_heartbeat 缺失（红态）")
            return
        server = make_server()   # 纯 MagicMock：last_send_time 为自动子桩非数值
        server.udp_sender.send.reset_mock()
        server._last_heartbeat = 0.0
        sent = server._maybe_send_heartbeat()
        self.assertFalse(sent, "发送端未暴露数值时间戳 → 不补发")
        server.udp_sender.send.assert_not_called()

    def test_control_recv_thread_integrates_heartbeat(self):
        """收线程兼职周期心跳（读码锚：不新建线程）。"""
        if not hasattr(hts.HandTrackingServer, "_maybe_send_heartbeat"):
            self.fail("P2：_maybe_send_heartbeat 缺失（红态）")
            return
        src = inspect.getsource(hts.HandTrackingServer._control_recv_thread)
        self.assertIn("_maybe_send_heartbeat", src,
                      "P2：控制命令收线程必须兼职调用 _maybe_send_heartbeat")

    def test_recv_thread_actually_sends_heartbeat(self):
        """端到端：收线程运行后 1.5s 内补发出心跳空包。"""
        if not hasattr(hts.HandTrackingServer, "_maybe_send_heartbeat"):
            self.fail("P2：_maybe_send_heartbeat 缺失（红态）")
            return
        server = make_server()
        server.udp_sender.last_send_time = 0.0
        server.udp_sender.send.reset_mock()
        server._last_heartbeat = 0.0
        ctrl = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        ctrl.bind(("127.0.0.1", 0))          # 高位回环：不占 9876/9878
        server.control_socket = ctrl
        server.control_port = ctrl.getsockname()[1]
        server._start_control_recv_thread()
        try:
            deadline = time.monotonic() + 1.5
            while time.monotonic() < deadline and \
                    server.udp_sender.send.call_count == 0:
                time.sleep(0.02)
            self.assertGreaterEqual(server.udp_sender.send.call_count, 1,
                                    "P2：收线程必须兼职补发心跳（1.5s 内）")
            pkt = server.udp_sender.send.call_args.args[0]
            self.assertTrue(pkt.get("stale"), "收线程补发包=现心跳同款（stale=true）")
            self.assertIsNone(pkt.get("left"))
        finally:
            server._control_recv_stop = True
            try:
                ctrl.close()
            except OSError:
                pass
            if getattr(server, "_control_thread", None) is not None:
                server._control_thread.join(timeout=2.0)


# ======================================================================
# ⑤ P3 launcher kill 无 wait：reap_server（wait → kill → wait → 再 kill 兜底）
# ======================================================================

class LauncherReapTest(unittest.TestCase):

    def test_reap_server_exists(self):
        if not hasattr(launcher, "reap_server"):
            self.fail("P3：launcher.reap_server 缺失（红态）")
            return
        self.assertTrue(callable(launcher.reap_server))

    def test_reap_exited_without_kill(self):
        if not hasattr(launcher, "reap_server"):
            self.fail("P3：launcher.reap_server 缺失（红态）")
            return
        p = mock.MagicMock(name="server")
        p.wait.return_value = 0
        self.assertEqual(launcher.reap_server(p), "exited", "首 wait 即退出")
        p.kill.assert_not_called()

    def test_reap_kill_then_wait(self):
        if not hasattr(launcher, "reap_server"):
            self.fail("P3：launcher.reap_server 缺失（红态）")
            return
        p = mock.MagicMock(name="server")
        p.wait.side_effect = [
            subprocess.TimeoutExpired(cmd="srv", timeout=3.0),
            0,                      # kill 后的第二次 wait 收割成功
        ]
        self.assertEqual(launcher.reap_server(p), "killed")
        p.kill.assert_called_once()
        self.assertEqual(p.wait.call_count, 2,
                         "P3：kill() 之后必须再 wait(timeout)（防句柄泄漏）")

    def test_reap_kill_timeout_fallback_kill(self):
        if not hasattr(launcher, "reap_server"):
            self.fail("P3：launcher.reap_server 缺失（红态）")
            return
        p = mock.MagicMock(name="server")
        p.wait.side_effect = subprocess.TimeoutExpired(cmd="srv", timeout=3.0)
        result = launcher.reap_server(p)
        self.assertEqual(result, "kill_timeout")
        self.assertGreaterEqual(p.kill.call_count, 2,
                                "P3：kill 后 wait 仍超时 → 再 kill 兜底")
        self.assertGreaterEqual(p.wait.call_count, 3,
                                "P3：兜底 kill 后仍有最终收割 wait 尝试")

    def test_main_uses_reap_server(self):
        if not hasattr(launcher, "reap_server"):
            self.fail("P3：launcher.reap_server 缺失（红态）")
            return
        src = inspect.getsource(launcher.main)
        self.assertIn("reap_server(", src,
                      "P3：main 游戏退出后的子进程收割改走 reap_server")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
