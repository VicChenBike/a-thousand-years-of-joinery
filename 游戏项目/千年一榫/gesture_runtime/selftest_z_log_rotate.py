#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Z（Z5-8 长跑稳定性 + Z-B 回修 P2-c，spec §5-8/§4）——launcher 日志轮转 /
探测线程收敛 / 就绪探测超时对齐。

零摄像头纪律：CameraSelector/UDPSender/cv 全 mock、不打开真实设备、不触碰 9876/9878
真端口；日志轮转走临时目录沙盒路径。

断言口径：
  ① launcher.py 日志追加（open "a"）无轮转 → 单文件上限 LOG_MAX_BYTES + 保留份数
     LOG_ROTATE_KEEP 常量断言；超限滚动 .1/.2/.3、旧最深份删除（份数有界，长跑不涨）；
     _open_log_stream 候选路径先轮转后打开（集成）。
  ② 探测线程收敛：PROBE_MATRIX 按命令 `Thread(...).start()` → 同时刻至多
     PROBE_THREAD_MAX=1 条探测线程（在忙忽略并发请求，长跑命令风暴不涨线程数）。
  ③ P2-c：PROBE_TIMEOUT_SEC ≥45s（与桥 gesture_bridge PROBE_TIMEOUT_SEC=45 对齐，
     旧 15s ≪ 桥 45s 致就绪判定不对齐）。

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import launcher  # noqa: E402
import hand_tracking_server as hts  # noqa: E402


def _sandbox_log_path(td: str, name: str = "gesture_runtime.log") -> str:
    """显式沙盒路径构造（路径边界校验）——本文件所有沙盒 open() 的路径唯一来源。

    ① 基础目录：`Path(td).resolve()` 拿到规范化的绝对沙盒根（tempfile.TemporaryDirectory）；
    ② 文件名：作为独立参数显式传入，与基础目录分离；
    ③ 边界断言：`(base / name).resolve()` 规范化后必须 `is_relative_to(base)`，
       越界（如 name="../B/x.log"）→ 抛 ValueError，绝不把越界路径交给 open()。

    意图：让「路径从哪来 / 边界在哪」在测试里显式可见，而不是把裸 os.path.join 的
    结果直接喂给 open。仅替换路径构造来源，各用例的断言内容与数量零改动。

    写入 API 约定（本文件 4 处沙盒写入统一遵守）：一律用
    `Path(path).write_text(<内容>, encoding="utf-8")`，等价于内建 open 以写模式 +
    UTF-8 编码写入后关闭。**encoding 必须显式给 "utf-8"** —— `Path.write_text`
    缺省 `encoding=None` 会走 locale 编码（Windows=GBK），会改变落盘字节、
    破坏与硬化前的逐字节等价。
    """
    base = Path(td).resolve()
    target = (base / name).resolve()
    if not target.is_relative_to(base):
        raise ValueError(f"沙盒路径越界: {target} 不在基础目录 {base} 内")
    return str(target)


class LogRotateTest(unittest.TestCase):
    """Z5-8①：日志单文件上限 + 轮转份数（常量 + 行为 + 集成）。"""

    def test_rotate_constants(self):
        self.assertTrue(hasattr(launcher, "LOG_MAX_BYTES"), "LOG_MAX_BYTES 常量在位（红态=缺失）")
        self.assertTrue(hasattr(launcher, "LOG_ROTATE_KEEP"), "LOG_ROTATE_KEEP 常量在位（红态=缺失）")
        self.assertGreater(launcher.LOG_MAX_BYTES, 0, "单文件上限 >0")
        self.assertLessEqual(launcher.LOG_MAX_BYTES, 10 * 1024 * 1024,
                             f"单文件上限 ≤10MB（实测 {launcher.LOG_MAX_BYTES}）")
        self.assertGreaterEqual(launcher.LOG_ROTATE_KEEP, 1, "轮转保留份数 ≥1")
        self.assertLessEqual(launcher.LOG_ROTATE_KEEP, 10, "轮转保留份数 ≤10（长跑文件数有界）")

    def test_rotation_shifts_and_bounds_keep(self):
        with tempfile.TemporaryDirectory() as td:
            path = _sandbox_log_path(td)
            # 轮转 #1：log → log.1
            Path(path).write_text("A" * 120, encoding="utf-8")
            ok = launcher._rotate_log_if_needed(path, max_bytes=100, keep=3)
            self.assertTrue(ok, "超限 → 发生轮转")
            self.assertFalse(os.path.exists(path), "原文件已滚走")
            self.assertTrue(os.path.exists(path + ".1"), "log.1 就位")
            # 未超限 → no-op
            Path(path).write_text("B" * 10, encoding="utf-8")
            self.assertFalse(launcher._rotate_log_if_needed(path, max_bytes=100, keep=3),
                             "未超限不轮转")
            # 连续轮转 keep+2 次：份数有界 ≤ keep（最深份被删）
            for i in range(5):
                Path(path).write_text(str(i) * 200, encoding="utf-8")
                launcher._rotate_log_if_needed(path, max_bytes=100, keep=3)
            present = [j for j in (1, 2, 3, 4) if os.path.exists(f"{path}.{j}")]
            self.assertEqual(sorted(present), [1, 2, 3],
                             f"保留份数有界 ≤3（实际残留 {present}）——长跑不涨盘")
            self.assertFalse(os.path.exists(path + ".4"), "最深越界份已删除")

    def test_open_log_stream_rotates_first(self):
        """集成：候选路径超限 → _open_log_stream 先轮转再以追加打开（新句柄文件小）。"""
        with tempfile.TemporaryDirectory() as td:
            path = _sandbox_log_path(td)
            Path(path).write_text("Z" * (launcher.LOG_MAX_BYTES + 1),
                                  encoding="utf-8")             # 制造超限现文件
            f = launcher._open_log_stream(candidates=[path])
            self.assertIsNotNone(f, "沙盒路径可写（前置）")
            try:
                self.assertTrue(os.path.exists(path + ".1"),
                                "超限旧内容已滚动到 .1（_open_log_stream 先轮转）")
                self.assertLess(os.path.getsize(path), launcher.LOG_MAX_BYTES,
                                "新句柄文件从头建立（不再继承超限旧内容）")
            finally:
                f.close()

    def test_source_opens_with_rotation(self):
        """读码断言：_open_log_stream 函数体内存在轮转调用（防「加了常量没接线」）。"""
        src = Path(launcher.__file__).read_text(encoding="utf-8")
        body = src.split("def _open_log_stream", 1)[-1].split("\ndef ", 1)[0]
        self.assertIn("_rotate_log_if_needed(", body,
                      "轮转调用位于 _open_log_stream 函数体内（open(\"a\") 前先轮转）")


class ProbeTimeoutAlignTest(unittest.TestCase):
    """Z-B 回修 P2-c：launcher 就绪探测超时与桥 45s 对齐。"""

    def test_probe_timeout_ge_45(self):
        self.assertGreaterEqual(
            launcher.PROBE_TIMEOUT_SEC, 45.0,
            f"P2-c：PROBE_TIMEOUT_SEC≥45s（与桥 PROBE_TIMEOUT_SEC=45 对齐；实测 {launcher.PROBE_TIMEOUT_SEC}）")

    def test_no_hardcoded_15s_message(self):
        src = Path(launcher.__file__).read_text(encoding="utf-8")
        self.assertNotIn("15 秒未就绪", src, "P2-c：未就绪提示不得硬编码旧 15 秒字面量")


class ProbeThreadCapTest(unittest.TestCase):
    """Z5-8②：探测线程收敛——命令风暴下同时刻线程数 ≤ PROBE_THREAD_MAX。"""

    def setUp(self):
        self._orig_worker = hts.HandTrackingServer._probe_matrix_worker

    def tearDown(self):
        hts.HandTrackingServer._probe_matrix_worker = self._orig_worker

    def _make_server(self):
        with mock.patch.object(hts, "CameraSelector"), \
             mock.patch.object(hts, "UDPSender"):
            server = hts.HandTrackingServer(udp_port=4242)
        server.camera_selector = mock.MagicMock(name="camera_selector")
        server.udp_sender = mock.MagicMock(name="udp_sender")
        server.headless = True
        return server

    def test_thread_cap_under_command_storm(self):
        self.assertTrue(hasattr(hts, "PROBE_THREAD_MAX"), "PROBE_THREAD_MAX 常量在位（红态=缺失）")
        self.assertEqual(hts.PROBE_THREAD_MAX, 1, "探测线程同时刻上限=1")
        server = self._make_server()
        gate = threading.Event()

        def blocked_worker(pid):
            gate.wait(timeout=10.0)   # 占住在忙态，模拟慢探测

        hts.HandTrackingServer._probe_matrix_worker = blocked_worker
        try:
            for i in range(6):
                server._execute_control_command(f"PROBE_MATRIX:{i % 2}")
            alive = [t for t in threading.enumerate()
                     if t.name == "probe-matrix" and t.is_alive()]
            self.assertLessEqual(
                len(alive), hts.PROBE_THREAD_MAX,
                f"命令风暴（6 连发）→ 探测线程 ≤{hts.PROBE_THREAD_MAX}（实际 {len(alive)}）——长跑不增线程")
            self.assertEqual(getattr(server, "_probe_spawn_count", 0), 1,
                             "6 次命令只 spawn 1 次（在忙复用/拒绝并发创建）")
        finally:
            gate.set()
            if server._probe_thread is not None:
                server._probe_thread.join(timeout=3.0)

    def test_spawn_entry_exists(self):
        self.assertTrue(hasattr(hts.HandTrackingServer, "_spawn_probe_thread"),
                        "Z5-8：探测线程单点入口 _spawn_probe_thread 在位（红态=散点 Thread.start）")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
