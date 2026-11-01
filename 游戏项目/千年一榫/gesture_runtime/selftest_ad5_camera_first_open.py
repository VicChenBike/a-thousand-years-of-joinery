#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AD-5 专项自测：摄像头首开卡死与频闪（看门狗基准复位 / 在飞幂等 / 首帧快速判定）。

零摄像头纪律（摄像头红线）：全程 mock——`cv.VideoCapture` 经
`camera_selector` 打桩、UDPSender/选择器替身、**绝不真实构造 VideoCapture、绝不枚举
真实设备、绝不 bind 真实端口**（唯一例外：frame_socket 预置 MagicMock，不创建真 socket）。

断言口径（批次 AD-5 需求 §4.1~§4.4）：
  A. F-1 看门狗基准复位——开镜成功段（`_switch_camera` 成功分支 / `_attempt_reconnect`
     成功分支）必须把 `_last_camera_read_time` + `_no_frame_count` + `_no_frame_last_mark`
     复位，并把「首帧未到」窗重新武装（首帧窗从**打开成功时刻**起算，而非进程构造时刻）；
     首帧真正到达（`_mark_frame_read`）再次复位并解除武装。
  B. F-1 首帧缺失快速判定——开镜成功后 `FIRST_FRAME_TIMEOUT_SEC` 内零帧 → 恰一次安静
     重连；连续无帧**上界**=1 次安静重连（总 release/open 计数写进断言，禁止快速连环
     open/release 造成指示灯频闪）。
  C. F-2 在飞幂等——开镜进行中收到同名/同目标重复启动指令 → 忽略（不 release、不
     重启、不再次进入 `_switch_camera`、不递增代际）。
  D. F-3 空 res/fps 不下发 + 流在场不连锁——桥侧 `camera_opened` 追发与 ensure 追发
     必须有 `mem_res != ""` / `mem_fps > 0` 守卫（源锚）；Python 侧 `SET_RESOLUTION`
     回读不符时**流真值在场（画面正在出）不得触发 release/reopen 连锁**（不画面全灭）。

判绿：末行输出 SELFTEST PASSED，退出码 0。
"""
import socket
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

_GESTURE_DIR = Path(__file__).resolve().parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import hand_tracking_server as hts  # noqa: E402

BRIDGE_GD = _GESTURE_DIR.parent / "autoload" / "gesture_bridge.gd"


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


def make_server(cameras=None):
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    # 预置 frame_socket 替身：_switch_camera 成功段的「缺失则建真 socket」分支不再真建
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
    """取 `def <name>(` 起至下一个顶格 `def `/类定义为止的函数体（源锚用）。"""
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


def gd_fn_body(source: str, name: str) -> str:
    """GDScript 侧取 `func <name>(` 起至下一个顶格 `func ` 为止。"""
    lines = source.split("\n")
    start = None
    for i, ln in enumerate(lines):
        if ln.startswith("func %s(" % name):
            start = i
            break
    if start is None:
        return ""
    out = []
    for ln in lines[start + 1:]:
        if ln.startswith("func ") or ln.startswith("class ") or ln.startswith("## ==="):
            break
        out.append(ln)
    return "\n".join(out)


# ----------------------------------------------------------------------
# A. F-1：开镜成功 → 看门狗基准与首帧窗复位
# ----------------------------------------------------------------------

class WatchdogBaselineResetTest(unittest.TestCase):
    """F-1 核心：`_last_camera_read_time` 初值=进程构造时刻（远早于开镜），
    开镜成功段不复位 → 主循环第一迭代即开始累计 3s 窗 → 6~9s 后必然误判无帧。"""

    def _switch_open(self, server):
        server.camera_selector.select_camera.side_effect = \
            lambda *a, **k: make_open_cap()
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(2)
        return server.camera_selector.select_camera

    def test_switch_success_resets_watchdog_baseline(self):
        server = make_server(cameras=ENTRIES)
        server._last_camera_read_time = time.time() - 999   # 进程构造期陈旧值（>>3s）
        server._no_frame_count = 3
        server._no_frame_last_mark = time.time() - 999
        server._first_frame_pending = False
        self._switch_open(server)
        self.assertIsNotNone(server.cap, "前置：开镜成功")
        self.assertLess(time.time() - server._last_camera_read_time, 2.0,
                        "F-1：开镜成功必须复位看门狗基准（首帧窗从开镜时刻起算）")
        self.assertEqual(server._no_frame_count, 0, "F-1：无帧窗口计数必须清零")
        self.assertEqual(server._no_frame_last_mark, 0.0,
                         "F-1：无帧计数基准时刻必须清 0.0")
        self.assertTrue(server._first_frame_pending,
                        "F-1：开镜成功必须重新武装「首帧未到」快速判定窗")

    def test_reconnect_success_resets_watchdog_baseline(self):
        server = make_server(cameras=ENTRIES)
        server.current_camera_id = 2
        server.cap = make_open_cap()
        server._last_camera_read_time = time.time() - 999
        server._no_frame_count = 3
        server._no_frame_last_mark = time.time() - 999
        server._first_frame_pending = False
        server.camera_selector._open_camera.side_effect = \
            lambda *a, **k: make_open_cap()
        with mock.patch.object(hts.time, "sleep"):
            server._attempt_reconnect()
        self.assertIsNotNone(server.cap, "前置：重连成功")
        self.assertLess(time.time() - server._last_camera_read_time, 2.0,
                        "F-1：重连成功同样必须复位看门狗基准")
        self.assertEqual(server._no_frame_count, 0)
        self.assertTrue(server._first_frame_pending,
                        "F-1：重连成功必须武装首帧快速判定窗")

    def test_first_frame_arrival_disarms_fast_window(self):
        server = make_server(cameras=ENTRIES)
        server._first_frame_pending = True
        server._frameless_open_streak = 1
        server._last_camera_read_time = time.time() - 999
        server._no_frame_count = 3
        self.assertTrue(hasattr(server, "_mark_frame_read"),
                        "F-1：读帧成功复位必须收敛为可断言原语 _mark_frame_read")
        server._mark_frame_read()
        self.assertFalse(server._first_frame_pending,
                         "F-1：首帧真正到达 → 解除首帧未到武装")
        self.assertEqual(server._frameless_open_streak, 0,
                         "F-1：首帧到达 → 连续无帧开镜计数清零（快速判定重置）")
        self.assertLess(time.time() - server._last_camera_read_time, 2.0,
                        "F-1：首帧到达必须复位看门狗基准（既有成功写点语义保持）")
        self.assertEqual(server._no_frame_count, 0)
        src = (_GESTURE_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")
        self.assertIn("self._mark_frame_read()",
                      fn_body(src, "_camera_read_thread"),
                      "F-1：读线程成功路径必须调用 _mark_frame_read（唯一写点收敛）")


# ----------------------------------------------------------------------
# B. F-1：首帧缺失 → 恰一次安静重连（release/open 计数上界）
# ----------------------------------------------------------------------

class FirstFrameFastReconnectTest(unittest.TestCase):
    """快速判定必须**有界**：连续无帧开镜的安静重连次数上界=1；
    总 release/open 计数写进断言（禁止快速连环 open/release）。"""

    def test_missing_first_frame_triggers_at_most_one_quiet_reconnect(self):
        if not hasattr(hts, "FIRST_FRAME_TIMEOUT_SEC"):
            self.fail("F-1：FIRST_FRAME_TIMEOUT_SEC 常量缺失（红态=无首帧快速判定）")
            return
        server = make_server(cameras=ENTRIES)
        open_calls = {"n": 0}

        def _select(camera_id, backend_shift=0):
            open_calls["n"] += 1
            return make_open_cap()

        def _open(camera_id, width=640, height=480, backend_shift=0):
            open_calls["n"] += 1
            return make_open_cap()

        server.camera_selector.select_camera.side_effect = _select
        server.camera_selector._open_camera.side_effect = _open

        releases = {"n": 0}
        orig_cleanup = server._cleanup_camera

        def _spy(reason="release"):
            if server.cap is not None:
                releases["n"] += 1
            return orig_cleanup(reason)

        server._cleanup_camera = _spy
        server.current_camera_id = 2
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(2)   # 开镜#1 成功（基准已复位）
        self.assertEqual(open_calls["n"], 1, "前置：首开恰一次")
        server._last_camera_read_time = time.time() - 30   # 首帧始终未到
        with mock.patch.object(hts.time, "sleep"):
            server._process_frame()    # 快速判定第 1 次 → 安静重连
        self.assertEqual(releases["n"], 1,
                         "F-1：首帧缺失恰触发 1 次安静重连（release=1）")
        self.assertEqual(open_calls["n"], 2,
                         "F-1：首帧缺失恰触发 1 次安静重连（open=2：首开+1 次）")
        server._last_camera_read_time = time.time() - 30
        with mock.patch.object(hts.time, "sleep"):
            server._process_frame()    # 快速判定第 2 次 → 必须被上界压住
        server._last_camera_read_time = time.time() - 30
        with mock.patch.object(hts.time, "sleep"):
            server._process_frame()
        self.assertEqual(releases["n"], 1,
                         "F-1 上界：连续无帧的快速安静重连不得累加（release 恒 ≤1；"
                         "实际 %d）" % releases["n"])
        self.assertEqual(open_calls["n"], 2,
                         "F-1 上界：快速判定不得产生连环 open（open 恒 ≤2；实际 %d）"
                         % open_calls["n"])
        self.assertLessEqual(releases["n"], 1, "F-1：总 release 次数上界=1")
        self.assertLessEqual(open_calls["n"], 2, "F-1：总 open 次数上界=2")

    def test_fast_window_not_armed_after_real_frame(self):
        """首帧已到 → 不进入快速判定（避免运行期普通停帧被 2.5s 误杀）。"""
        server = make_server(cameras=ENTRIES)
        server.camera_selector.select_camera.side_effect = \
            lambda *a, **k: make_open_cap()
        with mock.patch.object(hts.time, "sleep"):
            server._switch_camera(2)
        server._mark_frame_read()      # 首帧已到
        server._last_camera_read_time = time.time() - 30   # 运行期停帧
        with mock.patch.object(server, "_attempt_reconnect") as fake_re:
            with mock.patch.object(hts.time, "sleep"):
                server._process_frame()
        self.assertFalse(fake_re.called,
                         "F-1：首帧已到后的普通停帧走既有 3×3s 看门狗，不走快速判定")


# ----------------------------------------------------------------------
# C. F-2：开镜在飞期同名重复启动指令 → 忽略
# ----------------------------------------------------------------------

class InFlightIdempotencyTest(unittest.TestCase):
    """在飞幂等：开镜进行中（`_switch_camera` 持有目标 id）收到同目标重复启动指令
    → 零 release / 零 reopen / 零二次 switch / 零代际递增。"""

    def test_duplicate_start_while_open_in_flight_is_ignored(self):
        server = make_server(cameras=ENTRIES)
        cap = make_open_cap()
        opened_evt = threading.Event()
        release_evt = threading.Event()
        acquire_count = {"n": 0}

        def fake_acquire(camera_id, width=640, height=480,
                         backend_shift=0, remember=False):
            acquire_count["n"] += 1
            opened_evt.set()
            release_evt.wait(10)
            return cap

        server._acquire_camera_handle = fake_acquire
        switch_calls = {"n": 0}
        orig_switch = server._switch_camera

        def spy_switch(camera_id, *a, **k):
            switch_calls["n"] += 1
            return orig_switch(camera_id, *a, **k)

        server._switch_camera = spy_switch

        errs = []

        def worker():
            try:
                server._start_camera_by_name("HD Camera")
            except Exception as e:      # pragma: no cover
                errs.append(e)

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        self.assertTrue(opened_evt.wait(10), "前置：在飞开镜已进入打开阶段")
        # 同名重复启动指令（开镜仍在飞）
        server._start_camera_by_name("HD Camera")
        self.assertEqual(server._open_in_flight_target, 2,
                         "F-2：开镜在飞期目标登记在位（观测缝）")
        self.assertEqual(switch_calls["n"], 1,
                         "F-2：同名重复启动指令必须被忽略，不得二次进入 _switch_camera")
        self.assertEqual(acquire_count["n"], 1,
                         "F-2：同名重复启动指令零额外 open")
        self.assertEqual(server._switch_generation, 1,
                         "F-2：重复指令不得递增代际（代际递增会中止在飞开镜）")
        release_evt.set()
        t.join(10)
        self.assertEqual(errs, [], "在飞开镜线程不得抛异常")
        self.assertEqual(switch_calls["n"], 1, "在飞结束后仍是单次 switch")
        self.assertTrue(server.cap is cap, "在飞开镜结果落位（句柄未被重复指令抢占）")
        self.assertEqual(cap.release.call_count, 0,
                         "F-2：重复指令不得对刚打开的句柄执行 release（指示灯不闪）")

    def test_different_target_not_blocked_by_in_flight(self):
        """异目标（用户显式切换）不受在飞幂等拦阻——显式切换可达性保持。"""
        server = make_server(cameras=ENTRIES)
        server._open_in_flight_target = 2   # 在飞目标=2
        with mock.patch.object(server, "_switch_camera") as fake_switch:
            server._start_camera_by_name("USB Cam")   # 目标=3（不同）
        fake_switch.assert_called_once_with(3)
        self.assertEqual(server._switch_generation, 1,
                         "异目标照常登记代际并进入切换（0→1）")


# ----------------------------------------------------------------------
# D. F-3：空 res/fps 不下发 SET_*；流在场回读不符不连锁
# ----------------------------------------------------------------------

class ResFpsFollowupGuardTest(unittest.TestCase):
    """桥侧两处 res/fps 追发必须带守卫（源锚）；Python 侧流在场不得 release/reopen。"""

    def _bridge_src(self) -> str:
        return BRIDGE_GD.read_text(encoding="utf-8")

    def test_camera_opened_followup_guards_empty_res_and_zero_fps(self):
        src = self._bridge_src()
        body = gd_fn_body(src, "_handle_camera_event")
        self.assertIn('if mem_res != "":', body,
                      "F-3：camera_opened 追发 SET_RESOLUTION 必须空串守卫")
        self.assertIn("if mem_fps > 0:", body,
                      "F-3：camera_opened 追发 SET_FPS 必须 >0 守卫")
        idx_res = body.find('send_control("SET_RESOLUTION:')
        self.assertGreaterEqual(idx_res, 0, "F-3：追发点在位")
        self.assertGreater(body.rfind('if mem_res != "', 0, idx_res), 0,
                           "F-3：SET_RESOLUTION 追发必须位于空串守卫之后")
        idx_fps = body.find('send_control("SET_FPS:')
        self.assertGreaterEqual(idx_fps, 0, "F-3：SET_FPS 追发点在位")
        self.assertGreater(body.rfind("if mem_fps > 0", 0, idx_fps), 0,
                           "F-3：SET_FPS 追发必须位于 >0 守卫之后")

    def test_all_set_followup_sites_guarded(self):
        """全文件：每处 send_control(\"SET_RESOLUTION/SET_FPS\") 前必须有对应守卫。"""
        src = self._bridge_src()
        import re as _re
        for m in _re.finditer(r'send_control\("SET_RESOLUTION:', src):
            head = src[max(0, m.start() - 260):m.start()]
            self.assertIn('if mem_res != "', head,
                          "F-3：存在未守卫的 SET_RESOLUTION 下发点（offset %d）" % m.start())
        for m in _re.finditer(r'send_control\("SET_FPS:', src):
            head = src[max(0, m.start() - 260):m.start()]
            self.assertIn("if mem_fps > 0", head,
                          "F-3：存在未守卫的 SET_FPS 下发点（offset %d）" % m.start())

    def test_set_resolution_mismatch_keeps_stream_when_open(self):
        """流真值在场（画面正在出）→ 回读不符降级为仅日志，绝不 release/reopen。"""
        server = make_server(cameras=ENTRIES)
        server.current_camera_id = 1
        server.cap = make_open_cap(640, 480)
        server._emit_camera_opened()
        self.assertTrue(server._camera_stream_open, "前置：流真值在场")
        server.control_socket = mock.MagicMock(name="control_socket")
        server.control_socket.recvfrom.return_value = \
            (b"SET_RESOLUTION:1:800x600", ("127.0.0.1", 55555))
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        self.assertFalse(server.cap.release.called,
                         "F-3：流在场时 SET_RESOLUTION 回读不符不得 release（画面不全灭）")
        self.assertIsNotNone(server.cap, "F-3：句柄保持（不触发 reopen 连锁）")
        self.assertEqual(typed_packets(server, "camera_closed"), [],
                         "F-3：不得发 camera_closed（HUD 不清屏）")

    def test_set_resolution_still_reopens_when_no_stream(self):
        """反向护栏：无流态（既有语义/存量夹具形态）重开链保持——FATAL 仍回 camera_error。"""
        server = make_server(cameras=ENTRIES)
        server.current_camera_id = 1
        server.cap = make_open_cap(640, 480)
        self.assertFalse(server._camera_stream_open, "前置：无流（夹具默认态）")
        server.camera_selector.select_camera.return_value = None
        server.control_socket = mock.MagicMock(name="control_socket")
        server.control_socket.recvfrom.return_value = \
            (b"SET_RESOLUTION:1:800x600", ("127.0.0.1", 55555))
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()
        errs = [p for p in typed_packets(server, "camera_error")]
        self.assertEqual(len(errs), 1,
                         "F-3 反向护栏：无流态 FATAL 分支仍必回传 camera_error（存量契约）")

    def test_empty_res_payload_does_not_raise(self):
        """空/非法 res 载荷防御：不抛、不误触发重开链。"""
        server = make_server(cameras=ENTRIES)
        server.current_camera_id = 1
        server.cap = make_open_cap(640, 480)
        server.control_socket = mock.MagicMock(name="control_socket")
        server.control_socket.recvfrom.return_value = \
            (b"SET_RESOLUTION:1:", ("127.0.0.1", 55555))
        with mock.patch.object(hts.time, "sleep"):
            server._check_control_commands()   # 异常兜底不得上抛
        self.assertFalse(server.cap.release.called,
                         "F-3：空 res 载荷不得触发 release 连锁")


class FirstOpenConstantsTest(unittest.TestCase):
    """F-1 常量在位（红态=常量缺失，快速判定无从谈起）。"""

    def test_constants_exist(self):
        self.assertTrue(hasattr(hts, "FIRST_FRAME_TIMEOUT_SEC"),
                        "F-1：FIRST_FRAME_TIMEOUT_SEC 缺失")
        self.assertTrue(hasattr(hts, "FIRST_FRAME_QUIET_RECONNECT_MAX"),
                        "F-1：FIRST_FRAME_QUIET_RECONNECT_MAX 缺失")
        self.assertGreater(hts.FIRST_FRAME_TIMEOUT_SEC, 0)
        self.assertLessEqual(hts.FIRST_FRAME_TIMEOUT_SEC,
                             hts.CAMERA_TIMEOUT_SECONDS,
                             "首帧快速判定必须先于 3s 无帧看门狗触发")
        self.assertEqual(hts.FIRST_FRAME_QUIET_RECONNECT_MAX, 1,
                         "F-1：安静重连上界=1（需求 §4.1）")

    def test_socket_not_created_in_suite(self):
        """红线：本自测全程不得构造真实 UDP socket/frame_socket。"""
        server = make_server(cameras=ENTRIES)
        with mock.patch.object(hts.socket, "socket") as spy:
            server.camera_selector.select_camera.side_effect = \
                lambda *a, **k: make_open_cap()
            with mock.patch.object(hts.time, "sleep"):
                server._switch_camera(2)
            self.assertEqual(spy.call_count, 0,
                             "红线：开镜路径不得新建真实 socket（frame_socket 已预置替身）")


def main():
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for cls in (WatchdogBaselineResetTest, FirstFrameFastReconnectTest,
                InFlightIdempotencyTest, ResFpsFollowupGuardTest,
                FirstOpenConstantsTest):
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
