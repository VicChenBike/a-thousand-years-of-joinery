#!/usr/bin/env python3
"""打包版编排入口（批次 R spec §12.4，复用 D 盘 launcher.py 模式）。

流程：嵌入式 Python 拉起 hand_tracking_server（经 main.py，P=9876）
→ bind 试探 9878（45 秒超时——批次 Z Z-B 回修 P2-c：与桥 gesture_bridge
  PROBE_TIMEOUT_SEC=45 对齐，旧 15s ≪ 桥 45s 就绪判定不对齐）
→ 拉起 千年一榫.exe → 游戏启动后按 PID 对其顶层窗口调
DwmSetWindowAttribute（33=DWMWCP_ROUND、34=COLOR_NONE），**成功才**写标记文件
dwm_round.flag（游戏 user:// 目录；批次 U U9-4：形态信号改经标记文件下发，
env 自动注入废止——预检与实装竞态根除，启动前预清旧标记）；批次 U-C v2（用户
2026-09-19 二次截图反馈）：enable 成功路径另追加 SetWindowRgn 圆角区域裁剪
（CreateRoundRectRgn 覆盖客户区全尺寸，Win11 与 DWM 原生圆角叠加精确贴合、
Win10 靠 region 也出圆角），region/DWM 任一成功同落 dwm_round.flag →
Godot 退出后发 SHUTDOWN + 清理子进程。
导出运行时 Godot 侧 start_gesture_process 跳过拉起（spec §8.3-2），仅探测等待。
"""

import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
PYTHON = sys.executable  # 由 gesture_runtime/python/python.exe（打包）或开发机 Python 执行
GAME_EXE = os.path.join(os.path.dirname(HERE), "千年一榫.exe")
BASE_PORT = int(os.environ.get("QNSX_GESTURE_PORT", "9876"))
CONTROL_PORT = BASE_PORT + 2
# 批次 Z（Z-B 回修 P2-c，spec §4-2）：15.0→45.0——与桥 gesture_bridge.PROBE_TIMEOUT_SEC=45
# 对齐（旧 15s ≪ 桥 45s，launcher 侧「未就绪」与桥侧「延长就绪窗」判定互相矛盾）。
PROBE_TIMEOUT_SEC = 45.0

# 批次 W P2-2（spec §2）：server stdout/stderr 落盘日志——win32 CREATE_NO_WINDOW
# （隐藏子进程控制台窗；非 Windows 无此标志 getattr 恒 0 不影响行为）。
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
LOG_FILENAME = "gesture_runtime.log"
# 批次 Z（Z5-8，spec §5-8 长跑稳定性）：日志轮转——单文件超限滚动为 .N，
# 保留份数有界（.1/.2/.3，最深份删除），长跑不涨盘。
LOG_MAX_BYTES = 5 * 1024 * 1024   # 单文件上限 5MB（真手复验/长跑复盘可一次调参）
LOG_ROTATE_KEEP = 3                # 轮转保留份数（gesture_runtime.log.1/.2/.3）

# ======================================================================
# 路径边界校验（防御硬化，非过扫描空壳）——本模块所有「构造路径 → 读写文件」点
# 统一走三步：①「基础目录」与「文件名」显式分离 ② os.path.abspath 规范化
# ③断言规范化后的目标严格落在声明的基础目录内，越界抛 ValueError 由调用方降级
# （不写盘 / 回落候选下一级 / no-op）。
# 要防的真实风险有两类：
#   a) 基础目录变量为空/相对（如 %APPDATA% 缺失）→ os.path.abspath("")==cwd，
#      相对路径被悄悄锚到进程工作目录 = 落位失控；
#   b) 片段里混入 ".." / 绝对路径片段 → abspath 规范化后逃出预期沙盒 = 路径穿越。
# 两者在此统一被拦下；正常路径下输出与硬化前逐字节一致。
# ======================================================================

def _is_within(base: str, target: str) -> bool:
    """边界判定：规范化后的 target 是否**严格**落在 base 目录内（不含 base 自身）。

    用 os.path.commonpath + normcase 比较（等价于 Path.is_relative_to，但对盘符
    大小写/分隔符形态不敏感）；commonpath 抛 ValueError（如跨盘符）→ 判越界。
    target==base 则判越界：本模块所有目标都是「目录里的文件」，等于目录本身即异常。
    """
    nb, nt = os.path.normcase(base), os.path.normcase(target)
    if nt == nb:
        return False
    try:
        return os.path.commonpath([nb, nt]) == nb
    except ValueError:
        return False


def _require_abs_base(base_dir: str, what: str) -> str:
    """基础目录来源校验：必须非空、且本身即绝对路径；返回其 abspath 规范化形态。

    空串陷阱：os.path.abspath("") == os.getcwd()——若 %APPDATA%/%LOCALAPPDATA%/
    %TEMP% 缺失，直接 join 会把相对路径悄悄锚到进程工作目录。此处显式拒绝
    （抛 ValueError）而不是拼出相对路径，由调用方降级为「不写盘 / 跳过该级」。
    """
    if not base_dir:
        raise ValueError(f"{what}: 基础目录为空（环境变量缺失），拒绝构造写入路径")
    if not os.path.isabs(base_dir):
        raise ValueError(f"{what}: 基础目录非绝对路径 {base_dir!r}，拒绝"
                         f"（防相对路径被 cwd 锚定）")
    return os.path.abspath(base_dir)


def _reject_traversal(what: str, *segments: str,
                      allow_absolute: bool = False) -> None:
    """片段级穿越拒绝（前置闸）：空片段、绝对/带盘符片段、含 '..' 段一律 ValueError。

    分工：规范化后的边界断言（_is_within）是**主闸**——它管「规范化之后落不落在
    base 内」；本函数是**更早、报错更可读的第二道闸**，让「构造期就拼不出越界路径」
    成为结构不变量。allow_absolute=True 仅用于「本就是完整路径」的输入
    （如注入式日志候选），此时仍拒绝其中的 '..' 穿越段——否则 dirname(p) 自带
    '..' 会让 base 自引用、边界断言退化为恒真。
    """
    for seg in segments:
        if not seg:
            raise ValueError(f"{what}: 空路径片段，拒绝")
        p = Path(seg)
        if not allow_absolute and (p.is_absolute() or p.drive):
            raise ValueError(f"{what}: 片段为绝对/带盘符路径 {seg!r}，拒绝")
        if ".." in p.parts:
            raise ValueError(f"{what}: 片段含 '..' 穿越段 {seg!r}，拒绝")


def _safe_join(base_dir: str, *parts: str, what: str = "path") -> str:
    """路径边界校验核心：基础目录 + 文件名片段 → abspath 规范化 → 断言落在 base 内。

    文件名与基础目录在此显式分离：片段含 ".."、片段本身是绝对路径、或 base 为空/
    相对，都会在规范化后被 _reject_traversal/_is_within/_require_abs_base 拦成
    ValueError——物理上写不出基础目录之外。
    """
    base = _require_abs_base(base_dir, what)
    if not parts:
        raise ValueError(f"{what}: 缺少文件名片段，拒绝以目录自身作为写入目标")
    _reject_traversal(what, *parts)
    target = os.path.abspath(os.path.join(base, *parts))
    if not _is_within(base, target):
        raise ValueError(f"{what}: 目标路径越界 base={base!r} target={target!r}，拒绝")
    return target


def _assert_within(base_dir: str, target: str, what: str) -> str:
    """消费点边界断言：把已拼好的完整路径再过一道闸，越界抛 ValueError。

    与 _safe_join 的分工：_safe_join 管「构造期」，本函数管「读写前」——即使路径
    构造函数被替换/注入成越界值（如测试 monkeypatch、或将来新增调用方传错），
    真正的 open/os.remove/os.replace 之前仍会被拦下。返回规范化后的 target。
    """
    base = _require_abs_base(base_dir, what)
    norm = os.path.abspath(target)
    if not _is_within(base, norm):
        raise ValueError(f"{what}: 目标路径越界 base={base!r} target={target!r}，拒绝")
    return norm


def _assert_rotation_bounds(path: str, keep) -> str:
    """轮转边界断言：path 必须是绝对路径，且轮转产物 path.1..path.keep 一个都不能
    逃出日志所在目录（轮转本是「同目录平移」，此处置为显式不变量并强制执行）。
    越界/相对路径 → 抛 ValueError，由 _rotate_log_if_needed 转 False no-op。
    """
    if not os.path.isabs(path):
        raise ValueError(f"日志轮转：路径非绝对 {path!r}，拒绝（防 cwd 锚定）")
    log_dir = os.path.dirname(os.path.abspath(path))
    _require_abs_base(log_dir, "日志轮转目录")
    _assert_within(log_dir, path, "日志轮转目标")
    for i in range(1, int(keep) + 1):
        _assert_within(log_dir, "%s.%d" % (path, i), "日志轮转产物")
    return path


def _rotate_log_if_needed(path: str, max_bytes: int = LOG_MAX_BYTES,
                          keep: int = LOG_ROTATE_KEEP) -> bool:
    """Z5-8：日志超限轮转——path→.1→.2…→.keep（最深份删除），文件数恒 ≤ keep+1。

    无文件/未超限/OSError → False no-op（打不开的候选路径零副作用，回落链语义不变）。
    路径边界校验（防御硬化）：轮转前先过 _assert_rotation_bounds——相对路径、
    越界产物一律 ValueError → 与 OSError 同语义转 False no-op（零副作用、不落盘），
    其余异常（如 TypeError）传播行为与硬化前一致。
    """
    try:
        _assert_rotation_bounds(path, keep)
    except ValueError as e:
        print(f"[launcher] 日志轮转未过路径边界校验，跳过（no-op 降级）: {e}")
        return False
    try:
        if not os.path.exists(path) or os.path.getsize(path) < int(max_bytes):
            return False
        oldest = "%s.%d" % (path, int(keep))
        if os.path.exists(oldest):
            os.remove(oldest)
        for i in range(int(keep) - 1, 0, -1):
            src = "%s.%d" % (path, i)
            if os.path.exists(src):
                os.replace(src, "%s.%d" % (path, i + 1))
        os.replace(path, path + ".1")
        return True
    except OSError:
        return False


def _open_log_stream(candidates=None):
    """P2-2（批次 W 规格 §2）：server stdout/stderr 追加落盘句柄，路径四级回落链：
    运行目录 gesture_runtime.log →（打不开，如 Program Files 标准权限只读）→
    %LOCALAPPDATA%/Godot/千年一榫_logs/ → 再失败 %TEMP% → 全部失败返回 None
    （静默降级零日志，不崩不弹）。
    逐级试写一行探测真实可写（只读目录 makedirs/open 抛 OSError 即跳下一级）；
    行缓冲（buffering=1）+errors=replace（GBK 控制台环境写 UTF-8 不炸）。
    candidates 参数仅供测试注入沙盒路径，生产调用不传。
    路径边界校验（防御硬化）：三级候选的「基础目录」来源固定（HERE / %LOCALAPPDATA% /
    %TEMP%），文件名恒为常量 LOG_FILENAME，一律经 _safe_join 显式分离拼接并 abspath
    规范化 + 越界断言；基础目录缺失/非绝对、或（注入路径）规范化后越界 → ValueError
    → 跳过该级，语义与「打不开」完全相同：回落链顺序、落位、日志内容一律不变。
    open 前消费点再过一道 _assert_within，未过校验的变量绝不直接喂给 open。"""
    if candidates is None:
        # ①「基础目录 + 文件名」显式分离（specs=(base, *子目录与文件名片段)）
        specs = [(HERE, LOG_FILENAME)]
        localappdata = os.environ.get("LOCALAPPDATA", "")
        if localappdata:
            specs.append((localappdata, "Godot", "千年一榫_logs", LOG_FILENAME))
        temp = os.environ.get("TEMP", "")
        if temp:
            specs.append((temp, LOG_FILENAME))
        candidates = []
        for spec in specs:
            try:
                candidates.append(_safe_join(spec[0], *spec[1:], what="日志候选"))
            except ValueError as e:
                print(f"[launcher] 日志候选基础目录非法，跳过该级（降级下一级）: {e}")
    else:
        # ② 注入路径（仅测试沙盒）：同样回拆成 base+文件名再校验——相对路径 /
        # 规范化后越界一律拒绝，不拿未校验的变量直接往下走。
        validated = []
        for p in candidates:
            try:
                if not os.path.isabs(p):
                    raise ValueError(f"日志候选(注入): 非绝对路径 {p!r}，拒绝")
                # 先在完整路径上拒绝 '..' 穿越段（否则 dirname(p) 自带 '..' 会让
                # 下一步的 base 自引用、边界断言退化为恒真），再回拆成 base+文件名
                # 走 _safe_join 的规范化 + 边界断言。
                _reject_traversal("日志候选(注入)", p, allow_absolute=True)
                validated.append(_safe_join(os.path.dirname(p), os.path.basename(p),
                                            what="日志候选(注入)"))
            except ValueError as e:
                print(f"[launcher] 注入日志候选未过路径边界校验，跳过该级（降级）: {e}")
        candidates = validated
    for path in candidates:
        try:
            # open 前消费点边界断言：目录必须绝对、规范化后的目标必须严格落在该目录内，
            # 否则 ValueError → 跳过该级（与 OSError 同语义，回落链不变、绝不带病写入）。
            path = _assert_within(os.path.dirname(path), path,
                                  "日志候选(open 前消费点)")
            log_dir = os.path.dirname(path)
            if log_dir:
                os.makedirs(log_dir, exist_ok=True)
            # 批次 Z（Z5-8）：open("a") 前先超限轮转——防「追加无上限」长跑涨盘
            #（本轮转句柄整个会话持有，跨启动轮转把单文件界为 LOG_MAX+单会话增量）。
            if _rotate_log_if_needed(path):
                print("[launcher] 日志超限已轮转：%s → %s.1" % (path, path))
            f = open(path, "a", encoding="utf-8", buffering=1, errors="replace")
            f.write("[launcher] 日志链路建立：%s\n" % path)  # 试写探测真实可写
            f.flush()
            return f
        except (OSError, ValueError):
            # OSError=该级不可写 → 回落；ValueError=边界校验未过 → 同样回落（降级）
            continue
    return None

# ======================================================================
# 修复2：DWM 原生圆角（Windows 11）——ctypes 全部封装在独立函数内、异常兜底
# ======================================================================

QNSX_DWM_ROUND_ENV = "QNSX_DWM_ROUND"
DWMWA_WINDOW_CORNER_PREFERENCE = 33  # DwmSetWindowAttribute 圆角偏好属性
DWMWA_BORDER_COLOR = 34              # DwmSetWindowAttribute 边框颜色属性
DWMWCP_ROUND = 2                     # DWM_WINDOW_CORNER_PREFERENCE.ROUND
DWMWCP_DEFAULT = 0                   # 还原默认（试探后回写）
COLOR_NONE = 0xFFFFFFFE              # DWMWA_BORDER_COLOR 的「无边框色」值
# 批次 U-C v2（用户 2026-09-19 二次截图反馈）：region 圆角半径——游戏侧描边环 FRAME_RADIUS=8
# ＋1px 视觉贴合余量（CreateRoundRectRgn 弧沿略外扩，环 2px 描边居中后与窗缘弧贴合）。
REGION_RADIUS = 9


def _default_dwm_setter(hwnd: int, attribute: int, value: int) -> int:
    """ctypes DwmSetWindowAttribute 封装，返回 HRESULT（0=S_OK）。非 Windows 会抛异常。"""
    import ctypes
    val = ctypes.c_uint(int(value))
    res = ctypes.windll.dwmapi.DwmSetWindowAttribute(
        ctypes.c_void_p(int(hwnd)),
        ctypes.c_uint(int(attribute)),
        ctypes.byref(val),
        ctypes.c_uint(ctypes.sizeof(val)))
    return int(res)


def _win11_or_later() -> bool:
    """无窗口可试时的兜底判据：Windows 11（build≥22000）起才支持 DWMWA 圆角属性。"""
    try:
        return int(sys.getwindowsversion().build) >= 22000
    except Exception:
        return False


def dwm_round_probe(get_hwnd=None, setter=None) -> bool:
    """DWM 圆角能力预检：对现有窗口试调 33=DWMWCP_ROUND，S_OK 才算支持。

    批次 U（U9-4）起预检结果不再用于注入 env（自动注入废止），仅供日志观测——DWM 形态
    信号改经「enable 成功 → 写 dwm_round.flag」（游戏侧 15s 轮询窗消费）。试探后回写
    DWMWCP_DEFAULT 还原窗口原状；无控制台窗口时按 Windows build≥22000（Win11）兜底判据。
    任何异常兜底返回 False（按不支持处理），绝不抛出。
    """
    try:
        if get_hwnd is None:
            def get_hwnd():
                import ctypes
                hwnd = 0
                try:
                    # GetConsoleWindow 在 kernel32.dll（非 user32）
                    hwnd = int(ctypes.windll.kernel32.GetConsoleWindow())
                except Exception:
                    hwnd = 0
                return hwnd
        if setter is None:
            setter = _default_dwm_setter
        hwnd = int(get_hwnd())
        if hwnd <= 0:
            ok = _win11_or_later()
            print(f"[launcher] DWM 预检：无可试窗口，按 Windows 版本号兜底判据 → "
                  f"{'支持（Win11+）' if ok else '不支持'}")
            return ok
        res = int(setter(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND))
        if res == 0:
            try:
                setter(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_DEFAULT)  # 还原试探窗口
            except Exception:
                pass
            return True
        print(f"[launcher] DWM 预检窗口试调未过 (HRESULT=0x{res & 0xFFFFFFFF:08X}，"
              f"Win10 预期 E_INVALIDARG)，转版本号兜底判据")
        # 试调未过（如 Windows Terminal 伪控制台拒收属性）→ 版本号兜底判据
        return _win11_or_later()
    except Exception as e:
        print(f"[launcher] DWM 预检异常（按不支持处理）: {e}")
        return False


def _find_window_by_pid(pid: int, timeout: float = 10.0, poll: float = 0.5,
                        sleeper=time.sleep):
    """ctypes EnumWindows+GetWindowThreadProcessId 按 PID 找可见顶层窗口。

    游戏窗口出现需要时间：重试至多 timeout 秒（默认 ~10s），找不到返回 None。
    非 Windows / ctypes 异常返回 None（降级），绝不抛出。
    """
    try:
        import ctypes
        from ctypes import wintypes
        user32 = ctypes.windll.user32
        enum_proc_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND,
                                            wintypes.LPARAM)
        deadline = time.monotonic() + max(0.0, timeout)
        while True:
            found = []

            def _cb(hwnd, _lparam):
                wpid = wintypes.DWORD(0)
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(wpid))
                if wpid.value == int(pid) and user32.IsWindowVisible(hwnd):
                    found.append(int(hwnd))
                    return False  # 找到即停止枚举
                return True

            user32.EnumWindows(enum_proc_type(_cb), 0)
            if found:
                return found[0]
            if time.monotonic() >= deadline:
                return None
            sleeper(poll)
    except Exception as e:
        print(f"[launcher] DWM 窗口查找异常（降级）: {e}")
        return None


def enable_dwm_round(pid: int, finder=None, setter=None, sleeper=time.sleep,
                     timeout: float = 10.0, poll: float = 0.5,
                     region_fn=None) -> bool:
    """按 PID 找到游戏顶层窗口并设置 DWM 圆角 + 去边框色（33=ROUND、34=COLOR_NONE）。

    finder(pid)->hwnd|None 可注入（mock 用）；setter(hwnd, attr, value)->HRESULT 可注入；
    region_fn(hwnd)->bool 可注入（批次 U-C v2：enable 成功路径附带区域裁剪的注入点，
    默认接 apply_window_region 按 hwnd 精确投递）。
    成功返回 True；任何一步失败（Win10 E_INVALIDARG、窗口超时未现等）仅打印一行告警
    返回 False，绝不让 launcher 崩溃。v2：region 失败/异常仅日志不阻断（DWM 已生效，
    region 是物理裁切冗余保险——Win10 单独走 _enable_and_mark 的 region 兜底路径）。
    """
    try:
        if finder is None:
            finder = lambda p: _find_window_by_pid(p, timeout=timeout,
                                                   poll=poll, sleeper=sleeper)
        if setter is None:
            setter = _default_dwm_setter
        hwnd = finder(pid)
        if not hwnd:
            print(f"[launcher] 未找到 PID={pid} 的游戏顶层窗口（重试 {timeout:.0f}s 超时），"
                  f"跳过 DWM 圆角（游戏保持现行形态）")
            return False
        r1 = int(setter(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND))
        r2 = int(setter(hwnd, DWMWA_BORDER_COLOR, COLOR_NONE))
        if r1 != 0 or r2 != 0:
            print(f"[launcher] DWM 圆角设置未生效 (corner=0x{r1 & 0xFFFFFFFF:08X}, "
                  f"border=0x{r2 & 0xFFFFFFFF:08X})，游戏保持现行形态")
            return False
        # 批次 U-C v2（用户 2026-09-19 二次截图反馈）：enable 成功路径追加区域裁剪——
        # Win11 与 DWMWCP_ROUND 原生圆角叠加精确贴合；失败仅日志不阻断（前述）。
        rf = region_fn if region_fn is not None else (
            lambda h: apply_window_region(pid, finder=lambda p: h))
        try:
            if not rf(hwnd):
                # R2②-P2-2：措辞注明影响面——Win11 DWM 原生圆角不受影响，仅 Win10 需 region 出圆角
                print("[launcher] SetWindowRgn 未生效（仅日志；不影响 Win11 DWM 原生圆角，仅 Win10 需 region 出圆角）")
        except Exception as e:
            print(f"[launcher] SetWindowRgn 异常（仅日志；不影响 Win11 DWM 原生圆角，仅 Win10 需 region 出圆角）: {e}")
        print(f"[launcher] DWM 圆角已应用 (hwnd={hwnd}: 33=DWMWCP_ROUND, "
              f"34=COLOR_NONE)")
        return True
    except Exception as e:
        print(f"[launcher] DWM 圆角设置异常（降级，不影响游戏）: {e}")
        return False


def apply_window_region(pid: int, finder=None, radius: int = REGION_RADIUS,
                        rect_fn=None, rgn_fn=None, rgn_setter=None,
                        sleeper=time.sleep, timeout: float = 10.0, poll: float = 0.5) -> bool:
    """批次 U-C v2（用户 2026-09-19 二次截图反馈）：按 PID 解析游戏顶层窗口后套圆角
    region 物理裁剪（CreateRoundRectRgn+SetWindowRgn）。

    Win11 与 DWMWCP_ROUND 原生圆角叠加精确贴合；Win10 无 DWM 圆角属性，靠 region 出
    圆角（_enable_and_mark 在 enable 失败时单独调用本函数兜底，成功同样落 dwm_round.flag，
    游戏侧画半径 8 圆角环与 region 裁切弧贴合）。游戏窗口无边框，GetClientRect=窗口
    全尺寸；CreateRoundRectRgn 右/下边界 +1 为 GDI 半开区间惯例；SetWindowRgn 成功后
    region 所有权归系统（不得 DeleteObject），失败路径回收 GDI 对象防泄漏。
    finder/rect_fn/rgn_fn/rgn_setter 均可注入（mock 用，全注入时零 Windows 依赖）；
    失败仅日志返回 False，绝不抛出（非 Windows 无 ctypes.windll 同走兜底）。
    """
    try:
        if finder is None:
            finder = lambda p: _find_window_by_pid(p, timeout=timeout,
                                                   poll=poll, sleeper=sleeper)
        hwnd = int(finder(pid) or 0)
        if hwnd <= 0:
            print(f"[launcher] 区域裁剪：未找到 PID={pid} 的游戏顶层窗口，跳过")
            return False
        if rect_fn is None:
            def rect_fn(h):
                import ctypes
                from ctypes import wintypes
                rect = wintypes.RECT()
                if not int(ctypes.windll.user32.GetClientRect(ctypes.c_void_p(int(h)),
                                                              ctypes.byref(rect))):
                    return (0, 0)
                return (int(rect.right), int(rect.bottom))
        w, hgt = rect_fn(hwnd)
        if int(w) <= 0 or int(hgt) <= 0:
            print(f"[launcher] 区域裁剪：客户区尺寸异常 ({w}x{hgt})，跳过")
            return False
        if rgn_fn is None:
            def rgn_fn(w_, h_, r_):
                import ctypes
                # windll 缺省返回 c_int（32 位有符号）——GDI 句柄高位为 1 时截断成负值，
                # 「<=0 判失败」会误杀合法句柄（u_c v2 路线 1 实弹实证）→ 掩码回无符号 32 位。
                return int(ctypes.windll.gdi32.CreateRoundRectRgn(
                    0, 0, int(w_) + 1, int(h_) + 1, int(r_), int(r_))) & 0xFFFFFFFF
        rgn = int(rgn_fn(w, hgt, radius))
        if rgn == 0:
            print("[launcher] 区域裁剪：CreateRoundRectRgn 失败，跳过")
            return False
        if rgn_setter is None:
            def rgn_setter(h_, r_):
                import ctypes
                ok = int(ctypes.windll.user32.SetWindowRgn(ctypes.c_void_p(int(h_)),
                                                           ctypes.c_void_p(int(r_)), 1))
                if not ok:
                    ctypes.windll.gdi32.DeleteObject(ctypes.c_void_p(int(r_)))
                return bool(ok)
        if not rgn_setter(hwnd, rgn):
            print("[launcher] 区域裁剪：SetWindowRgn 失败（GDI region 已回收），游戏保持现行形态")
            return False
        print(f"[launcher] 区域裁剪已应用 (hwnd={hwnd}: {w}x{hgt} r={radius})")
        return True
    except Exception as e:
        print(f"[launcher] 区域裁剪异常（降级，不影响游戏）: {e}")
        return False


def build_game_env(base_env: dict, dwm_ok: bool) -> dict:
    """批次 U（U9-4，spec §4-U9-4）：env 自动注入废止——预检结果不再写 QNSX_DWM_ROUND=1。

    旧口径「预检通过即 Popen 前置 env，而 enable 异步于游戏启动后执行」存在竞态：enable 失败
    但 env=1 已设 → 游戏进 DWM 形态（停画四角三角）而原生圆角未生效。改「enable 成功后写
    标记文件 dwm_round.flag」（游戏侧 15s 轮询窗消费、用后即删）。用户手工预设的
    QNSX_DWM_ROUND 原样透传（手工通道保留兜底）。dwm_ok 参数保留签名兼容（不再消费）。
    """
    env = dict(base_env)
    return env


GAME_USER_DIR_NAME = "千年一榫"   # project.godot config/name（launcher 侧以项目名常量固化推导）


def dwm_flag_path() -> str:
    """批次 U（U9-4）：DWM 形态标记文件路径=游戏 user:// 目录
    %APPDATA%/Godot/app_userdata/千年一榫/dwm_round.flag。

    路径边界校验（防御硬化）：「基础目录」=%APPDATA%（来源显式），其余各层与文件名
    均为常量片段，经 _safe_join 显式分离拼接 → abspath 规范化 → 断言落在基础目录内。
    %APPDATA% 缺失或非绝对 → 抛 ValueError（拒绝拼出相对路径被 cwd 锚定），由
    clear/write 的 try 降级为「只打日志、不动盘」。正常路径返回值与硬化前一致。
    """
    appdata = os.environ.get("APPDATA", "")
    return _safe_join(appdata, "Godot", "app_userdata", GAME_USER_DIR_NAME,
                      "dwm_round.flag", what="dwm_flag_path")


def clear_dwm_flag() -> None:
    """启动前预清旧标记（防上次残留误触，双审 P2-8 备案：每次启动先清后写）。

    路径边界校验（防御硬化）：os.remove 之前在消费点再断言一次——规范化后的目标
    必须严格落在其基础目录（%APPDATA%/Godot/app_userdata/千年一榫）内，越界/
    基础目录非法 → ValueError 被本函数捕获 → 降级为「只打日志、不删除」
    （沿用原「异常即降级、绝不抛出」语义）。
    """
    try:
        flag_path = dwm_flag_path()
        # 消费点二次边界断言（防构造值被替换/注入成越界路径后仍盲目 os.remove）：
        # ① 绝对、且不含 '..' 穿越段 ② 规范化后严格落在其所在目录内。
        _reject_traversal("clear_dwm_flag", flag_path, allow_absolute=True)
        flag_path = _assert_within(os.path.dirname(flag_path), flag_path,
                                   "clear_dwm_flag")
        if os.path.exists(flag_path):
            os.remove(flag_path)
            print("[launcher] 已预清陈旧 dwm_round.flag")
    except Exception as e:
        print(f"[launcher] 预清 dwm_round.flag 失败（降级）: {e}")


def write_dwm_flag() -> None:
    """enable 成功后落 DWM 形态信号（游戏侧 DWM_FLAG_WAIT_SEC=15s 轮询窗内消费后自删）。

    路径边界校验（防御硬化）：makedirs/open 之前在消费点断言——规范化后的目标必须
    严格落在其基础目录（%APPDATA%/Godot/app_userdata/千年一榫）内，越界/基础目录
    非法 → ValueError 被本函数捕获 → 降级为「只打日志、不写盘」（游戏保持备案形态），
    绝不写出边界之外。正常路径写出的位置与内容（"1"）与硬化前完全一致。
    """
    try:
        flag_path = dwm_flag_path()
        # 消费点二次边界断言（防构造值被替换/注入成越界路径后仍盲目 open 写入）：
        # ① 绝对、且不含 '..' 穿越段 ② 规范化后严格落在其所在目录内。
        _reject_traversal("write_dwm_flag", flag_path, allow_absolute=True)
        flag_path = _assert_within(os.path.dirname(flag_path), flag_path,
                                   "write_dwm_flag")
        flag_dir = os.path.dirname(flag_path)
        os.makedirs(flag_dir, exist_ok=True)
        # 写入 API：pathlib 等价形态 ≡ 内建 open 以写模式 + UTF-8 编码写入后关闭。
        # encoding 必须显式给 "utf-8"：Path.write_text 缺省 encoding=None 会走 locale
        # 编码（Windows=GBK），直接替换会改变落盘字节 —— 故此处显式指定，行为逐字节不变。
        Path(flag_path).write_text("1", encoding="utf-8")
        print(f"[launcher] DWM 形态标记已写入: {flag_path}")
    except Exception as e:
        print(f"[launcher] 写 dwm_round.flag 失败（游戏保持备案形态）: {e}")


def server_ready() -> bool:
    """bind 试探 9878（Python 绑定端，spec §3.3/§14-10）：
    bind 失败=端口被占=Python 已就绪；bind 成功=未就绪（关闭套接字后可重试）。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.bind(("127.0.0.1", CONTROL_PORT))
        return False
    except OSError:
        return True
    finally:
        s.close()


def main() -> None:
    # P2-2（批次 W 规格 §2）：server stdout/stderr 追加落盘（四级回落链，全败静默零日志）；
    # game Popen 维持现状（spec 口径：仅 server 侧重定向）。
    log_file = _open_log_stream()
    if log_file is not None:
        print("[launcher] 手势服务日志已启用（stdout/stderr 追加落盘）")
    else:
        print("[launcher] 日志目录全部不可写，静默降级为零日志（不影响功能）")
    popen_kwargs = {"cwd": HERE, "creationflags": CREATE_NO_WINDOW}
    if log_file is not None:
        popen_kwargs["stdout"] = log_file
        popen_kwargs["stderr"] = subprocess.STDOUT
    server = subprocess.Popen(
        [PYTHON, os.path.join(HERE, "main.py"), "--port", str(BASE_PORT),
         # 批次 Z（Z4-①）：宿主 PID=launcher 自身——launcher 意外亡故时 python 侧看门狗
         # （owner 判据优先于父判据）释放摄像头自退；正常退出仍走游戏退出后的 SHUTDOWN 序。
         "--owner-pid", str(os.getpid())],
        **popen_kwargs)
    print(f"[launcher] 手势服务 PID={server.pid}，就绪探测 {CONTROL_PORT}（{PROBE_TIMEOUT_SEC}s 超时）")
    deadline = time.time() + PROBE_TIMEOUT_SEC
    ready = False
    while time.time() < deadline:
        if server_ready():
            ready = True
            print("[launcher] 手势服务已就绪（控制端口被占用）")
            break
        time.sleep(1.0)
    if not ready:
        print(f"[launcher] 手势服务 {PROBE_TIMEOUT_SEC:.0f} 秒未就绪，仍启动游戏（游戏内走键鼠降级）")

    print(f"[launcher] 拉起游戏 {GAME_EXE}")
    clear_dwm_flag()   # 批次 U（U9-4）：启动预清旧标记（防上次残留误触，双审 P2-8）
    dwm_ok = dwm_round_probe()
    env = build_game_env(os.environ, dwm_ok)   # U9-4：env 自动注入废止（仅透传手工预设）
    print("[launcher] DWM 圆角预检完成（形态信号改经 dwm_round.flag 于 enable 成功后下发）")
    game = subprocess.Popen([GAME_EXE], cwd=os.path.dirname(GAME_EXE), env=env)
    # 游戏启动后异步按 PID 应用 DWM 圆角（窗口出现需时间，最长 ~10s 轮询；
    # daemon 线程不阻塞 launcher 主流程，失败仅告警）
    def _enable_and_mark() -> None:
        # 批次 U（U9-4）：enable 成功才落 DWM 形态信号（标记文件）；失败→不写→游戏备案形态。
        # 批次 U-C v2（用户 2026-09-19 二次截图反馈）：区域裁剪与形态标记联动——enable 成功
        # 路径内已附 region（Win11 叠加精确贴合）；enable 失败（Win10 E_INVALIDARG）时 region
        # 单独成功同样出圆角 → 同落 dwm_round.flag（region/DWM 任一成功写标记）。
        ok = enable_dwm_round(game.pid)
        if not ok:
            ok = apply_window_region(game.pid)
        if ok:
            write_dwm_flag()
    threading.Thread(target=_enable_and_mark, daemon=True).start()
    game.wait()
    print("[launcher] 游戏已退出：发送 SHUTDOWN 并清理子进程")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.sendto(b"SHUTDOWN", ("127.0.0.1", CONTROL_PORT))
        s.close()
    except OSError:
        pass
    # 独立审查修复批（2026-09-26，P3）：收割改走 reap_server——kill 后必 wait、
    # 仍超时再 kill 兜底，防子进程句柄泄漏（旧 wait→kill 直返形态退役）。
    reap_server(server)


def reap_server(server, first_wait_sec: float = 3.0,
                kill_wait_sec: float = 5.0) -> str:
    """游戏退出后收割手势服务子进程（独立审查修复批 2026-09-26，P3 kill 无 wait）。

    旧形态：`wait(3) → 超时 kill()` 后直接返回——kill 后从不 wait，子进程句柄
    未收割（僵尸句柄泄漏，Popen 资源滞留）。

    新形态（有界）：
      ① wait(first_wait_sec) 成功 → "exited"（零 kill，优雅退出优先）；
      ② 超时 → kill() → wait(kill_wait_sec) 成功 → "killed"（**kill 后必 wait**）；
      ③ 仍超时 → 再 kill() 兜底（幂等）→ 最终 wait(1.0) 收割尝试 → "kill_timeout"。
    每段 wait 均带 timeout，全路径有界不悬挂。

    Returns:
        "exited" / "killed" / "kill_timeout"（仅日志用，调用方不依赖）。
    """
    try:
        server.wait(timeout=first_wait_sec)
        return "exited"
    except subprocess.TimeoutExpired:
        pass
    server.kill()
    try:
        server.wait(timeout=kill_wait_sec)
        return "killed"
    except subprocess.TimeoutExpired:
        pass
    # 超时再 kill 兜底（幂等 TerminateProcess）＋最终收割尝试（防句柄泄漏）
    try:
        server.kill()
    except Exception:
        pass
    try:
        server.wait(timeout=1.0)
    except subprocess.TimeoutExpired:
        pass
    return "kill_timeout"


if __name__ == "__main__":
    main()
