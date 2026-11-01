#!/usr/bin/env python3
"""枚举探测自测（修复1：摄像头枚举空导致游戏内下拉无可选项）。

TDD 断言（纯函数 + 可注入假 prober，无摄像头环境也应全绿）：
  A. try_read_frames 重试读帧判定（DSHOW/MSMF 首帧超时假阴性→连续多次+帧间短 sleep）
  B. probe_camera_usable 临时开-验证-立即 release（open_fn/verify_fn 可注入）
  C. enumerate_cameras 逐索引探测（每索引超时上限 + 总时长上限，防卡死循环）
  D. build_camera_entries 探测结果→条目列表（契约 [{"id":int,"name":str}]，id=CAP 索引）
  E. backfill_camera_entry 打开成功后回填实际设备（幂等）
  F. pick_auto_camera 自动选择（批次 AC 领域二等价改写：**黑名单过滤 + 关键词优先 +
     非黑名单最低索引回落 + 无可选设备返回 None**；旧「空列表兜底 0 / 恒最低索引」废止）
  G. hand_tracking_server / camera_selector 集成源码证据链（无摄像头不可达路径以源码固化）
  CTRL. 控制命令段：GET_CAMERAS 拉取命令 → 触发含 cameras+current_camera 的 init 重发
        （修复批 2026-09-18：init#1 一次性消息因启动时序丢失——服务端 t≈0.1s 即发、
        游戏进程 t≈17s 才绑定 9876；新增 9878 拉取命令 + 未知命令静默现状锁）
CAM-GATE. 禁摄像头护栏（B1，2026-09-25）：默认态调用 section_real()/section_h()
        不得触发任何真实枚举（假体计数=0 才判绿）；AA_ALLOW_REAL_CAMERA=1 才放行。
实机段：**默认跳过**（用户 2026-09-25 摄像头红线：本机 CAP 0/1 即荣耀
        Magic 7 前后摄，禁止枚举）；仅显式设 AA_ALLOW_REAL_CAMERA=1 时才真机枚举
        （临时开-验证-立即 release），打印实机枚举结果原文。
判绿：末行输出 SELFTEST PASSED，退出码 0。
"""

import os
import socket
import sys
import time
from pathlib import Path

import camera_selector as cs
# 顶层预 import：hand_tracking_server 模块级会替换 sys.stdout（其 UTF-8 编码修复），
# 若推迟到段内 import，此前已 print 且仍在块缓冲中的段落输出会在重定向时丢失
#（红灯轮实证：A~G 段输出全丢、CTRL 段置顶）——提前到任何 print 之前完成一次性切换。
import hand_tracking_server as hts

SCRIPT_DIR = Path(__file__).resolve().parent
FAILS = []


def expect(cond, label):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILS.append(label)


class FakeReader:
    """try_read_frames 的 reader 假体：按脚本逐次返回 (ret, frame)，越界复用末项。"""

    def __init__(self, script):
        self.script = list(script)
        self.calls = 0

    def __call__(self):
        self.calls += 1
        item = self.script[self.calls - 1] if self.calls <= len(self.script) else self.script[-1]
        if isinstance(item, Exception):
            raise item
        return item


class FakeCap:
    """probe_camera_usable 的 cap 假体。"""

    def __init__(self, opened=True, read_script=None):
        self._opened = opened
        self._read_script = list(read_script) if read_script is not None else [(True, "frame")]
        self.read_calls = 0
        self.released = False

    def isOpened(self):
        return self._opened

    def read(self):
        self.read_calls += 1
        item = (self._read_script[self.read_calls - 1]
                if self.read_calls <= len(self._read_script) else self._read_script[-1])
        if isinstance(item, Exception):
            raise item
        return item

    def release(self):
        self.released = True


class SleepRecorder:
    def __init__(self):
        self.calls = []

    def __call__(self, t):
        self.calls.append(t)


def section_a():
    print("\n[A] try_read_frames 重试读帧判定")
    # A1 全成功：一次即真
    r = FakeReader([(True, "f")])
    expect(cs.try_read_frames(r, tries=3, sleeper=SleepRecorder()) is True,
           "A1 首帧即真返回 True")
    expect(r.calls == 1, f"A1 成功后不再重试（calls={r.calls}）")
    # A2 前两帧假阴性第三帧成功：重试后真
    r = FakeReader([(False, None), (False, None), (True, "f")])
    ok = cs.try_read_frames(r, tries=3, sleeper=SleepRecorder())
    expect(ok is True and r.calls == 3, f"A2 第3帧成功（ok={ok}, calls={r.calls}）")
    # A3 全失败：tries 次后放弃，帧间短 sleep（tries-1 次）
    r = FakeReader([(False, None)])
    sr = SleepRecorder()
    ok = cs.try_read_frames(r, tries=3, frame_wait=0.08, sleeper=sr)
    expect(ok is False and r.calls == 3, f"A3 全失败返回 False（calls={r.calls}）")
    expect(sr.calls == [0.08, 0.08], f"A3 帧间 sleep=tries-1 次且间隔正确（{sr.calls}）")
    # A4 reader 抛异常：判失败不抛出
    r = FakeReader([RuntimeError("boom")])
    try:
        ok = cs.try_read_frames(r, tries=3, sleeper=SleepRecorder())
        expect(ok is False, "A4 reader 异常判 False 不抛出")
    except Exception as e:
        expect(False, f"A4 reader 异常判 False 不抛出（意外抛出 {e}）")
    # A5 tries=1：失败后无 sleep
    r = FakeReader([(False, None)])
    sr = SleepRecorder()
    ok = cs.try_read_frames(r, tries=1, sleeper=sr)
    expect(ok is False and sr.calls == [], f"A5 tries=1 无帧间 sleep（{sr.calls}）")


def section_a2():
    print("\n[A2] decode_console_bytes（P0 回修：字节捕获+显式解码双保险）")
    expect(cs.decode_console_bytes("摄像头 0".encode("gbk")) == "摄像头 0",
           "A2-1 GBK 字节正确解码（中文 Windows 控制台常态）")
    expect(cs.decode_console_bytes("€".encode("utf-8")) == "€",
           "A2-2 GBK 严格解码失败转 UTF-8 成功")
    try:
        out = cs.decode_console_bytes(b"\xff\xff\xff")
        expect(isinstance(out, str) and out != "", "A2-3 双重非法字节 replace 兜底不抛异常")
    except Exception as e:
        expect(False, f"A2-3 双重非法字节 replace 兜底不抛异常（意外抛出 {e}）")
    expect(cs.decode_console_bytes(None) == "", "A2-4 None 入参返回空串（绝不 None 出参）")
    expect(cs.decode_console_bytes(b"") == "", "A2-5 空字节返回空串")
    expect(cs.decode_console_bytes(b"ok") == "ok", "A2-6 ASCII 原样")
    expect(cs.decode_console_bytes("already str") == "already str", "A2-7 str 入参原样透传")


def section_b():
    print("\n[B] probe_camera_usable 临时开-验证-立即 release")
    # B1 打开+读帧成功 → True 且立即 release
    cap = FakeCap(opened=True, read_script=[(True, "f")])
    ok = cs.probe_camera_usable(0, open_fn=lambda i: cap)
    expect(ok is True, "B1 可用判定 True")
    expect(cap.released, "B1 验证后立即 release")
    # B2 open_fn 返回 None → False
    expect(cs.probe_camera_usable(1, open_fn=lambda i: None) is False,
           "B2 打开失败返回 None → False")
    # B3 cap 未打开 → False
    cap = FakeCap(opened=False)
    expect(cs.probe_camera_usable(1, open_fn=lambda i: cap) is False,
           "B3 isOpened()=False → False")
    # B4 open_fn 抛异常 → False 不抛出
    def boom(i):
        raise RuntimeError("open boom")
    try:
        expect(cs.probe_camera_usable(2, open_fn=boom) is False,
               "B4 open_fn 异常判 False 不抛出")
    except Exception as e:
        expect(False, f"B4 open_fn 异常判 False 不抛出（意外抛出 {e}）")
    # B5 首帧超时假阴性→重试读帧后成功（读帧判定走 try_read_frames）
    cap = FakeCap(opened=True, read_script=[(False, None), (False, None), (True, "f")])
    sr = SleepRecorder()
    ok = cs.probe_camera_usable(0, open_fn=lambda i: cap, sleeper=sr)
    expect(ok is True and cap.read_calls == 3, f"B5 首帧假阴性重试成功（calls={cap.read_calls}）")
    expect(cap.released, "B5 成功后仍立即 release")
    expect(len(sr.calls) == 2, f"B5 帧间短 sleep（{sr.calls}）")
    # B6 全读帧失败 → False 且 release
    cap = FakeCap(opened=True, read_script=[(False, None)])
    ok = cs.probe_camera_usable(0, open_fn=lambda i: cap, sleeper=SleepRecorder())
    expect(ok is False and cap.released, "B6 读帧全败 → False 且 release")
    # B7 verify_fn 显式注入覆盖默认
    cap = FakeCap(opened=True, read_script=[(False, None)])
    ok = cs.probe_camera_usable(0, open_fn=lambda i: cap, verify_fn=lambda c: True)
    expect(ok is True, "B7 verify_fn 可注入覆盖默认")


def section_c():
    print("\n[C] enumerate_cameras 逐索引探测 + 超时上限")
    # C1 正常枚举：0 与 2 可用
    caps = {0: FakeCap(), 2: FakeCap()}
    results = cs.enumerate_cameras(max_index=3, open_fn=lambda i: caps.get(i),
                                   sleeper=SleepRecorder())
    expect(results == [(0, True), (1, False), (2, True), (3, False)],
           f"C1 结果含可用标记且顺序正确（{results}）")
    # C2 单索引超时：open_fn 阻塞 2s > 预算 0.3s → 该索引判 False 且不等待阻塞结束
    def slow_open(i):
        time.sleep(2.0)
        return FakeCap()
    t0 = time.monotonic()
    results = cs.enumerate_cameras(max_index=3, open_fn=slow_open,
                                   per_index_budget=0.3)
    dt = time.monotonic() - t0
    expect(all(ok is False for _i, ok in results),
           f"C2 超预算索引判 False（{results}）")
    expect(dt < 3.0, f"C2 不等待阻塞 open 结束（耗时 {dt:.2f}s < 3s）")
    # C3 总时长上限：逐索引 0.5s、总预算 0.9s → 提前停止（结果数 < 4）
    def medium_open(i):
        time.sleep(0.5)
        return FakeCap()
    t0 = time.monotonic()
    results = cs.enumerate_cameras(max_index=3, open_fn=medium_open,
                                   per_index_budget=2.0, total_budget=0.9)
    dt = time.monotonic() - t0
    expect(len(results) < 4 and results and results[0] == (0, True),
           f"C3 总预算提前停止（n={len(results)}, {results}）")
    expect(dt < 3.0, f"C3 总时长受控（{dt:.2f}s < 3s）")


def section_d():
    print("\n[D] build_camera_entries 探测结果→条目列表")
    # D1 过滤不可用 + 回填名 + 缺省名
    entries = cs.build_camera_entries([(0, True), (1, False), (3, True)],
                                      {0: "HD WebCam"})
    expect(entries == [{"id": 0, "name": "HD WebCam"}, {"id": 3, "name": "摄像头 3"}],
           f"D1 过滤+回填+缺省名（{entries}）")
    # D2 空探测结果 → 空列表
    expect(cs.build_camera_entries([], {}) == [], "D2 空结果 → 空列表")
    # D3 全不可用 → 空列表
    expect(cs.build_camera_entries([(0, False), (1, False)], {0: "X"}) == [],
           "D3 全不可用 → 空列表")
    # D4 输入乱序 → 按 id 升序
    entries = cs.build_camera_entries([(2, True), (0, True)], {})
    expect([c["id"] for c in entries] == [0, 2], f"D4 按 id 升序（{entries}）")
    # D5 全部缺省名
    entries = cs.build_camera_entries([(1, True)], None)
    expect(entries == [{"id": 1, "name": "摄像头 1"}], f"D5 无回填名用「摄像头 N」（{entries}）")
    # D6 契约形状：id 为 int、name 为 str
    entries = cs.build_camera_entries([(0, True)], {0: "Cam"})
    expect(all(isinstance(c["id"], int) and isinstance(c["name"], str) for c in entries),
           'D6 契约形状 [{"id":int,"name":str}]')
    # D7~D9（P0 回修）：回填名防 None/防非字符串，逐条 isinstance(str) 过滤
    entries = cs.build_camera_entries([(0, True)], {0: None})
    expect(entries == [{"id": 0, "name": "摄像头 0"}], f"D7 None 回填名过滤（{entries}）")
    entries = cs.build_camera_entries([(0, True)], {0: 123})
    expect(entries == [{"id": 0, "name": "摄像头 0"}], f"D8 非 str 回填名过滤（{entries}）")
    entries = cs.build_camera_entries([(0, True)], "not-a-dict")
    expect(entries == [{"id": 0, "name": "摄像头 0"}], f"D9 非 dict 回填表防炸（{entries}）")


def section_e():
    print("\n[E] backfill_camera_entry 打开成功后回填")
    # E1 新条目追加并保持升序
    entries = [{"id": 0, "name": "摄像头 0"}]
    out = cs.backfill_camera_entry(entries, 2, name="USB Cam")
    expect(out == [{"id": 0, "name": "摄像头 0"}, {"id": 2, "name": "USB Cam"}],
           f"E1 追加并升序（{out}）")
    # E2 幂等：已存在不重复
    entries = [{"id": 0, "name": "摄像头 0"}]
    cs.backfill_camera_entry(entries, 0, name="Another")
    expect(len(entries) == 1 and entries[0]["name"] == "摄像头 0",
           f"E2 已存在不重复不改名（{entries}）")
    # E3 无名时缺省「摄像头 N」
    entries = []
    out = cs.backfill_camera_entry(entries, 0, name=None)
    expect(out == [{"id": 0, "name": "摄像头 0"}], f"E3 缺省名（{out}）")
    # E4 空枚举兜底回填 auto=0：空列表也能回填
    entries = []
    out = cs.backfill_camera_entry(entries, 0, name="Integrated Camera")
    expect(out and out[0]["id"] == 0, f"E4 空列表回填 auto=0（{out}）")
    # E5（P0 回修）：非 str 名过滤
    out = cs.backfill_camera_entry([], 0, name=123)
    expect(out == [{"id": 0, "name": "摄像头 0"}], f"E5 非 str 名过滤（{out}）")


def section_f():
    print("\n[F] pick_camera_by_name 查名直启（批次 AD 等价改写：黑名单+自动选择退役）")
    # 批次 AD（spec §4.2.1/§4.2.2-4）等价改写留痕（断言数 7→8 只增不减）：
    # AC 的「黑名单过滤 + 关键词优先 + 非黑名单最低索引」整体退役（不再按名称字符串
    # 猜测设备类型，也不再有任何自动缺省设备）。新口径=「按设备名查（忽略大小写与
    # 首尾空格）→ 命中即该设备；未命中/空名 → 降级列表首项；列表空 → None（保持未启动）」。
    expect(cs.pick_camera_by_name([]) is None, "F1 空列表 → None（保持未启动，零开镜）")
    expect(cs.pick_camera_by_name(None) is None, "F1b None 入参 → None（防御）")
    entries = [{"id": 0, "name": "Camera A"}, {"id": 2, "name": "Integrated Camera"}]
    expect(cs.pick_camera_by_name(entries, "integrated camera") == 2,
           f"F2 名称命中（忽略大小写）→ 2（{entries}）")
    entries = [{"id": 2, "name": "Integrated Camera"}, {"id": 0, "name": "Camera A"}]
    expect(cs.pick_camera_by_name(entries, "  Integrated Camera  ") == 2,
           f"F3 首尾空格不影响命中（{entries}）")
    entries = [{"id": 3, "name": "Camera A"}, {"id": 5, "name": "Camera B"}]
    expect(cs.pick_camera_by_name(entries, "Camera X") == 3,
           f"F4 未命中 → 降级列表首项 3（{entries}）")
    entries = [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
               {"id": 2, "name": "HD Camera"}]
    expect(cs.pick_camera_by_name(entries, "HD Camera") == 2,
           f"F5 记忆设备命中 → HD Camera 2（黑名单退役：名字即真值）（{entries}）")
    entries = [{"id": 3, "name": "Camera A"}, {"id": 5, "name": "Camera B"}]
    expect(cs.pick_camera_by_name(entries, "") == 3,
           f"F6 空名 → 降级列表首项（待用户先点设备）（{entries}）")
    expect(not hasattr(cs, "pick_auto_camera")
           and not hasattr(cs, "is_virtual_or_phone_camera")
           and not hasattr(cs, "VIRTUAL_OR_PHONE_CAMERA_KEYWORDS"),
           "F7 黑名单判定/自动选择纯函数彻底退役（AD §4.2.1）")
    expect(not hasattr(cs, "rotate_backend_chain"),
           "F8 后端轮换 chain 彻底退役（AD §4.2.3 单后端直启）")


def section_g():
    print("\n[G] 集成源码证据链（server / camera_selector）")
    server_src = (SCRIPT_DIR / "hand_tracking_server.py").read_text(encoding="utf-8")
    cs_src = (SCRIPT_DIR / "camera_selector.py").read_text(encoding="utf-8")
    # G1 server 枚举主体改用试探枚举
    # 批次 Z（Z4-④ 等价改写）：枚举 open_fn 经句柄单入口注入——锚点由闭括号精确串放宽为
    # 前缀串 + open_fn 注入同现（max_index=3 语义不变，获取路径收敛为 _acquire_camera_handle）。
    # 批次 AA 回修3（W4-P2-3）**等价改写（净强化，零弱化）**：懒探测 worker 的 open_fn 由无门
    # _acquire_probe_open 直注改为受门桩 _lazy_probe_open（AA_ALLOW_REAL_CAMERA 红线门与启动桩
    # _startup_probe_open 同一把）；单入口语义不变——两个受门桩设门路径内部仍收敛
    # _acquire_probe_open → _acquire_camera_handle。故锚点更新为「三注入点同现 + 单入口链在位」。
    expect("enumerate_cameras(max_index=3" in server_src
           and "open_fn=self._lazy_probe_open" in server_src
           and "open_fn=self._startup_probe_open" in server_src
           and "return self._acquire_probe_open(index)" in server_src,
           "G1 server 枚举主体调用 enumerate_cameras(max_index=3) 且 open_fn 经受门桩注入"
           "（启动桩/懒探测桩同门，设门路径收敛句柄单入口——回修3 等价改写）")
    expect("build_camera_entries(probe_results" in server_src,
           "G2 server 用 build_camera_entries 生成条目")
    expect("pick_camera_by_name(self._cameras, name)" in server_src,
           "G3 server 用 pick_camera_by_name 查名直启（AD 等价改写：pick_auto_camera 退役）")
    expect("_backfill_camera_entry(" in server_src and "_send_camera_list_init(" in server_src,
           "G4 server 打开成功后回填+重发含 cameras 的 init")
    # G5 id 语义统一：SWITCH_CAMERA 直用 CAP 索引（现有 :834 逻辑保留）、init 携带 current_camera
    expect('"current_camera"' in server_src and "SWITCH_CAMERA:" in server_src,
           "G5 init 携带 current_camera 且 SWITCH_CAMERA 分支在位")
    # G6 WMI 多链查询（>=4 条 Get-CimInstance）且失败有告警（不再静默吞）
    expect(server_src.count("Get-CimInstance") >= 4,
           f"G6 WMI 多链查询 >=4（实际 {server_src.count('Get-CimInstance')}）")
    expect("尝试下一链" in server_src and "全部失败" in server_src,
           "G7 WMI 查询失败打印告警（不再静默吞）")
    # G8 camera_selector._probe_camera 读帧加重试（旧单次读帧退场）
    expect("try_read_frames(cap.read" in cs_src,
           "G8 camera_selector._probe_camera 用 try_read_frames 重试读帧")
    # G9 _probe_camera 内旧单次读帧判定已移除（_open_camera 的读帧不在本批范围）
    probe_start = cs_src.index("def _probe_camera")
    probe_end = cs_src.index("def _open_camera", probe_start)
    probe_body = cs_src[probe_start:probe_end]
    expect("ret, _ = cap.read()" not in probe_body,
           "G9 _probe_camera 旧单次读帧判定已移除")
    # G10 server 导入新纯函数（括号续行拼接成完整 import 块再判）
    src_lines = server_src.splitlines()
    import_line = ""
    for si, line in enumerate(src_lines):
        if line.startswith("from camera_selector import"):
            import_line = line
            sj = si
            while import_line.count("(") > import_line.count(")") and sj + 1 < len(src_lines):
                sj += 1
                import_line += " " + src_lines[sj].strip()
            break
    for name in ("build_camera_entries", "backfill_camera_entry",
                 "enumerate_cameras", "pick_camera_by_name", "match_camera_by_name"):
        expect(name in import_line, f"G10 from camera_selector import 含 {name}")
    # G11~G13（P0 回修源码锁）：字节捕获显式解码、零 text=True、集成接缝
    expect("decode_console_bytes" in server_src and "decode_console_bytes" in cs_src,
           "G11 server/camera_selector 子进程捕获走显式解码助手")
    expect("text=True" not in server_src and "text=True" not in cs_src,
           "G12 子进程捕获零 text=True（读取线程解码崩溃根除）")
    expect("def _enumerate_cameras_step" in server_src,
           "G13 server 第 1 步枚举抽取为集成接缝 _enumerate_cameras_step")
    expect("def pick_camera_by_name(" in cs_src
           and "def match_camera_by_name(" in cs_src,
           "G14 查名直启纯函数在位（AD 等价改写：旧关键词启发式备案注记随黑名单退役）")


def section_h():
    print("\n[H] 集成段：server 第 1 步枚举真路径直调（真 WMI 查询，中文 GBK 环境回归样本）")
    try:
        server = hts.HandTrackingServer(camera_id=None, udp_port=29876,
                                        frame_port=29877, control_port=29878)
    except Exception as e:
        expect(False, f"H0 server 实例化成功（意外抛出 {e}）")
        return
    try:
        # B1 合规门（2026-09-25 摄像头红线）：默认态把「逐 CAP 索引试探开镜」这一步换成
        # 零开镜假 prober——`_enumerate_cameras_step` 真路径照跑（WMI 显示名查询、
        # build_camera_entries 全真），只枚举动作本身不碰设备；
        # 仅设 AA_ALLOW_REAL_CAMERA=1 才走真枚举（人工真机复验用）。
        if real_camera_allowed():
            cameras, auto_id = server._enumerate_cameras_step()
            _H_PROBE_SOURCE.append("real")
        else:
            print("[SKIP] 按禁摄像头口径：CAP 试探枚举换假 prober（零真实开镜，"
                  "设 AA_ALLOW_REAL_CAMERA=1 走真路径）")
            saved_enum = hts.enumerate_cameras
            hts.enumerate_cameras = _fake_enumerate_for_step
            try:
                cameras, auto_id = server._enumerate_cameras_step()
            finally:
                hts.enumerate_cameras = saved_enum
            _H_PROBE_SOURCE.append("fake")
        expect(isinstance(cameras, list), "H1 第 1 步枚举返回 list（可空，绝不 None）")
        # 批次 AD（spec §4.2.2-1）等价改写：第二返回值（旧 auto 缺省）**恒 None**——
        # 「自动缺省设备」概念随黑名单一起退役（设备启停一律由 Godot 查名直启指令驱动）。
        expect(auto_id is None,
               f"H2 auto 缺省恒 None（AD：不再有自动开镜候选；实际 {auto_id}）")
        usable_ids = [c["id"] for c in cameras]
        # H2b（批次 AD 等价改写）：查名直启口径——命中名返回该设备 id，未命中/空名
        # 降级列表首项，空列表 None。任取首条目名做真命中校验（无条目则只断空闲态）。
        if cameras:
            _first = cameras[0]
            expect(cs.pick_camera_by_name(cameras, str(_first.get("name") or ""))
                   == int(_first["id"]),
                   f"H2b 查名命中实机首条目（{_first}）")
            expect(cs.pick_camera_by_name(cameras, "不存在的相机 X") == int(_first["id"]),
                   f"H2b 未命中 → 降级列表首项（可用={usable_ids}）")
        else:
            expect(cs.pick_camera_by_name(cameras, "任意名") is None,
                   "H2b 空列表 → None（保持未启动，零开镜）")
        expect(all(isinstance(c, dict) and isinstance(c.get("id"), int)
                   and isinstance(c.get("name"), str) for c in cameras),
               "H3 条目形状 {id:int, name:str} 全合规")
        names = server._get_all_camera_names()
        expect(isinstance(names, dict), "H4 WMI 显示名查询返回 dict（绝不 None）")
        expect(all(isinstance(k, int) and isinstance(v, str) and v.strip()
                   for k, v in names.items()),
               "H5 显示名逐条 isinstance(str) 且非空")
        print(f"[集成] WMI 显示名查询结果原文: {names}")
        src_tag = _H_PROBE_SOURCE[-1] if _H_PROBE_SOURCE else "?"
        print(f"[集成] 第 1 步枚举条目原文: {cameras}（auto={auto_id}，枚举来源={src_tag}）")
    except Exception as e:
        expect(False, f"H6 集成路径全程不抛异常（意外抛出 {e}）")
    finally:
        try:
            server._cleanup()
        except Exception:
            pass


class FakeCtrlSock:
    """_check_control_commands 的 control_socket 假体：recvfrom 逐次返回预置命令字节，越界回超时。"""

    def __init__(self, cmds):
        self.cmds = list(cmds)
        self.calls = 0

    def recvfrom(self, _size):
        if self.calls < len(self.cmds):
            self.calls += 1
            return self.cmds[self.calls - 1], ("127.0.0.1", 40000)
        raise socket.timeout()

    def close(self):
        pass


class FakeSender:
    """udp_sender 假体：捕获 send(data) 载荷（不触网）。"""

    def __init__(self):
        self.sent = []

    def send(self, data):
        self.sent.append(data)

    def close(self):
        pass


def section_ctrl():
    print("\n[CTRL] 控制命令段：GET_CAMERAS 拉取命令重发 init#1（修复批 2026-09-18）")
    try:
        server = hts.HandTrackingServer(camera_id=None, udp_port=29886,
                                        frame_port=29887, control_port=29888)
    except Exception as e:
        expect(False, f"CTRL0 server 实例化成功（意外抛出 {e}）")
        return
    try:
        sender = FakeSender()
        server.udp_sender = sender
        # 预置「枚举已完成」状态（_enumerate_cameras_step 产物形状；id=CAP 索引契约）
        server._cameras = [{"id": 0, "name": "HD WebCam"}, {"id": 2, "name": "USB Cam"}]
        server.current_camera_id = 2
        # CTRL1 收到 GET_CAMERAS → 触发含 cameras+current_camera 的 init 重发（拉取模式核心）
        server.control_socket = FakeCtrlSock([b"GET_CAMERAS"])
        server._check_control_commands()
        expect(len(sender.sent) == 1, f"CTRL1 GET_CAMERAS → 恰发 1 包（{len(sender.sent)}）")
        if sender.sent:
            msg = sender.sent[0]
            expect(msg.get("type") == "init", f"CTRL1b type=init（{msg.get('type')}）")
            cams = msg.get("cameras")
            expect(isinstance(cams, list) and len(cams) == 2
                   and all(isinstance(c.get("id"), int) and isinstance(c.get("name"), str)
                           for c in cams),
                   f"CTRL1c cameras 契约形状 [{{id:int,name:str}}]×2（{cams}）")
            expect(msg.get("current_camera") == 2 and isinstance(msg.get("current_camera"), int),
                   f"CTRL1d current_camera=2（{msg.get('current_camera')}）")
        # CTRL2 未知命令行为保持现状：静默零发送（不崩不分发）
        sender.sent.clear()
        server.control_socket = FakeCtrlSock([b"SOME_UNKNOWN_CMD"])
        server._check_control_commands()
        expect(len(sender.sent) == 0, f"CTRL2 未知命令静默零发送（现状保持，{len(sender.sent)}）")
        # CTRL3 无命令（套接字超时路径）：零发送不抛出
        sender.sent.clear()
        server.control_socket = FakeCtrlSock([])
        try:
            server._check_control_commands()
            expect(len(sender.sent) == 0, "CTRL3 无命令（timeout）→ 零发送不抛出")
        except Exception as e:
            expect(False, f"CTRL3 无命令（timeout）→ 零发送不抛出（意外抛出 {e}）")
    finally:
        try:
            server._cleanup()
        except Exception:
            pass


# ======================================================================
# B1 禁摄像头护栏（批次 AA，用户 2026-09-25 摄像头红线）
# 本机 CAP 索引 0/1 = 荣耀 Magic 7 前后摄——默认态**绝不枚举、绝不打开**。
# ======================================================================
REAL_CAM_ENV = "AA_ALLOW_REAL_CAMERA"

# CAM1 计数：默认态 section_real 走真实 enumerate_cameras 的次数（假体埋点，恒应为 0）
_CAM1_CALLS: list = []
# CAM4 计数：默认态 section_h 走真实 enumerate_cameras 的次数（假体埋点，恒应为 0）
_CAM4_CALLS: list = []
# section_h 实际走的枚举来源留痕："real"=真枚举路径 / "fake"=假 prober（默认口径）
_H_PROBE_SOURCE: list = []
# section_h 默认态注入的假 prober 调用计数（>0 证明假 prober 分支真的被执行）
_H_FAKE_CALLS: list = []


def real_camera_allowed() -> bool:
    """B1 合规门：是否允许执行真实摄像头枚举。

    默认（未设 AA_ALLOW_REAL_CAMERA，或值 ≠ "1"）= **禁止**——用户
    2026-09-25 摄像头红线：测试/自测一律不打开、不枚举设备；本机 CAP 0/1 即荣耀
    Magic 7 前后摄，碰一次即违规。仅显式设 `AA_ALLOW_REAL_CAMERA=1` 才放行
    （人工真机复验专用，日常回归与 CI 一律走默认跳过）。
    """
    return os.environ.get(REAL_CAM_ENV, "") == "1"


def _cam1_probe(*_args, **_kwargs):
    """CAM1 埋点假体：替换 cs.enumerate_cameras，只计数、绝不打开设备。"""
    _CAM1_CALLS.append(1)
    return [(0, False)]


def _cam4_probe(*_args, **_kwargs):
    """CAM4 埋点假体：替换 hts.enumerate_cameras（真枚举报警弹），只计数、绝不打开设备。"""
    _CAM4_CALLS.append(1)
    return [(0, False)]


def _fake_enumerate_for_step(*_args, **_kwargs):
    """section_h 默认态注入的假 prober：形状与真探测一致（id=CAP 索引契约），零开镜。"""
    _H_FAKE_CALLS.append(1)
    return [(0, True), (1, False), (2, True), (3, False)]


def section_cam_gate():
    """B1 护栏段：默认态 section_real()/section_h() 零真实枚举（可判红）。

    验证手法 = 把 `enumerate_cameras` 换成**计数假体**后直调被测段：
    假体保证本段全程**零真实开镜**，计数 > 0 即判红——既证明护栏真实有效，
    又不在验证过程本身触碰摄像头（红线 1）。
    """
    print("\n[CAM-GATE] 禁摄像头护栏：默认态零真实枚举（B1，2026-09-25）")
    saved_env = os.environ.pop(REAL_CAM_ENV, None)   # 强制进入默认态（禁摄像头口径）
    real_orig = cs.enumerate_cameras                 # 本段任何路径都要还原的真函数
    try:
        # ---- CAM1：默认态 section_real 不得调用 enumerate_cameras ----
        real_orig = cs.enumerate_cameras
        cs.enumerate_cameras = _cam1_probe
        try:
            _CAM1_CALLS.clear()
            section_real()
        finally:
            cs.enumerate_cameras = real_orig
        expect(len(_CAM1_CALLS) == 0,
               f"CAM1 默认态 section_real 零 enumerate_cameras 调用"
               f"（假体计数 {len(_CAM1_CALLS)} 次，应为 0）")

        # ---- CAM4/CAM5：默认态集成段 H 同样零真实枚举、走假 prober 分支 ----
        hts_orig = hts.enumerate_cameras
        hts.enumerate_cameras = _cam4_probe
        try:
            _H_PROBE_SOURCE.clear()
            _H_FAKE_CALLS.clear()
            section_h()
        finally:
            hts.enumerate_cameras = hts_orig
        expect(len(_CAM4_CALLS) == 0,
               f"CAM4 默认态 section_h 零真实 enumerate_cameras 调用"
               f"（假体计数 {len(_CAM4_CALLS)} 次，应为 0）")
        expect(bool(_H_PROBE_SOURCE) and _H_PROBE_SOURCE[-1] == "fake",
               f"CAM5 默认态 section_h 走假 prober 分支（来源={_H_PROBE_SOURCE}）")
        expect(len(_H_FAKE_CALLS) >= 1,
               f"CAM5b 假 prober 分支真被执行（假体计数 {len(_H_FAKE_CALLS)} 次）")

        # ---- CAM2/CAM3：放行分支存在性（AA_ALLOW_REAL_CAMERA=1 才会执行枚举）----
        # 注意：CAM3 仍把 enumerate_cameras 换成假体执行——证明「代码路径存在」，
        # 但**不真枚举**（该分支的真机执行不在本自测范围，须人工显式开闸）。
        os.environ[REAL_CAM_ENV] = "1"
        expect(real_camera_allowed() is True,
               "CAM2 AA_ALLOW_REAL_CAMERA=1 → 门放行（放行分支存在）")
        cs.enumerate_cameras = _cam1_probe
        try:
            _CAM1_CALLS.clear()
            section_real()
        finally:
            cs.enumerate_cameras = real_orig
        expect(len(_CAM1_CALLS) == 1,
               f"CAM3 放行态 section_real 走枚举路径（假体计数 {len(_CAM1_CALLS)} 次，"
               f"真枚举 0 次）")
    finally:
        cs.enumerate_cameras = real_orig
        if saved_env is None:
            os.environ.pop(REAL_CAM_ENV, None)
        else:
            os.environ[REAL_CAM_ENV] = saved_env


def section_real():
    print("\n[实机段] 真实摄像头枚举（临时开-验证-立即 release）")
    # B1 合规门（2026-09-25 摄像头红线）：默认跳过，绝不在回归里碰本机 CAP 0~3。
    if not real_camera_allowed():
        print("[SKIP] 按禁摄像头口径跳过真实枚举（设 AA_ALLOW_REAL_CAMERA=1 可启用）")
        return
    t0 = time.monotonic()
    real = cs.enumerate_cameras(max_index=3, per_index_budget=2.5, total_budget=12.0)
    dt = time.monotonic() - t0
    print(f"[实机] enumerate_cameras 结果原文: {real}（耗时 {dt:.1f}s）")
    real_entries = cs.build_camera_entries(real, {})
    print(f"[实机] build_camera_entries: {real_entries}")
    expect(dt < 15.0, f"实机枚举总时长受控（{dt:.1f}s < 15s）")
    expect(all(isinstance(i, int) and isinstance(ok, bool) for i, ok in real),
           "实机结果形状 [(int, bool)]")
    usable = [i for i, ok in real if ok]
    if usable:
        expect(len(real_entries) == len(usable), "实机条目数与可用索引数一致")
        print(f"[实机] 可用摄像头 CAP 索引: {usable}")
        if 0 in usable:
            expect(any(c["id"] == 0 for c in real_entries),
                   "实机枚举出 index 0 的条目")
            expect([c["id"] for c in real_entries] == usable,
                   "实机条目 id 与可用 CAP 索引一一对应")
    else:
        print("[实机] 未探测到可用摄像头：按无摄像头环境判绿（假 prober 段已覆盖逻辑）")


def main() -> int:
    section_a()
    section_a2()
    section_b()
    section_c()
    section_d()
    section_e()
    section_f()
    section_g()
    section_ctrl()
    section_h()
    section_cam_gate()
    section_real()
    if not FAILS:
        print("\nSELFTEST PASSED（枚举探测：假 prober 全绿 + 集成源码证据链 + 控制命令段"
              " + 禁摄像头护栏 + 实机段）")
        return 0
    print(f"\nSELFTEST FAILED: {len(FAILS)} 项 -> {FAILS}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
