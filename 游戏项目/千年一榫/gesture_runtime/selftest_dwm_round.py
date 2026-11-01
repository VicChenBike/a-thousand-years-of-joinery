#!/usr/bin/env python3
"""DWM 原生圆角自测（修复2：Windows 11 圆角窗口）。

TDD 断言（ctypes 调用封装为可注入纯函数，finder/setter 均可 mock，无窗口环境也应全绿）：
  A. 常量契约：DWMWA_WINDOW_CORNER_PREFERENCE=33 / DWMWCP_ROUND=2 /
     DWMWA_BORDER_COLOR=34 / COLOR_NONE=0xFFFFFFFE / 环境变量名 QNSX_DWM_ROUND
  B. enable_dwm_round：按 PID 找窗口→两参设置（33=2、34=COLOR_NONE）→失败降级不抛异常
  C. dwm_round_probe：能力预检（对现有窗口试调 33=2），S_OK 才算支持，试探后还原
  D. build_game_env：仅当预检通过才注入 QNSX_DWM_ROUND=1，且不改传入 dict
  E. launcher 集成源码证据链（Popen 带 env、enable_dwm_round 挂接、线程化不阻塞）
  F. 批次 U-C v2（用户 2026-09-19 二次截图反馈）：apply_window_region 区域裁剪行为
     （finder/rect_fn/rgn_fn/rgn_setter 全注入零 Windows 依赖）＋ enable 成功路径附带
     region 且失败不阻断（B8/B9）＋ Win10 备案链路 enable 失败+region 成功落标记联动
实机段（可选）：dwm_round_probe 真调（本机 Win11 预期 True；Win10 预期 False），
只断言返回 bool 且不抛异常，launcher 实弹由主会话负责。
判绿：末行输出 SELFTEST PASSED，退出码 0。
"""

import sys
from pathlib import Path

import launcher as lw

SCRIPT_DIR = Path(__file__).resolve().parent
FAILS = []


def expect(cond, label):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILS.append(label)


class RecordingSetter:
    """记录 (hwnd, attr, value) 调用序列的 setter 假体，返回值可脚本化。"""

    def __init__(self, returns=0, raise_on=None):
        self.calls = []
        self.returns = returns
        self.raise_on = raise_on  # 第几次调用抛异常（1 起）

    def __call__(self, hwnd, attribute, value):
        self.calls.append((hwnd, attribute, value))
        if self.raise_on is not None and len(self.calls) >= self.raise_on:
            raise RuntimeError("setter boom")
        return self.returns


def section_a():
    print("\n[A] 常量契约")
    expect(lw.DWMWA_WINDOW_CORNER_PREFERENCE == 33, "A1 DWMWA_WINDOW_CORNER_PREFERENCE=33")
    expect(lw.DWMWCP_ROUND == 2, "A2 DWMWCP_ROUND=2")
    expect(lw.DWMWA_BORDER_COLOR == 34, "A3 DWMWA_BORDER_COLOR=34")
    expect(lw.COLOR_NONE == 0xFFFFFFFE, "A4 COLOR_NONE=0xFFFFFFFE")
    expect(lw.QNSX_DWM_ROUND_ENV == "QNSX_DWM_ROUND", "A5 环境变量名 QNSX_DWM_ROUND")


def section_b():
    print("\n[B] enable_dwm_round（finder/setter 可注入）")
    # B1 正常路径：两参设置顺序与取值正确
    calls = RecordingSetter()
    ok = lw.enable_dwm_round(4242, finder=lambda pid: 12345, setter=calls)
    expect(ok is True, "B1 返回 True")
    expect(calls.calls == [(12345, 33, 2), (12345, 34, 0xFFFFFFFE)],
           f"B1 调用参数正确（{calls.calls}）")
    # B2 找不到窗口：setter 不被调用、返回 False、不抛异常
    calls = RecordingSetter()
    try:
        ok = lw.enable_dwm_round(999999, finder=lambda pid: None, setter=calls)
        expect(ok is False and calls.calls == [], "B2 找不到窗口降级 False 且零调用")
    except Exception as e:
        expect(False, f"B2 找不到窗口降级 False 且零调用（意外抛出 {e}）")
    # B3 setter 抛异常：降级 False 不抛出
    calls = RecordingSetter(raise_on=1)
    try:
        ok = lw.enable_dwm_round(1, finder=lambda pid: 7, setter=calls)
        expect(ok is False, "B3 setter 异常降级 False")
    except Exception as e:
        expect(False, f"B3 setter 异常降级 False（意外抛出 {e}）")
    # B4 setter 返回非零（Win10 E_INVALIDARG 语义）：降级 False
    calls = RecordingSetter(returns=0x80070057)
    ok = lw.enable_dwm_round(1, finder=lambda pid: 7, setter=calls)
    expect(ok is False, "B4 HRESULT 非零降级 False")
    # B5 corner 成功但 border 失败：整体判 False
    class MixedSetter:
        def __init__(self):
            self.calls = []
        def __call__(self, hwnd, attribute, value):
            self.calls.append((hwnd, attribute, value))
            return 0 if attribute == 33 else 5
    mixed = MixedSetter()
    ok = lw.enable_dwm_round(1, finder=lambda pid: 7, setter=mixed)
    expect(ok is False and len(mixed.calls) == 2, "B5 border 失败整体 False（两次调用都在）")
    # B6 finder 抛异常：降级 False 不抛出
    def boom_finder(pid):
        raise RuntimeError("finder boom")
    try:
        ok = lw.enable_dwm_round(1, finder=boom_finder, setter=RecordingSetter())
        expect(ok is False, "B6 finder 异常降级 False")
    except Exception as e:
        expect(False, f"B6 finder 异常降级 False（意外抛出 {e}）")
    # B7 默认 finder 路径（真实 ctypes）：不存在的 PID + 极短超时 → False 不挂起
    import time as _t
    t0 = _t.monotonic()
    try:
        ok = lw.enable_dwm_round(999999, setter=RecordingSetter(), timeout=0.2, poll=0.05)
        expect(ok is False and (_t.monotonic() - t0) < 3.0,
               "B7 默认 finder 超时降级且不挂起")
    except Exception as e:
        expect(False, f"B7 默认 finder 超时降级且不挂起（意外抛出 {e}）")
    # ---- 批次 U-C v2（用户 2026-09-19 二次截图反馈）：enable 成功路径附带区域裁剪（+3）----
    # B8 v2：enable 成功 → region_fn 恰被调用一次且 hwnd 透传
    region_calls = []
    calls = RecordingSetter()
    ok = lw.enable_dwm_round(4242, finder=lambda pid: 12345, setter=calls,
                             region_fn=lambda h: region_calls.append(h) or True)
    expect(ok is True and region_calls == [12345],
           f"B8 v2：enable 成功附带 region(hwnd) 恰一次（{region_calls}）")
    # B9 v2：region 失败/异常不阻断 DWM 形态（enable 仍 True——失败仅日志）
    try:
        ok = lw.enable_dwm_round(4242, finder=lambda pid: 12345, setter=RecordingSetter(),
                                 region_fn=lambda h: False)
        expect(ok is True, "B9 v2：region 失败仅日志不阻断（enable 仍 True）")
    except Exception as e:
        expect(False, f"B9 v2：region 失败仅日志不阻断（意外抛出 {e}）")

    def _boom_region(h):
        raise RuntimeError("region boom")
    try:
        ok = lw.enable_dwm_round(4242, finder=lambda pid: 12345, setter=RecordingSetter(),
                                 region_fn=_boom_region)
        expect(ok is True, "B9 v2：region 异常不阻断（enable 仍 True）")
    except Exception as e:
        expect(False, f"B9 v2：region 异常不阻断（意外抛出 {e}）")


def section_c():
    print("\n[C] dwm_round_probe 能力预检")
    # C1 无可试窗口 → 按版本号兜底判据分两路，setter 零调用
    calls = RecordingSetter()
    orig = lw._win11_or_later
    try:
        lw._win11_or_later = lambda: False
        expect(lw.dwm_round_probe(get_hwnd=lambda: 0, setter=calls) is False,
               "C1a 无窗口+版本不支持 → False")
        expect(calls.calls == [], "C1a 无窗口路径 setter 零调用")
        lw._win11_or_later = lambda: True
        expect(lw.dwm_round_probe(get_hwnd=lambda: 0, setter=RecordingSetter()) is True,
               "C1b 无窗口+版本支持（Win11+）→ True")
    except Exception as e:
        expect(False, f"C1 无窗口兜底判据（意外抛出 {e}）")
    finally:
        lw._win11_or_later = orig
    # C2 试调成功（S_OK）→ True，且试探后还原为默认
    calls = RecordingSetter()
    ok = lw.dwm_round_probe(get_hwnd=lambda: 555, setter=calls)
    expect(ok is True, "C2 S_OK 判支持")
    expect(calls.calls and calls.calls[0] == (555, 33, 2),
           f"C2 首调参数 (555, 33, 2)（{calls.calls}）")
    expect(len(calls.calls) == 2 and calls.calls[1] == (555, 33, 0),
           "C2 试探后还原 DWMWCP_DEFAULT=0")
    # C3 试调返回非零（Win10 E_INVALIDARG）→ 版本号兜底分两路
    calls = RecordingSetter(returns=0x80070057)
    orig = lw._win11_or_later
    try:
        lw._win11_or_later = lambda: False
        expect(lw.dwm_round_probe(get_hwnd=lambda: 555, setter=calls) is False,
               "C3a E_INVALIDARG+版本不支持判 False")
        lw._win11_or_later = lambda: True
        expect(lw.dwm_round_probe(get_hwnd=lambda: 555, setter=RecordingSetter(returns=0x80070057)) is True,
               "C3b 试调拒收+Win11 版本兜底判 True")
    except Exception as e:
        expect(False, f"C3 E_INVALIDARG 兜底两路（意外抛出 {e}）")
    finally:
        lw._win11_or_later = orig
    # C4 setter 抛异常 → False 不抛出
    calls = RecordingSetter(raise_on=1)
    try:
        expect(lw.dwm_round_probe(get_hwnd=lambda: 555, setter=calls) is False,
               "C4 setter 异常判不支持不抛出")
    except Exception as e:
        expect(False, f"C4 setter 异常判不支持不抛出（意外抛出 {e}）")
    # C5 get_hwnd 抛异常 → False 不抛出
    def boom_hwnd():
        raise RuntimeError("hwnd boom")
    try:
        expect(lw.dwm_round_probe(get_hwnd=boom_hwnd, setter=RecordingSetter()) is False,
               "C5 get_hwnd 异常判不支持不抛出")
    except Exception as e:
        expect(False, f"C5 get_hwnd 异常判不支持不抛出（意外抛出 {e}）")


def section_d():
    print("\n[D] build_game_env 环境变量注入（批次 U U9-4 等价替换：env 自动注入废止）")
    base = {"PATH": "X"}
    env = lw.build_game_env(base, True)
    # 批次 U 等价替换（U9-4，spec §4-U9-4）：旧 D1「预检通过注入 QNSX_DWM_ROUND=1」口径废止——
    # 预检（dwm_ok=True）与 enable 实装异步竞态根除，形态信号改经 dwm_round.flag 下发。
    expect(lw.QNSX_DWM_ROUND_ENV not in env,
           "D1 等价替换（U9-4）：dwm_ok=True 也不自动注入（旧「预检通过注入=1」口径废止）")
    expect(env.get("PATH") == "X" and set(env) == {"PATH"},
           "D1 其余环境变量原样保留（返回新 dict 不新增键）")
    expect("QNSX_DWM_ROUND" not in base, "D2 不改动传入的 base dict")
    env = lw.build_game_env(base, False)
    expect("QNSX_DWM_ROUND" not in env, "D3 预检未通过不注入")
    base2 = {"QNSX_DWM_ROUND": "1"}  # 用户手工预设场景：保留
    env = lw.build_game_env(base2, False)
    expect(env.get("QNSX_DWM_ROUND") == "1", "D4 用户手工预设的环境变量保留")


def section_e():
    print("\n[E] launcher 集成源码证据链")
    src = (SCRIPT_DIR / "launcher.py").read_text(encoding="utf-8")
    expect("dwm_ok = dwm_round_probe()" in src, "E1 main 内先做 DWM 能力预检")
    expect("env = build_game_env(os.environ, dwm_ok)" in src,
           "E2 游戏环境变量经 build_game_env 构造")
    expect("subprocess.Popen([GAME_EXE], cwd=os.path.dirname(GAME_EXE), env=env)" in src,
           "E3 游戏 Popen 携带 env 继承传递")
    expect("enable_dwm_round" in src and "game.pid" in src,
           "E4 游戏启动后按 PID 应用 DWM 圆角")
    expect("daemon=True" in src, "E5 DWM 应用不阻塞 launcher 主流程（daemon 线程）")
    # ---- 批次 U v2（用户 2026-09-19 二次截图反馈）断言（+2）：SetWindowRgn 区域裁剪 ----
    expect("CreateRoundRectRgn" in src and "SetWindowRgn" in src,
           "E6 v2：launcher 含 CreateRoundRectRgn+SetWindowRgn 区域裁剪（Win10 靠 region 也出圆角）")
    expect("apply_window_region" in src and "write_dwm_flag" in src,
           "E7 v2：区域裁剪与形态标记联动（region/DWM 任一成功落 dwm_round.flag）")


def section_real():
    print("\n[实机段] dwm_round_probe 真调（可选，launcher 实弹由主会话负责）")
    try:
        ok = lw.dwm_round_probe()
        print(f"[实机] dwm_round_probe 返回: {ok}")
        expect(isinstance(ok, bool), "实机预检返回 bool 且不抛异常")
    except Exception as e:
        expect(False, f"实机预检返回 bool 且不抛异常（意外抛出 {e}）")


def section_f():
    # ---- 批次 U-C v2（用户 2026-09-19 二次截图反馈）：apply_window_region 行为断言（5 expect）----
    # 全参数可注入（finder/rect_fn/rgn_fn/rgn_setter），全注入时零 Windows 依赖；失败仅日志。
    print("\n[F] v2 区域裁剪 apply_window_region（finder/rect_fn/rgn_fn/rgn_setter 可注入）")
    # F1 全链成功：finder→hwnd、rect_fn→(800,600)、rgn_fn→句柄、rgn_setter 记录 → True
    seen = {}
    ok = lw.apply_window_region(4242, finder=lambda p: 777,
                                rect_fn=lambda h: (800, 600),
                                rgn_fn=lambda w, h, r: 4242,
                                rgn_setter=lambda h, r: seen.update(hwnd=h, rgn=r) or True)
    expect(ok is True and seen.get("hwnd") == 777 and seen.get("rgn") == 4242,
           f"F1 v2：全链成功 True（hwnd/rgn 透传正确 {seen}）")
    # F2 找不到窗口 → False
    expect(lw.apply_window_region(999999, finder=lambda p: None,
                                  rect_fn=lambda h: (800, 600),
                                  rgn_fn=lambda w, h, r: 1,
                                  rgn_setter=lambda h, r: True) is False,
           "F2 v2：找不到窗口 False")
    # F3 rect_fn 返回 (0,0)（GetClientRect 失败语义）→ False 且 rgn_fn/rgn_setter 零调用
    called = []
    expect(lw.apply_window_region(4242, finder=lambda p: 777,
                                  rect_fn=lambda h: (0, 0),
                                  rgn_fn=lambda w, h, r: called.append(("rgn", w, h, r)) or 1,
                                  rgn_setter=lambda h, r: called.append(("set", h, r)) or True) is False
           and called == [],
           f"F3 v2：客户区尺寸异常 False 且后续零调用（{called}）")
    # F4 rgn_setter 返回 False → False
    expect(lw.apply_window_region(4242, finder=lambda p: 777,
                                  rect_fn=lambda h: (800, 600),
                                  rgn_fn=lambda w, h, r: 4242,
                                  rgn_setter=lambda h, r: False) is False,
           "F4 v2：SetWindowRgn 失败 False")
    # F5 rgn_fn 返回 0（CreateRoundRectRgn 失败语义）/ rect_fn 抛异常 → False 不抛出
    try:
        expect(lw.apply_window_region(4242, finder=lambda p: 777,
                                      rect_fn=lambda h: (800, 600),
                                      rgn_fn=lambda w, h, r: 0,
                                      rgn_setter=lambda h, r: True) is False,
               "F5 v2：CreateRoundRectRgn 失败（返回 0）False")
    except Exception as e:
        expect(False, f"F5 v2：CreateRoundRectRgn 失败（意外抛出 {e}）")

    def _boom_rect(h):
        raise RuntimeError("rect boom")
    try:
        expect(lw.apply_window_region(4242, finder=lambda p: 777,
                                      rect_fn=_boom_rect,
                                      rgn_fn=lambda w, h, r: 1,
                                      rgn_setter=lambda h, r: True) is False,
               "F5 v2：rect_fn 异常降级 False 不抛出")
    except Exception as e:
        expect(False, f"F5 v2：rect_fn 异常降级 False 不抛出（意外抛出 {e}）")


def main() -> int:
    section_a()
    section_b()
    section_c()
    section_d()
    section_e()
    section_f()
    section_real()
    # ---- 批次 U（U9-4，spec §4-U9-4）断言段：env 自动注入废止＋标记文件三态＋预清（6 expect）----
    # （双审回修③ 缩进适配：整块自模块级 0 缩进逐行整体平移至 main() 4 空格缩进区，内容零改动，
    # global _written 声明随平移保留；落位后本文件判绿口径=末行 SELFTEST PASSED 不变。）
    import os as _os
    _env = lw.build_game_env({"A": "1"}, True)
    expect(lw.QNSX_DWM_ROUND_ENV not in _env, "U9-4：build_game_env 不再自动注入 QNSX_DWM_ROUND（dwm_ok=True 也不注入——预检与实装竞态根除）")
    _env_manual = lw.build_game_env({lw.QNSX_DWM_ROUND_ENV: "1"}, False)
    expect(_env_manual.get(lw.QNSX_DWM_ROUND_ENV) == "1", "U9-4：用户手工预设透传保留（dwm_ok=False 不清除）")
    _tmp_flag = str(Path(_os.environ.get("TEMP", ".")) / "u_dwm_flag_test")
    _orig_flag_fn = lw.dwm_flag_path
    lw.dwm_flag_path = lambda: _tmp_flag   # 路径注入（测试隔离，不触真实 user://）
    try:
        if _os.path.exists(_tmp_flag):
            _os.remove(_tmp_flag)
        lw.write_dwm_flag()
        expect(_os.path.exists(_tmp_flag), "U9-4：enable 成功 → 写 dwm_round.flag（游戏侧轮询消费）")
        lw.clear_dwm_flag()
        expect(not _os.path.exists(_tmp_flag), "U9-4：启动预清旧标记（双审 P2-8：launcher 每次启动先清后写）")
        # 实施修正留痕（计划稿缺陷）：计划块在此处先 lw.write_dwm_flag() 再断言「enable 失败 →
        # not exists」自相矛盾——预写的标记在 enable 失败后仍在盘，not exists 恒 False（绿灯期
        # 实测 FAIL 实锤）。按断言语义（enable 失败不得凭空产生标记，游戏保持备案形态）删去该
        # 预写行，直接走 enable 失败路径后断言文件不存在。
        _written = False
        def _enable_and_mark_under_test(pid: int) -> None:
            global _written
            if lw.enable_dwm_round(pid, finder=lambda p: None):   # finder 恒 None=窗口超时=失败路径
                lw.write_dwm_flag()
                _written = True
        _enable_and_mark_under_test(12345)
        expect(not _written and not _os.path.exists(_tmp_flag), "U9-4：enable 失败 → 不写标记（游戏保持备案形态）")
        # ---- 批次 U-C v2（用户 2026-09-19 二次截图反馈）：区域裁剪与形态标记联动镜像（+1）----
        # Win10 备案链路：enable 失败（E_INVALIDARG）但 region 成功 → 同落 dwm_round.flag
        #（游戏侧画半径 8 圆角环与 region 裁切弧贴合）。镜像 main._enable_and_mark 的 v2 联动式
        #（ok=enable→失败再 region→任一成功写标记）；用列表单元规避 global/_written 局部歧义。
        _cell = [False]
        def _enable_and_mark_v2_under_test(pid: int) -> None:
            ok = lw.enable_dwm_round(pid, finder=lambda p: 7,
                                     setter=RecordingSetter(returns=0x80070057))  # Win10 E_INVALIDARG
            if not ok:
                ok = lw.apply_window_region(pid, finder=lambda p: 7,
                                            rect_fn=lambda h: (800, 600),
                                            rgn_fn=lambda w, h, r: 99,
                                            rgn_setter=lambda h, r: True)
            if ok:
                lw.write_dwm_flag()
                _cell[0] = True
        _enable_and_mark_v2_under_test(12345)
        expect(_cell[0] and _os.path.exists(_tmp_flag),
               "v2：enable 失败（Win10 E_INVALIDARG）+region 成功 → 落 dwm_round.flag（区域裁剪与形态标记联动）")
    finally:
        lw.dwm_flag_path = _orig_flag_fn
        if _os.path.exists(_tmp_flag):
            _os.remove(_tmp_flag)
    expect("dwm_round.flag" in lw.dwm_flag_path() and "千年一榫" in lw.dwm_flag_path(),
           "U9-4：标记路径=user:// 目录（项目名常量固化推导 %APPDATA%/Godot/app_userdata/千年一榫/）")
    if not FAILS:
        print("\nSELFTEST PASSED（DWM 圆角：假 finder/setter 全绿 + 集成源码证据链 + 实机预检）")
        return 0
    print(f"\nSELFTEST FAILED: {len(FAILS)} 项 -> {FAILS}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
