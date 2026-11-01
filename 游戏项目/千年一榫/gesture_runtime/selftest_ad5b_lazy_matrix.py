#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AD-5b 专项自测：启动期矩阵探测移出关键路径（播种 + 按需惰性探测 + 探测让位/抑制）。

零摄像头纪律（摄像头红线）：全程 mock——`cv.VideoCapture` 经
`camera_selector` 打桩、UDPSender/选择器替身、**绝不真实构造 VideoCapture、绝不枚举
真实设备、绝不 bind 真实端口**。

断言口径（批次 AD-5b 需求 §4.5~§4.6）：
  A. 切换成功**不做** 5×5 set 风暴——`_switch_camera` 成功段 cap.set 计数上界=播种允许的
     ≤2（宽/高各一）、零 FPS set、函数体源锚零 `RES_PROBE_LIST`/`FPS_PROBE_LIST` 引用；
  B. 播种矩阵在位且照发——`_supported_resolutions`=[实际生效分辨率]、`_fps_options`=
     [当前实际帧率]（不可读/0 → 留空=Godot 空 fps 子列不弹出既有契约）；init#2 与
     resolutions_update 照发（协议与 Godot 重建下拉时序不变）；SET_RESOLUTION 应用后
     播种矩阵跟随实际生效值（种子=「含当前生效分辨率」的定义保持）；
  C. `pid==current` 的 PROBE_MATRIX 走**复用 live 句柄**路径（实测
     ad5b_probe_block_measure.txt：另开句柄风暴抢流 → 二选一裁定 (b)）——探测后恢复
     记住的 res/fps、绝不 release live 句柄、零 `_acquire_camera_handle` 调用；
     `pid!=current` 仍走另开句柄（既有路径），句柄用完即释放；
  D. 探测期间看门狗被抑制——`_matrix_probe_active` 置位窗口内首帧快速判定与 3×3s 无帧
     看门狗全部静默（不产生 release/`camera_closed`/重连），看门狗源锚两处在位；
     探测收尾补起算（陈旧基线在 finally 恢复）；
  E. 探测中收到 SWITCH/RELEASE 等主流命令能**中止让位**——主流命令分类与纪元
     （`_probe_cmd_epoch`）bump 行为在位；中止后不回 probe_result（缓存不污染）、
     live 路径仍恢复 res/fps、第二句柄路径释放自有句柄（零泄漏）。
  F. 批次 AD-5d（P2-A，终审 P2 闭环）：current 设备被用户主动释放（`_release_latch`/
     `_camera_intentionally_released` 在位、`cap=None`）→ 矩阵探测**拒绝开镜**（零
     `_acquire_camera_handle`，回 `ok=false`）——指示灯绝不因探测被点亮；反向（未主动关）
     与非 current 两条既有语义不变（闸门非死码/不误伤）。

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

import hand_tracking_server as hts  # noqa: E402


# ----------------------------------------------------------------------
# 夹具（零真开镜）
# ----------------------------------------------------------------------

def make_open_cap(w=640, h=480, fps=30.0):
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


def make_stateful_cap(w=640, h=480, fps=30.0):
    """set 生效的替身 cap（get 回读=set 后的状态）——播种「实际生效值」与恢复断言用。"""
    cap = mock.MagicMock(name="stateful_cap")
    cap.isOpened.return_value = True
    state = {"w": float(w), "h": float(h), "fps": float(fps)}

    def _set(prop, val, *a):
        if prop == hts.cv.CAP_PROP_FRAME_WIDTH:
            state["w"] = float(val)
        elif prop == hts.cv.CAP_PROP_FRAME_HEIGHT:
            state["h"] = float(val)
        elif prop == hts.cv.CAP_PROP_FPS:
            state["fps"] = float(val)
        return True

    def _get(prop):
        if prop == hts.cv.CAP_PROP_FRAME_WIDTH:
            return state["w"]
        if prop == hts.cv.CAP_PROP_FRAME_HEIGHT:
            return state["h"]
        if prop == hts.cv.CAP_PROP_FPS:
            return state["fps"]
        return 0.0

    cap.set.side_effect = _set
    cap.get.side_effect = _get
    cap.state = state
    return cap


def make_server(cameras=None):
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    server.frame_socket = mock.MagicMock(name="frame_socket")
    if cameras is not None:
        server._cameras = list(cameras)
    return server


ENTRIES = [{"id": 0, "name": "荣耀Magic7 跨屏互联"},
           {"id": 2, "name": "HD Camera"},
           {"id": 3, "name": "USB Cam"}]


def typed_packets(server, msg_type):
    return [p for p in (c.args[0] for c in server.udp_sender.send.call_args_list
                        if c.args and isinstance(c.args[0], dict))
            if isinstance(p, dict) and p.get("type") == msg_type]


def fn_body(source: str, name: str) -> str:
    lines = source.split("\n")
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith("def %s(" % name) or ln.startswith("    def %s(" % name):
            start = i
            break
    if start is None:
        return ""
    out = []
    indent = len(lines[start]) - len(lines[start].lstrip())
    for ln in lines[start + 1:]:
        if ln.strip() and (len(ln) - len(ln.lstrip())) <= indent \
                and not ln.lstrip().startswith("#"):
            break
        out.append(ln)
    return "\n".join(out)


SERVER_SRC = (_GESTURE_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")


# ----------------------------------------------------------------------
# A. 切换成功不做 set 风暴（播种上界 ≤2）
# ----------------------------------------------------------------------

class SeedMatrixNoStormTest(unittest.TestCase):
    """AD-5b §4.5：`_switch_camera` 成功段 cap.set ≤2（宽/高各一）、零 FPS set、
    源锚零探测列表引用——红态=5×5 set 风暴（首帧 9.25s 的时长主体）。"""

    def _switch_open(self, cap):
        server = make_server(cameras=ENTRIES)
        server.camera_selector.select_camera.side_effect = \
            lambda *a, **k: cap
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(2)
        return server

    def test_switch_success_set_count_bounded_by_seed(self):
        # 场景 A：开镜后已达标（_open_camera 刚按同一目标 set 过）→ **零重复 set**
        #（同值 set(H) 在 DSHOW 上仍 ≈0.53s 重协商——ad5b_open_latency_diag 实测
        #  SELECT_out→MARK=0.549s 纯耗时，必须移出关键路径）
        cap_a = make_stateful_cap(640, 480, 30.0)
        server = self._switch_open(cap_a)
        self.assertIsNotNone(server.cap, "前置：开镜成功")
        set_a = [c.args for c in cap_a.set.call_args_list if c.args]
        self.assertLessEqual(
            len(set_a), 2,
            "AD-5b：已达标时零重复 set（实际 %d；红态=宽/高重复 set + 5×5 探测风暴）"
            % len(set_a))
        self.assertNotIn(hts.cv.CAP_PROP_FPS, [a[0] for a in set_a],
                         "AD-5b：切换段零 FPS set（fps 只读播种，不下发）")
        # 场景 B：开镜回读与目标不符 → 单次校正恰 ≤2 次 set（宽/高各一）
        cap_b = make_stateful_cap(1280, 720, 30.0)
        server = self._switch_open(cap_b)
        set_b = [c.args for c in cap_b.set.call_args_list if c.args]
        self.assertLessEqual(
            len(set_b), 2,
            "AD-5b：不符时单次校正 set 上界=2（实际 %d；红态=RES×5+FPS×5 set 风暴"
            "阻塞读线程→首帧迟至 9.25s）" % len(set_b))
        props = [a[0] for a in set_b]
        self.assertNotIn(hts.cv.CAP_PROP_FPS, props,
                         "AD-5b：校正段零 FPS set（fps 只读播种）")
        self.assertIn(hts.cv.CAP_PROP_FRAME_WIDTH, props)
        self.assertIn(hts.cv.CAP_PROP_FRAME_HEIGHT, props)
        self.assertEqual(server._supported_resolutions, [(640, 480)],
                         "AD-5b：校正后播种=实际生效分辨率")

    def test_switch_source_has_no_probe_storm(self):
        body = fn_body(SERVER_SRC, "_switch_camera")
        self.assertNotIn("RES_PROBE_LIST", body,
                         "AD-5b：_switch_camera 函数体零 RES_PROBE_LIST 引用"
                         "（红态=同步分辨率探测风暴仍在关键路径）")
        self.assertNotIn("FPS_PROBE_LIST", body,
                         "AD-5b：_switch_camera 函数体零 FPS_PROBE_LIST 引用"
                         "（红态=同步帧率探测风暴仍在关键路径）")

    def test_switch_seeds_resolution_and_fps(self):
        cap = make_stateful_cap(640, 480, 30.0)
        server = self._switch_open(cap)
        self.assertEqual(server._supported_resolutions, [(640, 480)],
                         "AD-5b：res 播种=当前实际生效分辨率（刚 set 完读回的值）")
        self.assertEqual(server._fps_options, [30],
                         "AD-5b：fps 播种=当前实际帧率（可读且合理）")

    def test_init2_and_resolutions_update_still_sent(self):
        cap = make_stateful_cap(640, 480, 30.0)
        server = self._switch_open(cap)
        inits2 = [p for p in typed_packets(server, "init") if "resolutions" in p]
        self.assertEqual(len(inits2), 1,
                         "AD-5b：init#2 照发（保持协议与 Godot 重建下拉的时序不变）")
        self.assertEqual([tuple(r) for r in inits2[0]["resolutions"]], [(640, 480)])
        self.assertEqual(list(inits2[0]["fps_options"]), [30])
        ups = typed_packets(server, "resolutions_update")
        self.assertEqual(len(ups), 1,
                         "AD-5b：resolutions_update 照发（既有协议保形）")
        self.assertEqual([tuple(r) for r in ups[0]["resolutions"]], [(640, 480)])

    def test_fps_seed_empty_when_unreadable(self):
        cap = make_stateful_cap(640, 480, 0.0)   # cap.get(FPS)=0 → 不合理 → 留空
        server = self._switch_open(cap)
        self.assertEqual(server._fps_options, [],
                         "AD-5b：fps 不可读（0）→ 播种留空（Godot 空 fps 子列不弹出"
                         "既有契约，不伪造数值）")

    def test_set_resolution_moves_seed_to_applied_value(self):
        """种子=「含当前生效分辨率」的定义保持：SET_RESOLUTION 应用后播种矩阵跟随。"""
        server = make_server(cameras=ENTRIES)
        server.current_camera_id = 2
        server.cap = make_stateful_cap(640, 480, 30.0)
        server._supported_resolutions = [(640, 480)]
        server._camera_stream_open = True
        server.control_socket = mock.MagicMock(name="control_socket")
        server.control_socket.recvfrom.return_value = \
            (b"SET_RESOLUTION:2:800x600", ("127.0.0.1", 55555))
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        self.assertIn((800, 600), server._supported_resolutions,
                      "AD-5b：SET_RESOLUTION 应用成功 → 播种矩阵跟随实际生效值"
                      "（实际 %s）" % (server._supported_resolutions,))
        inits2 = [p for p in typed_packets(server, "init") if "resolutions" in p]
        self.assertTrue(inits2 and any(tuple(r) == (800, 600)
                                       for r in inits2[-1]["resolutions"]),
                        "AD-5b：跟随后的 init#2 含新生效分辨率")

    def test_set_fps_moves_seed_options(self):
        """种子=「含当前生效帧率」同口径：SET_FPS 应用成功后播种帧率集跟随。"""
        server = make_server(cameras=ENTRIES)
        server.current_camera_id = 2
        server.cap = make_stateful_cap(640, 480, 24.0)
        server._fps_options = [24]
        server.control_socket = mock.MagicMock(name="control_socket")
        server.control_socket.recvfrom.return_value = \
            (b"SET_FPS:2:60", ("127.0.0.1", 55555))
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        self.assertIn(60, server._fps_options,
                      "AD-5b：SET_FPS 应用成功 → 播种帧率集跟随实际生效值"
                      "（实际 %s）" % (server._fps_options,))


# ----------------------------------------------------------------------
# C. pid==current → 复用 live 句柄（二选一裁定 (b)）；pid!=current → 另开句柄
# ----------------------------------------------------------------------

class LazyProbePathTest(unittest.TestCase):
    """AD-5b §4.6：探测目标==当前流设备必须复用 live 句柄（实测另开句柄风暴抢流），
    探测前记住 res/fps、探测后恢复；异设备沿用另开句柄且用完即放。"""

    def _live_server(self, cap):
        server = make_server(cameras=ENTRIES)
        server.cap = cap
        server.current_camera_id = 2
        return server

    def test_probe_current_device_reuses_live_handle_and_restores(self):
        cap = make_stateful_cap(640, 480, 30.0)
        server = self._live_server(cap)
        server._acquire_camera_handle = mock.MagicMock(name="acquire_spy")
        server._last_camera_read_time = time.time() - 999   # 陈旧基线（探测前）
        server._first_frame_pending = True
        flags_seen = []
        inner_set = cap.set.side_effect

        def spy_set(prop, val, *a):
            flags_seen.append(bool(server._matrix_probe_active))
            return inner_set(prop, val, *a)

        cap.set.side_effect = spy_set
        server._probe_matrix_worker(2)

        self.assertTrue(flags_seen, "前置：探测确有 set 动作")
        self.assertTrue(all(flags_seen),
                        "D：探测期间 _matrix_probe_active 必须恒真（抑制看门狗窗口）")
        server._acquire_camera_handle.assert_not_called()
        self.assertGreater(len(cap.set.call_args_list), 2,
                           "C：live 探测确实跑了全矩阵扫描（非空转）")
        self.assertEqual(cap.state, {"w": 640.0, "h": 480.0, "fps": 30.0},
                         "C：探测后恢复探测前记住的 res/fps（state 归位）")
        self.assertEqual(cap.release.call_count, 0,
                         "C：live 句柄绝不 release（画面不灭）")
        results = typed_packets(server, "probe_result")
        self.assertEqual(len(results), 1, "C：正常探测回 probe_result")
        self.assertEqual(results[0]["id"], 2)
        self.assertTrue(results[0]["ok"])
        self.assertTrue(results[0]["resolutions"], "C：回包带全矩阵 resolutions")
        self.assertTrue(results[0]["fps_options"], "C：回包带全矩阵 fps_options")
        self.assertFalse(server._matrix_probe_active, "D：探测结束清除抑制标志")
        self.assertIsNone(server._probe_in_flight_id, "D：在探 id 收尾清空")
        self.assertLess(time.time() - server._last_camera_read_time, 2.0,
                        "D：探测收尾补起算看门狗基线（陈旧 999s → 归新）")

    def test_probe_other_device_uses_second_handle(self):
        live = make_stateful_cap(640, 480, 30.0)
        server = self._live_server(live)
        second = make_stateful_cap(640, 480, 30.0)
        server._acquire_camera_handle = mock.MagicMock(return_value=second)
        server._probe_matrix_worker(3)
        server._acquire_camera_handle.assert_called_once_with(3, 640, 480)
        self.assertGreaterEqual(second.release.call_count, 1,
                                "C：另开句柄用完即释放（零泄漏）")
        self.assertEqual(len(live.set.call_args_list), 0,
                         "C：异设备探测不触碰 live 句柄")
        results = typed_packets(server, "probe_result")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["id"], 3)
        self.assertFalse(server._matrix_probe_active, "D：探测结束清除抑制标志")


# ----------------------------------------------------------------------
# D. 探测期间看门狗抑制
# ----------------------------------------------------------------------

class ProbeWatchdogSuppressionTest(unittest.TestCase):
    """AD-5b §4.6：探测中标志抑制首帧快速判定与 3×3s 无帧看门狗——
    绝不产生 release/`camera_closed`/重连（画面与 HUD 不消失）。"""

    def _stale_open_server(self):
        server = make_server(cameras=ENTRIES)
        server.cap = make_open_cap()
        server.current_camera_id = 2
        server._first_frame_pending = True
        server._first_frame_fast_tried = False
        server._no_frame_count = 3
        server._no_frame_last_mark = 0.0
        server._last_camera_read_time = time.time() - 999
        return server

    def test_probe_active_suppresses_watchdogs(self):
        server = self._stale_open_server()
        server._matrix_probe_active = True
        with mock.patch.object(server, "_attempt_reconnect") as fake_re, \
             mock.patch.object(server, "_watchdog_recover") as fake_rec, \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        fake_re.assert_not_called()
        fake_rec.assert_not_called()
        self.assertEqual(server._no_frame_count, 3,
                         "D：探测抑制期无帧窗口计数不再增长（红态=计数推进→误判）")

    def test_suppression_release_on_flag_clear_restores_watchdogs(self):
        """反向护栏：标志清除后两条看门狗恢复可达（守卫非死码）。"""
        server = self._stale_open_server()
        server._matrix_probe_active = True
        with mock.patch.object(server, "_attempt_reconnect") as fake_re, \
             mock.patch.object(server, "_watchdog_recover") as fake_rec, \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        fake_re.assert_not_called()
        fake_rec.assert_not_called()
        server._matrix_probe_active = False
        server._last_camera_read_time = time.time() - 999
        with mock.patch.object(server, "_attempt_reconnect") as fake_re2, \
             mock.patch.object(server, "_watchdog_recover") as fake_rec2, \
             mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        fake_re2.assert_called_once()
        fake_rec2.assert_called_once()
        self.assertTrue(server._first_frame_fast_tried,
                        "D 反向：无抑制时首帧快速判定照常介入（守卫两处均为活码）")

    def test_watchdog_source_gates_on_probe_flag(self):
        body = fn_body(SERVER_SRC, "_process_frame")
        self.assertGreaterEqual(
            body.count("not self._matrix_probe_active"), 2,
            "D：首帧快速判定与 3×3s 看门狗两处判定均须带 _matrix_probe_active 守卫"
            "（源锚；实际 %d 处）" % body.count("not self._matrix_probe_active"))


# ----------------------------------------------------------------------
# E. 主流命令让位（分类 / 纪元 bump / 中止）
# ----------------------------------------------------------------------

class ProbeYieldTest(unittest.TestCase):
    def test_main_command_classification(self):
        f = hts.HandTrackingServer._is_main_camera_cmd
        for cmd in ("SWITCH_CAMERA:1", "RELEASE_CAMERA", "SHUTDOWN",
                    "START_CAMERA_BY_NAME:HD Camera",
                    "SET_PREFERRED_CAMERA:HD Camera",
                    "SET_RESOLUTION:2:640x480", "SET_FPS:2:30"):
            self.assertTrue(f(cmd), "E：%s 须判为主流命令（探测让位）" % cmd)
        for cmd in ("GET_CAMERAS", "PROBE_MATRIX:3"):
            self.assertFalse(f(cmd), "E：%s 非主流命令（探测不无谓让位）" % cmd)

    def test_execute_main_commands_bump_epoch(self):
        server = make_server(cameras=ENTRIES)
        addr = ("127.0.0.1", 55555)
        e0 = server._probe_cmd_epoch
        # SET_FPS（3 参 → 切设备家族）走完整执行漏斗
        server.control_socket = mock.MagicMock(name="control_socket")
        server.control_socket.recvfrom.side_effect = [
            (b"SET_FPS:2:30", addr), socket.timeout()]
        with mock.patch.object(server, "_switch_camera") as fake_switch, \
             mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        fake_switch.assert_called_once_with(2)
        self.assertGreater(server._probe_cmd_epoch, e0,
                           "E：SET_FPS（切设备）→ 让位纪元 bump")
        # GET_CAMERAS（非主流）不 bump
        e1 = server._probe_cmd_epoch
        server.control_socket.recvfrom.side_effect = [
            (b"GET_CAMERAS", addr), socket.timeout()]
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        self.assertEqual(server._probe_cmd_epoch, e1,
                         "E：GET_CAMERAS 不 bump（探测不无谓中止）")

    def test_release_and_shutdown_bump_epoch(self):
        server = make_server(cameras=ENTRIES)
        addr = ("127.0.0.1", 55555)
        for raw in (b"RELEASE_CAMERA", b"SHUTDOWN"):
            e0 = server._probe_cmd_epoch
            server.control_socket = mock.MagicMock(name="control_socket")
            server.control_socket.recvfrom.side_effect = [ (raw, addr),
                                                           socket.timeout()]
            with mock.patch.object(hts.time, "sleep"):
                server._check_control_commands()
            self.assertGreater(server._probe_cmd_epoch, e0,
                               "E：%s → 让位纪元 bump" % raw.decode())
        server._camera_intentionally_released = False   # 夹具收尾

    def test_switch_target_registration_bumps_epoch(self):
        server = make_server(cameras=ENTRIES)
        e0 = server._probe_cmd_epoch
        server._note_switch_target(1)
        self.assertGreater(server._probe_cmd_epoch, e0,
                           "E：切换目标登记（含收线程接收点/键盘切换）→ 让位纪元 bump")

    def test_recv_thread_yield_call_sites(self):
        body = fn_body(SERVER_SRC, "_control_recv_thread")
        self.assertGreaterEqual(
            body.count("self._note_probe_yield()"), 3,
            "E：收线程 RELEASE/SHUTDOWN/SWITCH 三处接收点即刻让位"
            "（源锚；实际 %d 处）" % body.count("self._note_probe_yield()"))


class ProbeAbortTest(unittest.TestCase):
    """E（续）：探测在飞收到主流命令 → 尽快中止让位、不回包、恢复/释放到位。"""

    def test_live_probe_aborts_and_restores_on_main_command(self):
        server = make_server(cameras=ENTRIES)
        cap = make_stateful_cap(640, 480, 30.0)
        server.cap = cap
        server.current_camera_id = 2
        server._acquire_camera_handle = mock.MagicMock(name="acquire_spy")
        bumped = {"n": 0}
        inner_set = cap.set.side_effect

        def set_then_bump(prop, val, *a):
            if bumped["n"] == 0:
                bumped["n"] += 1
                server._note_probe_yield()   # 模拟首个 set 在飞时主流命令接收点到达
            return inner_set(prop, val, *a)

        cap.set.side_effect = set_then_bump
        server._probe_matrix_worker(2)

        self.assertEqual(typed_packets(server, "probe_result"), [],
                         "E：中止探测不回 probe_result（Godot 缓存不被污染，"
                         "下次 hover 重探）")
        self.assertEqual(cap.state, {"w": 640.0, "h": 480.0, "fps": 30.0},
                         "E：中止仍恢复探测前 res/fps（画面参数不被遗弃在中间态）")
        self.assertEqual(cap.release.call_count, 0,
                         "E：中止不 release live 句柄")
        server._acquire_camera_handle.assert_not_called()
        self.assertFalse(server._matrix_probe_active, "E：中止路径同样清除抑制标志")
        self.assertIsNone(server._probe_in_flight_id, "E：中止路径清在探 id")

    def test_live_probe_save_failure_never_releases_live_handle(self):
        """E2（AD-5 终验回修）：live 复用探测——探测前记住 res/fps 的 get 抛异常
        （saved_w 保持 None）时**绝不 release live 句柄**。红态=恢复段判据漏
        「not live_mode」条件落 elif 分支误放流句柄 → 画面灭且流真值不变
        （须等 3×3s 看门狗才自愈，正是本批要根除的「画面+HUD 全灭」形态）。"""
        cap = make_stateful_cap(640, 480, 30.0)
        inner_get = cap.get.side_effect

        def get_fail_on_save(prop):
            if prop in (hts.cv.CAP_PROP_FRAME_WIDTH, hts.cv.CAP_PROP_FRAME_HEIGHT):
                raise RuntimeError("DSHOW get failure (probe save step)")
            return inner_get(prop)

        cap.get.side_effect = get_fail_on_save
        server = make_server(cameras=ENTRIES)
        server.cap = cap
        server.current_camera_id = 2
        server._probe_matrix_worker(2)

        self.assertEqual(cap.release.call_count, 0,
                         "E2：探测前参数读取失败也绝不 release live 句柄（画面不灭；"
                         "红态=恢复段误落 elif 释放分支）")
        self.assertEqual(cap.set.call_count, 0,
                         "E2：live 探测前参数不可记 → 保守跳过探测（不改动 live 流参数；"
                         "红态=逐档 set 风暴把流参数遗弃在中间态）")
        self.assertFalse(server._matrix_probe_active,
                         "E2：异常路径同样清除抑制标志")
        self.assertIsNone(server._probe_in_flight_id,
                          "E2：异常路径清在探 id")
        results = typed_packets(server, "probe_result")
        self.assertEqual(len(results), 1, "E2：异常降级仍回 probe_result（ok=false 契约）")
        self.assertFalse(results[0]["ok"], "E2：该场景回包 ok=false（探测失败已如实上报，不伪造矩阵）")

    def test_second_handle_probe_aborts_and_releases(self):
        server = make_server(cameras=ENTRIES)
        live = make_stateful_cap(640, 480, 30.0)
        server.cap = live
        server.current_camera_id = 2
        second = make_stateful_cap(640, 480, 30.0)
        server._acquire_camera_handle = mock.MagicMock(return_value=second)
        bumped = {"n": 0}
        inner_set = second.set.side_effect

        def set_then_bump(prop, val, *a):
            if bumped["n"] == 0:
                bumped["n"] += 1
                server._note_probe_yield()
            return inner_set(prop, val, *a)

        second.set.side_effect = set_then_bump
        server._probe_matrix_worker(3)

        self.assertEqual(typed_packets(server, "probe_result"), [],
                         "E：另开句柄中止同样不回包")
        self.assertGreaterEqual(second.release.call_count, 1,
                                "E：另开句柄中止必须释放（零句柄泄漏）")
        self.assertEqual(len(live.set.call_args_list), 0,
                         "E：异设备探测全程不触碰 live 句柄")
        self.assertFalse(server._matrix_probe_active)
        self.assertIsNone(server._probe_in_flight_id)


# ----------------------------------------------------------------------
# AD-5d（P2-A）：current 设备被用户主动释放 → 矩阵探测绝不重新开镜
# ----------------------------------------------------------------------

class ReleasedCurrentProbeGateTest(unittest.TestCase):
    """批次 AD-5d（P2-A，项目铁律「用户显式关闭后任何自动路径不得重开」）：

    RELEASE 后 `cap=None` 而 `current_camera_id` 仍在 → 非 live 分支若直接
    `_acquire_camera_handle(pid)` 就会为矩阵探测重新开镜（**指示灯被点亮**）。
    闸门：`pid == current_camera_id` 且（`_release_latch` 或
    `_camera_intentionally_released` 在位）→ 拒绝开镜，回 `ok=false`。
    非 current 设备的「悬停行即探测」与「未主动关时探测可达」两条语义不变。"""

    def _released_server(self):
        server = make_server(cameras=ENTRIES)
        server.cap = None                     # RELEASE 后句柄已放（current_camera_id 仍在）
        server.current_camera_id = 2
        server._release_latch = True
        server._camera_intentionally_released = True
        return server

    def test_probe_released_current_never_reopens(self):
        server = self._released_server()
        server._acquire_camera_handle = mock.MagicMock(name="acquire_spy")
        server._probe_matrix_worker(2)

        server._acquire_camera_handle.assert_not_called()
        results = typed_packets(server, "probe_result")
        self.assertEqual(len(results), 1,
                         "P2-A：拒绝开镜仍回 probe_result（ok=false 如实上报，缓存不悬空）")
        self.assertFalse(results[0]["ok"], "P2-A：主动关 current 探测 → ok=false")
        self.assertFalse(server._matrix_probe_active, "P2-A：拒绝路径同样清除抑制标志")
        self.assertIsNone(server._probe_in_flight_id, "P2-A：拒绝路径清在探 id")

    def test_probe_current_not_released_still_opens(self):
        """反向护栏（闸门非死码）：未主动关（双锁存皆清）且流未开 → 照旧另开句柄探测。"""
        server = make_server(cameras=ENTRIES)
        server.cap = None
        server.current_camera_id = 2
        second = make_stateful_cap(640, 480, 30.0)
        server._acquire_camera_handle = mock.MagicMock(return_value=second)
        server._probe_matrix_worker(2)

        server._acquire_camera_handle.assert_called_once_with(2, 640, 480)
        results = typed_packets(server, "probe_result")
        self.assertEqual(len(results), 1, "P2-A 反向：未主动关 → 探测照常回包")
        self.assertTrue(results[0]["ok"], "P2-A 反向：探测可达（不因 pid==current 误拦）")

    def test_probe_other_device_unaffected_by_latch(self):
        """非 current 设备语义不变：即便 current 已主动关，探测其它设备照旧另开句柄。"""
        server = self._released_server()
        second = make_stateful_cap(640, 480, 30.0)
        server._acquire_camera_handle = mock.MagicMock(return_value=second)
        server._probe_matrix_worker(3)

        server._acquire_camera_handle.assert_called_once_with(3, 640, 480)
        self.assertGreaterEqual(second.release.call_count, 1,
                                "P2-A：异设备探测另开句柄用完即释放（零泄漏）")


ALL = (SeedMatrixNoStormTest, LazyProbePathTest, ProbeWatchdogSuppressionTest,
       ProbeYieldTest, ProbeAbortTest, ReleasedCurrentProbeGateTest)


def main():
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for cls in ALL:
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
