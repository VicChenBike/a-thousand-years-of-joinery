#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""批次 V-B1（spec §6.3/§6.4）：摄像头生命周期四修复——unittest+mock 逻辑测试。

零摄像头纪律：cv2.VideoCapture 与 socket 全部 mock，不依赖真实设备、不占用真实端口。
四项修复口径（缺一不可）：
1. 粘滞标志生命周期——SWITCH 命令开始与成功开启双点清、失败不残留、
   失败后可再次 SWITCH；标志只抑制「无命令时的自动重连」，永不阻断显式 SWITCH；
2. release→open 释放时延 0.35s + 打开失败重试×2（共 3 轮）+
   每轮后端尝试链左旋一位（DSHOW→MSMF→默认，纯函数表驱动）；
3. 失败必回传——SWITCH 全失败 / SET_RESOLUTION FATAL 与异常分支都必须发
   camera_error（含失败设备 id 与原因摘要）；SET_FPS 失败维持仅日志；
4. 控制口 9878 接管序——bind 失败→向旧实例发既有 SHUTDOWN→重试×3（间隔 0.5s）
   →三次仍失败放弃（调用方以非零退出码退出）。
"""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import camera_selector  # noqa: E402
import hand_tracking_server as hts  # noqa: E402


# ======================================================================
# 测试夹具
# ======================================================================

def make_open_cap(w=640, h=480, fps=30.0):
    """构造「已打开」的 mock cap：isOpened True、get 回读与期望一致。

    get 对 WIDTH/HEIGHT 恒回 (w, h)——用于 SET_RESOLUTION 触发「set 后回读
    不匹配→重开链」；对 FPS 回 fps 供切换成功路径的帧率探测收敛。
    """
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
    """构造被测服务器：CameraSelector/UDPSender 打桩（不触真实设备与端口）。"""
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    return server


def camera_errors(sender_mock):
    """从 udp_sender 打桩记录中筛出 camera_error 载荷列表。"""
    out = []
    for c in sender_mock.send.call_args_list:
        payload = c.args[0] if c.args else None
        if isinstance(payload, dict) and payload.get("type") == "camera_error":
            out.append(payload)
    return out


def feed_command(server, cmd: bytes):
    """经 mock 控制口向 _check_control_commands 喂一条命令（单步、无真实端口）。"""
    server.control_socket = mock.MagicMock(name="control_socket")
    server.control_socket.recvfrom.return_value = (cmd, ("127.0.0.1", 55555))
    server._check_control_commands()


# ======================================================================
# ① 粘滞标志生命周期（spec §6.3-1）
# ======================================================================

class StickyFlagLifecycleTest(unittest.TestCase):
    """_camera_intentionally_released 双点清 + 只抑制自动重连。"""

    def test_switch_clears_flag_at_command_start_and_on_success(self):
        server = make_server()
        server._camera_intentionally_released = True  # RELEASE_CAMERA 后的粘滞态
        good_cap = make_open_cap()
        flag_seen_at_open = {}

        def _select(camera_id, backend_shift=0):
            flag_seen_at_open["value"] = server._camera_intentionally_released
            return good_cap

        server.camera_selector.select_camera.side_effect = _select
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertFalse(
            flag_seen_at_open.get("value", True),
            "SWITCH 命令开始时（打开设备之前）必须已清粘滞标志")
        self.assertFalse(server._camera_intentionally_released,
                         "成功开启后粘滞标志保持已清（双点清第二点）")

    def test_failed_switch_keeps_flag_clear_and_reports_camera_error(self):
        server = make_server()
        server._camera_intentionally_released = True  # RELEASE 后切失败的病灶形态
        server.camera_selector.select_camera.side_effect = \
            RuntimeError("无法打开摄像头 [1]")
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertFalse(
            server._camera_intentionally_released,
            "SWITCH 失败路径也不得残留粘滞标志（旧缺陷：失败后标志残留→重连被永久跳过）")
        errs = camera_errors(server.udp_sender)
        self.assertEqual(len(errs), 1, "SWITCH 失败必回传一条 camera_error")
        self.assertEqual(errs[0]["id"], 1)
        self.assertTrue(str(errs[0].get("reason", "")).strip(),
                        "camera_error 必须携带原因摘要")

    def test_switch_after_failure_can_succeed_again(self):
        server = make_server()
        server.camera_selector.select_camera.side_effect = RuntimeError("boom")
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertEqual(len(camera_errors(server.udp_sender)), 1)
        # 「切坏一次全死」根治点：失败后再次 SWITCH 可正常尝试
        good_cap = make_open_cap()
        server.camera_selector.select_camera.side_effect = None
        server.camera_selector.select_camera.return_value = good_cap
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertIs(server.cap, good_cap)
        self.assertEqual(server.current_camera_id, 1)
        self.assertFalse(server._camera_intentionally_released)

    def test_release_flag_suppresses_auto_reconnect_only(self):
        server = make_server()
        server.cap = None
        server._latest_frame = None
        server._camera_intentionally_released = True
        with mock.patch.object(server, "_attempt_reconnect") as fake_reconnect:
            server._process_frame()
        fake_reconnect.assert_not_called()
        self.assertEqual(len(server.udp_sender.send.call_args_list), 1,
                         "标志抑制重连期间 1Hz 心跳空包照发（READY 语义保留）")

    def test_flag_cleared_still_auto_reconnects(self):
        server = make_server()
        # 批次 AC（2026-09-27，spec §4.2-2）等价改写：待命态（current_camera_id is None，
        # 无自动可用物理设备）零重连是本批**有意**新语义（旧码会以 None 为目标开镜，
        # 既无意义又可能命中 CAP 0=荣耀手机）；"标志清除即重连"的既有语义由**已选定设备**
        # 形态继续锁定（显式注入 current_camera_id），并补待命态反向护栏，断言只增不减。
        server.current_camera_id = 2
        server.cap = None
        server._latest_frame = None
        server._camera_intentionally_released = False
        with mock.patch.object(server, "_attempt_reconnect") as fake_reconnect:
            server._process_frame()
        fake_reconnect.assert_called_once()
        # 待命态反向护栏：无设备目标 → 零重连（不借重连打开任何设备）
        standby = make_server()
        standby.current_camera_id = None
        standby.cap = None
        standby._latest_frame = None
        standby._camera_intentionally_released = False
        with mock.patch.object(standby, "_attempt_reconnect") as fake_standby:
            standby._process_frame()
        fake_standby.assert_not_called()
        # 直调入口同款门（覆盖 _process_frame 之外的调用形态）
        with mock.patch.object(standby.camera_selector, "_open_camera") as fake_open:
            standby._attempt_reconnect()
        fake_open.assert_not_called()


# ======================================================================
# ② 释放时延 0.35s + 重试×2 + 后端链左旋（spec §6.3-2）
# ======================================================================

class SwitchRetryAndRotationTest(unittest.TestCase):
    def test_switch_release_delay_is_035s(self):
        server = make_server()
        server.camera_selector.select_camera.return_value = make_open_cap()
        with mock.patch.object(hts.time, "sleep") as fake_sleep:
            server._switch_camera(1)
        sleeps = [c.args[0] for c in fake_sleep.call_args_list if c.args]
        self.assertIn(0.35, sleeps,
                      "release→open 释放时延必须为 0.35s（旧值 0.1s 驱动不足）")

    def test_switch_retries_two_rounds_with_backend_shift_0_1_2(self):
        server = make_server()
        good_cap = make_open_cap()
        server.camera_selector.select_camera.side_effect = [
            RuntimeError("无法打开摄像头 [2]"),
            RuntimeError("无法打开摄像头 [2]"),
            good_cap,
        ]
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(2)
        calls = server.camera_selector.select_camera.call_args_list
        self.assertEqual(len(calls), 3, "打开失败重试×2：共 3 轮，全部失败才判失败")
        self.assertEqual([c.kwargs.get("backend_shift") for c in calls], [0, 1, 2],
                         "每轮后端尝试链左旋一位（backend_shift 递增）")
        self.assertIs(server.cap, good_cap)

    def test_switch_all_rounds_fail_sends_single_camera_error(self):
        server = make_server()
        server.camera_selector.select_camera.side_effect = \
            RuntimeError("无法打开摄像头 [9]")
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(9)
        self.assertEqual(server.camera_selector.select_camera.call_count, 3)
        errs = camera_errors(server.udp_sender)
        self.assertEqual(len(errs), 1, "全部轮次失败才判失败且回传一条 camera_error")
        self.assertEqual(errs[0]["id"], 9)
        self.assertTrue(str(errs[0].get("reason", "")).strip())
        self.assertIsNone(server.cap)

    def test_rotate_backend_chain_retired(self):
        """批次 AD（spec §4.2.3）：后端轮换纯函数彻底退役（单后端 CAP_DSHOW 直启）。"""
        self.assertFalse(hasattr(camera_selector, "rotate_backend_chain"),
                         "AD：rotate_backend_chain 必须彻底退役")

    def test_open_camera_single_dshow_backend_and_config(self):
        """批次 AD（spec §4.2.3）：单后端 CAP_DSHOW 一次性直启 + MJPG/BUFFERSIZE=1；
        失败不换后端重开（一次性直启，零指示灯光闪烁）。"""
        dshow = camera_selector.cv.CAP_DSHOW
        with mock.patch.object(camera_selector.cv, "VideoCapture") as fake_vc:
            fake_vc.return_value.isOpened.return_value = False  # 打不开
            self.assertIsNone(
                camera_selector.CameraSelector._open_camera(3, 640, 480))
            attempted = [c.args[1] if len(c.args) > 1 else None
                         for c in fake_vc.call_args_list]
        self.assertEqual(attempted, [dshow], "AD：恒单后端一次直启（零 MSMF/默认轮换）")
        # 成功路径：MJPG + BUFFERSIZE=1 固定配置在位
        with mock.patch.object(camera_selector.cv, "VideoCapture") as fake_vc:
            cap = fake_vc.return_value
            cap.isOpened.return_value = True
            cap.read.return_value = (True, object())
            got = camera_selector.CameraSelector._open_camera(2, 640, 480)
        self.assertIs(got, cap, "单后端成功即返回该句柄")
        sets = [c.args[0] for c in cap.set.call_args_list if c.args]
        self.assertIn(camera_selector.cv.CAP_PROP_FOURCC, sets, "AD：MJPG 配置在位")
        self.assertIn(camera_selector.cv.CAP_PROP_BUFFERSIZE, sets, "AD：BUFFERSIZE 配置在位")
        self.assertEqual(fake_vc.call_count, 1, "AD：一次直启（零轮换）")

    def test_select_camera_passes_backend_shift_to_open_camera(self):
        """批次 AD：`backend_shift` 保留为 API 兼容占位（取值被忽略，零轮换语义）。"""
        with tempfile.TemporaryDirectory() as tmp:
            sel = camera_selector.CameraSelector(
                config_file=str(Path(tmp) / "camera_config.json"))
            with mock.patch.object(sel, "_open_camera",
                                   return_value=make_open_cap()) as fake_open:
                sel.select_camera(2, backend_shift=2)
            fake_open.assert_called_once_with(2, backend_shift=2)


# ======================================================================
# ③ 失败必回传 camera_error（spec §6.3-3）
# ======================================================================

class CameraErrorReportingTest(unittest.TestCase):
    def _make_res_server(self):
        server = make_server()
        server.current_camera_id = 1
        # cap get 恒回 640x480：SET_RESOLUTION:1:800x600 set 后回读不匹配 → 触发重开链
        server.cap = make_open_cap(640, 480)
        return server

    def test_set_resolution_fatal_restore_failure_sends_camera_error(self):
        server = self._make_res_server()
        # 重开与恢复均失败（select_camera 返回 None）→ FATAL 分支
        server.camera_selector.select_camera.return_value = None
        with mock.patch.object(hts.time, "sleep"):
            feed_command(server, b"SET_RESOLUTION:1:800x600")
        errs = camera_errors(server.udp_sender)
        self.assertEqual(len(errs), 1,
                         "SET_RESOLUTION 恢复失败 FATAL 分支必回传 camera_error（旧缺陷：仅 print）")
        self.assertEqual(errs[0]["id"], 1)
        self.assertTrue(str(errs[0].get("reason", "")).strip())

    def test_set_resolution_exception_sends_camera_error(self):
        server = self._make_res_server()
        with mock.patch.object(hts.time, "sleep"):
            feed_command(server, b"SET_RESOLUTION:1:abcxdef")
        errs = camera_errors(server.udp_sender)
        self.assertEqual(len(errs), 1, "SET_RESOLUTION 异常分支必回传 camera_error")
        self.assertEqual(errs[0]["id"], 1)
        self.assertTrue(str(errs[0].get("reason", "")).strip())

    def test_set_fps_failure_stays_log_only(self):
        server = self._make_res_server()
        with mock.patch.object(hts.time, "sleep"):
            feed_command(server, b"SET_FPS:1:notanumber")
        self.assertEqual(camera_errors(server.udp_sender), [],
                         "SET_FPS 失败维持仅日志（spec §6.3-3 明示不回传）")


# ======================================================================
# ④ 控制口 9878 接管序（spec §6.3-4）
# ======================================================================

class ControlPortTakeoverTest(unittest.TestCase):
    def test_bind_failure_sends_shutdown_retries_three_then_gives_up(self):
        server = make_server()
        with mock.patch.object(hts.time, "sleep") as fake_sleep, \
             mock.patch.object(hts.socket, "socket") as fake_sock_cls:
            sock = fake_sock_cls.return_value
            sock.bind.side_effect = OSError("通常每个套接字地址只允许使用一次")
            ok = server._bind_control_socket()
        self.assertFalse(ok, "重试×3 仍失败必须放弃（返回 False → 调用方非零退出）")
        self.assertEqual(sock.bind.call_count, 4, "首轮 bind + 重试×3")
        sendto_calls = sock.sendto.call_args_list
        self.assertEqual(len(sendto_calls), 3, "每次重试前向旧实例发一次 SHUTDOWN")
        for c in sendto_calls:
            payload, addr = c.args
            self.assertEqual(payload, b"SHUTDOWN", "必须复用既有 SHUTDOWN 控制指令")
            self.assertEqual(addr, ("127.0.0.1", server.control_port))
        intervals = [c.args[0] for c in fake_sleep.call_args_list if c.args]
        self.assertEqual(intervals, [0.5, 0.5, 0.5], "重试间隔 0.5s×3")
        self.assertIsNone(server.control_socket, "放弃后不得留下半开控制口")

    def test_bind_takeover_succeeds_after_shutdown(self):
        server = make_server()
        with mock.patch.object(hts.time, "sleep"), \
             mock.patch.object(hts.socket, "socket") as fake_sock_cls:
            sock = fake_sock_cls.return_value
            sock.bind.side_effect = [OSError("占用"), OSError("占用"), None]
            ok = server._bind_control_socket()
        self.assertTrue(ok, "孤儿旧实例自杀后重试 bind 应成功")
        self.assertEqual(sock.bind.call_count, 3)
        self.assertEqual(sock.sendto.call_count, 2, "成功轮不再发送 SHUTDOWN")
        self.assertIs(server.control_socket, sock)

    def test_start_exits_nonzero_when_takeover_fails(self):
        server = make_server()
        server.camera_selector.select_camera.return_value = make_open_cap()
        with mock.patch.object(server, "_enumerate_cameras_step",
                               return_value=([{"id": 0, "name": "摄像头 0"}], 0)), \
             mock.patch.object(server, "_bind_control_socket", return_value=False), \
             mock.patch.object(server, "_cleanup") as fake_cleanup, \
             mock.patch.object(hts.time, "sleep"), \
             mock.patch.object(hts.socket, "socket"), \
             mock.patch.object(hts.threading, "Thread"):
            with self.assertRaises(SystemExit) as ctx:
                server.start()
        self.assertEqual(ctx.exception.code, 1, "接管失败必须以非零退出码退出")
        fake_cleanup.assert_called()


# ======================================================================
# ⑤ SWITCH 全失败重连冷却（批次V审查①-P2）
# ======================================================================

class SwitchFailCooldownTest(unittest.TestCase):
    """SWITCH 全失败（camera_error 已发）→ 对失败设备 id 加自动重连冷却。

    口径（批次V审查①-P2，SWITCH_FAIL_COOLDOWN_SEC=8.0 集中可调）：
    - 冷却期内自动重连（_attempt_reconnect）跳过该失败 id（防重连风暴）；
    - 显式 SWITCH 命令不受冷却限制（人工重试永远可达）；
    - 冷却随成功开启清除；时间到期自然恢复；
    - 冷却按设备 id 记账，不同 id 不互扰。协议零变更。
    """

    def _fail_switch(self, server, camera_id):
        """使对 camera_id 的 SWITCH 全轮失败并断言 camera_error 已回传（前置）。"""
        server.camera_selector.select_camera.side_effect = \
            RuntimeError(f"无法打开摄像头 [{camera_id}]")
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(camera_id)
        self.assertEqual(len(camera_errors(server.udp_sender)), 1,
                         "前置：SWITCH 全失败必已回传 camera_error")
        self.assertIn(camera_id, server._switch_fail_cooldown,
                      "SWITCH 全失败后必须登记该设备 id 的重连冷却")

    def test_failed_switch_cooldown_skips_auto_reconnect(self):
        server = make_server()
        server.current_camera_id = 1
        self._fail_switch(server, 1)
        with mock.patch.object(server.camera_selector, "_open_camera") as fake_open:
            server._attempt_reconnect()
        # 冷却期内自动重连必须跳过失败设备 id（防重连风暴）
        fake_open.assert_not_called()
        # 冷却到期自然恢复：直注过期时间戳后自动重连照常尝试
        server._switch_fail_cooldown[1] = hts.time.time() - 0.01
        with mock.patch.object(server.camera_selector, "_open_camera") as fake_open2, \
             mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        self.assertTrue(fake_open2.called, "冷却到期后自动重连必须恢复尝试（不永久半死）")

    def test_explicit_switch_not_blocked_by_cooldown(self):
        server = make_server()
        server.current_camera_id = 1
        self._fail_switch(server, 1)
        attempts = []

        def _select(camera_id, backend_shift=0):
            attempts.append(camera_id)
            raise RuntimeError("still down")

        server.camera_selector.select_camera.side_effect = _select
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertEqual(attempts, [1, 1, 1],
                         "冷却期内显式 SWITCH 不受限（3 轮打开尝试照常发起）")
        self.assertEqual(len(camera_errors(server.udp_sender)), 2,
                         "冷却期内再次全失败仍照常回传 camera_error")

    def test_success_clears_cooldown(self):
        server = make_server()
        server.current_camera_id = 1
        self._fail_switch(server, 1)
        server.camera_selector.select_camera.side_effect = None
        server.camera_selector.select_camera.return_value = make_open_cap()
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(1)
        self.assertIs(server.cap, server.camera_selector.select_camera.return_value,
                      "前置：SWITCH 成功开启")
        self.assertNotIn(1, server._switch_fail_cooldown,
                         "成功开启后冷却必须清除（冷却随成功开启清除）")
        with mock.patch.object(server.camera_selector, "_open_camera") as fake_open, \
             mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        self.assertTrue(fake_open.called, "冷却清除后自动重连不再被跳过")

    def test_cooldown_is_per_device_id_no_cross_interference(self):
        server = make_server()
        server.current_camera_id = 1
        self._fail_switch(server, 1)
        # 另一设备 id（未失败）不受冷却互扰：自动重连照常尝试
        server.current_camera_id = 2
        with mock.patch.object(server.camera_selector, "_open_camera") as fake_open, \
             mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        self.assertTrue(fake_open.called, "冷却只作用于失败设备 id，不互扰其他 id")
        self.assertEqual(fake_open.call_args[0][0], 2,
                         "自动重连目标=当前设备 id 2（非冷却中的 id 1）")


if __name__ == "__main__":
    unittest.main()
