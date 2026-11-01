#!/usr/bin/env python3
"""P2-2（批次 W 规格 §2）launcher 日志四级回落链自测（P2-4 回修：W1 独立审查要求
gesture_runtime 既有 selftest 先例——selftest_dwm_round.py 等两件——同风格入库）。

注入式纯函数断言（零真实用户目录写入：LOCALAPPDATA/TEMP 进程内重定向 + launcher.HERE
monkeypatch 沙盒化；同名目录占位=确定性 OSError 注入面）：
  A. 常量契约：LOG_FILENAME="gesture_runtime.log" / CREATE_NO_WINDOW（win32=0x08000000，非 0）
  B. 级1 运行目录：默认链首级落盘 + 试写头（「日志链路建立：<路径>」）
  C. 级2 回落：级1 被同名目录占位 → %LOCALAPPDATA%/Godot/千年一榫_logs/gesture_runtime.log
  D. 级3 回落：级1/级2 双断（LOCALAPPDATA 指向文件占位路径）→ %TEMP%/gesture_runtime.log
  E. 级4 全败：三级全断 → 返回 None 静默降级（不崩不弹零日志）
  F. candidates 注入：自定候选列表直连生效（参数契约）
  G. launcher 集成源码证据链：main() 内 _open_log_stream 挂接 + Popen stdout/stderr/
     creationflags 三 kwargs 在位 + game Popen 维持现状（无 stdout/stderr 重定向）
实弹段（可选）：无（打包版 30s 日志含启动行由 W7 重导清单⑦负责，主会话执行）。
判绿：末行输出 SELFTEST PASSED，退出码 0。
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import launcher as lw  # noqa: E402

FAILS = []


def expect(cond, label):
    if cond:
        print(f"  [PASS] {label}")
    else:
        print(f"  [FAIL] {label}")
        FAILS.append(label)


def with_env(key, value):
    """进程内环境变量重定向（_open_log_stream 在调用时读 env），返回还原函数。"""
    old = os.environ.get(key)
    if value is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = value

    def restore():
        if old is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = old
    return restore


def main():
    print("== selftest_log_fallback ==")
    sandbox = Path(tempfile.mkdtemp(prefix="w1_selftest_log_"))
    try:
        # A. 常量契约
        expect(getattr(lw, "LOG_FILENAME", "") == "gesture_runtime.log",
               "A1 LOG_FILENAME=gesture_runtime.log")
        expect(lw.CREATE_NO_WINDOW == getattr(subprocess, "CREATE_NO_WINDOW", 0)
               and (os.name != "nt" or lw.CREATE_NO_WINDOW == 0x08000000),
               "A2 CREATE_NO_WINDOW（win32=0x08000000；非 Windows getattr 恒 0）")

        # B. 级1 运行目录（monkeypatch HERE 沙盒化，避免在真实 gesture_runtime/ 留文件）
        here_sb = sandbox / "runtime"
        here_sb.mkdir(parents=True, exist_ok=True)
        real_here = lw.HERE
        lw.HERE = str(here_sb)
        try:
            f1 = lw._open_log_stream()
            expect(f1 is not None, "B1 级1：运行目录句柄建立")
            if f1 is not None:
                f1.close()
            p1 = here_sb / "gesture_runtime.log"
            expect(p1.exists() and "日志链路建立" in p1.read_text(encoding="utf-8"),
                   "B2 级1：日志落盘且含试写头")

            # C. 级2 回落（级1 同名目录占位 = 确定性 OSError 注入面）
            p1.unlink()
            p1.mkdir()
            la_sb = sandbox / "la"
            la_sb.mkdir()
            r1 = with_env("LOCALAPPDATA", str(la_sb))
            try:
                f2 = lw._open_log_stream()
                expect(f2 is not None, "C1 级2：级1 阻断 → 回落 LOCALAPPDATA")
                if f2 is not None:
                    f2.close()
                p2 = la_sb / "Godot" / "千年一榫_logs" / "gesture_runtime.log"
                expect(p2.exists(), "C2 级2：落位 %LOCALAPPDATA%/Godot/千年一榫_logs/gesture_runtime.log")

                # D. 级3 回落（级2 父目录被文件占位 → makedirs OSError）
                file_block = sandbox / "file_block"
                file_block.write_text("x", encoding="utf-8")
                r2 = with_env("LOCALAPPDATA", str(file_block))
                tmp_sb = sandbox / "tmp"
                tmp_sb.mkdir()
                r3 = with_env("TEMP", str(tmp_sb))
                try:
                    f3 = lw._open_log_stream()
                    expect(f3 is not None, "D1 级3：级1/级2 双断 → 回落 TEMP")
                    if f3 is not None:
                        f3.close()
                    expect((tmp_sb / "gesture_runtime.log").exists(),
                           "D2 级3：落位 %TEMP%/gesture_runtime.log")

                    # E. 级4 全败 → None
                    r4 = with_env("TEMP", str(file_block))
                    try:
                        f4 = lw._open_log_stream()
                        expect(f4 is None, "E1 级4：全断 → None 静默降级（不崩不弹零日志）")
                    finally:
                        r4()
                finally:
                    r3()
                    r2()
            finally:
                r1()

            # F. candidates 注入直连生效
            cand_sb = sandbox / "cand"
            cand_sb.mkdir()
            f5 = lw._open_log_stream(candidates=[str(cand_sb / "custom.log")])
            expect(f5 is not None, "F1 注入 candidates：句柄建立")
            if f5 is not None:
                f5.close()
            expect((cand_sb / "custom.log").exists(), "F2 注入 candidates：落位自定义路径")
        finally:
            lw.HERE = real_here

        # G. launcher 集成源码证据链
        src = (SCRIPT_DIR / "launcher.py").read_text(encoding="utf-8")
        expect("log_file = _open_log_stream()" in src, "G1 main() 挂接 _open_log_stream")
        expect('popen_kwargs["stdout"] = log_file' in src, "G2 server Popen stdout=日志句柄")
        expect('popen_kwargs["stderr"] = subprocess.STDOUT' in src, "G3 server Popen stderr 合流 stdout")
        expect('"creationflags": CREATE_NO_WINDOW' in src, "G4 server Popen creationflags=CREATE_NO_WINDOW")
        game_line = next((ln for ln in src.splitlines()
                          if "game = subprocess.Popen" in ln), "")
        expect(bool(game_line) and "GAME_EXE" in game_line
               and "stdout" not in game_line and "stderr" not in game_line
               and "**popen_kwargs" not in game_line,
               "G5 game Popen 维持现状（该行无 stdout/stderr 重定向，规格口径）")
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    if FAILS:
        print(f"SELFTEST FAILED: {len(FAILS)}")
        sys.exit(1)
    print("SELFTEST PASSED")
    sys.exit(0)


if __name__ == "__main__":
    main()
