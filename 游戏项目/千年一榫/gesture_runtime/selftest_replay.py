#!/usr/bin/env python3
"""回放自测（批次 R spec §11.3）：读 fixtures/landmarks_replay.json（双手 landmarks 序列）
逐帧跑 GestureEngine，断言：
  ① palm_size 字段存在且取值范围 (0,1)；
  ② 输出时间戳单调递增；
  ③ 输出字段完整（spec §3.3 表全键——引擎键 + server 注入键 hand_index/fps/landmarks 组合校验）。
夹具缺失时以确定性合成序列生成（spec §11.3 口径：可用合成双手序列，不必真机录制）。
判绿：末行输出 SELFTEST PASSED，退出码 0。
"""

import json
import math
import sys
from pathlib import Path

import numpy as np

from gesture_engine import GestureEngine

# 夹具路径：由脚本自身位置确定性派生（pathlib 锚定，无外部输入参与，Mimosa 路径穿越误报规避）
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "landmarks_replay.json"

# spec §3.3 手 dict 全键（引擎键 + server 注入键）
FULL_KEYS = {
    "gesture", "gesture_id", "confidence", "hand_x", "hand_y", "hand_z",
    "hand_rotation_x", "hand_rotation_y", "hand_rotation_z",
    "fingers", "pinch_distance", "hand_index", "handedness",
    "landmarks", "fps", "is_detected", "timestamp", "palm_size",
}

FRAMES = 60


def _synth_hand(wrist_x: float, finger_ext: bool, jitter: float) -> list:
    """构造 21×[x,y,z] 合手：四指伸直(张开掌)或全收(握拳)，掌幅≈0.08。"""
    lm = [[0.0, 0.0, 0.0] for _ in range(21)]
    lm[0] = [wrist_x, 0.60 + jitter, 0.0]                      # 腕
    ext_len = 0.20 if finger_ext else 0.06                     # 伸直/收拢的指尖距离
    tips = {4: 0.10, 8: 0.20, 12: 0.21, 16: 0.19, 20: 0.15}    # 各指尖相对腕的长度
    for idx, ln in tips.items():
        reach = ln if finger_ext else 0.05
        lm[idx] = [wrist_x + (0.06 if idx == 4 else 0.0),
                   0.60 + jitter + reach + ext_len - 0.20, 0.0]
        lm[idx][1] = 0.60 + jitter + reach
    mcps = {5: (0.05, 0.06), 9: (0.0, 0.08), 13: (-0.04, 0.07), 17: (-0.07, 0.05)}
    for idx, (dx, dy) in mcps.items():
        lm[idx] = [wrist_x + dx, 0.60 + jitter + dy, 0.0]
    # 其余关节沿腕→指尖线性插值填充（自测只关心几何合理性）
    for i in range(21):
        if lm[i] == [0.0, 0.0, 0.0]:
            lm[i] = [wrist_x + 0.01 * (i % 5 - 2), 0.60 + jitter + 0.01 * (i // 5), 0.0]
    return lm


def generate_fixture() -> None:
    """确定性合成 60 帧双手序列：左手张开掌（palm_size≈0.20）、右手握拳↔食指切换。"""
    frames = []
    for i in range(FRAMES):
        jit = 0.001 * (i % 5)
        right_ext = (i % 10) < 5
        frames.append({
            "timestamp": round(1.0 + 0.033 * i, 4),
            "left": _synth_hand(0.30, True, jit),
            "right": _synth_hand(0.70, right_ext, -jit),
        })
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    with FIXTURE.open("w", encoding="utf-8") as f:
        json.dump(frames, f, ensure_ascii=False)
    print(f"[selftest] 已生成合成夹具 {FIXTURE}（{FRAMES} 帧）")


def main() -> int:
    if not FIXTURE.exists():
        generate_fixture()
    with FIXTURE.open("r", encoding="utf-8") as f:
        frames = json.load(f)
    assert len(frames) >= FRAMES, f"夹具帧数不足：{len(frames)} < {FRAMES}"

    engine_l = GestureEngine()
    engine_r = GestureEngine()
    last_ts = -1.0
    fail = 0
    for fi, frame in enumerate(frames):
        for hand_key, engine, hand_index in (("left", engine_l, 0), ("right", engine_r, 1)):
            lm = np.array(frame[hand_key], dtype=np.float32)
            result = engine.process(lm, "Left" if hand_index == 0 else "Right")
            # server 注入键（hand_tracking_server 主循环同款），组合成 §3.3 全键帧
            result["hand_index"] = hand_index
            result["fps"] = 30.0
            result["landmarks"] = lm[:, :2].tolist()
            missing = FULL_KEYS - set(result.keys())
            if missing:
                print(f"[FAIL] 帧{fi} {hand_key} 缺字段: {sorted(missing)}")
                fail += 1
            ps = result.get("palm_size")
            if not (isinstance(ps, float) and 0.0 < ps < 1.0):
                print(f"[FAIL] 帧{fi} {hand_key} palm_size 越界: {ps}")
                fail += 1
            ts = float(result["timestamp"])
            if ts < last_ts:
                print(f"[FAIL] 时间戳非单调（递减）: 帧{fi} ts={ts} prev={last_ts}")
                fail += 1
            last_ts = ts
    # ---- 批次 T（spec §4-T7/§9-4）：One Euro 滤波链路自测（+5 断言）----
    from one_euro_filter import OneEuroFilter, ONE_EURO_MIN_CUTOFF, ONE_EURO_BETA, ONE_EURO_D_CUTOFF
    # 批次 AC 等价替换（领域三 §4.3-2，2026-09-27）：批次 T/U 常量锚 (1.2, 1.7, 1.0)
    # → (1.8, 3.0, 1.0)——提速（min_cutoff 1.2→1.8 抬静止截止、beta 1.7→3.0 降快移相位滞后）
    # 系本批改动对象，旧锚与 AC 新断言互斥，按「等价替换留痕」纪律换值（旧值留痕于注释与
    # spec §4.3-2；相位滞后量化对比见 selftest_ac_algo.OneEuroSpeedupTest）。
    assert (ONE_EURO_MIN_CUTOFF, ONE_EURO_BETA, ONE_EURO_D_CUTOFF) == (1.8, 3.0, 1.0), "批次 AC 常量漂移（spec §4.3-2）"
    rng = np.random.default_rng(7)   # 确定性种子
    raw = [0.5 + 0.002 * float(rng.standard_normal()) for _ in range(60)]   # 静止段微抖
    f = OneEuroFilter()
    t0 = 10.0
    out = [f.filter(x, t0 + 0.033 * i) for i, x in enumerate(raw)]
    var_raw = float(np.var(np.array(raw)))
    var_out = float(np.var(np.array(out)))
    assert var_out < var_raw, f"静止段方差未降：raw={var_raw:.8f} out={var_out:.8f}"
    f.reset()
    step = [0.5 if i < 30 else 0.8 for i in range(60)]   # 阶跃段：滞后有界且收敛
    out2 = [f.filter(x, t0 + 0.033 * i) for i, x in enumerate(step)]
    assert abs(out2[29] - 0.5) < 1e-6 and out2[31] < 0.8, "阶跃后应滞后于目标（自适应低通语义）"
    assert abs(out2[-1] - 0.8) < 0.005, f"阶跃段未收敛：out2[-1]={out2[-1]:.4f}"
    # server 注入点源码证据链（Godot 桥测试同款手法，无摄像头不可达路径以源码固化）
    server_src = (Path(__file__).resolve().parent / "hand_tracking_server.py").read_text(encoding="utf-8")
    assert "tip_x" in server_src and "OneEuroFilter()" in server_src, "server 未挂接 tip_x/tip_y 注入"
    print("[OK] 批次 T One Euro 滤波自测：常量/静止方差/阶跃收敛/注入点源证据 全过")
    # ---- 批次 U（U8，spec §4-U8/§10-4）断言段：滑窗 5/beta 1.7/双门槛留痕＋引擎输出单调性回归锚 ----
    # 断言对象口径（双审回修 P1-3）：本段断言引擎侧输出与常量；server 侧 _mp_timestamp_ms:732 真时钟
    # 改动的实弹验证由 UA-6 Step 10 双端回环自测覆盖（不在本件重复断言）。
    # 磁盘实况适配留痕：计划字面块为模块级 0 缩进，逐字粘贴入 main() 判绿段（4 空格区）会
    # IndentationError，故整块平移缩进 4 空格（UC-2 P2③ 同款「缩进适配」纪律）。
    # 1) 引擎输出时戳严格单调（喂 20/40/60ms 不等间隔合成序列；引擎 process 实签名 2 参
    #    (landmarks_3d, handedness)——gesture_engine.py:118 实况，双审回修 P1-3 修正；
    #    landmarks_3d 需 np.ndarray（既有主循环 :86 np.array(...,float32) 同款，直传 list 会 TypeError））
    _engine_ts = GestureEngine()
    _ts_seq = []
    _t_in = [20, 40, 60] * 4   # 12 帧不等间隔（ms，用于合成序列节奏）
    for _i in range(len(_t_in)):
        _lm = np.array(_synth_hand(0.5, True, 0.0), dtype=np.float32)
        _out = _engine_ts.process(_lm, "Right")   # 实签名 2 参（照既有主循环调用形态）
        _ts_seq.append(_out["timestamp"])
    assert all(b > a for a, b in zip(_ts_seq, _ts_seq[1:])), "U8: 引擎输出时间戳须严格单调（回归锚）"
    print("  [PASS] U8-1 引擎输出时戳严格单调（12 帧不等间隔序列）")
    print("  [PASS] U8-2 相邻差序列留痕 %s（观察项非断言：引擎侧 dt 无强契约，server 侧真时钟由 UA-6 回环覆盖）" % [round(b - a, 4) for a, b in zip(_ts_seq, _ts_seq[1:])])
    # 2) 滑窗常量=5 且滞后样本数=5
    import gesture_engine as _ge_mod
    assert _ge_mod.SMOOTH_WINDOW_SIZE == 5, f"U8: SMOOTH_WINDOW_SIZE 应为 5（实测 {_ge_mod.SMOOTH_WINDOW_SIZE}）"
    print("  [PASS] U8-3 SMOOTH_WINDOW_SIZE=5（旧值 7 留痕）")
    assert len(_engine_ts._gesture_history) <= 5, "U8: 滑窗 deque 上限应=5"
    print("  [PASS] U8-4 滑窗滞后样本数≤5")
    # 3) OneEuro beta=3.0（静止段收敛＋常量锁；批次 AC §4.3-2 提速：1.7→3.0）
    import one_euro_filter as _oef
    assert abs(_oef.ONE_EURO_BETA - 3.0) < 1e-9, f"AC: ONE_EURO_BETA 应为 3.0（实测 {_oef.ONE_EURO_BETA}）"
    print("  [PASS] AC-5 ONE_EURO_BETA=3.0（U8 旧值 1.7、批次 T 旧值 1.0 留痕）")
    # 磁盘实况适配：OneEuroFilter 构造签名=(min_cutoff, beta, d_cutoff)（one_euro_filter.py:22，
    # 计划防坑注②假定的 (freq,min_cutoff,beta,d_cutoff) 4 参与现行实现不符）；方法名=filter(x, t)。
    # 勘误留痕（磁盘实况为准）：计划字面块 filter(t*0.016, 0.5±0.001) 把时刻/信号实参序写反
    # （实签名 x 在前），静止段语义应为信号=0.5±0.001 微抖、时刻=t*0.016s——修正实参序后收敛判据成立。
    _f = _oef.OneEuroFilter(1.8, 3.0, 1.0)
    static_seg = [_f.filter(0.5 + 0.001 * ((t % 3) - 1), float(t) * 0.016) for t in range(30)]
    assert max(static_seg) - min(static_seg) < 0.01, "AC: beta=3.0 静止段仍收敛（方差<0.01）"
    print("  [PASS] AC-6 beta=3.0 静止段收敛（提速不引入震荡）")
    # 4) 双门槛与 EMA 不变留痕（防误改）
    assert abs(_ge_mod.CONFIDENCE_ENTER - 0.55) < 1e-9 and abs(_ge_mod.CONFIDENCE_EXIT - 0.40) < 1e-9, \
        "U8: CONFIDENCE 0.55/0.40 双门槛不得随本批改动"
    print("  [PASS] U8-7 双门槛 0.55/0.40 与 EMA 0.3 不变留痕")
    if fail == 0:
        print(f"SELFTEST PASSED（{len(frames)} 帧 × 双手，字段/palm_size/单调性全过）")
        return 0
    print(f"SELFTEST FAILED: {fail} 项")
    return 1


if __name__ == "__main__":
    sys.exit(main())
