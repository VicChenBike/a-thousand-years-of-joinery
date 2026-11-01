#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
手势跟踪服务器 - 整合摄像头、MediaPipe Tasks API 手部检测、增强手势引擎，

TDD 断言（当前架构的关键不变约束）：
# TEST: cap.read() 只在 _camera_read_thread 中调用（唯一读取点）
# TEST: _latest_frame 是简单引用赋值（GIL 保证，无锁、无队列）
# TEST: _camera_stream_thread 读 self._latest_frame，不直接 cap.read()
# TEST: 无手时发送两条空结果（hand_index=0 和 1）
# TEST: MediaPipe 时间戳用 _mp_timestamp_ms 单调递增计数器（≠ time.time()）
# TEST: cv.waitKey(1) 只在非 headless 模式下调用
# TEST: Godot 控制端口检测用 P+2（Python 绑定），不是基准 P
# TEST: frame_socket.sendto 应发送 4 字节长度头 + JPEG 数据到 127.0.0.1:frame_send_port(=P+1)

通过 UDP 将识别结果发送到 Godot 引擎。

流程：
1. CameraSelector 选择摄像头
2. 启动 MediaPipe HandLandmarker 检测
3. GestureEngine 处理关键点 → 手势分类 + 手指状态 + 位置
4. 通过 UDP 将结果发送到 Godot
5. OpenCV 窗口显示摄像头画面 + 手势标注 + FPS
6. 按 ESC 安全退出，按 C 切换摄像头

UDP 数据格式 (JSON, 端口 4242):
    {
        "gesture": "Open_Palm",
        "gesture_id": 0,
        "confidence": 0.97,
        "hand_x": 0.52,
        "hand_y": 0.38,
        "hand_z": -0.15,
        "hand_rotation_x": 0.12,
        "hand_rotation_y": -0.08,
        "hand_rotation_z": 0.03,
        "fingers": [1.0, 0.98, 0.95, 0.92, 0.88],
        "pinch_distance": 0.35,
        "hand_index": 0,          # 手索引：0=左手, 1=右手
        "handedness": "Right",
        "fps": 30,
        "is_detected": true,
        "timestamp": 1234567890
    }
    双手独立发送，每只手各发送一条 UDP 消息。
    Godot 端通过 hand_index 区分左右手数据。
"""

import argparse
import atexit
import functools
import itertools
import json
import os
import signal
import socket
import threading
import time
import traceback
from collections import deque
from typing import Optional

import cv2 as cv
import mediapipe as mp  # 仍然需要 mp.Image
import numpy as np

from camera_selector import (CameraSelector, backfill_camera_entry,
                             build_camera_entries, decode_console_bytes,
                             enumerate_cameras, match_camera_by_name,
                             pick_camera_by_name)
from gesture_engine import GestureEngine
from one_euro_filter import OneEuroFilter  # 批次 T（spec §4-T7）：tip 输出通道防抖滤波


# ======================================================================
# 编码修复：强制 stdout/stderr 使用 UTF-8，防止 Windows GBK 下 UnicodeEncodeError
# ======================================================================
import sys as _sys
import io as _io
try:
    _sys.stdout = _io.TextIOWrapper(_sys.stdout.buffer, encoding='utf-8', errors='replace')
    _sys.stderr = _io.TextIOWrapper(_sys.stderr.buffer, encoding='utf-8', errors='replace')
except Exception:
    pass

# 将工作目录切换到脚本所在目录，确保相对路径始终正确（不被 Godot 的 CWD 影响）
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(SCRIPT_DIR)

# ======================================================================
# 常量
# ======================================================================

UDP_IP = "127.0.0.1"
UDP_PORT = 4242

WINDOW_NAME = "Hand Gesture Tracking - Godot Server"

# 安全机制
FPS_WARNING_THRESHOLD = 15       # 低于此 FPS 发送警告
CAMERA_TIMEOUT_SECONDS = 3.0      # 摄像头无帧超时
RECONNECT_MAX_RETRIES = 3         # 最大重连尝试次数
PROBE_BUDGET_SEC = 8.0            # 批次 U（U2，spec §5）：PROBE_MATRIX 探测软预算（秒，超时自愈）

# 批次 AA（W4-2，spec §7.3/§7.7）：自动重连根治三常量——速率限制+指数退避+预算。
RECONNECT_BACKOFF_BASE_SEC = 1.0  # 退避基数【暂定值·待用户复验】
RECONNECT_BACKOFF_MAX_SEC = 5.0   # 指数退避上限（单调不减）【暂定值·待用户复验】
RECONNECT_BUDGET = 10             # 重试预算（次）→ 转 FAILED + camera_error【暂定值·待用户复验】
# 批次 AA（W4-5，spec §7.3/§7.7）：无帧看门狗连续超阈次数（3×3s=9s）【暂定值·待用户复验】
NO_FRAME_TRIP_COUNT = 3

# 批次 AD-5（F-1，需求 §4.1）：**首帧快速判定**——开镜成功后到首帧到达的独立更短窗。
# 病灶：`_last_camera_read_time` 初值=进程构造时刻（WMI 枚举+MediaPipe 初始化之后早已 >3s），
# 旧实现开镜成功段不复位 → 主循环第一迭代即开始累计 3s 窗 → 约 6~9s 后必然误判「无帧」
# → 释放（指示灯灭 + HUD 全灭）→ 立即重连（设备已热）→ ≤1s 自愈。用户实机四段症状
# 「僵死十余秒→频闪→全灭→1s 恢复」与此链条完全吻合。
# 处置：①开镜成功段**复位基准+窗口计数并武装首帧窗**（`_mark_camera_open_success`）；
# ②首帧真正到达再次复位并解除武装（`_mark_frame_read`）；③首帧超 `FIRST_FRAME_TIMEOUT_SEC`
# 仍未到 → **恰一次**安静重连（`FIRST_FRAME_QUIET_RECONNECT_MAX=1`，连续无帧开镜计数
# `_frameless_open_streak` 只由真实帧到达清零），总 release/open 上界写进 selftest 断言，
# 严禁产生多次快速 open/release（指示灯频闪根除）。阈值必须 ≤3s（先于无帧看门狗触发）。
FIRST_FRAME_TIMEOUT_SEC = 2.5     # 首帧等待快速判定窗（秒）
FIRST_FRAME_QUIET_RECONNECT_MAX = 1  # 连续无帧开镜的安静重连上界（次）

# 批次 AD-5b（需求 §4.5/§4.6）：**启动期矩阵探测移出关键路径**。实测证据
# （AI工作记录/批次AD_走查_20260927/ad5b_probe_block_measure.txt、
#  adcamera_firstopen2_before.txt）：`_switch_camera` 成功段同步「分辨率×5 + 帧率×5」
# set/get 风暴实测 5.99s——每一档分辨率 set 都触发 DSHOW 格式重协商 ≈1.1s 并阻塞
# 读线程（风暴期间活流仅 5 帧、5×>0.5s 间隔）→ camera_opened→SWITCH_END≈6s、
# 首帧迟至 ~9.3s，用户见「画面一帧卡死十来秒」。处置：切换段只**播种**最小矩阵
# （宽/高各 ≤1 次 set、fps 只读零 set），完整矩阵按需惰性探测（Godot 下拉对矩阵
# 缓存缺失设备自动发 PROBE_MATRIX → `_probe_matrix_worker`，「检测中…」UI 契约不变）。
# 另：探测在飞时收到主流命令须**让位**（纪元 bump + 尽快中止），且探测期间**抑制
# 无帧看门狗**（绝不因探测产生 release/camera_closed——画面与 HUD 不消失）。
FPS_SEED_MAX = 240.0             # fps 播种合理性上界（cap.get 回 0/异常/离谱值 → 播种留空）
PROBE_MAIN_CMD_PREFIXES = ("SWITCH_CAMERA:", "START_CAMERA_BY_NAME:",
                           "SET_PREFERRED_CAMERA:", "SET_RESOLUTION:", "SET_FPS:")
PROBE_MAIN_CMDS = ("RELEASE_CAMERA", "SHUTDOWN")   # 无前缀主流命令（收线程即时生效族）

# 批次 V-B1（spec §6.3）：摄像头生命周期四修复常量
SWITCH_RELEASE_SETTLE_SEC = 0.35   # ② release→open 释放时延（0.1s 对部分驱动不足，DSHOW 句柄释放自证需 0.15~0.2s+）
SWITCH_OPEN_ROUNDS = 3             # ② SWITCH 打开尝试总轮数（AD：每轮同为 CAP_DSHOW 单后端，后端轮换已退役）
CONTROL_BIND_MAX_RETRIES = 3       # ④ 控制口接管重试次数（bind 失败→SHUTDOWN→重试×3）
CONTROL_BIND_RETRY_INTERVAL = 0.5  # ④ 接管重试间隔（秒）
CONTROL_TAKEOVER_CMD = "SHUTDOWN"  # ④ 既有 SHUTDOWN 控制指令（协议零变更，仅接管序使用）
CAMERA_ERROR_REASON_MAX_LEN = 200  # ③ camera_error.reason 摘要截断长度（UDP 载荷护栏）
SWITCH_FAIL_COOLDOWN_SEC = 8.0     # 批次V审查①-P2：SWITCH 全失败后对该设备 id 的自动重连冷却（秒，集中可调）

# 批次 Z（Z4，spec §4）：摄像头生命周期三常量
WATCHDOG_POLL_SEC = 0.5            # ① 父/宿主进程看门狗轮询间隔（秒；≤10s 零残留验收裕量）
CONTROL_RECV_POLL_SEC = 0.25       # ③ 控制口收线程 recvfrom 轮询超时（秒；线程可及时收尸）
CONTROL_DRAIN_MAX_PER_CALL = 8     # ③ 主循环单次执行命令上限（FIFO 清队，防一帧内命令风暴）
# 独立审查修复批（2026-09-26，P2）：心跳最小间隔单源常量——主循环无帧分支与
# 收线程兼职补发（_maybe_send_heartbeat）共用，防双写漂移。
HEARTBEAT_MIN_GAP_SEC = 1.0


def _pid_alive(pid) -> bool:
    """Z4-①：进程存活判定（Windows 专用实现 + posix 兜底）。

    Windows 严禁 os.kill(pid, 0) 族——Python 文档明示非 CTRL_* 信号值会走
    TerminateProcess 无条件杀目标（0 亦然），属误杀地雷；改走 OpenProcess +
    GetExitCodeProcess==STILL_ACTIVE(259) 只读判定。posix 走 signal 0 惯例。
    """
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        STILL_ACTIVE = 259
        k32 = ctypes.windll.kernel32
        h = k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not h:
            return False
        try:
            code = ctypes.c_ulong()
            ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
            return bool(ok) and code.value == STILL_ACTIVE
        finally:
            k32.CloseHandle(h)
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

# 批次 T（spec §6.2）：探测矩阵常量化（原 :521/:901 内联列表固化；帧率矩阵新增）
RES_PROBE_LIST = [(1920, 1080), (1280, 720), (960, 540), (640, 480), (320, 240)]
FPS_PROBE_LIST = [30, 60, 15, 120, 24]

# 批次 Y（Y1，spec §2 Y-A4/Y-A6/Y-A16 + §4-4 参数集中）：手感参数集中常量，
# 真手复验后一次性调参，不散落魔改。
HAND_HOLD_TTL_SEC = 0.6           # 批次 Z（Z5-4，spec §5-4 丢手补偿；0.3 退役留痕）：手丢失后保留上一帧数据时长（秒）——竖掌正对摄像头 MediaPipe 整帧检不出的典型空窗 ≤0.6s，超窗才判死→null→GDScript teardown 清翻转累计态
HAND_MATCH_DIST = 0.50            # 批次 AD（§4.1.3；AC 0.65 留痕，旧值族 0.35/0.65）：最近邻关联判定阈值（归一坐标曼哈顿距离）
# ——AC 0.65 在「换手」形态下过宽：撤走左手、在另一处抬起右手时，右手检出到左手残留 track
# 的中心距常落 (0.50, 0.65) → 右手继承左手 track（手性/累计态全部错位）。AD 按 spec §4.1.3
# 收回 0.50：常态快移仍在阈内（30fps 挥手单帧位移典型 ≤0.45），换手继承被切断。
HAND_SINGLE_FAST_MATCH_DIST = 0.55  # 批次 AD（§4.1.3；AC 0.85 留痕）：**单 track×单检出**快移关联门限
# ——场上仅 1 条活跃 track 且本帧仅 1 个检出时，配对判据用本值（无第二只手可配，不存在串手）。
# AD 收紧理由：0.85 覆盖了「换手间隙」尺度（用户实机反馈「右手伸入时误匹配并继承刚放下的左手
# 残留 Track」）；0.55 在保住单手快移连续性的同时切断残影继承。**结构约束：本值必须 ≥
# HAND_MATCH_DIST（0.50）**——否则单人单检出形态下快移通道反比常态通道更严，单手快移会
# 比双手场景更易断链（held 幽灵 + 换 id → GDScript 整侧清态），即 AC §4.3-1 已根治的缺陷回潮。

# 批次 AA（AA-A 波，spec §4 W1-4/W1-5/W1-7 + §4.7 暂定值）：同手判定与检出去重常量。
# 症状③「一只手同时出现蓝+红两份骨架」= 重复检出/快速位移 ghost 让同一只手落进两个
# hand_index → 包内 left/right 各一份同手数据。守卫与去重共用同一判据（集中常量一次调参）。
HAND_SAME_HAND_LM_TOL = 0.02      # 同手 landmark 逐点最大偏差容差（归一坐标）【暂定值·待用户复验】
# 审查回修 P3-3：尺寸比 = max(extent)/min(extent) **恒 ≥ 1** → 旧元组 (0.7, 1.4) 的 0.7
# 下界是**死元素**（比值永不可能 < 0.7），已删除、只留上界；行为**等价**：
#   ratio ≤ 1.4  ⟺  min/max ≥ 1/1.4 = 0.714 ≈ 规格 §4.7 所记下界 0.7（等价实现）。
HAND_DEDUP_SIZE_RATIO = 1.4       # 重复检出框尺寸比**上界**【暂定值·待用户复验】（旧值留痕 (0.7, 1.4)）
# 批次 AD（spec §4.2.2-1）：冷启动握手等待窗 `PREFERRED_WAIT_SEC` 已**彻底退役**——
# 启动阶段只枚举物理设备（零开镜、零阻塞），设备启停等 Godot 经 9878 下发
# `START_CAMERA_BY_NAME:<名>` 由主循环消费；旧 AC 的 5.0s 待命窗（超窗即按
# pick_auto_camera 自动开镜）连同黑名单自动选择一并废止，根除「未确认设备就自启」。
CAMERA_OPEN_DEFAULT_FPS = 0.0     # camera_opened 事件 fps 读取失败兜底值

# 批次 Z（Z5-4，spec §5-4）：检测/跟踪置信度下调——「手竖立正对摄像头整帧检不出」主因之一
# 是 0.7 检测门过严；下调 0.7→0.55 / 0.5→0.4 提召回。误检权衡：GDScript 侧 CONFIRM_FRAMES=2
# 双帧确认 + HandTracker 最近邻关联 + 引擎 5 帧滑窗投票三层兜底，单帧误检进不了语义层；
# 与 HAND_HOLD_TTL_SEC 同组集中常量，真手复验一次调参。
MIN_DETECTION_CONFIDENCE = 0.55   # Z5-4 最小检测/存在置信度（旧 0.7 退役留痕）
MIN_TRACKING_CONFIDENCE = 0.4     # Z5-4 最小跟踪置信度（旧 0.5 退役留痕）

# 修复5（批次Z走查 P2）：mp 主判**改判** score 下限——_resolve_sides 的 mp 权威通道旧码
# 无 score 门槛，低分 mp 标签一帧抖动即 _relabel_track 换 id → GDScript 据 id 变化清该侧
# 累计态 → 翻转配对/缩放被打断。低于下限视同 mp 缺失（走粘性/几何兜底）；选 score 下限
# 而非 2 帧确认：零新增状态、零纠错延迟、判据单一（handedness score 本身即分类置信度）。
# 与置信度常量同组集中，真手复验一次调参。
MP_RELABEL_MIN_SCORE = 0.6        # 修复5：mp 改判 score 下限（<0.6 不改判）

# 批次 AD（§4.1.3，2026-09-27）：**单手入画初期动态手性校正**参数（多帧滑窗投票）。
# 病灶：AC §4.3-2「单手强连续锁定」把 `_resolve_sides` 的单手分支写成 `return changed`
# （绝不改手性）——玩家单手从画面边缘入画的第一帧，MediaPipe 关键点被边缘裁剪、分类
# 置信度极低甚至左右颠倒，该帧的误判被**永久焊死**，整局右手只能当左手用。
# 新口径：入画初期 `age <= HANDEDNESS_VOTE_MAX_AGE` 内维护 mp 分类标签滑窗；窗口**尾部连续**
# `HANDEDNESS_VOTE_MIN_FRAMES` 帧给出「与当前 track side 相反且 `mp_score >= 本阈`」的稳定
# 判定时，就地校正 track 手性（**只改 side/label/hand_index，不换 id、不重置引擎/滤波器**）；
# 超窗（age > 5）后进入锁定保护，不再因单帧侧立/旋转姿态噪声翻转手性。
# 取值口径（spec §4.1.3 逐条）：窗口 5 帧 / 连续 3 帧 / score ≥0.70；不取任务书示例值 0.75
# （spec 为落盘权威且 0.75 在任务书中标为「例如」），0.70 与既有 MP_RELABEL_MIN_SCORE(0.6)
# 同族、更保守（两阈不相干：0.6 控「多手域逐帧改判」、本阈控「单手初期投票」）。
HANDEDNESS_VOTE_WINDOW = 5        # 入画初期滑窗长度（帧）
HANDEDNESS_VOTE_MIN_FRAMES = 3    # 窗口**尾部连续**需满足的相反手性高置信帧数
HANDEDNESS_VOTE_MIN_SCORE = 0.70  # 计入票数的 mp_score 下限
HANDEDNESS_VOTE_MAX_AGE = 5       # 仅 age ≤ 本值（入画初期）允许校正；之后手性锁定

# 批次 Z（Z5-8，spec §5-8 长跑稳定性）：探测线程收敛——旧「每条 PROBE_MATRIX 命令
# threading.Thread(...).start()」按命令创建（命令风暴=线程数增长）；收敛为单点入口
# _spawn_probe_thread：在忙复用（拒绝并发创建），同时刻存活探测线程 ≤ PROBE_THREAD_MAX。
PROBE_THREAD_MAX = 1

# 批次 AA（W2-8，spec §5.3/§5.4-8/9）：全 21 landmark 下发平滑——滤波只作用于下发字段
# result["landmarks"]（骨架显示），判定内核 engine.process 读原始 landmarks_3d 零改动
# （§5.4-9 判定内核零改动断言）。
# 批次 AC（领域三 §4.3-2）：固定滞后低通 α=0.35 → **动态速度自适应加权**（消除 3~5 帧滞后）：
#   α_eff = clamp(α_base + GAIN × Δmax, α_base, α_max)
#   · 静止微抖（Δmax→0）→ α≈0.55：平滑防抖照旧（σ 降幅语义保留，判据阈值随 α 放宽）
#   · 快速移动（Δmax ≥ 0.046）→ α→0.92：紧贴真手零拖影（旧 0.35 单帧仅跟进 35%）
LANDMARK_SMOOTH_ALPHA = 0.55      # 批次 AC（旧值 0.35 留痕）：基准（静止档）系数
LANDMARK_SMOOTH_ALPHA_MAX = 0.92  # 批次 AC 新增：高速档上限（≈1 直通，留 8% 去噪余量）
LANDMARK_SMOOTH_SPEED_GAIN = 8.0  # 批次 AC 新增：速度增益（Δmax=0.046 → α 触顶 0.92）


# ======================================================================
# 批次 AA（AA-A 波，spec §4 W1-4/W1-5）：同一只手判定与检出去重（纯函数，selftest 直测）
# ======================================================================

def _det_score(det: dict) -> float:
    """检出排序分：MediaPipe handedness score（缺省 0.0）。"""
    try:
        return float(det.get("mp_score", 0.0) or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _landmark_extent(landmarks) -> float:
    """检出框尺寸代理：21 点归一坐标 x/y 跨度最大值（无/退化 landmark 回退 0.0）。"""
    if landmarks is None:
        return 0.0
    arr = np.asarray(landmarks, dtype=np.float32)
    if arr.ndim != 2 or arr.shape[0] == 0:
        return 0.0
    xs, ys = arr[:, 0], arr[:, 1]
    return float(max(float(xs.max() - xs.min()), float(ys.max() - ys.min())))


def _lm_pair_dev(la, lb) -> "float | None":
    """两组 landmark 的 **xy 逐点最大偏差**（D1 同手判据的共享实现，selftest 同源护栏锁死）。

    返回 None = 不可比（任一侧缺失 / 全零退化 / 点数不等 / 列数 <2），调用方按 D1 第二档
    退回中心距兜底。列数容忍 2 与 3 混比：track 的 `last_landmarks` 存 21×2（xy 下发裁剪），
    fresh 检出存 21×3（含 z）——只取 [:, :2] 逐点比对，避免「同手但形状列数不同」被误判不可比。
    """
    if la is None or lb is None:
        return None
    ea, eb = _landmark_extent(la), _landmark_extent(lb)
    if ea <= 1e-4 or eb <= 1e-4:
        return None   # 全零/退化 landmark 视作「无形状信息」（夹具常量数组）
    a = np.asarray(la, dtype=np.float32)
    b = np.asarray(lb, dtype=np.float32)
    if a.ndim != 2 or b.ndim != 2 or a.shape[0] != b.shape[0] \
            or a.shape[1] < 2 or b.shape[1] < 2:
        return None   # 点数不等/列数不足 → 不可比
    return float(np.abs(a[:, :2] - b[:, :2]).max())


def _center_dist(a: dict, b: dict) -> "float | None":
    """两检出中心曼哈顿距离（中心缺失 → None）。"""
    ca, cb = a.get("center"), b.get("center")
    if ca is None or cb is None:
        return None
    return abs(float(ca[0]) - float(cb[0])) + abs(float(ca[1]) - float(cb[1]))


def _is_same_hand(det_a: dict, det_b: dict) -> bool:
    """两个检出是否属于**同一只手**（spec §4.3 W1-4 前置判据 / W1-5 去重判据）。

    判据分两档（**实测修正，见下方偏离说明**）：
      ① **landmark 可用（生产恒真）→ 逐点最大偏差 < HAND_SAME_HAND_LM_TOL（0.02）是
         唯一判据**。理由：中心距**无法**区分「同手重复检出」与「两只真手交叉」——
         批次 Y 回归 `selftest_y1_holding_id.test_crossing_integration_ids_stable` 实证
         两真手交叉时中心可完全重合（0.3+0.4t 与 0.7−0.4t 在 t=0.5 交于 0.5），按 spec
         字面「中心距 < HAND_MATCH_DIST 即判同手」会把交叉的第二只手当重复框丢掉 =
         症状②「第二只手丢失」回归（spec §4.7 暂定值表亦自警「若实测误合并双手可下调
         阈值」，但交叠极限态下任何阈值都失效）。而同手重复框的 landmark 近乎逐点相同，
         两只真手（左右互为镜像）逐点偏差远超 0.02 → 该判据两向皆准。
      ② **landmark 缺失/退化（仅夹具/异常路径）→ spec 字面中心距 + 尺寸比**：
         中心距 < HAND_MATCH_DIST **且** 框尺寸比 ≤ HAND_DEDUP_SIZE_RATIO 上界（W1-5 判据，
         比纯中心距多一道门，宁可不合并也不吞真正在场的第二只手）。
    """
    la, lb = det_a.get("landmarks"), det_b.get("landmarks")
    dev = _lm_pair_dev(la, lb)
    if dev is not None:
        return dev < HAND_SAME_HAND_LM_TOL
    # D1 第二档：landmark 缺失/退化/不可比 → 中心距（+ 可用时补尺寸比门）
    d = _center_dist(det_a, det_b)
    if d is None or d >= HAND_MATCH_DIST:
        return False
    ea, eb = _landmark_extent(la), _landmark_extent(lb)
    if ea <= 1e-4 or eb <= 1e-4:
        return True   # 无形状信息 → 按 spec 字面：中心距即判同手
    ratio = (ea / eb) if ea >= eb else (eb / ea)
    return ratio <= HAND_DEDUP_SIZE_RATIO   # 比值 = max/min 恒 ≥1，只判上界（P3-3 删死下界）


def _dedup_detections(detections: list) -> list:
    """批次 AA（W1-5，spec §4.3）：同手重复检出去重（保留 mp_score 高者）。

    落点 = `_process_frame` 检出组装后、`HandTracker.update` 前——防同手两个检出占满
    `num_hands=2` 名额把第二只真手挤出结果集（症状②根因之一）。
    """
    kept: list = []
    for det in detections:
        dup_idx = None
        for i, k in enumerate(kept):
            if _is_same_hand(det, k):
                dup_idx = i
                break
        if dup_idx is None:
            kept.append(det)
        elif _det_score(det) > _det_score(kept[dup_idx]):
            kept[dup_idx] = det
    return kept


def _held_ghost_is_same_hand(track: dict, detections: list) -> bool:
    """批次 AA（W1-6，spec §4.3；**审查回修 P2-1 统一 D1 口径**）：
    held track（ghost）是否与本帧任一 fresh 检出属**同一只手**。

    判据与 `_is_same_hand`（W1-4/W1-5 的 D1 口径）**同源同结论**：
      ① 两侧 landmark 可用（生产恒真）→ 与 `track["last_landmarks"]`（21×2 原始值，
         W2-8 平滑只作用下发字段，ghost 裁决源零影响）逐点最大偏差 <
         HAND_SAME_HAND_LM_TOL(0.02) 才判同手；逐点明显不同即判异手——**不退回中心距**；
      ② landmark 缺失/退化 → 中心距 < HAND_MATCH_DIST 兜底（仅此分支）。
    旧码（纯中心距 < 0.35）在两真手交叉时误杀：MediaPipe 遮挡丢检手的 ghost 距另一手
    fresh 中心常 < 0.35 → 被误判同手丢弃 → 该侧置 None → GDScript `_teardown_side` 整侧
    清态（翻转配对/语义/缩放基准全丢）= 症状②「第二只手丢失」变体（审查 P2-1）。
    命中即在组包处丢弃 ghost（该侧置 None），防同一只手以 held 形态占另一侧槽位。
    """
    tl = track.get("last_landmarks")
    for det in detections:
        dev = _lm_pair_dev(tl, det.get("landmarks"))
        if dev is not None:
            if dev < HAND_SAME_HAND_LM_TOL:
                return True
            continue   # landmark 可用且逐点不同 → 异手，中心距不作数（D1 第一档唯一判据）
        d = _center_dist(track, det)
        if d is not None and d < HAND_MATCH_DIST:
            return True
    return False


# ======================================================================
# 批次 AA（W2-8，spec §5.3）：全 21 landmark 下发平滑器（骨架显示专用）
# ======================================================================

class LandmarkSmoother:
    """下发 landmark 独立 EMA 平滑（每手一份实例，按 track id 复位）。

    - 作用域红线（spec §5.4-9）：**只平滑下发字段**（result["landmarks"]，Godot
      camera_skeleton 骨架渲染消费）；判定内核 gesture_engine.process 在组包前读
      原始 landmarks_3d，零改动；track 复用/ghost 裁决的 tr["last_landmarks"] 仍为
      原始值（批次 AA W1-6 ghost 判定零影响）。
    - 按 track id 复位：新手（Y1 per-hand id 变化）不继承旧手平滑状态。
    - 形状/类型防御：入参非等形 ndarray 重新初始化（不 in-place 污染）。
    - 批次 AC（§4.3-2）**动态速度自适应加权**：每帧以 21 点最大帧间位移 Δmax 上调有效系数
      α_eff = clamp(α_base + GAIN×Δmax, α_base, α_max)——静止微抖保持基准平滑，快速移动
      α→0.92 实时跟手（旧固定 α=0.35 在 30fps 下 ≈2 帧相位滞后，叠加下游 OneEuro 与
      GDScript 二级 EMA 后用户实测 3~5 帧滞后）。
    """

    __slots__ = ("_id", "_ema")

    def __init__(self):
        self._id = None
        self._ema = None

    def reset(self) -> None:
        self._id = None
        self._ema = None

    @staticmethod
    def effective_alpha(max_delta: float | None) -> float:
        """批次 AC（§4.3-2）：速度自适应有效系数（纯函数，selftest 直测；None → 基准档）。"""
        if max_delta is None:
            return LANDMARK_SMOOTH_ALPHA
        a = LANDMARK_SMOOTH_ALPHA + LANDMARK_SMOOTH_SPEED_GAIN * float(max_delta)
        return min(max(a, LANDMARK_SMOOTH_ALPHA), LANDMARK_SMOOTH_ALPHA_MAX)

    def smooth(self, hand_id, lm):
        """lm: 21×2 可下标序列（list[[x,y],…] / ndarray）→ 平滑后同形 list。"""
        arr = np.asarray(lm, dtype=np.float64)
        if self._id != hand_id or self._ema is None or self._ema.shape != arr.shape:
            self._id = hand_id
            self._ema = arr.copy()
        else:
            max_delta = float(np.abs(arr - self._ema).max())
            alpha = self.effective_alpha(max_delta)
            self._ema = self._ema + alpha * (arr - self._ema)
        return self._ema.tolist()


# ======================================================================
# UDP 发送器
# ======================================================================

class UDPSender:
    """UDP 数据发送器，将识别结果发送到 Godot。"""

    def __init__(self, ip: str = UDP_IP, port: int = UDP_PORT):
        self.ip = ip
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(0.01)
        self._send_count = 0
        # 独立审查修复批（2026-09-26，P2）：最近成功发包时刻（epoch 秒）——
        # 收线程兼职心跳 _maybe_send_heartbeat 判「距上次发包 >1s 才补发」的单一真值。
        self.last_send_time = 0.0

    def send(self, data: dict):
        """
        发送 JSON 数据到 Godot。

        Args:
            data: 要发送的数据字典
        """
        try:
            message = json.dumps(data, ensure_ascii=False)
            self.sock.sendto(message.encode("utf-8"), (self.ip, self.port))
            self._send_count += 1
            self.last_send_time = time.time()
        except socket.error as e:
            print(f"[UDP] 发送失败: {e}")
        except Exception as e:
            print(f"[UDP] 意外错误: {e}")

    def close(self):
        """关闭 UDP 套接字。"""
        try:
            self.sock.close()
        except Exception:
            pass


# ======================================================================
# per-hand 稳定 id 跟踪器（批次 Y，Y-A6/Y-A4，spec §3.1）
# ======================================================================

class HandTracker:
    """双手最近邻关联跟踪 + 每手独立丢帧容忍窗。

    根治现状粘性判手三大缺陷（spec §1 域二根因：key=帧内枚举序号、单手在场不清
    另一手陈旧条目、几何判手镜像反转）：

    - **最近邻关联**：track×detection 距离矩阵做最小总距离一对一分配（num_hands≤2
      枚举全排列取最优，规模可忽略），距离 ≥HAND_MATCH_DIST 视为不可能配对；
    - **标签随 track 延续**：几何判手只决定新手初始标签，后续帧不再改判——同一
      物理手手性不随侧立/翻转抖动，串手根除；
    - **每手独立 hold 窗**：本帧未检出的 track 保留上一帧完整数据 HAND_HOLD_TTL_SEC
      （输出 held=True），超窗判死（dead）并移除；单手丢失不影响另一手；
    - **id 稳定且不复用**：格式 "L0"/"R0"，同侧重分配递增尾号——id 变化=新手，
      GDScript 侧据 id 清该侧累计态（spec §3.1 消费契约）。
    """

    def __init__(self, hold_ttl: float = HAND_HOLD_TTL_SEC,
                 match_dist: float = HAND_MATCH_DIST):
        self._hold_ttl = float(hold_ttl)
        self._match_dist = float(match_dist)
        self._tracks: dict = {}            # id → track dict（server 可回写 last_result）
        self._id_counter = {"L": 0, "R": 0}

    def tracks(self) -> dict:
        """暴露内部 track 表（selftest 拨时间/回写数据用；生产代码勿依赖内部键）。"""
        return self._tracks

    # ------------------------------------------------------------------
    # 批次 Z（Z5-2/Z5-3，spec §5-2/§5-3）：侧别裁决辅助（mp 主判 / 几何兜底 / 换侧换 id）
    # ------------------------------------------------------------------

    @staticmethod
    def _side_of_label(label) -> "str | None":
        """"Left"/"Right" → "L"/"R"；其它（缺失/脏值）→ None。"""
        if label == "Left":
            return "L"
        if label == "Right":
            return "R"
        return None

    @classmethod
    def _mp_side_scored(cls, det: dict) -> "str | None":
        """mp 主判侧别（带改判 score 下限，修复5 批次Z走查 P2）：
        label_mp 缺失/脏值 → None；mp_score < MP_RELABEL_MIN_SCORE → None
        （低分标签视同缺失——防一帧抖动换 id 清该侧累计态打断翻转配对/缩放）。"""
        if float(det.get("mp_score", 0.0) or 0.0) < MP_RELABEL_MIN_SCORE:
            return None
        return cls._side_of_label(det.get("label_mp"))

    @staticmethod
    def _label_of_side(side: str) -> str:
        return "Left" if side == "L" else "Right"

    def _initial_side(self, det: dict) -> str:
        """新手初始侧：MediaPipe handedness 主判，几何判定兜底（Z5-3 权威序）。

        批次 AA（W1-7，spec §4.3）：mp 主判改走 `_mp_side_scored`——与逐帧纠错同口径
        过 `MP_RELABEL_MIN_SCORE` 下限；低分标签视同缺失走几何兜底（旧码不过 score 门，
        低分 mp 首帧即定侧 → 后续纠错换 id → GDScript 整侧清态）。
        """
        side = self._mp_side_scored(det)
        if side is not None:
            return side
        return "L" if det.get("label_geo") == "Left" else "R"

    @staticmethod
    def _apply_side(track: dict, side: str) -> None:
        track["side"] = side
        track["label"] = HandTracker._label_of_side(side)
        track["hand_index"] = 0 if side == "L" else 1

    def _record_mp_observation(self, track: dict, det: "dict | None") -> None:
        """批次 AD（§4.1.3）：记录本帧 mp 分类观测进滑窗（`det is None` = 无观测，零追加）。

        条目形如 `(side|None, score)`；窗口长度上限 HANDEDNESS_VOTE_WINDOW。
        `side=None`（label_mp 缺失/脏值）同样**只占位不参与连续判据**：它在投票尾部遍历中
        立刻中断连续段（非「相反手性高置信」），语义=「本帧无相反手性证据」。
        """
        if det is None:
            return
        labels = track.get("mp_labels")
        if not isinstance(labels, list):
            labels = []
            track["mp_labels"] = labels
        labels.append((self._side_of_label(det.get("label_mp")),
                       float(det.get("mp_score", 0.0) or 0.0)))
        while len(labels) > HANDEDNESS_VOTE_WINDOW:
            labels.pop(0)

    def _advance_track_age(self, track: dict) -> None:
        """批次 AD（§4.1.3）：track 生命周期帧数 +1（spec「初始为 0，每帧递增」）。

        **held 帧同样递增**（spec 字面「每帧」）：防「反复短丢帧」把 `age > 5` 的锁定保护
        无限期推迟。观测与年龄解耦——只在真有 mp 分类产出的帧才调 `_record_mp_observation`。
        """
        track["age"] = int(track.get("age", 0) or 0) + 1

    def _early_handedness_vote(self, track: dict) -> "str | None":
        """批次 AD（§4.1.3）：入画初期手性投票——返回建议侧别（"L"/"R"），无建议=None。

        判据（spec §4.1.3 逐条）：滑窗**尾部连续** ≥ HANDEDNESS_VOTE_MIN_FRAMES 帧均为
        「`mp_score >= HANDEDNESS_VOTE_MIN_SCORE` 且侧别 = 当前 track 侧别的**对侧**」→
        返回该对侧；否则 None。

        仅 `track["age"] <= HANDEDNESS_VOTE_MAX_AGE`（入画初期）时评估——超窗即**手性锁定
        保护**：单帧侧立/旋转姿态噪声不再翻转手性（AC「单手强连续锁定」的零抖动收益保留，
        仅把「永久焊死」收窄为「初期可纠、之后锁定」）。
        """
        if int(track.get("age", 0) or 0) > HANDEDNESS_VOTE_MAX_AGE:
            return None
        labels = track.get("mp_labels")
        if not isinstance(labels, list) or not labels:
            return None
        cur = track.get("side")
        want = "R" if cur == "L" else "L"
        run = 0
        for side, score in reversed(labels):
            if side == want and float(score) >= HANDEDNESS_VOTE_MIN_SCORE:
                run += 1
            else:
                break
        return want if run >= HANDEDNESS_VOTE_MIN_FRAMES else None

    def _relabel_track(self, track: dict, side: str, now: float) -> str:
        """既有 track 改侧（mp 主判纠错）→ 换新 id（id 含侧别前缀；同侧递增不复用）。

        返回新 id（调用方并入 new_ids——server 据此复位该侧引擎/滤波器，GDScript 据 id
        变化清该侧累计态，语义=「数据纠错等价新手」）。
        """
        old_id = track.get("id")
        if old_id in self._tracks:
            del self._tracks[old_id]
        self._apply_side(track, side)
        new_id = f"{side}{self._id_counter[side]}"
        self._id_counter[side] += 1
        track["id"] = new_id
        self._tracks[new_id] = track
        return new_id

    @staticmethod
    def _pick_same_hand_pair(a: dict, b: dict) -> tuple:
        """同手重复条目取舍（W1-4）：已有 track 优先（保侧别/id 零抖动），否则 mp_score 高者。"""
        a_id = a["track"].get("id")
        b_id = b["track"].get("id")
        if (a_id is None) != (b_id is None):
            return (a, b) if a_id is not None else (b, a)
        if _det_score(a["det"]) != _det_score(b["det"]):
            return (a, b) if _det_score(a["det"]) > _det_score(b["det"]) else (b, a)
        return (a, b)

    def _resolve_sides(self, entries: list, now: float) -> list:
        """Z5-2/3：本帧实检出条目的侧别裁决（至多 2 只手）。

        批次 AA（W1-4，spec §4.3）**同一只手前置守卫**：两个检出若属同一只手（中心距+
        尺寸比 / landmark 重合，见 `_is_same_hand`），**不拆 L/R**——旧码分支③假定「两个
        检出必是两只手」，用几何/中心 x 强行拆侧，重复检出或快速位移 ghost 会让同一只手
        落进两个 hand_index → 包内 left/right 各一份同手数据 → 蓝+红双骨架。处置=保留一条
        （已有 track 优先 / mp_score 高者），另一条就地剔除且**不注册新 track**（`entries`
        为调用方列表，就地改写；`update` 据「tentative 是否仍在 entries 中」跳过注册）。

        **纵深防御（审查回修 P3-1，勿误读为双保险）**：本守卫与 `_dedup_detections` **共用
        同一谓词 `_is_same_hand`，不是独立的第二层**。生产路径上唯一调用链是
        `_process_frame` → `_dedup_detections`（同谓词前置去重）→ `HandTracker.update` →
        本守卫，故「两个检出同手」在到达此处前已被去重合并，`len(entries)==2 ∧
        _is_same_hand(...)` 分支在**生产上不可达**；可达路径仅剩 selftest 直调 `update`
        的夹具。保留它是为了「任何调用方绕过前置去重也不产生双骨架」，而非叠加防线。

        权威序（spec §5-3「以 MediaPipe handedness 为准，几何判定降为兜底」+ Y-A6 粘性防线）：
        ① 两侧 label_mp 相异 → **逐帧以 mp 为准**（含与既有 track 粘性标签不符的纠错——
           「已知 handedness 序列 100% 正确」夹具口径；mp 缺失时粘性才兜底）；
        ② 无侧别冲突（两 track 已分属两侧）且 mp 缺失/同标 → **粘性保持**（几何不逐帧
           改判——双手交叉运动时最近邻可能换配检出，几何随帧抖动，逐帧改判=批次 Y 已根除
           的串手/id 漂移回归，Y-A6 验收防线）；
        ③ 同侧冲突（两手同标，Z5-2「后者覆盖前者→只出一只手」根因）必须拆分，裁决序：
           单侧可用 mp → 用之取对侧；否则 label_geo 相异 → 按几何；否则 **既有 track 粘性
           优先、新手让位**（mp/几何同标无判据时，存续侧别按历史保持，冲突的新手取对侧；
           双双既有按 mp_score 高者保侧）；双双新手 → 中心 x 大者 Right（镜像画面用户右手
           在图像右半）。
        保证同帧两侧 hand_index 恒为 {0,1}（两手同标覆盖致「只出一只手」根因根除）。

        Returns:
            list: 被改侧的**既有** track 新 id 列表（新手候选 id 尚未分配，就地改侧不换 id）。
        """
        changed: list = []
        if not entries:
            return changed
        if len(entries) == 2 and _is_same_hand(entries[0]["det"], entries[1]["det"]):
            # 审查回修 P3-2：旧码在此给 `drop["track"]` 打 `_aa_dedup_drop` 标记，而唯一
            # 消费点是 `update` 的 tentative 注册循环 → 打在**既有** track 上时标记会随
            # 长生命周期 dict 存活终身（消费方永不复位，潜在脚枪）。现改为**本帧 entry 级
            # 临时判定**：直接从 entries 剔除、track dict 零残留；`update` 据「tentative
            # 是否仍在 entries 中」决定注册与否（语义与旧标记逐点等价）。
            _keep, drop = self._pick_same_hand_pair(entries[0], entries[1])
            entries[:] = [e for e in entries if e is not drop]
        if len(entries) == 1:
            # 批次 AC（领域三 §4.3-2「单手强连续锁定」）+ 批次 AD（§4.1.3 动态手性校正）：
            # 单手连续跟踪期间 **id 与累计态严格锁定**——不得 `_relabel_track`（换 id →
            # GDScript 据 id 变化 `_teardown_side` 清空全部累计态；旧 track 数据以对侧槽位
            # 错位组包 → 红蓝双骨架）。这一点 AC 与 AD 口径一致。
            #
            # **AD 修正 AC 的「永久焊死」**：AC 在本分支 `return changed`（绝不改手性），
            # 导致玩家单手从画面边缘入画的首帧（关键点被裁剪、分类置信度极低甚至左右颠倒）
            # 的误判被永久焊死，整局右手只能当左手用。现改为**入画初期多帧滑窗投票校正**：
            #   · 仅 `age <= HANDEDNESS_VOTE_MAX_AGE`（前 5 帧）内评估；
            #   · 窗口尾部连续 ≥3 帧「mp_score ≥0.70 且判为当前 track 的对侧」才触发；
            #   · 校正时**只改 side/label/hand_index**（就地 `_apply_side`），
            #     **绝不换 id、绝不重置 OneEuro/LandmarkSmoother、绝不进 new_ids**——
            #     故 GDScript 侧不触发 `_teardown_side`、累计态与滤波器全保留（spec §4.1.3
            #     「校正手性时严禁重置 ID 或销毁过滤器」）。
            #   · `age > 5` 后进入锁定保护：单帧侧立/旋转姿态噪声不再翻转手性。
            # 多手场景照常走下方面 len(entries)==2 的 mp 权威分支（含换 id 纠错/交换）；
            # 手出画超 HAND_HOLD_TTL_SEC 判死后再入画 → 建新手，侧别由 `_initial_side` 重评。
            entry = entries[0]
            trk = entry["track"]
            if trk.get("id") is None:
                # 新手候选（注册前）：侧别已由 `_initial_side` 决定，就地零改判（AC 语义）
                return changed
            want = self._early_handedness_vote(trk)
            if want is not None and want != trk.get("side"):
                self._apply_side(trk, want)   # 只改标签：零换 id / 零 new_ids / 零滤波器复位
            return changed
        a, b = entries[0], entries[1]
        ta, tb = a["track"], b["track"]
        a_mp = self._mp_side_scored(a["det"])
        b_mp = self._mp_side_scored(b["det"])
        a_geo = "L" if a["det"].get("label_geo") == "Left" else "R"
        b_geo = "L" if b["det"].get("label_geo") == "Left" else "R"
        if a_mp is not None and b_mp is not None and a_mp != b_mp:
            wa, wb = a_mp, b_mp                       # ① mp 权威（交叉验证/纠错/交换）
        elif ta["side"] != tb["side"]:
            # ② 无侧别冲突：mp 缺失/同标 → 粘性保持（既有几何逐帧改判=串手回归，禁用）
            wa, wb = ta["side"], tb["side"]
        else:
            # ③ 同侧冲突拆分
            if a_mp is not None and b_mp is None:
                wa, wb = a_mp, ("R" if a_mp == "L" else "L")
            elif b_mp is not None and a_mp is None:
                wb, wa = b_mp, ("R" if b_mp == "L" else "L")
            elif a_geo != b_geo:
                wa, wb = a_geo, b_geo                  # 几何兜底（仅冲突域内启用）
            elif ta.get("id") is not None and tb.get("id") is None:
                wa = ta["side"]; wb = ("R" if wa == "L" else "L")   # 既有优先，新手让位
            elif tb.get("id") is not None and ta.get("id") is None:
                wb = tb["side"]; wa = ("R" if wb == "L" else "L")
            else:
                sa = float(a["det"].get("mp_score", 0.0) or 0.0)
                sb = float(b["det"].get("mp_score", 0.0) or 0.0)
                if sa != sb:
                    # 双双既有/新手按 mp 分数：高者保侧、低者取对侧
                    if sa > sb:
                        wa, wb = ta["side"], ("R" if ta["side"] == "L" else "L")
                    else:
                        wa, wb = ("R" if tb["side"] == "L" else "L"), tb["side"]
                else:
                    xa = float(a["det"]["center"][0])
                    xb = float(b["det"]["center"][0])
                    if abs(xa - xb) > 1e-9:
                        wa, wb = (("R", "L") if xa > xb else ("L", "R"))
                    else:
                        wa, wb = "L", "R"
        for entry, want in ((a, wa), (b, wb)):
            track = entry["track"]
            if track["side"] == want:
                continue
            if track.get("id") is None:
                self._apply_side(track, want)   # 新手候选：注册前就地改（无 id 无须换）
            else:
                changed.append(self._relabel_track(track, want, now))
        return changed

    def update(self, detections: list, now: float) -> tuple:
        """喂入本帧检出列表，返回 (items, new_ids, dead)。

        Args:
            detections: [{"center": (x, y), "label_geo": "Left"/"Right",
                          "label_mp": "Left"/"Right"|None, "mp_score": float,
                          "landmarks": np.ndarray|None}, ...]（center 为归一坐标）。
            now: time.monotonic()（秒；单调时钟，不受系统时间跳变影响）。

        Returns:
            items: 每条 {"id", "hand_index", "label", "held", "detection", "track"}；
                   held=True 时 detection=None（server 取 track["last_result"] 组包）。
            new_ids: 本帧新分配 id 列表 + 改侧换 id 列表（server 据此复位该侧引擎/滤波器）。
            dead: 判死 track 摘要 [{"id", "hand_index", "side"}]（server 据此复位滤波器）。
        """
        items = []
        new_ids = []
        # 1) 最小总距离一对一分配（track ↔ detection）
        pairs = self._best_assignment(detections)
        consumed = set()
        entries = []
        for track_id, det_idx in pairs:
            track = self._tracks[track_id]
            det = detections[det_idx]
            consumed.add(det_idx)
            track["center"] = det["center"]
            track["last_seen"] = now
            # 批次 AD（§4.1.3）：实检出帧——age 递增 + mp 分类观测入滑窗（投票数据源）
            self._advance_track_age(track)
            self._record_mp_observation(track, det)
            entries.append({"track": track, "det": det})
        # 2) 未配对检出 → 新手候选（初始侧=mp 主判/几何兜底；id 注册前留空）
        tentative = []
        for det_idx, det in enumerate(detections):
            if det_idx in consumed:
                continue
            side = self._initial_side(det)
            trk = {"id": None, "side": side, "label": self._label_of_side(side),
                   "hand_index": 0 if side == "L" else 1, "center": det["center"],
                   "last_seen": now, "last_result": None, "last_landmarks": None,
                   # 批次 AD（§4.1.3）：生命周期帧数与 mp 分类滑窗（入画初期投票数据源）。
                   # age 初始 0（spec 字面）；**首帧观测即入窗**——入画首帧的 mp 判定同样
                   # 是投票证据（边缘首帧常为低置信误判，故既可能是被纠正的对象，也可能是
                   # 纠正所需的证据）。
                   "age": 0, "mp_labels": []}
            self._record_mp_observation(trk, det)
            tentative.append(trk)
            entries.append({"track": trk, "det": det})
        # 3) Z5-2 同侧冲突修正 + Z5-3 mp 主判纠错（先裁决、后注册，保证首帧即双侧在场）
        #    批次 AA（W1-4）：`_resolve_sides` 的「同一只手」守卫会就地把重复条目从 entries
        #    剔除 → 此处按「tentative 是否仍在 entries 中」决定注册（重复检出不占 track 槽）。
        #    审查回修 P3-2：旧实现给 track 打 `_aa_dedup_drop` 标记、本循环按标记跳过——
        #    打在**既有** track 上时标记会随长生命周期 dict 存活终身（消费点仅本循环、
        #    永不复位，属潜在脚枪），已改为上述 entry 级临时判定，track dict 零残留。
        new_ids.extend(self._resolve_sides(entries, now))
        kept_track_ids = {id(e["track"]) for e in entries}
        fresh_track_ids: list = []   # 批次 AC（§4.3-3）：本帧**新生** track（残影吸收判据）
        for trk in tentative:
            if id(trk) not in kept_track_ids:
                continue   # 同手守卫剔除的 tentative（未进 entries → 不注册）
            side = trk["side"]
            new_id = f"{side}{self._id_counter[side]}"
            self._id_counter[side] += 1
            trk["id"] = new_id
            self._tracks[new_id] = trk
            new_ids.append(new_id)
            fresh_track_ids.append(new_id)
        # 4) 实检出 items（裁决后两侧 hand_index 恒相异）
        for e in entries:
            trk = e["track"]
            items.append({"id": trk["id"], "hand_index": trk["hand_index"],
                          "label": trk["label"], "held": False,
                          "detection": e["det"], "track": trk})
        # 5) 未配对 track：hold 窗内保留（held），超窗判死移除
        #    批次 AC（§4.3-3，单手 Ghost 同源吸收）：本帧**恰 1 个实检出且新生了 track**
        #    时，与该检出中心距 < HAND_SINGLE_FAST_MATCH_DIST 的未配对 held track 判为
        #    **同一只手的残影**，直接判死移除（绝不输出红+蓝双骨架）。
        #    可达性（非死代码）：单 track×单检出形态由 0.85 快移通道直接配对、零新生 track；
        #    残影吸收只在「 ≥2 条 track（如另一手刚离场留下的陈旧 track）+ 快移超 0.85 断链建新
        #    track」形态命中——此时新生 track 与残影中心距恰落在 [0.65,0.85) 且仅 1 只手可见。
        #    结构护栏（保护批次 AA R1-e 防线）：仅当本帧**新生 track**（fresh_track_ids 非空）
        #    才启用本条——两真手交叉单帧丢检（本帧零新生 track）时残影按既有 hold 语义保留，
        #    否则会置 None → GDScript `_teardown_side` 整侧清态（=批次 AA 已修的「第二只手丢失」）。
        matched_ids = {it["id"] for it in items}
        absorbed: set = set()
        if len(detections) == 1 and fresh_track_ids:
            fc = detections[0]["center"]
            for track_id in list(self._tracks.keys()):
                if track_id in matched_ids:
                    continue
                tc = self._tracks[track_id].get("center")
                if tc is None:
                    continue
                d = abs(float(fc[0]) - float(tc[0])) + abs(float(fc[1]) - float(tc[1]))
                if d < HAND_SINGLE_FAST_MATCH_DIST:
                    absorbed.add(track_id)
        dead = []
        for track_id in list(self._tracks.keys()):
            if track_id in matched_ids:
                continue
            track = self._tracks[track_id]
            if track_id in absorbed:
                # 同源残影：判死移除（server 据 dead 复位该侧 tip 滤波器；组包零输出）
                dead.append({"id": track_id, "hand_index": track["hand_index"],
                             "side": track["side"]})
                del self._tracks[track_id]
            elif now - track["last_seen"] <= self._hold_ttl:
                # 批次 AD（§4.1.3）：held 帧 age 照常递增（spec「每帧递增」）——防反复短丢帧
                # 把 `age > 5` 的手性锁定保护无限期推迟；**不追加 mp 观测**（本帧无分类产出）。
                self._advance_track_age(track)
                items.append({"id": track_id, "hand_index": track["hand_index"],
                              "label": track["label"], "held": True,
                              "detection": None, "track": track})
            else:
                dead.append({"id": track_id, "hand_index": track["hand_index"],
                             "side": track["side"]})
                del self._tracks[track_id]
        return items, new_ids, dead

    def _best_assignment(self, detections: list) -> list:
        """track×detection 最小总距离分配（曼哈顿距离；超阈值不配对）。

        审查① P1-1 回修：允许**非满配**匹配——旧实现只枚举「最大基数完美配对」，
        任一 track 本帧无阈值内可用检测时整组匹配判无效返回 []，导致同一物理手
        同时产生 held 旧 id + 新 id（槽覆盖）。现枚举全部基数 1..n 的一对一子集
        配对，按（配对数最大优先，同数总距离最小）取最优；未匹配 track 由调用方
        走 hold、未消费 detection 才建新手。
        规模有界：track/detection 受 max_num_hands≤2 约束，全枚举开销可忽略。

        批次 AC（§4.3-1）：**单手快移通道**——场上恰 1 条活跃 track 且本帧恰 1 个检出时，
        配对门限放宽到 HAND_SINGLE_FAST_MATCH_DIST(0.85)（该形态无第二只手可配，不存在串手
        风险），根治「单手快速挥动单帧位移超 0.35 断链 → held 幽灵 + 新手」双骨架。
        """
        track_ids = list(self._tracks.keys())
        if not track_ids or not detections:
            return []
        single_fast = len(track_ids) == 1 and len(detections) == 1
        limit = HAND_SINGLE_FAST_MATCH_DIST if single_fast else self._match_dist
        cost = {}
        for tid in track_ids:
            tc = self._tracks[tid]["center"]
            for di, det in enumerate(detections):
                d = abs(det["center"][0] - tc[0]) + abs(det["center"][1] - tc[1])
                if d < limit:
                    cost[(tid, di)] = d
        best_key = None
        best_pairs = []
        n = min(len(track_ids), len(detections))
        for k in range(n, 0, -1):   # 配对数最大优先：高层有解即停
            for tid_perm in itertools.permutations(track_ids, k):
                for det_perm in itertools.permutations(range(len(detections)), k):
                    pairs = list(zip(tid_perm, det_perm))
                    if all(p in cost for p in pairs):
                        total = sum(cost[p] for p in pairs)
                        key = (-k, total)
                        if best_key is None or key < best_key:
                            best_key = key
                            best_pairs = pairs
            if best_key is not None:
                break
        return best_pairs


# ======================================================================
# 可视化工具
# ======================================================================

class Visualizer:
    """在 OpenCV 窗口上绘制手部关键点和手势信息。"""

    # 手部连接线（与 MediaPipe 定义一致）
    HAND_CONNECTIONS = [
        # 拇指
        (0, 1), (1, 2), (2, 3), (3, 4),
        # 食指
        (0, 5), (5, 6), (6, 7), (7, 8),
        # 中指
        (0, 9), (9, 10), (10, 11), (11, 12),
        # 无名指
        (0, 13), (13, 14), (14, 15), (15, 16),
        # 小指
        (0, 17), (17, 18), (18, 19), (19, 20),
        # 掌骨
        (5, 9), (9, 13), (13, 17),
    ]

    # 手指颜色
    COLORS = {
        "bone": (200, 200, 200),
        "joint": (255, 255, 255),
        "tip": (0, 255, 0),
        "text_bg": (0, 0, 0),
        "text_fg": (255, 255, 255),
        "warning": (0, 0, 255),
        "fps": (0, 255, 255),
    }

    def __init__(self):
        self.font = cv.FONT_HERSHEY_SIMPLEX

    def draw_landmarks(self, image: np.ndarray,
                        landmarks_2d: list) -> np.ndarray:
        """
        绘制 21 个关键点和连接线。

        Args:
            image: 输入图像
            landmarks_2d: [(x, y), ...] 像素坐标列表

        Returns:
            np.ndarray: 绘制后的图像
        """
        if not landmarks_2d or len(landmarks_2d) < 21:
            return image

        h, w = image.shape[:2]
        # 转换为像素坐标
        points = []
        for lm in landmarks_2d:
            x = int(lm[0] * w)
            y = int(lm[1] * h)
            points.append((x, y))

        # 绘制连接线
        for i, j in self.HAND_CONNECTIONS:
            if i < len(points) and j < len(points):
                cv.line(image, points[i], points[j],
                        self.COLORS["bone"], 2)

        # 绘制关键点
        for i, pt in enumerate(points):
            if i in (4, 8, 12, 16, 20):  # 指尖
                cv.circle(image, pt, 7, self.COLORS["tip"], -1)
                cv.circle(image, pt, 7, (0, 0, 0), 1)
            else:
                cv.circle(image, pt, 4, self.COLORS["joint"], -1)
                cv.circle(image, pt, 4, (0, 0, 0), 1)

        return image

    def draw_hand_info(self, image: np.ndarray,
                        result: dict,
                        fps: float,
                        x_offset: int = 0) -> np.ndarray:
        """
        在图像上绘制手势识别信息。

        Args:
            image: 输入图像
            result: 识别结果字典
            fps: 当前帧率
            x_offset: 水平偏移量（用于双手分栏显示）
        """
        h, w = image.shape[:2]

        # FPS（仅在偏移量为0时显示，避免重复）
        if x_offset == 0:
            fps_text = f"FPS: {fps:.1f}"
            cv.putText(image, fps_text, (10, 30),
                       self.font, 0.8, self.COLORS["fps"], 2, cv.LINE_AA)

        if not result.get("is_detected", False):
            cv.putText(image, "No hand detected", (10 + x_offset, 60),
                       self.font, 0.7, self.COLORS["warning"], 2, cv.LINE_AA)
            return image

        # 手势名称 + 置信度
        gesture = result.get("gesture", "Unknown")
        confidence = result.get("confidence", 0.0)
        gesture_text = f"{gesture} ({confidence:.2f})"
        cv.putText(image, gesture_text, (10 + x_offset, 60),
                   self.font, 0.8, self.COLORS["text_fg"], 2, cv.LINE_AA)

        # 左右手 + 手索引
        handedness = result.get("handedness", "Unknown")
        hand_index = result.get("hand_index", -1)
        hand_text = f"Hand: {handedness} [idx={hand_index}]"
        cv.putText(image, hand_text, (10 + x_offset, 90),
                   self.font, 0.6, self.COLORS["text_fg"], 1, cv.LINE_AA)

        # 旋转角度
        rot_x = result.get("hand_rotation_x", 0.0)
        rot_y = result.get("hand_rotation_y", 0.0)
        rot_z = result.get("hand_rotation_z", 0.0)
        rot_text = f"Rot: roll={rot_x:.1f} pitch={rot_y:.1f} yaw={rot_z:.1f}"
        cv.putText(image, rot_text, (10 + x_offset, 110),
                   self.font, 0.5, self.COLORS["text_fg"], 1, cv.LINE_AA)

        # 手指状态条
        fingers = result.get("fingers", [0.0] * 5)
        finger_names = ["Thumb", "Index", "Middle", "Ring", "Pinky"]
        bar_x = 10 + x_offset
        bar_y = 130
        bar_w, bar_h = 100, 12
        gap = 18

        for i, (name, val) in enumerate(zip(finger_names, fingers)):
            y = bar_y + i * gap
            # 背景
            cv.rectangle(image, (bar_x, y),
                         (bar_x + bar_w, y + bar_h),
                         (50, 50, 50), -1)
            # 填充（绿色到红色渐变色）
            fill_w = int(bar_w * val)
            color_b = int(255 * (1.0 - val))
            color_g = int(255 * val)
            cv.rectangle(image, (bar_x, y),
                         (bar_x + fill_w, y + bar_h),
                         (color_b, color_g, 0), -1)
            # 边框
            cv.rectangle(image, (bar_x, y),
                         (bar_x + bar_w, y + bar_h),
                         (200, 200, 200), 1)
            # 标签
            cv.putText(image, name, (bar_x + bar_w + 8, y + bar_h - 2),
                       self.font, 0.4, self.COLORS["text_fg"], 1, cv.LINE_AA)
            # 数值
            cv.putText(image, f"{val:.2f}",
                       (bar_x + bar_w + 60, y + bar_h - 2),
                       self.font, 0.4, self.COLORS["text_fg"], 1, cv.LINE_AA)

        # Pinch 距离
        pinch = result.get("pinch_distance", 1.0)
        pinch_text = f"Pinch: {pinch:.3f}"
        cv.putText(image, pinch_text, (10 + x_offset, bar_y + 5 * gap + 10),
                   self.font, 0.6, self.COLORS["text_fg"], 1, cv.LINE_AA)

        # 手部坐标
        hx = result.get("hand_x", 0.0)
        hy = result.get("hand_y", 0.0)
        coord_text = f"Pos: ({hx:.2f}, {hy:.2f})"
        cv.putText(image, coord_text, (10 + x_offset, bar_y + 6 * gap + 10),
                   self.font, 0.6, self.COLORS["text_fg"], 1, cv.LINE_AA)

        # 低帧率警告
        if fps < FPS_WARNING_THRESHOLD:
            warning = f"LOW FPS ({fps:.0f})! Reduce resolution or close other apps."
            cv.putText(image, warning, (w // 2 - 200, h - 20),
                       self.font, 0.6, self.COLORS["warning"], 2, cv.LINE_AA)

        return image


# ======================================================================
# 核心服务器
# ======================================================================

def _inflight_open_guard(func):
    """批次 AD-5（F-2，需求 §4.2）：在飞开镜登记薄壳——`_switch_camera` 执行期（含所有
    早退分支）把目标 id 登记在 `self._open_in_flight_target`，返回（无论正常/异常）即清。

    消费方：`_start_camera_by_name` 收到**同目标**重复启动指令时，若开镜仍在飞 → 直接忽略
    （不 release、不重启、不再次进入 `_switch_camera`、不递增 `_switch_generation`）。
    为何必须：`_start_camera_by_name` → `_note_switch_target` 会对**相同目标**也递增代际，
    代际递增会让在飞 `_switch_camera` 的逐轮核对判定「已过期」→ 刚连上就就地 release →
    指示灯闪断 + 反复 open/release（用户诉求「一次加载好摄像头」的破坏源之一）。

    实现口径：装饰器（`functools.wraps` 保留原函数，`inspect.getsource` 经 `unwrap`
    仍取到 `_switch_camera` 本体源码——存量源锚 `selftest_review_fixes` 零影响）。
    """
    @functools.wraps(func)
    def wrapper(self, *args, **kwargs):
        try:
            return func(self, *args, **kwargs)
        finally:
            self._open_in_flight_target = None
    return wrapper


class HandTrackingServer:
    """
    手势跟踪服务器主类。
    整合摄像头、MediaPipe 手势检测、增强手势引擎和 UDP 输出。
    """

    def __init__(self,
                 camera_id: int = None,
                 udp_ip: str = UDP_IP,
                 udp_port: int = UDP_PORT,
                 frame_port: int = None,
                 control_port: int = None,
                 width: int = 640,
                 height: int = 480,
                 min_detection_confidence: float = MIN_DETECTION_CONFIDENCE,
                 min_tracking_confidence: float = MIN_TRACKING_CONFIDENCE,
                 max_num_hands: int = 2,
                 owner_pid: Optional[int] = None):
        """
        初始化服务器。

        Args:
            camera_id: 摄像头索引，None 自动选择
            udp_ip: Godot UDP 监听地址
            udp_port: Godot UDP 监听端口
            width: 摄像头宽度
            height: 摄像头高度
            min_detection_confidence: 最小检测置信度
            min_tracking_confidence: 最小跟踪置信度
            max_num_hands: 最大检测手数量
            owner_pid: Z4-① 宿主进程 PID（编辑器态=游戏进程 / 打包态=launcher）——
                父进程看门狗的主判据；None 时看门狗回退自然父 PID 判据。
        """
        self.width = width
        self.height = height
        self.min_detection_confidence = min_detection_confidence
        self.min_tracking_confidence = min_tracking_confidence
        self.max_num_hands = max_num_hands

        # 批次 Z（Z4，spec §4）：命令收发解耦 + 看门狗 + 句柄单入口状态
        self._owner_pid = owner_pid          # ① 宿主 PID（看门狗主判据）
        self._cmd_queue: "deque" = deque()   # ③ 收线程 → 主循环 FIFO 命令队列
        self._control_thread: Optional[threading.Thread] = None
        self._control_recv_stop = False
        self._watchdog_thread: Optional[threading.Thread] = None
        self._watchdog_initial_ppid = 0
        self._shutdown_requested = False     # ③ SHUTDOWN 早生效（启动期跳过首开/主循环）
        self._release_latch = False          # ③④ RELEASE 闩（首开/在飞 SWITCH 完成后就地释放）
        # 批次 AD（spec §4.2.2-1）留痕：本标志（Z4-③ 首开配置窗）现有唯一写值=False——
        # 首开段（含分辨率探测/预热）随冷启动零开镜一并退役，已不存在任何配置窗；下游
        # `not self._cap_configuring` 守卫随之恒真（行为=批次 Z 语义下「无窗」形态）。
        # 保留成员与守卫（不清扫）理由：RELEASE/SHUTDOWN 路径为安全关键路径，本波只做
        # 语义留痕，避免无关重构引入发布语义漂移。
        self._cap_configuring = False        # ④ 首开配置窗（批次 AD 起恒 False，见上注）
        self._acquire_lock = threading.Lock()  # ④ 句柄获取互斥（单入口内建，开镜零并发）

        # 组件
        self.camera_selector = CameraSelector()
        # 双手独立引擎实例：左右手各有一个独立的 7 帧滑窗，
        # 避免双手数据交替写入同一个历史窗口导致手势投票无法收敛
        self.gesture_engine_left = GestureEngine()
        self.gesture_engine_right = GestureEngine()
        self.udp_sender = UDPSender(udp_ip, udp_port)
        self.visualizer = Visualizer()

        # 摄像头
        self.cap: Optional[cv.VideoCapture] = None
        self.current_camera_id = camera_id

        # MediaPipe - 使用 Tasks API 的 HandLandmarker
        self.landmarker = None

        # 状态
        self.running = False
        self.fps_counter = deque(maxlen=30)
        self._last_frame_time = time.time()
        self._last_camera_read_time = time.time()
        self._no_frame_count = 0
        self._no_frame_last_mark = 0.0   # 批次 AA 回修2（W4-P2-2）：上次无帧计数时刻（0=从未计，0.0 与真实 epoch 差恒超阈）
        # 批次 AD-5（F-1，需求 §4.1）：首帧快速判定三态——`_first_frame_pending`=开镜成功
        # 后「首帧未到」武装（真实帧到达解除）；`_first_frame_fast_tried`=本开镜会话快速
        # 判定已用（每开镜成功复位，单会话至多触发一次）；`_frameless_open_streak`=连续
        # 「开了却一帧未出」的开镜次数，仅由真实帧到达清零 → 安静重连总上界
        # FIRST_FRAME_QUIET_RECONNECT_MAX。
        self._first_frame_pending = False
        self._first_frame_fast_tried = False
        self._frameless_open_streak = 0
        # 批次 AD-5（F-2，需求 §4.2）：在飞开镜目标登记（_inflight_open_guard 维护）
        self._open_in_flight_target = None
        self._last_heartbeat = 0.0
        self._camera_lock = threading.Lock()
        # 批次 U（U4/U2，spec §6.2）：RELEASE 抗自动重连标志（双审 P0-2）＋探测线程串行锁
        self._camera_intentionally_released = False
        self._probe_lock = threading.Lock()
        self._probe_in_flight_id = None
        # 批次 Z（Z5-8）：探测线程收敛状态（单点 spawn 入口 + 存活上限计数）
        self._probe_thread: Optional[threading.Thread] = None
        self._probe_spawn_count = 0
        # 批次 AD-5b（需求 §4.6）：惰性矩阵探测窗状态——`_matrix_probe_active`=探测
        # 在飞（`_process_frame` 两条无帧看门狗判定据此静默；finally 必清，探测期
        # 绝不触发 release/`camera_closed`）；`_probe_cmd_epoch`=主流命令让位纪元
        # （收线程接收点与执行漏斗入口 bump；worker 逐档比对 → 变化即中止让位）。
        # 用纪元而非布尔：免疫「探测开始前已到的命令」被陈旧布尔误判为让位令。
        self._matrix_probe_active = False
        self._probe_cmd_epoch = 0
        # 批次V审查①-P2：SWITCH 全失败重连冷却——{设备id: 冷却到期 time.time()}。
        # 冷却期内自动重连跳过该 id（防失败设备重连风暴）；显式 SWITCH 不受限；成功开启即清除。
        self._switch_fail_cooldown: dict = {}
        # 批次 AA（W4-2，spec §7.3）：自动重连状态机——速率限制（退避窗）+ 预算 + FAILED。
        self._reconnect_next_at = 0.0            # 下次允许重连时刻（指数退避闸）
        self._reconnect_attempts = 0             # 已用重试预算（成功即清零）
        self._reconnect_backoff = RECONNECT_BACKOFF_BASE_SEC   # 当前退避（×2 至上限）
        self._reconnect_failed = False           # 预算耗尽 FAILED 态（显式 SWITCH 成功即复位）
        self._reconnect_error_reported = False   # FAILED 的 camera_error 恰一条护栏
        # 批次 AA（W4-3，spec §7.3）：SWITCH 目标 id 单一真值 + 代际号——收线程接收点登记，
        # 新 SWITCH 到达即递增代际；在飞 SWITCH 每轮核对，过期立即中止（旧设备不复开）。
        self._switch_target_id = None
        self._switch_generation = 0
        # 批次 AA（W4-8，spec §7.3/§22 裁决 5）：启动枚举降扰——启动期 WMI 候选零开镜，
        # CAP 可用性探测懒化（WMI 空 → GET_CAMERAS 触发独立线程补全）。
        self._enum_probe_pending = False
        self._enum_probe_started = False
        self._enum_probe_thread: Optional[threading.Thread] = None
        # 最新帧引用：_camera_read_thread 中赋值，主线程和流线程读取（无锁、无队列）
        self._latest_frame = None
        # MediaPipe 单调递增时间戳计数器（替代 time.time()，避免 detect_for_video 重复时间戳）
        self._mp_timestamp_ms: int = 0
        # 批次 Y（Y-A6/Y-A4）：per-hand 稳定 id 跟踪 + 每手独立丢帧容忍窗
        # （替换旧版 _sticky_handedness 粘性判手——key=帧内枚举序号的串手根因）
        self._hand_tracker = HandTracker()
        # 批次 Y（Y-A17，spec §3.2）：摄像头开启真值（边沿事件的电平镜像，
        # 心跳 camera_open 字段与事件发送共用；False=流未开启）
        self._camera_stream_open: bool = False
        # 批次 Y（Y-A16，spec §3.3）→ 批次 AD（spec §4.2.2-3）：启动指令携带的设备名
        # （`START_CAMERA_BY_NAME:<名>` / 兼容旧 `SET_PREFERRED_CAMERA:<名>`）。
        self._preferred_camera_name: str = ""
        # 批次 AC（领域二，spec §4.2-2）→ 批次 AD：**握手已达**状态位——收到设备启动
        # 指令（START_CAMERA_BY_NAME / 兼容 SET_PREFERRED_CAMERA）或 SWITCH_CAMERA 即置真。
        # 批次 AD 后启动序已不阻塞等待（零握手窗），本标志仅作「Godot 已表达意图」的
        # 状态留痕与自测锚点。
        self._handshake_received: bool = False
        # 批次 AC（领域二，spec §4.2-2 时序卫士）→ 批次 AD：`_startup_open_done` 首开段
        # 标志**彻底退役**——批次 AD 冷启动完全无首开段（零开镜、零阻塞），启动指令一律
        # 直达 `_start_camera_by_name` → `_switch_camera`，无需任何时序卫士标志区分。

        # 摄像头画面 UDP 发送
        self.frame_socket: Optional[socket.socket] = None
        self.frame_send_ip = "127.0.0.1"
        # 批次 R（spec §3.3 端口派生终态）：JPEG=P+1、控制=P+2；入参未给时按 P 派生
        self.frame_send_port = frame_port if frame_port is not None else udp_port + 1
        self._frame_counter = 0

        # 控制命令接收（Godot → Python）
        self.control_socket: Optional[socket.socket] = None
        self.control_ip = "127.0.0.1"
        self.control_port = control_port if control_port is not None else udp_port + 2

        # Headless 模式（无窗口，Godot 后台启动）
        self.headless = False

        # 图片翻转（镜像显示）
        self.flip_image = True

        # 摄像头支持的分辨率列表（启动时一次性检测）
        self._supported_resolutions = []

        # 批次 T（spec §4-T7/§6.2）：tip 滤波实例（key=(hand_index, 轴)）与帧率探测结果
        self._tip_filters = {}
        self._fps_options = []
        # 批次 AA（W2-8，spec §5.3）：全 landmark 下发平滑实例（key=hand_index，
        # 每实例按 track id 自复位——与 _tip_filters 同侧别粒度）
        self._lm_smoother = {}

        # 摄像头后台采集线程
        self._stream_thread: Optional[threading.Thread] = None

        # 摄像头独立读取线程（将 cap.read() 从主循环串行路径分离）
        self._read_thread: Optional[threading.Thread] = None

        # 独立审查修复批（2026-09-26，P0）：建线幂等 flag——_ensure_capture_threads
        # 唯一置位点；首开失败/被 RELEASE 跳过后，SWITCH/重连成功段补建线不再漏。
        self._capture_threads_started = False

        # 修复批次（枚举空）：init 消息摄像头条目列表（id=CAP 索引）与 WMI 显示名缓存
        self._cameras: list = []
        self._camera_names: dict = {}

        # 注册退出清理（确保摄像头被释放）
        atexit.register(self._cleanup)
        try:
            signal.signal(signal.SIGTERM, lambda *_: (
                self._cleanup(), os._exit(0)))
        except Exception:
            pass

    # ------------------------------------------------------------------
    # 生命周期
    # ------------------------------------------------------------------

    def _get_all_camera_names(self) -> dict:
        """多链 WMI 查询获取摄像头显示名，返回 {index: name}（仅作显示名回填，不参与 id 判定）。

        修复批次（枚举空）：与 camera_selector.py 同款四链查询（单链 timeout=5s）；
        失败/超时打印告警不再静默吞；全部失败返回空 dict，显示名回退「摄像头 N」。
        注意：WMI 名单序≠CAP 索引序，本字典只用于显示名回填，设备 id 一律为 CAP 索引。
        """
        import subprocess as _sp
        queries = [
            # 策略1：Win32_PnPEntity + PNPClass = Camera（最常见）
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'Camera' } | Select-Object -ExpandProperty Name",
            # 策略2：Win32_PnPEntity + PNPClass = Image（部分笔记本）
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'Image' } | Select-Object -ExpandProperty Name",
            # 策略3：Win32_PnPEntity + 名称含 camera/webcam（兜底）
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.Name -match 'camera|webcam|hd' } | Select-Object -ExpandProperty Name",
            # 策略4：Win32_PnPEntity + PNPClass = USB 且名称含 camera/webcam/video
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'USB' -and $_.Name -match 'camera|webcam|video' } | Select-Object -ExpandProperty Name",
        ]
        for qi, query in enumerate(queries, start=1):
            try:
                # P0 回修：字节模式捕获（捕获侧不做编码解码，读取线程绝无
                # UnicodeDecodeError）+ decode_console_bytes 显式解码（gbk→utf-8→replace）
                r = _sp.run(["powershell", "-NoProfile", "-Command", query],
                            capture_output=True, timeout=5)
            except Exception as e:
                print(f"[枚举] WMI 显示名查询链{qi} 异常: {e}，尝试下一链")
                continue
            stdout_text = decode_console_bytes(getattr(r, "stdout", None))
            if r.returncode == 0 and stdout_text.strip():
                names = [line.strip() for line in stdout_text.split('\n') if line.strip()]
                # P0 回修：显示名逐条 isinstance(str) 过滤（防 None/防非字符串）
                names = [n for n in names if isinstance(n, str) and n.strip()]
                if names:
                    print(f"[枚举] WMI 显示名查询链{qi} 命中 {len(names)} 条")
                    return {i: n for i, n in enumerate(names)}
            print(f"[枚举] WMI 显示名查询链{qi} 无结果 (rc={r.returncode})，尝试下一链")
        print("[枚举] WMI 显示名查询全部失败：显示名将回退为「摄像头 N」（不影响可用性判定）")
        return {}

    def _startup_probe_open(self, index: int):
        """批次 AA（W4-8）：启动期枚举探针桩——**默认零开镜**（返回 None → 全索引
        探测失败，候选名单回落 WMI 显示名构建，启动期开镜上界=1 仅首开）。

        仅显式 `AA_ALLOW_REAL_CAMERA=1`（摄像头红线同一把门，人工真机
        复验用）才经句柄单入口真开镜试探——与 selftest_enum_probe 的门同源语义。
        完整 CAP 可用性探测的生产路径 = 懒线程 `_enum_probe_worker`（用户打开下拉时）。
        """
        if os.environ.get("AA_ALLOW_REAL_CAMERA") == "1":
            return self._acquire_probe_open(index)
        return None

    def _enumerate_cameras_step(self) -> tuple:
        """第 1 步枚举：**仅物理设备名单（零开镜）** → 候选条目（批次 AD 语义收窄）。

        批次 AA（W4-8，spec §7.3 + §22 裁决 5）保留 + 批次 AD（spec §4.2.2-1）收窄：
        - **启动期开镜次数上界 = 0**（旧「=1 仅记忆设备首开」进一步退役）——启动阶段
          只枚举物理设备列表，**绝不调用 `_acquire_camera_handle` / `cv.VideoCapture`
          打开任何摄像头**；设备启停一律等 Godot 经 9878 下发启动指令（查名直启）；
        - 实施路径 = 懒探测：`enumerate_cameras` 照常调用（协议/自测契约兼容）但
          open_fn 换**零开镜桩** `_startup_probe_open`（默认 None，AA_ALLOW_REAL_CAMERA=1
          才真探）→ probe_results 全 False → 候选条目回落 **WMI 名单合成**（不激活设备）；
          CAP 可用性探测延后到用户打开下拉（GET_CAMERAS）由**独立线程**补全
          （_enum_probe_worker 走真 _acquire_probe_open，不阻塞主循环/首开）；
        - id 语义不变：候选 id = WMI 名单位次（与既有显示名回填 _camera_names[i]
          同一映射假设，非本批新引入；CAP 可用性由懒探测线程回填校正）；
        - WMI 全链失效 → 候选空 + _enum_probe_pending=true（懒线程兜底找设备）。
        - **auto 缺省已退役**（批次 AD §4.2.1）：返回值第二项恒为 None（无「自动缺省
          设备」概念，设备名一律由 Godot 下发），保留二元组签名以兼容既有调用点。

        Returns:
            tuple[list, None]: (cameras 条目列表, None)。

        本函数任何路径不抛异常，cameras 恒为 list。
        """
        self._camera_names = self._get_all_camera_names()
        probe_results = enumerate_cameras(max_index=3, open_fn=self._startup_probe_open)
        print(f"探测结果（启动期零开镜桩）: {probe_results}")
        if not any(usable for _idx, usable in probe_results):
            # 零开镜态（默认）：probe 全 False → 候选存在性按 WMI 名单合成（零激活）
            # 批次 AA（W4-P3-5 留痕，P3-d）：**WMI 名单位次 ↔ CAP 索引映射为既有回填假设**
            #（候选 id=名单位次 i、显示名=_camera_names[i]，两者非同一坐标系——USB 枚举序
            # 与 DSHOW CAP 序可能错位）。错位形态：记忆名开到错误物理设备（有 camera_error
            # + 用户手动下拉收口兜底，**无 ping-pong**：SWITCH 失败不回切、无自动重连抖动）。
            # 建议真机用首开后 _backfill_camera_entry 实测名回环校验（CAP 探测成功即以
            # 实测校正），本波不改逻辑仅留痕。
            probe_results = [(int(i), True) for i in sorted(self._camera_names)]
        cameras = build_camera_entries(probe_results, self._camera_names)
        self._cameras = cameras
        self._enum_probe_pending = not cameras
        # 批次 AD（spec §4.2.2-1）：启动期只需候选物理设备列表——**不再计算自动缺省设备**
        # （pick_auto_camera 已随黑名单一并退役）；首启目标由 Godot 的
        # START_CAMERA_BY_NAME 握手经 pick_camera_by_name 解析。
        print(f"[枚举] 启动期候选名单（零开镜）: {[(c['id'], c['name']) for c in cameras]}"
              f"（设备启停等 Godot 查名直启指令；本进程不自动开任何设备）")
        return cameras, None

    def start(self):
        """启动服务器。"""
        self._start_watchdog()   # 批次 Z（Z4-①）：看门狗先行——宿主/父消失即释放自退
        print("=" * 50)
        print("   手部跟踪服务器 v1.0")
        print("   UDP: {}:{}".format(self.udp_sender.ip, self.udp_sender.port))
        print(f"   摄像头画面流端口: {self.frame_send_port}")
        print("=" * 50)

        # 启动前序（批次 Y 回修审查① P1-2 抽取；批次 AD §4.2.2-1 收窄）：控制口接管 →
        # 物理设备枚举（零开镜）→ init#1（current_camera=-1）。**无握手等待窗、无首开**。
        chosen_id = self._startup_sequence()
        self.current_camera_id = chosen_id   # 批次 AD：恒 None（未启动设备）

        # 第2步：批次 AD（spec §4.2.2-1）：**冷启动不打开任何摄像头**——cap 恒 None、
        # current_camera_id 恒 None；设备启停等 Godot 经 9878 下发 START_CAMERA_BY_NAME
        # （主循环 _check_control_commands 消费：查名直启 / 未命中降级首项 / 列表空回传
        # 0 摄像头状态）。旧 AC 的「首开段」（_wait_for_preference + _acquire_camera_handle
        # 开镜 + 分辨率探测/预热）整体退役——启动期开镜次数上界由 1 降为 0。
        print("\n[2/3] 等待设备启动指令（冷启动零开镜）...")
        self.cap = None
        self._cap_configuring = False

        # 发送分辨率信息到 Godot（无论摄像头是否打开，空列表表示无）
        # 批次 T：init#2 携带 fps_options（摄像头未打开时空列表=无，spec §6.1）
        self._send_init2()
        print(f"[OK] 分辨率/帧率信息已发送: resolutions={self._supported_resolutions}, fps_options={self._fps_options}")

        # （批次 Y：控制口 bind 已前移至第 2 步首开之前——SET_PREFERRED_CAMERA
        # 等待窗依赖；接管序与 FATAL 语义不变，见 start() 前段。）

        # 2. 初始化 MediaPipe HandLandmarker (Tasks API)
        print("\n[2/3] 初始化 MediaPipe HandLandmarker...")
        model_path = "models/hand_landmarker.task"
        try:
            from mediapipe.tasks import python
            from mediapipe.tasks.python import vision
            options = vision.HandLandmarkerOptions(
                base_options=python.BaseOptions(model_asset_path=model_path),
                running_mode=vision.RunningMode.VIDEO,
                num_hands=self.max_num_hands,
                min_hand_detection_confidence=self.min_detection_confidence,
                min_hand_presence_confidence=self.min_detection_confidence,
                min_tracking_confidence=self.min_tracking_confidence)
            self.landmarker = vision.HandLandmarker.create_from_options(options)
            print("[OK] MediaPipe HandLandmarker 已初始化")
        except Exception as e:
            print(f"[FAIL] MediaPipe 初始化失败: {e}")
            self._cleanup()
            return

        # 3. 启动主循环
        print("\n[3/3] 启动主循环...")
        print(f"\n  按 ESC 退出")
        print(f"  按 C   切换摄像头")
        print(f"  按 F   切换镜像\n")
        print("-" * 50)

        # 通知 Godot 启动完成（确保在 MediaPipe 初始化之后）
        print("__GESTURE_SERVER_READY__")
        import sys
        sys.stdout.flush()

        if self._shutdown_requested:
            # 批次 Z（Z4-③）：启动期间 SHUTDOWN 已达（收线程早生效）→ 不进主循环直接收拢
            print("[CTRL] 启动期间收到 SHUTDOWN → 清理退出（不进主循环）")
            self._cleanup()
            return
        self.running = True
        self._main_loop()

    def stop(self):
        """停止服务器。"""
        self.running = False
        self._cleanup()

    # ------------------------------------------------------------------
    # 批次 Z（Z4-①，spec §4-1）：父/宿主进程看门狗（孤儿双保险之①）
    # ------------------------------------------------------------------

    def _start_watchdog(self) -> None:
        """启动看门狗线程（start() 首步调用）：父/宿主 PID 消失 → 释放摄像头并自退。"""
        if self._watchdog_thread is not None:
            return
        try:
            self._watchdog_initial_ppid = os.getppid()
        except Exception:
            self._watchdog_initial_ppid = 0
        self._watchdog_thread = threading.Thread(target=self._watchdog_loop,
                                                 daemon=True, name="parent-watchdog")
        self._watchdog_thread.start()
        print(f"[看门狗] 已启动（owner_pid={self._owner_pid}，"
              f"ppid={self._watchdog_initial_ppid}，轮询 {WATCHDOG_POLL_SEC}s）")

    def _watchdog_loop(self) -> None:
        while True:
            time.sleep(WATCHDOG_POLL_SEC)
            if self._watchdog_should_exit(self._watchdog_initial_ppid, self._owner_pid):
                print("[看门狗] 宿主/父进程已消失 → 释放摄像头并自退（孤儿零残留）")
                try:
                    # 批次 Z（Z-B 回修 P2-b）：退出序改走 _shutdown_release——
                    # 停循环 → join 工作线程（读取线程 1.5s）→ 再释放摄像头；
                    # 旧序（先 _release_camera_only 后 _cleanup join）存在读取线程
                    # 持旧 cap 引用的 ~1s 窄窗。
                    self._shutdown_release()
                    self._cleanup()               # 收拢线程/套接字（幂等，join 已完成秒返）
                except Exception as e:
                    print(f"[看门狗] 退出清理异常（忽略，仍强制退出）: {e}")
                os._exit(0)

    def _shutdown_release(self) -> None:
        """Z-B 回修 P2-b：看门狗/硬退统一退出序——停循环 → join 工作线程 → 释放摄像头。

        顺序：running=False（读取/采集线程循环退出）→ join(_stream, 1.0) →
        join(_read, 1.5) → _release_camera_only()（camera_closed 边沿照发）。
        根除「先释放、后 join」时读取线程持旧 cap 引用的重开/读取窄窗；SHUTDOWN 常规路径
        （_cleanup：join 先于 _cleanup_camera）同序更稳。
        """
        self.running = False
        self._shutdown_requested = True
        if self._stream_thread and self._stream_thread.is_alive():
            self._stream_thread.join(timeout=1.0)
        if self._read_thread and self._read_thread.is_alive():
            self._read_thread.join(timeout=1.5)
        self._release_camera_only()

    @staticmethod
    def _watchdog_should_exit(initial_ppid, owner_pid, alive=None) -> bool:
        """看门狗判定纯函数（selftest 直测）：owner 存在以 owner 为唯一判据（编辑器态
        父=py.exe 恒存活，父判据不可用）；无 owner 才回退自然父判据（打包/legacy 兜底）。
        alive 为注入缝（默认 _pid_alive）。"""
        if alive is None:
            alive = _pid_alive
        if owner_pid is not None and int(owner_pid) > 0:
            return not alive(int(owner_pid))
        return not alive(int(initial_ppid))

    def _startup_sequence(self):
        """启动前序（批次 Y 回修审查① P1-2 抽取，供顺序断言直调）。

        顺序（批次 AD §4.2.2-1 定档）：控制口接管（bind）→ 物理设备枚举（零开镜）→
        init#1（`current_camera=-1` 未启动哨兵）。**无握手等待窗、无首开选择**。

        - **bind 前移至枚举之前**（P1-2② 保留）：枚举最长 15s+（WMI 4 链×5s），若 bind
          在后，Godot 桥 spawn 后早期下发的设备启动指令在无接收者状态下被内核丢弃——
          开机恢复落空。前移后早期命令积压在内核收缓冲，主循环首轮即消费。
        - 接管序/FATAL 语义不变：bind 失败 → SHUTDOWN 旧实例重试 ×3 → 仍失败
          打印清晰中文原因并 SystemExit(1)。与原「枚举后 bind」位置相比仅时序
          提前（绑不了本就须退出），无语义冲突；枚举阶段不使用控制口，前移无副作用。
        - 批次 AD（spec §4.2.2-1/2）：**冷启动彻底零开镜**——本函数只做「控制口接管 →
          物理设备枚举 → 发 init#1（`current_camera=-1` 未启动哨兵）」，**不打开任何
          摄像头、不阻塞等待**（旧 AC 的 5.0s `_wait_for_preference` 待命窗退役：
          设备启停改由 Godot 经 9878 下发 `START_CAMERA_BY_NAME:<名>` 驱动，命令随
          控制口收线程入队、主循环首轮即执行——冷启动零额外延迟且绝不擅自开镜）。
          返回恒为 `None`（首开段不存在，`start()` 保持 `cap=None` / `current_camera_id=None`）。

        Returns:
            None: 首开目标恒 None（设备启动一律等 Godot 查名直启指令）。
        """
        # 0. 控制口接管（P1-2②：前移至枚举之前，接住桥早期重发的偏好命令）
        if not self._bind_control_socket():
            print(f"[FATAL] 存在无法接管的孤儿手势服务进程（占用控制口 "
                  f"{self.control_ip}:{self.control_port}），本进程退出。")
            print("[FATAL] 请在任务管理器结束旧的 python 手势服务进程后重新启动游戏。")
            self._cleanup()
            raise SystemExit(1)
        print(f"[OK] 控制命令接收已启动 [{self.control_ip}:{self.control_port}]")
        # 批次 Z（Z4-③）：bind 即起收线程——首开阻塞期（下述枚举/首开）命令改经队列
        # 照收，RELEASE/SHUTDOWN 收线程内提前生效（≤1s 硬指标）。
        self._start_control_recv_thread()

        # 1. 枚举摄像头并发 init 消息（**零开镜**；这样 Godot 端能立刻收到列表）
        # 批次 AD（spec §4.2.2-1）：启动阶段只枚举物理设备列表（WMI/设备注册表显示名，
        # 零 open）；**绝不调用 _acquire_camera_handle/cv.VideoCapture** 打开任何摄像头。
        print("\n[1/3] 枚举物理摄像头设备（零开镜）...")
        # 字节模式捕获+显式解码（P0 回修）：WMI/PowerShell 子进程读取线程绝无
        # UnicodeDecodeError，查询异常/解码失败一律回空显示名（绝不 None），
        # 消费处全部防 None/防非字符串；WMI 多链查询仅作显示名回填（失败告警不静默吞）
        cameras, _auto_cam_id = self._enumerate_cameras_step()

        print(f"摄像头列表: {[(c['id'],c['name']) for c in cameras]}")

        # 立即发送 init 消息（不依赖摄像头打开）
        # 契约（修复批次）：cameras=[{"id": int(CAP索引), "name": str}]、
        # current_camera=CAP 索引 int；9876 JSON 带内 type:init 分流逻辑不变。
        # 批次 AD（spec §4.2.2-1）：**首次 init 握手 current_camera 恒为 -1**
        # （未启动设备哨兵；设备启停由 Godot 下发 START_CAMERA_BY_NAME 后经
        # init#1 重发/事件上报回传真实 id）。
        init_msg = {
            "type": "init",
            "cameras": [{"id": int(c["id"]), "name": str(c["name"])} for c in cameras],
            "current_camera": -1,
        }
        self.udp_sender.send(init_msg)
        print("[OK] init 消息已发送（current_camera=-1，未启动设备）")

        # 批次 AD（spec §4.2.2-1）：无握手等待窗、无首开选择——启动序到此为止，
        # `start()` 保持 cap=None / current_camera_id=None，随即进入主循环等指令。
        return None

    # ------------------------------------------------------------------
    # 主循环
    # ------------------------------------------------------------------

    def _main_loop(self):
        """主处理循环。"""
        while self.running:
            # 检查控制命令（非阻塞）
            self._check_control_commands()
            try:
                self._process_frame()
            except KeyboardInterrupt:
                print("\n[服务器] 收到中断信号")
                break
            except Exception as e:
                print(f"[服务器] 处理帧时出错: {e}")
                traceback.print_exc()
                # 短暂休眠避免错误风暴
                time.sleep(0.1)

        self._cleanup()

    def _process_frame(self):
        """处理单帧。"""
        # 批次 Z（Z4-③ 自查回修）：RELEASE 闩主循环复查——重连/SET_RESOLUTION 重开等在飞
        # 窗口内晚到的 RELEASE（收线程置闩时尚无 cap 可放），于开镜落位后的下一帧就地再执行：
        # _release_camera_only（含 camera_closed 边沿与标志位），开镜完成也无法保持打开；
        # 显式新 SWITCH 入口清闩（新意图）不受复查误伤。
        if self._release_latch and self.cap is not None and not self._cap_configuring:
            print("[CTRL] RELEASE 闩复查 → 在飞开镜就地释放（晚到释放优先）")
            self._release_camera_only()
        # 批次 AA（W4-5，spec §7.3/验收 7）：**无帧看门狗**——三死变量（CAMERA_TIMEOUT_SECONDS/
        # _last_camera_read_time/_no_frame_count）只写不读的根治：读线程挂死时 _latest_frame
        # 停在旧帧（非 None），旧实现照常处理旧帧+心跳 → 画面永久冻结零重连（症状⑤根因）。
        # 判定序（先看门狗后取帧，recover 后取帧即 None）：
        # - 仅「真实句柄在场（cap 非 None）∧ 非首开配置窗」才计数——时间戳唯一生产写点=
        #   读线程成功路径（挂死=同帧对象时间戳冻结）；存量 selftest 夹具 cap=None 直喂帧
        #   零影响（兼容缝）；
        # - 连续 NO_FRAME_TRIP_COUNT 次超阈（3×3s=9s）→ release 旧句柄 + 按预算重连。
        # 批次 AA 回修2（W4-P2-2，W4-5 语义修订）：**按窗口计数**——距上次计数 ≥
        # CAMERA_TIMEOUT_SECONDS 才 +1（「连续超阈 3 窗」语义）。旧实现逐主循环迭代 +1，
        # 冻结期主循环无 MediaPipe/无空转 sleep 高速自旋 → 3 次计数在同一次超阈窗内达成
        # → 实际触发阈 ≈3s 而非口径 9s（慢启动/瞬时停帧设备被误杀重开，指示灯闪烁家族
        # 复发风险）。CAMERA_TIMEOUT_SECONDS 常量值不变（0 起算时与真实 epoch 差恒超阈，
        # 首个超阈迭代即计第 1 窗，语义自洽）。
        # 批次 AD-5（F-1，需求 §4.1）：**首帧快速判定**——开镜成功后
        # `FIRST_FRAME_TIMEOUT_SEC` 内一帧未出 → 恰一次安静重连（连续无帧开镜上界
        # FIRST_FRAME_QUIET_RECONNECT_MAX）。置于 3×3s 无帧看门狗**之前**：一旦触发，
        # `_attempt_reconnect` 已复位基准与窗口计数，同迭代的看门狗分支零计数（零双触发）。
        # 未出帧形态专属（`_first_frame_pending`）：运行期普通停帧仍走既有 3×3s 看门狗，
        # 不被 2.5s 误杀（反向断言见 selftest_ad5 `test_fast_window_not_armed_after_real_frame`）。
        # 批次 AD-5b（需求 §4.6）：`_matrix_probe_active`（矩阵探测在飞）抑制本判定——
        # 探测期间读线程可能被 set/get 风暴短暂阻塞（实测每档分辨率重协商 ≈1.1s），
        # 此为**预期静默**而非开镜无帧，绝不因此 release/重连（画面与 HUD 不消失）。
        if self.cap is not None and not self._cap_configuring \
                and not self._matrix_probe_active \
                and self._first_frame_pending and not self._first_frame_fast_tried \
                and time.time() - self._last_camera_read_time > FIRST_FRAME_TIMEOUT_SEC:
            self._first_frame_fast_tried = True   # 本开镜会话快速判定至多介入一次
            if self._frameless_open_streak >= FIRST_FRAME_QUIET_RECONNECT_MAX:
                # 上界已达：不再快速重连（防连环 open/release 频闪），交既有看门狗按预算处置
                print(f"[AD-5] 首帧缺失但连续无帧开镜已达上界 "
                      f"({self._frameless_open_streak}/{FIRST_FRAME_QUIET_RECONNECT_MAX})，"
                      f"快速判定不再介入（由无帧看门狗按预算接管）")
            elif self._camera_intentionally_released:
                pass   # 用户已主动释放：不代其重连（与 _attempt_reconnect 同门）
            else:
                self._frameless_open_streak += 1
                print(f"[AD-5] 首帧 {FIRST_FRAME_TIMEOUT_SEC}s 未到 → 恰一次安静重连"
                      f"（第 {self._frameless_open_streak}/{FIRST_FRAME_QUIET_RECONNECT_MAX} 次）")
                self._attempt_reconnect()
        # 批次 AD-5b（需求 §4.6）：矩阵探测在飞同样抑制 3×3s 无帧看门狗——探测窗内
        # 帧间隔拉长（另开句柄风暴实测亦抢流，ad5b_probe_block_measure.txt 段 D）属
        # 预期静默，探测收尾由 worker finally 补起算看门狗基线后恢复正常判定；
        # 探测期**绝不**产生 release/`camera_closed`（画面与 HUD 不消失）。
        if self.cap is not None and not self._cap_configuring \
                and not self._matrix_probe_active \
                and time.time() - self._last_camera_read_time > CAMERA_TIMEOUT_SECONDS:
            _now_t = time.time()
            if _now_t - self._no_frame_last_mark >= CAMERA_TIMEOUT_SECONDS:
                self._no_frame_last_mark = _now_t
                self._no_frame_count += 1
                if self._no_frame_count >= NO_FRAME_TRIP_COUNT:
                    self._watchdog_recover()
        # 1. 读取最新帧（由 _camera_read_thread 独立线程填充，无锁 GIL 保证原子性）
        frame = self._latest_frame
        # 陈旧帧不进处理：句柄在场 ∧（已死 或 读帧超时）→ 交心跳/重连分支接管
        if frame is not None and self.cap is not None:
            if not self.cap.isOpened() or \
                    time.time() - self._last_camera_read_time > CAMERA_TIMEOUT_SECONDS:
                frame = None
        if frame is None:
            # 无帧可用：检查摄像头状态，尝试重连
            if self.cap is None or not self.cap.isOpened():
                # 批次 U（U4）：RELEASE 置标志后跳过重连（双审 P0-2），下方 1Hz 心跳空包照发保 READY
                # 批次 AC（领域二，spec §4.2-2）：**待命态（current_camera_id is None）零重连**——
                # 未确认/无自动可用物理设备时不指任何目标开镜（_attempt_reconnect 内同款门，
                # 此处前置以覆盖其被 mock/旁路的调用形态）。
                if not self._camera_intentionally_released \
                        and self.current_camera_id is not None:
                    self._attempt_reconnect()
            now = time.time()
            if now - self._last_heartbeat > HEARTBEAT_MIN_GAP_SEC:
                self._last_heartbeat = now
                # 批次 R（spec §3.3）：心跳=顶层双手空包（left/right 各 null），1Hz 沿用
                # 批次 Y（Y-A17，spec §3.2）：新增 camera_open 电平字段（流实际开启才
                # true）——事件=边沿真值，心跳字段=周期校准兜底（防 UDP 丢事件真值卡死）
                # 批次 AA（W1-11，spec §4.3）：新增 `stale: true` 顶层字段——无帧期心跳的
                # 「陈旧」标记，GDScript 侧按 held 语义短路（保留累计态、不派发语义事件、
                # **不 teardown**）。协议**只增不改**：老包（无该字段）行为零变化。
                # P2（独立审查修复批）：节拍常量单源 HEARTBEAT_MIN_GAP_SEC，与收线程
                # 兼职补发 _maybe_send_heartbeat 共享 _last_heartbeat 节拍。
                self.udp_sender.send({
                    "left": None,
                    "right": None,
                    "stale": True,
                    "timestamp": time.time(),
                    "camera_open": bool(self._camera_stream_open),
                })
            return

        # 2. 帧已由 _camera_read_thread 翻转，主循环不再处理翻转
        self._frame_counter += 1

        # 3. MediaPipe 每帧都处理（提高采样率）
        # 4. MediaPipe 检测——使用单调递增计数器替代 time.time()，
        #    避免同一毫秒调用两次导致跟踪状态损坏
        rgb = cv.cvtColor(frame, cv.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        # 批次 U（U8，spec §4-U8-1）：固定步长假设废止——真实单调时钟替代（采集波动不再失真
        # MediaPipe 时序）；max(+1, now) 双保证：严格单调（同毫秒两次调用）且间隔≈真实帧间隔。
        now_ms = time.monotonic_ns() // 1_000_000
        self._mp_timestamp_ms = max(self._mp_timestamp_ms + 1, now_ms)
        results = self.landmarker.detect_for_video(mp_image, self._mp_timestamp_ms)

        # 6. 处理每只手
        fps = self._get_fps()
        display_frame = frame.copy() if not self.headless else None
        multi_result = []
        left_result = None    # 批次 R：顶层双手组包收集位（spec §3.3）
        right_result = None

        # 批次 Y（Y-A6）：先构造本帧检出列表，交 HandTracker 做最近邻关联与
        # 稳定 id 分配（标签随 track 延续，几何判手只定新手初始标签）。
        # 批次 Z（Z5-2/Z5-3）：检出携带 MediaPipe handedness（label_mp/mp_score，交叉验证
        # 权威源）——HandTracker 内 mp 主判/几何兜底/同侧冲突修正。
        mp_handedness = self._extract_handedness(results)
        detections = []
        if results.hand_landmarks:
            for h_idx, hand_landmarks in enumerate(results.hand_landmarks):
                landmarks_3d = np.zeros((21, 3), dtype=np.float32)
                for i, lm in enumerate(hand_landmarks):
                    landmarks_3d[i] = [lm.x, lm.y, lm.z]
                hand_center_x = float(np.mean([lm.x for lm in hand_landmarks]))
                hand_center_y = float(np.mean([lm.y for lm in hand_landmarks]))
                label_geo, _ = self._determine_handedness(
                    hand_landmarks, mirrored=self.flip_image)
                label_mp, mp_score = (mp_handedness[h_idx]
                                      if h_idx < len(mp_handedness) else (None, 0.0))
                detections.append({
                    "center": (hand_center_x, hand_center_y),
                    "label_geo": label_geo,
                    "label_mp": label_mp,
                    "mp_score": mp_score,
                    "landmarks": landmarks_3d,
                })
            # 批次 AA（W1-5，spec §4.3）：检出后去重——同手重复框（中心距+尺寸比 / landmark
            # 重合）合并保留 mp_score 高者，防同手两个检出占满 num_hands=2 名额吞掉第二只真手。
            detections = _dedup_detections(detections)
            num_hands = len(detections)
            if num_hands > 1 or (num_hands == 1 and self._frame_counter % 30 == 0):
                hands_info = [
                    f"手{i}: {d['label_geo']}(c=({d['center'][0]:.2f},{d['center'][1]:.2f}))"
                    for i, d in enumerate(detections)]
                print(f"检测到 {num_hands} 只手 — {' | '.join(hands_info)}")

        now_mono = time.monotonic()
        items, new_ids, dead = self._hand_tracker.update(detections, now_mono)

        # Y-A6：id 变化=新手——该侧引擎（滑窗/EMA 历史）与 tip 滤波器复位，
        # 防老手时序状态污染新手判定与输出
        for new_id in new_ids:
            new_hidx = 0 if new_id.startswith("L") else 1
            (self.gesture_engine_left if new_hidx == 0
             else self.gesture_engine_right).reset()
            self._tip_filters.pop((new_hidx, 0), None)
            self._tip_filters.pop((new_hidx, 1), None)
        # track 判死 → 该侧 tip 滤波器复位（原「整帧 0 手全清」收紧为按侧，
        # hold 中的手不清滤波状态，单手离场不影响另一手）
        for d in dead:
            self._tip_filters.pop((d["hand_index"], 0), None)
            self._tip_filters.pop((d["hand_index"], 1), None)

        # MediaPipe 单调计数（秒），tip 滤波时间戳
        t_sec = self._mp_timestamp_ms / 1000.0

        for item in items:
            tr = item["track"]
            landmarks_2d = None
            if item["held"]:
                # 批次 Y（Y-A4，spec §3.1）：丢帧容忍窗——保留上一帧该手完整数据
                # （全部字段沿用上一帧值）+ held:true；超窗的 track 已判死不进 items
                last = tr["last_result"]
                if last is None:
                    continue  # 极端态：track 建立后从未产出数据即失帧，缺包一轮
                result = dict(last)
                result["held"] = True
                # 审查① P2-③：可变字段显式拷贝（fingers/landmarks 列表）——
                # 防跨帧共享引用被下游 in-place 修改污染 track 内的 hold 数据源
                result["fingers"] = list(last["fingers"])
                result["landmarks"] = [list(p) for p in last["landmarks"]]
                landmarks_2d = tr["last_landmarks"]
            else:
                det = item["detection"]
                landmarks_3d = det["landmarks"]
                # 根据 track 的 hand_index 选择对应的独立引擎实例（标签随 track 延续，
                # 不再逐帧几何改判——串手根除的另一半）
                engine = (self.gesture_engine_right
                          if tr["hand_index"] == 1
                          else self.gesture_engine_left)
                result = engine.process(landmarks_3d, tr["label"])
                result["hand_index"] = tr["hand_index"]
                result["fps"] = fps
                result["landmarks"] = landmarks_3d[:, :2].tolist()
                # 批次 AA（W2-8，spec §5.3）：全 21 landmark 下发平滑——只作用于下发字段
                # result["landmarks"]（骨架显示）；上方 engine.process 已读原始
                # landmarks_3d（判定内核零改动），tr["last_landmarks"]（ghost 裁决源）
                # 仍写原始值（W1-6 零影响）。
                sm = self._lm_smoother.setdefault(tr["hand_index"], LandmarkSmoother())
                result["landmarks"] = sm.smooth(tr["id"], result["landmarks"])
                # 批次 T（spec §4-T7）：One Euro 滤波只作用 lm[8] 输出通道
                fx = self._tip_filters.setdefault((tr["hand_index"], 0), OneEuroFilter())
                fy = self._tip_filters.setdefault((tr["hand_index"], 1), OneEuroFilter())
                result["tip_x"] = round(float(fx.filter(float(landmarks_3d[8][0]), t_sec)), 4)
                result["tip_y"] = round(float(fy.filter(float(landmarks_3d[8][1]), t_sec)), 4)
                # 批次 Y（Y-A6/Y-A4，spec §3.1）：手 dict 新增键仅 id/held 两个
                result["id"] = tr["id"]
                result["held"] = False
                # 批次 AA（W1-8，spec §4.3）：诊断三字段透传（gesture_map 的
                # GAME_GESTURE_DEBUG=1 日志消费，便于真手复验定位手性）。协议**只增不改**：
                # 老包缺键由 GDScript 侧 `.get(key, 缺省)` 兜底，老版本消费方零变化。
                result["label_mp"] = det.get("label_mp")
                result["mp_score"] = float(det.get("mp_score", 0.0) or 0.0)
                result["label_geo"] = det.get("label_geo")
                # 回写 track：丢帧容忍窗内 hold-last 的数据源
                tr["last_result"] = result
                tr["last_landmarks"] = landmarks_3d[:, :2]
                landmarks_2d = landmarks_3d[:, :2]

            # 批次 AA（W1-6，spec §4.3）：ghost 参与组包裁决——held track 中心若与本帧任一
            # fresh 检出中心 < HAND_MATCH_DIST → 判为**同一只手** → 丢弃 ghost（该侧置 None，
            # 不走下方「fresh 覆盖 held」路径）。防同一只手以 held 形态占另一侧 = 蓝+红双骨架。
            if bool(result.get("held", False)) and _held_ghost_is_same_hand(tr, detections):
                continue

            if tr["hand_index"] == 1:
                # Z5-2 槽位优先级：本帧实检出恒优先于 held（fresh 覆盖 held；held 只填空槽、
                # 不覆盖 fresh）——防「同侧冲突修正后的新手被对侧陈旧 held 数据遮蔽」。
                if right_result is None or not bool(result.get("held", False)):
                    right_result = result
            else:
                if left_result is None or not bool(result.get("held", False)):
                    left_result = result

            multi_result.append({
                "result": result,
                "landmarks_2d": landmarks_2d,
            })

            if display_frame is not None and landmarks_2d is not None:
                display_frame = self.visualizer.draw_landmarks(
                    display_frame, landmarks_2d)

        # 批次 R（spec §3.3）+ 批次 Y（Y-A4/Y-A17）：顶层双手组包，每帧恰一包。
        # 0 手时各手独立走 hold 逻辑后按实际组包（hold 窗内该手仍带完整数据）；
        # camera_open 电平字段随包下发（开启真值周期校准兜底，spec §3.2）
        self.udp_sender.send({
            "left": left_result,
            "right": right_result,
            "timestamp": time.time(),
            "camera_open": bool(self._camera_stream_open),
        })

        # 7. 绘制信息
        if display_frame is not None:
            if multi_result:
                for item in multi_result:
                    handedness = item["result"].get("handedness", "Right")
                    display_frame = self.visualizer.draw_hand_info(
                        display_frame, item["result"], fps,
                        x_offset=400 if handedness == "Left" else 0)
            else:
                empty_result = self.gesture_engine_right.get_empty_result(time.time())
                display_frame = self.visualizer.draw_hand_info(
                    display_frame, empty_result, fps)

            cv.imshow(WINDOW_NAME, display_frame)

        # 8. 键盘处理（headless 模式下完全跳过 waitKey，避免 CPU 100% 空转）
        if not self.headless:
            key = cv.waitKey(1) & 0xFF
            self._handle_key(key)

    # ------------------------------------------------------------------
    # 左右手判断
    # ------------------------------------------------------------------

    def _extract_handedness(self, results) -> list:
        """批次 Z（Z5-2/Z5-3）接入、批次 AA（W1-1，spec §4.3）修正映射方向。

        `HandLandmarkerResult.handedness: List[List[category.Category]]`（mediapipe 0.10.x
        实证，与 hand_landmarks **同序对齐**，每手取 top-1：category_name ∈ {Left, Right}
        + score）。

        **映射方向（批次 AA W1-1 终态）：镜像输入 → 交换采用**（`if self.flip_image: swap`）。
        依据（官方标注图黄金判据，`selftest_aa_handedness.py` 实证）：Tasks API 的 handedness
        描述的是**「画面中被描绘那只手」的手性**——
          * 生产默认 flip_image=True：读取线程已 `cv.flip(frame, 1)`，镜像使手性外观翻转
            → 模型输出 = 用户真手的**镜像身份** → **必须交换**才得到物理侧别；
          * flip_image=False（--no-flip 原图）：模型输出即物理侧别 → **原样采用**。
        （批次 Z 旧码按 legacy `Hands` 文档字面实现为 `if not flip_image: swap`，与上恰好
        相反 → 全姿态系统性左右全反；批次 AA 前的文档串「flip=True 直接采用」同属错误，
        已同步修正。交换后与 `_determine_handedness(mirrored=…)` 几何口径在「掌心朝镜」
        姿态下同向——两口径互为交叉验证。）
        字段缺失/空按 (None, 0.0) 兜底（长度与 hand_landmarks 不齐由调用方按序号守卫）。
        """
        out = []
        try:
            handedness = getattr(results, "handedness", None) or []
        except Exception:
            handedness = []
        for cats in handedness:
            label, score = None, 0.0
            try:
                if cats:
                    cat = cats[0]
                    name = getattr(cat, "category_name", None)
                    if name in ("Left", "Right"):
                        label = name
                        if self.flip_image:
                            # 批次 AA（W1-1）：镜像输入 → 交换采用（旧码 `if not flip_image` 方向反）
                            label = "Right" if name == "Left" else "Left"
                        score = float(getattr(cat, "score", 0.0) or 0.0)
            except Exception:
                label, score = None, 0.0
            out.append((label, score))
        return out

    @staticmethod
    def _determine_handedness(
            hand_landmarks, mirrored: bool = True) -> tuple[str, int]:
        """
        通过拇指尖(4)与小指根(17)的 x 坐标判断左右手。

        批次 Z（Z5-3，spec §5-3）：本几何判定**降级为兜底**——正常路径以 MediaPipe
        handedness（_extract_handedness → HandTracker label_mp）为准；mp 缺失/同标冲突时
        才回落本函数（镜像修正口径不变）。

        批次 Y（Y-A6）：本几何判定仅决定「新手进入时的初始标签」——该手后续帧的
        标签由 HandTracker 按 track 延续，不再逐帧改判（几何误判不再扩散为串手）。

        镜像反转修正（几何口径；**前提=掌心朝镜、手指朝上**——手性外观随「掌/背朝镜」翻转，
        背朝镜姿态本函数会反标，故只作兜底，正常路径以 mp 为准）：
        - mirrored=True（默认，读取线程已 cv.flip(frame, 1) 镜像翻转）：
          右手：thumb_tip.x < pinky_mcp.x（拇指在图像左侧）
        - mirrored=False（--no-flip 直通画面）：判定取反——同一物理手在未镜像
          画面中 thumb/pinky 左右关系颠倒，沿用原口径会系统性左右反标。
        批次 AA（W1-1）同族同步：`_extract_handedness` 的 mp 映射已改为「flip=True → 交换」，
        与本几何口径在「掌心朝镜」姿态下**同向**（两口径互为交叉验证）；批次 Z 旧 mp 映射
        （flip=True 不换）恰与本几何口径反向，即「换 mp 权威后全姿态全反」的根因之一。

        Args:
            hand_landmarks: MediaPipe 手部关键点列表（含 .x/.y/.z）
            mirrored: 采集帧是否已经镜像翻转（server.flip_image）

        Returns:
            tuple[str, int]: (hand_label, hand_index)
                             "Left"/"Right" 和 0/1
        """
        thumb_tip = hand_landmarks[4]
        pinky_mcp = hand_landmarks[17]

        thumb_left = thumb_tip.x < pinky_mcp.x
        is_right = thumb_left if mirrored else (not thumb_left)
        if is_right:
            return "Right", 1  # 右手
        else:
            return "Left", 0   # 左手

    # ------------------------------------------------------------------
    # 控制命令
    # ------------------------------------------------------------------

    def _send_shutdown_to_control_port(self) -> None:
        """批次 V-B1（spec §6.3-4）：经临时 UDP 向 127.0.0.1:控制口 发送既有 SHUTDOWN
        控制指令，让占用控制口的孤儿旧实例自杀（SHUTDOWN 协议零变更，仅接管序使用）。
        """
        try:
            tmp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                tmp.sendto(CONTROL_TAKEOVER_CMD.encode("utf-8"),
                           (self.control_ip, self.control_port))
            finally:
                try:
                    tmp.close()
                except Exception:
                    pass
        except Exception as e:
            print(f"[接管] 向旧实例发送 SHUTDOWN 失败: {e}")

    def _bind_control_socket(self) -> bool:
        """批次 V-B1（spec §6.3-4）：控制口 bind 接管序。

        bind 失败 → 向 127.0.0.1:9878 旧实例发 SHUTDOWN → sleep 0.5s → 重试 bind
        （×3）；三次重试仍失败 → 打印清晰中文原因并返回 False（调用方以非零退出码
        退出）。根治「孤儿 Python 进程独占摄像头+控制口 9878，新实例 bind 失败即崩、
        重启游戏也无法接管」形态。
        """
        for attempt in range(CONTROL_BIND_MAX_RETRIES + 1):
            sock = None
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.settimeout(0.01)
                sock.bind((self.control_ip, self.control_port))
                self.control_socket = sock
                if attempt > 0:
                    print(f"[OK] 控制口接管成功（第 {attempt}/{CONTROL_BIND_MAX_RETRIES} 次重试后）")
                return True
            except OSError as e:
                if sock is not None:
                    try:
                        sock.close()
                    except Exception:
                        pass
                if attempt >= CONTROL_BIND_MAX_RETRIES:
                    print(f"[FATAL] 控制口 {self.control_ip}:{self.control_port} "
                          f"绑定失败且重试耗尽: {e}")
                    break
                print(f"[接管] 控制口 {self.control_port} 被占用（{e}），向旧实例发送 "
                      f"SHUTDOWN 后重试 {attempt + 1}/{CONTROL_BIND_MAX_RETRIES}"
                      f"（间隔 {CONTROL_BIND_RETRY_INTERVAL}s）...")
                self._send_shutdown_to_control_port()
                time.sleep(CONTROL_BIND_RETRY_INTERVAL)
        print(f"[FATAL] 控制口 {self.control_port} 接管失败：已向旧实例发送 SHUTDOWN 并重试 "
              f"{CONTROL_BIND_MAX_RETRIES} 次仍无法绑定。")
        return False

    # ------------------------------------------------------------------
    # 批次 Z（Z4-③，spec §4-3）：控制命令「收 / 执行」解耦
    # ------------------------------------------------------------------

    def _start_control_recv_thread(self) -> None:
        """Z4-③：启动独立收线程（控制口 bind 成功后调用——_startup_sequence 第 0 步）。

        收线程把命令落 _cmd_queue（FIFO），主循环 _check_control_commands 清队执行——
        首开阻塞期（WMI 枚举 15s+CAP 试探+同步首开+MediaPipe 初始化）命令不再丢失；
        RELEASE_CAMERA/SHUTDOWN 例外：收线程内**立即生效**（≤1s 实际释放硬指标）。
        """
        if self._control_thread is not None or self.control_socket is None:
            return
        try:
            self.control_socket.settimeout(CONTROL_RECV_POLL_SEC)
        except Exception:
            pass
        self._control_recv_stop = False
        self._control_thread = threading.Thread(target=self._control_recv_thread,
                                                daemon=True, name="ctrl-recv")
        self._control_thread.start()
        print(f"[线程] 控制命令收线程已启动（轮询 {CONTROL_RECV_POLL_SEC}s）")

    def _maybe_send_heartbeat(self) -> bool:
        """P2 心跳补发（独立审查修复批 2026-09-26）：控制口收线程兼职调用，不新建线程。

        病灶：心跳原先只在主循环 `_process_frame` 无帧分支发；SWITCH/重连在主循环内
        阻塞 >5s（开镜轮询/退避 sleep）→ 9876 零包 → 桥 `NO_PACKET_TIMEOUT_SEC=5.0`
        误判 UNAVAILABLE。

        判据（两道门，缺一不发）：
        - `_last_heartbeat` 距今 > HEARTBEAT_MIN_GAP_SEC（与主循环无帧分支共享同一
          节拍变量，双路并发经此对齐，UDP sendto 可并发、最坏重复一包无害）；
        - `udp_sender.last_send_time` 距今 > HEARTBEAT_MIN_GAP_SEC（主循环正常帧
          连发时零补发；发送端未暴露数值时间戳=测试桩 → 不越权补发，存量 selftest
          零影响）。

        包格式与现心跳**完全一致**（顶层双手空包 + stale + camera_open 电平），
        桥侧消费零变更。

        Returns:
            True=本次补发了心跳；False=节流中/主循环刚发过/发送端无时间戳。
        """
        now = time.time()
        if now - self._last_heartbeat <= HEARTBEAT_MIN_GAP_SEC:
            return False
        last = getattr(self.udp_sender, "last_send_time", None)
        if not isinstance(last, (int, float)):
            return False
        if now - last <= HEARTBEAT_MIN_GAP_SEC:
            return False
        self._last_heartbeat = now
        self.udp_sender.send({
            "left": None,
            "right": None,
            "stale": True,
            "timestamp": time.time(),
            "camera_open": bool(self._camera_stream_open),
        })
        return True

    def _control_recv_thread(self) -> None:
        """Z4-③：控制口收线程主体。RELEASE/SHUTDOWN 提前生效，其余命令入队待主循环执行。"""
        while not self._control_recv_stop:
            # P2（独立审查修复批）：兼职周期心跳——轮询节拍（≤CONTROL_RECV_POLL_SEC）
            # 内补发 9876 心跳，主循环被 SWITCH/重连阻塞时桥不误判 UNAVAILABLE。
            self._maybe_send_heartbeat()
            try:
                control_data, _ = self.control_socket.recvfrom(1024)
            except socket.timeout:
                continue
            except OSError:
                break   # socket 已被 _cleanup 关闭（收尸路径）
            try:
                cmd = control_data.decode('utf-8').strip()
            except Exception:
                continue
            if not cmd:
                continue
            if cmd == "RELEASE_CAMERA":
                # 提前生效（首开阻塞期 ≤1s 硬指标）：清在积队列（RELEASE 后先行命令作废，
                # 顺序语义确定）+ 置闩 + 立即释放（配置窗内只置闩不物理释放，见下）。
                # 批次 AD-5b：接收瞬间置让位纪元——在飞矩阵探测立即中止（不与释放抢句柄）
                self._note_probe_yield()
                self._cmd_queue.clear()
                self._release_latch = True
                print("[CTRL] RELEASE_CAMERA（收线程即时生效）: 只释放摄像头（服务循环常驻）")
                if not self._cap_configuring:
                    self._release_camera_only()
                continue
            if cmd == "SHUTDOWN":
                # 提前生效：停循环 + 无条件释放摄像头（退出零残留）；完整 _cleanup 交主循环
                #（队列单条 SHUTDOWN 语义与旧口径一致；主循环若长期阻塞则由看门狗兜底自退）。
                # 批次 AD-5b：接收瞬间置让位纪元——在飞矩阵探测立即中止
                self._note_probe_yield()
                self._cmd_queue.clear()
                self._shutdown_requested = True
                self.running = False
                self._release_latch = True
                if not self._cap_configuring:
                    self._release_camera_only()
                self._cmd_queue.append("SHUTDOWN")
                continue
            if cmd.startswith("SWITCH_CAMERA:"):
                # 批次 AA（W4-3，spec §7.3）：**接收点**登记目标 id 单一真值——新 SWITCH
                # 到达即递增代际（不等 FIFO 执行），在飞旧 SWITCH 下一轮核对即中止。
                # 批次 AD-5b：接收点同时置让位纪元（在飞矩阵探测先于 FIFO 执行让位）
                self._note_probe_yield()
                try:
                    self._note_switch_target(int(cmd.split(":", 1)[1]))
                except (TypeError, ValueError):
                    pass
            self._cmd_queue.append(cmd)

    def _check_control_commands(self):
        """执行已收控制命令（Z4-③：收/执行解耦后的执行侧）。

        - 收线程模式（生产）：FIFO 清队，单次至多 CONTROL_DRAIN_MAX_PER_CALL 条；
        - 无收线程模式（selftest/直喂夹具，_control_thread is None）：保留旧口径单次
          非阻塞 recvfrom（FakeCtrlSock/mock 直喂语义零回归，且 recvfrom 至多调用一次
          ——mock return_value 恒定返回时不得拉成死循环）。
        """
        if self._control_thread is not None:
            n = 0
            while self._cmd_queue and n < CONTROL_DRAIN_MAX_PER_CALL:
                self._execute_control_command(self._cmd_queue.popleft())
                n += 1
            return
        if not self.control_socket:
            return
        try:
            control_data, _ = self.control_socket.recvfrom(1024)
            cmd = control_data.decode('utf-8').strip()
        except socket.timeout:
            return
        except Exception:
            return
        self._execute_control_command(cmd)

    def _execute_control_command(self, cmd: str) -> None:
        """控制命令执行单漏斗（收线程队列与兼容直喂路径共用；协议零变更）。

        批次 AD-5b（§4.6）：入口对主流命令置探测让位纪元——直喂夹具（无收线程）
        与收线程模式同一判据；主流命令随后执行（`_switch_camera`/释放/就地改配）
        时在飞矩阵探测已在让位途中（逐档比对，≤一档驱动耗时即中止）。
        """
        if self._is_main_camera_cmd(cmd):
            self._note_probe_yield()
        try:
            if cmd == "SHUTDOWN":
                print("[CTRL] 收到关闭命令，释放摄像头...")
                self._cleanup()
                self.running = False
                self._shutdown_requested = True
            elif cmd == "RELEASE_CAMERA":
                # 批次 U（U4，spec §6.2）：只释放摄像头，进程与 9876/9877/9878 服务循环常驻；
                # 置 _camera_intentionally_released 击穿 _attempt_reconnect（双审 P0-2），心跳空包
                # 照发保 9876 带内活跃与 READY 语义。SHUTDOWN 协议保留但 Q3 不再使用。
                # 批次 Z（Z4-③）：兼容路径同语义 + 置闩（在飞首开/切换完成后不复开）。
                print("[CTRL] RELEASE_CAMERA: 只释放摄像头（服务循环常驻）")
                self._release_latch = True
                self._release_camera_only()
            elif cmd.startswith("PROBE_MATRIX:"):
                # 批次 U（U2，spec §6.2）：惰性按设备探测 RES/FPS 矩阵——独立线程执行（主循环帧流
                # 不断）；同 id 在探则忽略；全局 _probe_lock 串行；软预算 PROBE_BUDGET_SEC 自愈；
                # 成功/失败均经 9876 回 probe_result；全程不动当前流设备。
                try:
                    _probe_id = int(cmd.split(":")[1])
                except ValueError:
                    _probe_id = -1
                if _probe_id >= 0:
                    print(f"[CTRL] PROBE_MATRIX: {_probe_id}（独立线程）")
                    # 批次 Z（Z5-8）：线程收敛——单点入口，在忙复用/拒绝并发创建
                    self._spawn_probe_thread(_probe_id)
            elif cmd.startswith("SWITCH_CAMERA:"):
                new_id = int(cmd.split(":")[1])
                # 批次 AC（领域二，spec §4.2-2）：显式选设备=用户/桥已确认设备 → 结束等待窗
                # （握手已达语义，与 SET_PREFERRED_CAMERA 同族；空载荷握手之外的第二唤醒源）。
                self._handshake_received = True
                if self._control_thread is None:
                    # 批次 AA（W4-3）：直喂兼容路径（无收线程时接收点缺失）在此登记；
                    # 生产（收线程在）已在接收点登记，此处不重复递增代际。
                    self._note_switch_target(new_id)
                self._switch_camera(new_id)
            elif cmd.startswith("SET_RESOLUTION:"):
                try:
                    # 批次 U（U2，spec §6.2）：3 参扩展 SET_RESOLUTION:<id>:<w>x<h>——id≠当前先
                    # _switch_camera(id) 再 set（既有重开恢复流程沿用）；2 参旧式保留=对当前设备。
                    parts = cmd.split(":")
                    if len(parts) >= 3:
                        target_id = int(parts[1])
                        res_str = parts[2]
                    else:
                        target_id = self.current_camera_id
                        res_str = parts[1]
                    print(f"[CTRL] SET_RESOLUTION: id={target_id} {res_str}")
                    w_str, h_str = res_str.split("x")
                    new_w, new_h = int(w_str), int(h_str)
                    if target_id != self.current_camera_id:
                        # 批次 AA（W4-3）：3 参显式切设备 → 登记目标单一真值
                        self._note_switch_target(target_id)
                        self._switch_camera(target_id)
                    if self.cap and self.cap.isOpened():
                        self.cap.set(cv.CAP_PROP_FRAME_WIDTH, new_w)
                        self.cap.set(cv.CAP_PROP_FRAME_HEIGHT, new_h)
                        aw = int(self.cap.get(cv.CAP_PROP_FRAME_WIDTH))
                        ah = int(self.cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                        _mismatch = aw != new_w or ah != new_h
                        if _mismatch and self._camera_stream_open:
                            # 批次 AD-5（F-3，需求 §4.3）：**流真值在场（画面正在出）→ 保
                            # 画面优先**：回读不符降级为仅日志，绝不 release/reopen 连锁
                            #（重开失败会连锁 FATAL → camera_closed(error)+camera_error →
                            # HUD 全灭，正是用户实机「画面+手势 HUD 全部消失」的放大器）。
                            # 无流态（冷开/夹具形态）保持既有重开链与 FATAL 回传契约不变。
                            print(f"  [CTRL] cap.set mismatch ({aw}x{ah} vs {new_w}x{new_h})，"
                                  f"流已在场 → 降级仅日志（不触发 release/reopen 连锁）")
                        elif _mismatch:
                            # cap.set 未生效，释放重开摄像头
                            print(f"  [CTRL] cap.set mismatch ({aw}x{ah} vs {new_w}x{new_h}), reopening camera...")
                            self.cap.release()
                            self.cap = None
                            time.sleep(0.15)  # Windows DShow needs time to release device handle
                            # 批次 Z（Z4-④）：重开经句柄单入口（同设备，remember 语义沿用）
                            new_cap = self._acquire_camera_handle(
                                int(self.current_camera_id), remember=True)
                            if new_cap and new_cap.isOpened():
                                new_cap.set(cv.CAP_PROP_FRAME_WIDTH, new_w)
                                new_cap.set(cv.CAP_PROP_FRAME_HEIGHT, new_h)
                                aw = int(new_cap.get(cv.CAP_PROP_FRAME_WIDTH))
                                ah = int(new_cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                                self.cap = new_cap
                                # 批次 AD-5（F-1）：重开成功同样复位基准+武装首帧窗
                                self._mark_camera_open_success()
                                print(f"  [CTRL] Camera reopened OK: {aw}x{ah}")
                            else:
                                # reopen failed, try to restore old camera
                                print(f"  [CTRL] Camera reopen FAILED, attempting restore...")
                                time.sleep(0.3)
                                # 批次 Z（Z4-④）：恢复经句柄单入口（同设备）
                                restore_cap = self._acquire_camera_handle(
                                    int(self.current_camera_id), remember=True)
                                if restore_cap and restore_cap.isOpened():
                                    self.cap = restore_cap
                                    # 批次 AD-5（F-1）：恢复成功同样复位基准+武装首帧窗
                                    self._mark_camera_open_success()
                                    aw = int(self.cap.get(cv.CAP_PROP_FRAME_WIDTH))
                                    ah = int(self.cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                                    print(f"  [CTRL] Camera restored at {aw}x{ah}")
                                else:
                                    # 批次 V-B1（spec §6.3-3）：恢复失败 FATAL 必回传 camera_error
                                    print(f"  [CTRL] FATAL: Cannot restore camera!")
                                    # 批次 Y（Y-A17）：流已实际消亡 → camera_closed(reason="error")
                                    self._emit_camera_closed("error")
                                    self._send_camera_error(
                                        target_id,
                                        "SET_RESOLUTION 恢复失败：重开与恢复均无法打开设备")
                        self.width, self.height = aw, ah
                        # 批次 AD-5b（§4.5）：播种矩阵跟随**实际生效值**——种子定义
                        # （_supported_resolutions 含当前生效分辨率）在 SET_RESOLUTION
                        # 应用后保持为真，随后的 init#2 不落后于实际（下拉子列可回切）
                        if (aw, ah) not in self._supported_resolutions:
                            self._supported_resolutions.append((aw, ah))
                        print(f"  [CTRL] Resolution applied: {aw}x{ah}")
                        self._send_init2()  # 批次 T（spec §6.2）：应用后发 init#2 刷新矩阵
                except Exception as e:
                    print(f"  [CTRL] SET_RESOLUTION failed: {e}")
                    # 批次 V-B1（spec §6.3-3）：异常分支必回传 camera_error（失败设备
                    # id 防御解析：3 参式取显式 id，否则当前设备；再失败由 helper 回 0）
                    _err_id = self.current_camera_id
                    _parts = cmd.split(":")
                    if len(_parts) >= 3:
                        try:
                            _err_id = int(_parts[1])
                        except (TypeError, ValueError):
                            _err_id = self.current_camera_id
                    self._send_camera_error(_err_id, f"SET_RESOLUTION 失败: {e}")
            elif cmd.startswith("SET_FPS:"):
                # 批次 T（spec §6.2）：新增帧率命令——回读不符仅日志不回滚（UI 只展示探测通过档）
                # 批次 U（U2，spec §6.2）：3 参扩展 SET_FPS:<id>:<n>——id≠当前先切后设；2 参保留
                try:
                    _parts = cmd.split(":")
                    if len(_parts) >= 3:
                        _target_id = int(_parts[1])
                        _n_str = _parts[2]
                    else:
                        _target_id = self.current_camera_id
                        _n_str = _parts[1]
                    n = int(_n_str)
                    if _target_id != self.current_camera_id:
                        # 批次 AA（W4-3）：3 参显式切设备 → 登记目标单一真值
                        self._note_switch_target(_target_id)
                        self._switch_camera(_target_id)
                    print(f"[CTRL] SET_FPS: {n}")
                    if self.cap and self.cap.isOpened():
                        self.cap.set(cv.CAP_PROP_FPS, n)
                        af = self.cap.get(cv.CAP_PROP_FPS)
                        if abs(af - n) > 1.0:
                            print(f"  [CTRL] FPS set mismatch (got {af:.1f}), display-only fallback")
                        elif int(n) not in self._fps_options:
                            # 批次 AD-5b（§4.5）：播种帧率集跟随实际生效值（与 res 同口径）
                            self._fps_options.append(int(n))
                        self._send_init2()
                except Exception as e:
                    print(f"  [CTRL] SET_FPS failed: {e}")
            elif cmd == "GET_CAMERAS":
                # 修复批（拉取模式，2026-09-18）：init#1 为一次性 UDP 消息，服务端 t≈0.1s 枚举完
                # 即发、t≈5s 打开成功补发，游戏进程可能尚未绑定 9876（打包实弹实测 t≈17s 启动）
                # → 两次 init 全部丢失、Godot 侧 _camera_enum 缓存恒空。新增 9878 拉取命令：
                # 收到即调 _send_camera_list_init() 重发含 cameras+current_camera 的 init#1
                # （幂等无状态；未知命令行为保持现状——静默）。
                # 批次 AC（领域二，spec §4.2-4）：**空名单强制重扫**——外接摄像头热插拔后
                # 用户点下拉刷新（ArrowBtn/重开下拉 → GET_CAMERAS）必须重新探测物理硬件，
                # 根除旧版「自启动期跑过一次探针后 `_cameras` 恒空、新插入设备永不可见」。
                if not self._cameras:
                    self._rescan_cameras_on_demand()
                elif self._enum_probe_pending and not self._enum_probe_started:
                    # 批次 AA（W4-8）：启动期候选空（WMI 失效）→ 首次 GET_CAMERAS 触发
                    # 懒枚举线程（CAP 可用性探测延后 + 独立线程不阻塞主循环；一次性门）。
                    self._enum_probe_started = True
                    self._spawn_enum_probe_thread()
                else:
                    print("[CTRL] GET_CAMERAS: 重发摄像头枚举 init")
                    self._send_camera_list_init()
                    # 批次 U（U2，spec §4-U2-⑤）：当前设备已打开则补发 init#2——桥矩阵缓存不再恒空，
                    # 当前设备子列直出全局矩阵（id==current 直读分支；批次 AD-5c 起为**条件探测**：
                    # 播种矩阵不充分（≤1 档）时 Godot 亦发 PROBE_MATRIX，P2-6「自探自败」由下方
                    # `_probe_matrix_worker` pid==current live 复用路径消解——不另开句柄不抢流）
                    if self.cap is not None and self.cap.isOpened():
                        self._send_init2()
            elif cmd.startswith("START_CAMERA_BY_NAME:") \
                    or cmd.startswith("SET_PREFERRED_CAMERA:"):
                # 批次 AD（spec §4.2.2-3/4）：**查名直启**唯一入口。
                # 主协议 `START_CAMERA_BY_NAME:<设备名>`；旧 `SET_PREFERRED_CAMERA:<设备名>`
                # 为向后兼容同路（两者协议格式等价：首个冒号后整行剩余、允许空格）。
                # 口径（批次 AD 定档）：
                # - 在 `self._cameras` 中按设备名匹配（忽略大小写与首尾空格）；
                # - 命中 → 精准启动对应物理设备；
                # - 未命中或名称为空 → 降级启动 `self._cameras[0]`（首项物理设备）；
                # - 列表为空 → 保持未启动，回传 0 摄像头状态（零开镜）。
                # 已开同一设备 → 零 release/零 reopen（幂等，防指示灯闪断）。
                name = cmd.split(":", 1)[1].strip()
                self._preferred_camera_name = name
                self._handshake_received = True
                self._start_camera_by_name(name)
            # 批次 R（spec §3.4）：摄像头列表回传分支（端口=P+3）删除——游戏无摄像头选择 UI；
            # camera_selector.py 保留为 CLI 枚举工具，auto 模式由其枚举逻辑复用
        except socket.timeout:
            pass
        except Exception as e:
            # 独立审查修复批（2026-09-26，P3 吞异常）：不再 pass 静默——记一行日志
            #（含命令与异常摘要）后继续，服务主循环保持健康，排障有据可查。
            print(f"[CTRL] 命令执行异常（已忽略，服务继续）: cmd={cmd!r} err={e}")

    def _acquire_camera_handle(self, camera_id: int, width: int = 640, height: int = 480,
                               backend_shift: int = 0, remember: bool = False):
        """Z4-④（spec §4-4）：**摄像头句柄获取唯一入口**——全进程一切设备打开（首开/SWITCH/
        SET_RESOLUTION 重开/恢复/重连/探测矩阵/枚举试探/键盘切换）均经本方法，`_acquire_lock`
        互斥保证任意时刻至多一次开镜（多路抢句柄=切换闪烁根因收敛为单点串行）。

        remember=True：select_camera 语义（失败抛 RuntimeError；含选择器配置回写）——
        流设备路径（既有 mock 契约与行为零变化）；remember=False：_open_camera 直取
        （None 失败返回、可传宽高）——重连/探测等非流路径（不回写配置）。
        旧多点获取（start 回退扫开 ×2、reconnect range(3)、键盘无 id 交互扫描选择）
        全部退役，见各调用点留痕。
        """
        with self._acquire_lock:
            if remember:
                return self.camera_selector.select_camera(camera_id, backend_shift=backend_shift)
            return self.camera_selector._open_camera(camera_id, width, height,
                                                     backend_shift=backend_shift)

    def _acquire_probe_open(self, index: int):
        """Z4-④：枚举试探开镜——经句柄单入口（enumerate_cameras 的 open_fn 注入）；
        探测方（probe_camera_usable）负责 release。**无门原语**：仅供已受
        AA_ALLOW_REAL_CAMERA 门控的桩（_startup_probe_open/_lazy_probe_open）或显式
        设门路径调用，不得直接作为 open_fn 注入（回修3，W4-P2-3 红线单门纪律）。"""
        return self._acquire_camera_handle(int(index))

    def _lazy_probe_open(self, index: int):
        """批次 AA 回修3（W4-P2-3）：懒探测线程 open_fn 受门桩——与启动桩
        _startup_probe_open **同一把 AA_ALLOW_REAL_CAMERA 门**（默认返回 None 零开镜）。

        旧实现 _enum_probe_worker 直注 _acquire_probe_open（无门）→ WMI 全失效的退化
        机器上 GET_CAMERAS 触发懒探测线程会**无门真开 CAP 0..3**（荣耀 Magic 7 前后摄
        误开风险，摄像头红线两把门不一致）。设门（=1）才经句柄单入口真探，
        人工真机复验用，语义与启动桩完全同构。"""
        if os.environ.get("AA_ALLOW_REAL_CAMERA") == "1":
            return self._acquire_probe_open(index)
        return None

    def _note_switch_target(self, camera_id) -> None:
        """批次 AA（W4-3，spec §7.3）：SWITCH 目标 id 单一真值登记（代际递增）。

        登记点（穷举）：①收线程接收点（生产——新 SWITCH 在**接收时**即取代在飞旧
        SWITCH，不等 FIFO 执行）；②执行漏斗直喂分支（无收线程的 selftest/夹具）；
        ③3 参 SET_RESOLUTION/SET_FPS 的显式切设备；④键盘 C 切换。
        RELEASE/SHUTDOWN **不**调本方法（代际不因释放递增，防误中止，spec 风险 2）。
        """
        try:
            tid = int(camera_id)
        except (TypeError, ValueError):
            return
        self._switch_target_id = tid
        self._switch_generation += 1
        # 批次 AD-5b（§4.6）：新切换意图登记 → 在飞矩阵探测同点让位（不等 FIFO 执行；
        # 收线程接收点/执行漏斗/键盘切换三路均经本方法，让位口径单点收敛）。
        self._note_probe_yield()

    def _note_probe_yield(self) -> None:
        """批次 AD-5b（需求 §4.6）：主流命令**让位令**——纪元 +1，在飞矩阵探测
        （`_probe_matrix_worker`）每档 set/get 前比对，变化即尽快中止让位。

        调用点（穷举）：①收线程接收点 `RELEASE_CAMERA`/`SHUTDOWN`（即时生效族，
        不进 FIFO——探测须在接收瞬间让位）；②收线程 `SWITCH_CAMERA:` 接收点
        （与目标登记同点提前让位）；③`_note_switch_target`（切换目标登记：SWITCH/
        按名直启/3 参 SET_*/键盘切换）；④`_execute_control_command` 入口对一切主流
        命令（覆盖直喂夹具路径与 SET_RESOLUTION/SET_FPS 就地改当前设备形态）。
        非主流（GET_CAMERAS/PROBE_MATRIX 等只读命令）不 bump——探测不无谓中止。
        纪元可重复 bump（无害）；worker 以「探测起点纪元」为基准，陈旧令不误判。
        """
        self._probe_cmd_epoch += 1

    @staticmethod
    def _is_main_camera_cmd(cmd) -> bool:
        """批次 AD-5b（§4.6）：主流摄像头命令判定（探测让位分类单点）。

        主流 = 一切会切目标/开/放/改配摄像头句柄的命令；非主流 = 只读枚举与
        矩阵探测自身（GET_CAMERAS、PROBE_MATRIX——后两者绝不能让位自身/互相中止）。
        """
        if cmd in PROBE_MAIN_CMDS:
            return True
        return str(cmd).startswith(PROBE_MAIN_CMD_PREFIXES)

    def _mark_camera_open_success(self, quiet_reconnect: bool = False) -> None:
        """批次 AD-5（F-1，需求 §4.1）：**开镜成功段唯一基准复位原语**。

        三个开镜成功落点（`_switch_camera` 成功段 / `_attempt_reconnect` 成功段 /
        `SET_RESOLUTION` 重开·恢复成功段）统一调用，把无帧看门狗从「打开成功时刻」
        重新起算完整首帧等待窗——根治「基准初值=进程构造时刻 → 开镜后 6~9s 必然误判
        无帧 → 释放→重连自愈」的首开卡死与频闪链（F-1）。

        - `quiet_reconnect=False`（显式切换/首次开镜）：连续无帧开镜计数清零——新的显式
          意图获得完整快速判定预算；
        - `quiet_reconnect=True`（安静重连自身成功）：**保留**计数——正是「首帧缺失最多
          安静重连 1 次」的上界来源（`FIRST_FRAME_QUIET_RECONNECT_MAX`）。
        """
        self._last_camera_read_time = time.time()
        self._no_frame_count = 0
        self._no_frame_last_mark = 0.0   # 回修2 口径同步：窗口计数基准清 0.0
        self._first_frame_pending = True     # 首帧未到：武装快速判定窗
        self._first_frame_fast_tried = False  # 本开镜会话快速判定未用
        if not quiet_reconnect:
            self._frameless_open_streak = 0

    def _mark_frame_read(self) -> None:
        """批次 AD-5（F-1）：读帧成功唯一写点（`_camera_read_thread` 成功路径调用）。

        既有写点语义（批次 AA W4-5）保持：时间戳 + 无帧计数 + 窗口基准复位；AD-5 附加
        「首帧真正到达」→ 解除快速判定武装 + 连续无帧开镜计数清零（快速判定只管
        「开了却零帧」形态，运行期普通停帧仍走既有 3×3s 看门狗，不被 2.5s 误杀）。
        """
        self._last_camera_read_time = time.time()
        self._no_frame_count = 0
        self._no_frame_last_mark = 0.0   # 回修2：读帧成功 → 窗口计数基准同步复位
        self._first_frame_pending = False
        self._frameless_open_streak = 0

    def _rearm_first_frame_window_if_pending(self) -> None:
        """批次 AD-5（F-1）→ 批次 AD-5b（§4.5）：开镜配置段收尾的首帧窗补起算（兜底保留）。

        AD-5 原病灶：`_switch_camera` 成功段在基准复位之后同步跑「分辨率×5+帧率×5」
        set/get 探测（DSHOW 上可达秒级）→ 配置耗时吞掉首帧预算造成误判。AD-5b 已把
        该探测移出关键路径（播种替代，见 `_switch_camera` 成功段注释），本原语作为
        配置段收尾的**兜底**保留：任何耗时配置后若此刻仍一帧未出，把首帧窗从「配置
        完成」重新给满 `FIRST_FRAME_TIMEOUT_SEC`（矩阵探测 worker 收尾亦经同口径
        补起算——探测窗不计「无帧」）；已有帧则不动（基准已由 `_mark_frame_read`
        复位，重复武装反而会把运行期停帧误引进快速判定）。
        """
        if not self._first_frame_pending:
            return
        self._last_camera_read_time = time.time()
        self._first_frame_fast_tried = False

    @_inflight_open_guard   # 批次 AD-5（F-2）：在飞开镜目标登记/退出即清（见装饰器注释）
    def _switch_camera(self, camera_id: int) -> None:
        """切换摄像头。

        批次 V-B1（spec §6.3）修复落点：
        - ①粘滞标志双点清：命令开始即清 _camera_intentionally_released（成功点保留），
          该标志只用于抑制「无命令时的自动重连」，永不阻断显式 SWITCH——修
          「RELEASE 后切换失败→标志残留→重连被永久跳过→设备半死」形态；
        - ②release→open 释放时延 0.1→0.35s；打开失败重试×2（共 3 轮），每轮仍在
          `_acquire_lock` 内串行重试（批次 AD §4.2.3：每轮同为 CAP_DSHOW 单后端，
          `rotate_backend_chain` 后端轮换已退役——重试只兜「句柄释放后驱动尚未就绪」
          这一时序抖动，不再换后端重开，硬件指示灯不再频闪）；
        - ③全部轮次失败才判失败，必回传 camera_error（含失败设备 id 与原因摘要），
          主循环保持健康——失败后再次 SWITCH 可正常尝试。

        批次 AA（W4-3/W4-4，spec §7.3）新增两门（均在任何副作用之前）：
        - **同 id no-op**：目标==当前且句柄健在 → 零 release / 零 reopen（R4-e）；
        - **目标单一真值 + 代际取消**：更晚登记的 SWITCH 已改目标 → 本命令被取代，
          零副作用直接返回（旧目标零 open，R4-d）；在飞期新 SWITCH 到达（代际递增）
          → 重试循环每轮核对，过期立即中止——「已连上则 release，连接中则中止」。
        """
        camera_id = int(camera_id)
        # 批次 AD-5（F-2，需求 §4.2）：在飞开镜目标登记——`_start_camera_by_name` 同目标
        # 重复指令据此忽略（装饰器 finally 恒清；含所有早退分支）。
        self._open_in_flight_target = camera_id
        # W4-4：同 id no-op（零 release / 零 reopen）
        if camera_id == self.current_camera_id and self.cap is not None \
                and self.cap.isOpened():
            print(f"[SWITCH] 同 id no-op: [{camera_id}] 已打开，零 release/reopen")
            return
        # W4-3：目标单一真值——被更新的 SWITCH 取代 → 零副作用
        if self._switch_target_id is not None and camera_id != int(self._switch_target_id):
            print(f"[SWITCH] 命令 [{camera_id}] 已被新目标 [{self._switch_target_id}] 取代 "
                  f"→ 跳过（零 open/零 release）")
            return
        my_gen = self._switch_generation
        print(f"[SWITCH] 收到切换命令: camera_id={camera_id} (gen={my_gen})")
        self._release_latch = False   # 批次 Z（Z4-③）：新 SWITCH=新意图，清陈旧 RELEASE 闩
        with self._camera_lock:
            # 批次 V-B1（spec §6.3-1）：SWITCH 命令开始即清粘滞标志（双点清第一点）
            self._camera_intentionally_released = False
            if self.cap:
                self.cap.release()
                self.cap = None
        # 批次 Y（Y-A17）：切换释放摄像头 → camera_closed(reason="switch")（边沿触发）
        self._emit_camera_closed("switch")
        # 批次 V-B1（spec §6.3-2）：释放时延 0.35s
        time.sleep(SWITCH_RELEASE_SETTLE_SEC)
        if self._switch_generation != my_gen:
            # W4-3：释放窗内新 SWITCH 已达 → 立即中止（旧设备不复开）
            print(f"[SWITCH] 代际过期（gen {my_gen}→{self._switch_generation}）→ 中止")
            return
        new_cap = None
        last_error = None
        for round_idx in range(SWITCH_OPEN_ROUNDS):
            if self._switch_generation != my_gen:
                # W4-3：每轮核对代际——过期即中止（连接中则中止）
                print(f"[SWITCH] 第 {round_idx + 1} 轮前代际过期 → 中止切换（零后续 open）")
                return
            try:
                # 批次 Z（Z4-④）：打开经句柄单入口（select_camera 语义/后端左旋参数原样保留）
                cap_try = self._acquire_camera_handle(
                    camera_id, backend_shift=round_idx, remember=True)
            except Exception as e:
                last_error = e
                print(f"  [SWITCH] 第 {round_idx + 1}/{SWITCH_OPEN_ROUNDS} 轮打开失败: {e}")
                cap_try = None
            if cap_try is not None and cap_try.isOpened():
                if self._switch_generation != my_gen:
                    # W4-3：刚连上但已被取代 → 「已连上则 release」（句柄零泄漏）
                    try:
                        cap_try.release()
                    except Exception:
                        pass
                    print(f"[SWITCH] 打开完成但代际已过期 → 就地 release（新目标不复用旧开）")
                    return
                new_cap = cap_try
                break
        if new_cap is None:
            # 批次 V-B1（spec §6.3-3）：全部轮次失败才判失败，必回传 camera_error；
            # 粘滞标志已在入口清除——失败后再次 SWITCH 可正常尝试（显式 SWITCH 不受
            # 批次V审查①-P2 冷却限制，冷却只退避自动重连）
            with self._camera_lock:
                self.cap = None
            reason = (f"切换摄像头失败：共尝试 {SWITCH_OPEN_ROUNDS} 轮（CAP_DSHOW 单后端）"
                      f"仍无法打开设备 {camera_id}"
                      + (f"（末次错误: {last_error}）" if last_error else ""))
            self._send_camera_error(camera_id, reason)
            # 批次V审查①-P2：全失败→对该失败设备 id 登记自动重连冷却（防重连风暴）。
            # 批次 AA（W4-2/R4-4 错位修复）：current_camera_id 只在成功路径更新（:成功段），
            # 失败后自动重连的实际目标=**旧 current id** → 同步按实际重连目标登记冷却，
            # 根治「冷却只登记新 id、旧设备被无速率限制反复重开」（症状①②根因之一）。
            self._switch_fail_cooldown[int(camera_id)] = time.time() + SWITCH_FAIL_COOLDOWN_SEC
            if self.current_camera_id is not None and int(self.current_camera_id) != int(camera_id):
                self._switch_fail_cooldown[int(self.current_camera_id)] = \
                    time.time() + SWITCH_FAIL_COOLDOWN_SEC
            print(f"[FAIL] 切换摄像头失败: {camera_id}")
            return
        with self._camera_lock:
            self.cap = new_cap
        if self._release_latch and self.cap is not None:
            # 批次 Z（Z4-③）：SWITCH 在飞期间 RELEASE 已到（收线程置闩）→ 打开完成即就地
            # 释放：不跑分辨率/帧率探测、不发 camera_opened（切换起点已发 closed，
            # 流真值保持 false；晚到 RELEASE 优先，旧设备零复开）。
            with self._camera_lock:
                try:
                    self.cap.release()
                except Exception:
                    pass
                self.cap = None
                self._latest_frame = None
            print("[SWITCH] 打开完成但 RELEASE 已达 → 就地释放（晚到释放优先）")
            return
        if self.cap:
            with self._camera_lock:
                # 批次 AD-5b（§4.5，任务书「单次校正 ≤2 次 set」口径）：目标配置
                # **先回读、不符才 set**——`_open_camera` 刚按同一目标 set 过，同值
                # 重复 set 在 DSHOW 上仍触发 ≈0.53s 格式重协商（实测
                # ad5b_open_latency_diag.txt：SELECT_out→MARK 段 0.549s 纯耗时）。
                # 回读已达标 → 零 set；不符 → 宽/高各一次 set 校正 + 读回（≤2 次 set）。
                aw0 = int(self.cap.get(cv.CAP_PROP_FRAME_WIDTH))
                ah0 = int(self.cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                if aw0 != self.width or ah0 != self.height:
                    self.cap.set(cv.CAP_PROP_FRAME_WIDTH, self.width)
                    self.cap.set(cv.CAP_PROP_FRAME_HEIGHT, self.height)
                actual_w = int(self.cap.get(cv.CAP_PROP_FRAME_WIDTH))
                actual_h = int(self.cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                if actual_w != self.width or actual_h != self.height:
                    print(f"  WARNING: actual resolution: {actual_w}x{actual_h} (target {self.width}x{self.height})")
                else:
                    print(f"  resolution: {actual_w}x{actual_h}")
            self.current_camera_id = camera_id
            # 批次 AD-5（F-1，需求 §4.1）：**开镜成功立即复位**无帧看门狗基准与窗口计数，
            # 并武装首帧窗——首帧等待从「打开成功时刻」起算（旧实现此处不复位，基准仍停在
            # 进程构造时刻 → 主循环第一迭代即累计 3s 窗 → 6~9s 后必然误判无帧→释放→重连）。
            self._mark_camera_open_success()
            # 批次 U（U4）：切换成功恢复自动重连常态（清 RELEASE 标志）
            # 批次 V-B1（spec §6.3-1）：成功开启后再清粘滞标志（双点清第二点）
            self._camera_intentionally_released = False
            # 批次 AA（W4-2）：显式 SWITCH 成功 → 自动重连预算/FAILED 复位（人工重试可达）
            self._reconnect_attempts = 0
            self._reconnect_backoff = RECONNECT_BACKOFF_BASE_SEC
            self._reconnect_next_at = 0.0
            self._reconnect_failed = False
            self._reconnect_error_reported = False
            # 批次V审查①-P2：成功开启→清除该设备 id 的失败冷却
            self._switch_fail_cooldown.pop(int(camera_id), None)
            # 修复批次（枚举空）：切换成功同样回填实际设备并重发含 cameras 的 init
            # （id 语义=CAP 索引，SWITCH_CAMERA:id 直用该索引打开，多设备不再选错）
            self._backfill_camera_entry(int(camera_id))
            self._send_camera_list_init()
            # 批次 Y（Y-A17）：切换后真实打开成功 → camera_opened 事件（边沿触发）
            self._emit_camera_opened()
            if not hasattr(self, 'frame_socket') or self.frame_socket is None:
                self.frame_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                self.frame_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
            # 独立审查修复批（2026-09-26，P0 建线唯一）：首开失败后经 SWITCH 打开
            # 成功也必须建采集双线程（幂等 flag，已建则 no-op）——否则
            # _latest_frame 恒 None → 看门狗释放/重开永动循环。
            self._ensure_capture_threads()
            print(f"[OK] 已切换到摄像头: [{camera_id}]")

            # Z-B 回修 P3-c：探测段入口重查——上方 emit/帧间收线程 RELEASE 可能已把
            # self.cap 置 None，直接 self.cap.set → AttributeError 被命令层 except 静默吞，
            # 后续 fps 探测/组包照跑致状态漂移。早退（晚到释放优先，与闩语义一致）。
            if self.cap is None:
                print("[SWITCH] 打开完成后 cap 已被并发释放 → 跳过分辨率/帧率探测（P3-c 早退）")
                return

            # 批次 AD-5b（需求 §4.5）：**启动期同步矩阵探测移出关键路径**——
            # 旧实现此处同步跑「分辨率×5 + 帧率×5」的 set/get 探测风暴（引用模块级
            # 探测列表逐档扫描），实测 5.99s 且每档分辨率 set 触发 DSHOW 格式重协商
            # ≈1.1s 阻塞读线程 → camera_opened→SWITCH_END≈6s、首帧迟至 ~9.25s，
            # 用户见「画面一帧卡死十来秒」（adcamera_firstopen2_before.txt 在案）。
            # 改为**播种最小矩阵**（cap.set 总数保持 2：上方宽/高目标各一；fps 只读零 set）：
            # - `_supported_resolutions` = 当前实际生效分辨率（上方刚 set 完读回的
            #   actual_w/actual_h——种子即「生效值」；SET_RESOLUTION 应用后亦同步跟随，
            #   见该命令成功段）；
            # - `_fps_options` = 当前实际帧率（cap.get 可读且 ≤FPS_SEED_MAX 才播，
            #   否则留空——Godot 侧空 fps 子列不弹出为既有契约，不伪造数值）。
            # 完整 RES/FPS 矩阵**按需惰性探测**：Godot 下拉对矩阵缓存不充分的设备
            # 自动发 PROBE_MATRIX → `_probe_matrix_worker`（「检测中…」既有 UI 契约不变；
            # 批次 AD-5c：current 行同为条件探测——播种不充分（≤1 档）即发，camera_menu.gd
            # 经 live 复用路径探测本流设备，画面不灭）。
            self._supported_resolutions = [(int(actual_w), int(actual_h))]
            _seed_fps = 0.0
            try:
                _seed_fps = float(self.cap.get(cv.CAP_PROP_FPS))
            except Exception:
                _seed_fps = 0.0
            if 0.0 < _seed_fps <= FPS_SEED_MAX:
                self._fps_options = [int(round(_seed_fps))]
            else:
                self._fps_options = []
            print(f"  Seeded matrix (AD-5b 按需探测): resolutions={self._supported_resolutions} "
                  f"fps_options={self._fps_options}")
            self._send_init2()

            # 发送到 Godot 重建下拉框（既有协议保形，消费端无变化）
            res_msg = {"type": "resolutions_update", "resolutions": self._supported_resolutions}
            self.udp_sender.send(res_msg)
            # 批次 AD-5（F-1）：配置段收尾补起算（仍无帧才重新武装，见原语注释）
            self._rearm_first_frame_window_if_pending()

    def _send_camera_error(self, camera_id, reason: str) -> None:
        """批次 V-B1（spec §6.3-3）：摄像头操作失败必经 9876 回传 camera_error。

        协议只增不改：在既有 {"type":"camera_error","id":int} 基础上新增 reason
        摘要键（Godot 桥 .get 取键不受影响）；id 解析失败防御回 0，任何失败路径
        都必须回传且服务主循环保持健康。
        """
        try:
            cid = int(camera_id)
        except (TypeError, ValueError):
            cid = 0
        payload = {"type": "camera_error", "id": cid,
                   "reason": str(reason)[:CAMERA_ERROR_REASON_MAX_LEN]}
        self.udp_sender.send(payload)
        print(f"[CAMERA_ERROR] id={cid} reason={payload['reason']}")

    def _send_init2(self) -> None:
        """批次 T（spec §6.1）：init#2 回传（resolutions + fps_options；摄像头打开/切换/设分辨率后）。"""
        self.udp_sender.send({
            "type": "init",
            "resolutions": self._supported_resolutions,
            "fps_options": getattr(self, "_fps_options", []),
        })

    # ------------------------------------------------------------------
    # 修复批次（枚举空）：摄像头条目回填与含 cameras 的 init 重发
    # ------------------------------------------------------------------

    def _camera_display_name(self, camera_id: int) -> str:
        """显示名：优先 WMI 多链回填缓存，否则「摄像头 N」（防 None/防非字符串）。"""
        name = (getattr(self, "_camera_names", None) or {}).get(int(camera_id))
        if not (isinstance(name, str) and name.strip()):
            name = f"摄像头 {camera_id}"
        return name

    def _backfill_camera_entry(self, camera_id: int) -> None:
        """打开成功后把实际设备回填进摄像头列表（幂等；id=CAP 索引语义）。"""
        backfill_camera_entry(self._cameras, camera_id,
                              name=self._camera_display_name(camera_id))

    def _send_camera_list_init(self) -> None:
        """（重新）发送含 cameras 的 init 消息（设备开启/切换/重扫成功后调用）。

        契约：cameras=[{"id": int(CAP索引), "name": str}]、current_camera=CAP 索引 int。
        与 init#2（resolutions/fps_options）分开发送，type:init 带内分流逻辑不变。
        批次 AD（spec §4.2.2-1）：未启动设备时 `current_camera` 发 **-1** 哨兵
        （旧实现 None→0 会把「未启动」误报为设备 0）。
        """
        entries = self._cameras or []
        cur = int(self.current_camera_id) if self.current_camera_id is not None else -1
        self.udp_sender.send({
            "type": "init",
            "cameras": [{"id": int(c["id"]), "name": str(c["name"])} for c in entries],
            "current_camera": cur,
        })

    # ------------------------------------------------------------------
    # 批次 AD（spec §4.2.2）：查名直启 + 摄像头真值事件
    # ------------------------------------------------------------------

    def _start_camera_by_name(self, name: str) -> None:
        """批次 AD（spec §4.2.2-3/4）：设备名 → 查名直启唯一漏斗（命令层与 selftest 共用）。

        口径：
        - 在 `self._cameras` 中按设备名匹配（忽略大小写与首尾空格，`pick_camera_by_name`）；
        - 命中 → 精准启动对应物理设备；
        - 未命中或名称为空 → 降级启动 `self._cameras[0]`（首项物理设备）；
        - 列表为空 → **保持未启动**，回传 0 摄像头状态（零开镜）；
        - 已开同一设备 → 零 release/零 reopen（幂等，防指示灯闪断）。

        命令即显式开启意图：**不再按 `_camera_intentionally_released` 拦截**——该标志只抑制
        「无命令时的自动重连」（`_attempt_reconnect`），永不阻断显式开启（与 `_switch_camera`
        的「粘滞标志不阻断显式 SWITCH」同一条项目铁律；旧 AC 的 release 锁存由**桥侧**
        `_camera_release_intent` 承担：自动补发路径被桥侧门住，用户显式再开时桥侧先清锁存
        再下发本指令）。`_switch_camera` 成功段沿用双点清复位该标志。
        """
        matched_id = match_camera_by_name(self._cameras, name)
        target_id = pick_camera_by_name(self._cameras, name)
        if target_id is None:
            print("[CTRL] 启动指令收到但物理设备列表为空 → 保持未启动，"
                  "回传 0 摄像头状态（零开镜）")
            self._send_camera_list_init()
            return
        if self.current_camera_id == int(target_id) and self.cap is not None \
                and self.cap.isOpened():
            print(f"[CTRL] 启动指令 '{name}' → 目标 [{target_id}] 已开启，"
                  f"零 release/reopen（幂等）")
            return
        # 批次 AD-5（F-2，需求 §4.2）：**在飞幂等**——同目标开镜进行中收到重复启动指令
        # → 直接忽略：不 release、不重启、不进入 `_switch_camera`、不递增 `_switch_generation`
        #（代际递增会让在飞开镜逐轮核对判「已过期」→ 刚连上就就地 release，指示灯闪断）。
        # 异目标（用户显式切换到别的设备）不走本门，显式切换可达性保持。
        if self._open_in_flight_target is not None \
                and int(self._open_in_flight_target) == int(target_id):
            print(f"[CTRL] 启动指令 '{name}' → 目标 [{target_id}] 开镜进行中（在飞），"
                  f"同目标重复指令忽略（零 release/零 reopen/零代际递增）")
            return
        if matched_id is not None:
            src = "命中"
        elif not name:
            src = "空名降级首项"
        else:
            src = "未命中降级首项"
        print(f"[CTRL] 启动指令 '{name}' → {src}，开启 CAP [{target_id}]")
        self._note_switch_target(int(target_id))
        self._switch_camera(int(target_id))

    # ------------------------------------------------------------------
    # 批次 AD（spec §4.2.2）：查名直启 + 摄像头真值事件
    # ------------------------------------------------------------------

    def _camera_entry_name(self, camera_id: int) -> str:
        """从枚举条目表取显示名（Y-A17 camera_opened 载荷 name 来源），
        缺省回退 WMI 缓存/「摄像头 N」（_camera_display_name 同款兜底）。"""
        cid = int(camera_id)
        for cam in getattr(self, "_cameras", None) or []:
            try:
                if int(cam.get("id", -1)) == cid:
                    name = str(cam.get("name") or "")
                    if name.strip():
                        return name
            except (TypeError, ValueError):
                continue
        return self._camera_display_name(cid)

    def _emit_camera_opened(self) -> None:
        """Y-A17（spec §3.2）：摄像头真实打开成功 → 9876 带内 camera_opened 事件。

        边沿触发：仅 _camera_stream_open False→True 时发送一次；重连/同设备重开
        等真值未翻转的重复 open 静默（备案：SET_RESOLUTION 重开链不发事件——
        开启真值持续为 true，消费方只关心边沿）。载荷含设备 id/名/分辨率/帧率。
        """
        if self._camera_stream_open:
            return
        self._camera_stream_open = True
        cid = int(self.current_camera_id) if self.current_camera_id is not None else 0
        w = h = 0
        fps = CAMERA_OPEN_DEFAULT_FPS
        try:
            if self.cap is not None:
                w = int(self.cap.get(cv.CAP_PROP_FRAME_WIDTH))
                h = int(self.cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                fps = float(self.cap.get(cv.CAP_PROP_FPS))
        except Exception:
            w = h = 0
            fps = CAMERA_OPEN_DEFAULT_FPS
        name = self._camera_entry_name(cid)
        self.udp_sender.send({
            "type": "camera_opened", "id": cid, "name": name,
            "width": w, "height": h, "fps": fps,
        })
        print(f"[事件] camera_opened id={cid} name={name} {w}x{h}@{fps:.0f}fps")

    def _emit_camera_closed(self, reason: str) -> None:
        """Y-A17（spec §3.2）：摄像头实际释放 → 9876 带内 camera_closed 事件。

        边沿触发（True→False 才发）；reason ∈ release|error|switch|device_lost。
        """
        if not self._camera_stream_open:
            return
        self._camera_stream_open = False
        cid = int(self.current_camera_id) if self.current_camera_id is not None else 0
        self.udp_sender.send({
            "type": "camera_closed", "id": cid, "reason": str(reason),
        })
        print(f"[事件] camera_closed id={cid} reason={reason}")

    # ------------------------------------------------------------------
    # 摄像头后台采集线程
    # ------------------------------------------------------------------

    def _ensure_capture_threads(self) -> bool:
        """幂等启动采集双线程（独立审查修复批 2026-09-26，P0 建线唯一）。

        病灶：`_read_thread`/`_stream_thread` 原先只在 start() 首开成功分支内联
        创建；首开失败/被 RELEASE 跳过后，`_switch_camera` 成功（只建 frame_socket）
        与 `_attempt_reconnect` 成功（只换 cap）也不建线 → `_latest_frame` 恒 None
        → `_process_frame` 无帧看门狗 3×3s 释放/重开永动循环。

        三成功段统一调用本方法：start 成功段 / _switch_camera 成功段 /
        _attempt_reconnect 成功段。约束（任务书）：不改线程数（恒 ≤2）与既有
        线程职责（读=cap.read 唯一读点、流=JPEG 发送）。

        - flag 守卫 `_capture_threads_started`：已建则 no-op（返回 False）；
        - `running` 门：未进运行态不建线（start 成功段先置 running=True 再调用；
          selftest 直调 switch/reconnect 且 running=False 时不落真实线程）；
        - frame_socket 缺失则一并补建（首开失败后重连成功的流线程发帧依赖；
          start/SWITCH 已建则幂等跳过）。

        Returns:
            True=本次新建了线程；False=no-op（已建或未进运行态）。
        """
        if self._capture_threads_started:
            return False
        if not self.running:
            return False
        self._capture_threads_started = True
        if self.frame_socket is None:
            self.frame_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.frame_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
        if self._stream_thread is None or not self._stream_thread.is_alive():
            self._stream_thread = threading.Thread(target=self._camera_stream_thread,
                                                   daemon=True)
            self._stream_thread.start()
            print("[线程] 摄像头采集线程已启动")
        if self._read_thread is None or not self._read_thread.is_alive():
            self._read_thread = threading.Thread(target=self._camera_read_thread,
                                                 daemon=True)
            self._read_thread.start()
            print("[Thread] Camera read thread started")
        return True

    def _camera_stream_thread(self):
        """后台线程：取主线程最新帧，JPEG 编码后发送到 Godot（frame_send_port=P+1）。

        不再直接读取摄像头（由主线程 _read_camera 独占读取），
        改读 self._latest_frame，彻底消除锁竞争。
        """
        print(f"[线程] 摄像头流线程已启动，开始发送JPEG到{self.frame_send_port}")
        send_count = 0
        while self.running:
            frame = getattr(self, '_latest_frame', None)
            if frame is None:
                time.sleep(0.02)
                continue

            # JPEG 编码和发送到 Godot（frame_send_port=P+1）
            try:
                h, w = frame.shape[:2]
                # 发送分辨率跟随摄像头，但限制最大 480p（避免 UDP 包过大）
                target_h = min(h, 480)
                scale = target_h / h
                new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
                small = cv.resize(frame, (new_w, new_h))
                ok, jpg = cv.imencode('.jpg', small, [cv.IMWRITE_JPEG_QUALITY, 50])
                if ok and self.frame_socket:
                    jpg_bytes = jpg.tobytes()
                    hdr = len(jpg_bytes).to_bytes(4, 'little')
                    self.frame_socket.sendto(hdr + jpg_bytes,
                                             (self.frame_send_ip, self.frame_send_port))
                    send_count += 1
                    if send_count % 100 == 0:
                        print(f"[线程] 已发送 {send_count} 帧摄像头画面到 {self.frame_send_port}")
            except Exception as e:
                print(f"[线程] JPEG 发送失败: {e}")

            # 帧率节流：~50fps，更流畅的摄像头画面
            time.sleep(0.02)

    # ------------------------------------------------------------------
    # 摄像头独立读取线程
    # ------------------------------------------------------------------

    def _camera_read_thread(self):
        """独立摄像头读取线程：全速调用 cap.read()，结果赋值到 self._latest_frame。

        设计要点：
        - 本线程是 cap.read() 的唯一调用点（遵守本模块线程模型）
        - 每循环开头通过 self.cap 的原子引用读取获取最新摄像头对象
        - 在读取线程内完成镜像翻转，主线程和流线程不再处理翻转
        - 独立审查修复批（2026-09-26，P1 cap 读写竞态）：**每次 read 前取
          _camera_lock**——与锁内 release（_release_camera_only / _cleanup_camera /
          _switch_camera 起手释放 / 看门狗处置等）互斥，根治「锁外 cap.read() vs
          锁内 cap.release()」竞态（read 毫秒级，阻塞 release 可接受）；**持锁期
          只做 cap 引用与 read，不取任何其他锁**（flip/时间戳/帧赋值全在锁外），
          无死锁面。
        - 读取失败或摄像头未就绪时，将 self._latest_frame 设为 None，
          通知主线程当前无可用帧、触发心跳/重连逻辑
        """
        print("[Thread] Camera read thread started")
        while self.running:
            frame = None
            with self._camera_lock:
                cap = self.cap   # 锁内取引用 + 锁内 read（与锁内 release 互斥）
                if cap is not None and cap.isOpened():
                    ret, frame = cap.read()
                    if not ret:
                        frame = None
            if frame is None:
                self._latest_frame = None
                time.sleep(0.01)
                continue

            # 批次 AA（W4-5）：读帧时间戳与无帧计数的**唯一写点**移到读线程成功路径——
            #（旧码写在 _process_frame 处理陈旧帧时也刷新 → 看门狗永远检测不到挂死）。
            # 批次 AD-5（F-1）：写点收敛为 `_mark_frame_read` 原语——除既有三项复位外，
            # 追加「首帧真正到达 → 解除快速判定武装 + 连续无帧开镜计数清零」。
            self._mark_frame_read()

            # 镜像翻转（原在 _process_frame 中处理，现移到读取线程；锁外执行）
            if self.flip_image:
                frame = cv.flip(frame, 1)

            # 赋值到最新帧引用（流线程和主线程通过此引用读取）
            self._latest_frame = frame

    # ------------------------------------------------------------------
    # 摄像头管理
    # ------------------------------------------------------------------

    def _read_camera(self):
        """检查摄像头状态并在必要时触发重连（不再直接读取 cap，由独立读取线程负责）。

        Returns:
            True 摄像头可用，False 摄像头未就绪
        """
        if self.cap is None or not self.cap.isOpened():
            # 批次 U（U4）：RELEASE 后跳过重连（双审 P0-2；False=未就绪，主循环走心跳分支）
            if not self._camera_intentionally_released:
                self._attempt_reconnect()
            return False

        # 摄像头已就绪，最新帧由 _camera_read_thread 填充到 self._latest_frame
        return True

    def _watchdog_recover(self):
        """批次 AA（W4-5，spec §7.3）：无帧看门狗触发处置——释放挂死句柄 + 清陈旧帧 +
        按预算发起重连（根治「画面永久冻结且零重连」）。

        触发序（_process_frame 内，连续 NO_FRAME_TRIP_COUNT 次读帧超阈后调用一次）：
        ① camera_closed(device_lost) 边沿（_cleanup_camera 内建，cap 幂等释放）；
        ② _latest_frame 清空（陈旧帧不再喂主循环/流线程）；
        ③ 计数与时间戳复位（防同窗连环触发；下轮超时重新计数）；
        ④ _attempt_reconnect（速率限制/预算/FAILED 全部内建，风暴有界）。
        """
        print(f"[看门狗] 读帧超时（>{CAMERA_TIMEOUT_SECONDS}s 连续 {NO_FRAME_TRIP_COUNT} 次）"
              f"→ 释放挂死句柄并按预算重连")
        self._cleanup_camera("device_lost")
        with self._camera_lock:
            self._latest_frame = None
        self._no_frame_count = 0
        self._no_frame_last_mark = 0.0   # 回修2：恢复处置后窗口计数基准同步复位
        self._last_camera_read_time = time.time()
        if not self._camera_intentionally_released:
            self._attempt_reconnect()

    def _attempt_reconnect(self):
        """尝试重连摄像头。

        批次 AA（W4-2，spec §7.3/§7.4 验收 4，根治症状①②重连风暴）：
        - **速率限制**：指数退避窗（base 1s → ×2 → 上限 5s，单调不减）内零尝试；
        - **重试预算**：RECONNECT_BUDGET=10 次调用上限 → 转 FAILED 并**上报
          camera_error 恰一条**（不静默）；FAILED 后零尝试（显式 SWITCH 成功即复位）；
        - **冷却按实际重连目标 id 登记**（修 :1833 错位——旧码冷却登记失败 SWITCH 的
          新 id，而重连实际目标是 current id，冷却永不命中）；
        - 批次V审查①-P2 既有语义保留：SWITCH 全失败冷却期内跳过、显式 SWITCH 不受限。
        """
        if self._camera_intentionally_released:
            return
        # 批次 AC（领域二，spec §4.2-2）：**待命态零重连**——未确认/无自动可用物理设备时
        # current_camera_id 为 None，无重连目标可指（旧路径会以 None 为目标开镜，
        # 既无意义又可能命中 CAP 0=荣耀手机）。用户手动选择后 current_camera_id 即非 None，
        # 自动重连常态自然恢复。
        if self.current_camera_id is None:
            return
        if self._reconnect_failed:
            return   # 预算耗尽 FAILED：零尝试（等显式 SWITCH/重开复位）
        now = time.time()
        if now < self._reconnect_next_at:
            return   # 速率限制：指数退避窗内不重试
        _cd_until = self._switch_fail_cooldown.get(int(self.current_camera_id)) \
            if self.current_camera_id is not None else None
        if _cd_until is not None and now < _cd_until:
            print(f"[摄像头] 设备 {self.current_camera_id} SWITCH 失败冷却中，"
                  f"跳过自动重连（剩余 {_cd_until - now:.1f}s）")
            return
        if self._reconnect_attempts >= RECONNECT_BUDGET:
            self._reconnect_failed = True
            if not self._reconnect_error_reported:
                self._reconnect_error_reported = True
                _fail_id = int(self.current_camera_id) \
                    if self.current_camera_id is not None else 0
                self._send_camera_error(
                    _fail_id,
                    f"自动重连已达预算上限（{RECONNECT_BUDGET} 次），暂停自动重连，"
                    f"请从设置下拉选择设备")
            return
        target = self.current_camera_id
        self._reconnect_attempts += 1
        print(f"[摄像头] 正在重连...（第 {self._reconnect_attempts}/{RECONNECT_BUDGET} 次，"
              f"目标 [{target}]）")
        # 批次 Y（Y-A17）：设备失联释放 → camera_closed(reason="device_lost")
        self._cleanup_camera("device_lost")

        for attempt in range(1, RECONNECT_MAX_RETRIES + 1):
            print(f"  重连尝试 {attempt}/{RECONNECT_MAX_RETRIES}...")
            # 批次 Z（Z4-④）：同设备重连经句柄单入口（宽高/后端语义与旧 _open_camera 直调一致）
            cap = self._acquire_camera_handle(
                target, width=self.width, height=self.height)
            if cap is not None:
                with self._camera_lock:
                    self.cap = cap
                print(f"[OK] 重连成功!")
                # 批次 Y（Y-A17）：重连真实打开成功 → camera_opened（边沿触发）
                self._emit_camera_opened()
                # 独立审查修复批（2026-09-26，P0 建线唯一）：首开失败后经重连打开
                # 成功也必须建采集双线程（幂等 flag，已建则 no-op）。
                self._ensure_capture_threads()
                # 批次 AD-5（F-1）：重连成功统一经原语复位基准/窗口计数（回修2 口径保持）
                # + 武装首帧窗；`quiet_reconnect=True` **保留**连续无帧开镜计数——
                # 「首帧缺失最多安静重连 1 次」上界即由此达成。
                self._mark_camera_open_success(quiet_reconnect=True)
                # W4-2：成功即复位预算/退避/FAILED（会话内故障恢复可再攒预算）
                self._reconnect_attempts = 0
                self._reconnect_backoff = RECONNECT_BACKOFF_BASE_SEC
                self._reconnect_next_at = 0.0
                self._reconnect_failed = False
                self._reconnect_error_reported = False
                return
            time.sleep(1.0)

        # 批次 Z（Z4-④，spec §4-4）：重连失败后旧「range(3) 回退扫开其他摄像头」退役——
        # 自动改开别的设备=「切换后旧设备仍被请求/闪烁」根因之一；失败即等待（Godot 下拉
        # 手动选择为唯一异设备切换通路，经 _switch_camera 单入口串行执行）。
        # 批次 AA（W4-2）：失败 → 指数退避 + **按实际重连目标 id 登记冷却**。
        delay = self._reconnect_backoff
        self._reconnect_backoff = min(self._reconnect_backoff * 2.0,
                                      RECONNECT_BACKOFF_MAX_SEC)
        self._reconnect_next_at = time.time() + delay
        if target is not None:
            self._switch_fail_cooldown[int(target)] = time.time() + delay
        print(f"[FAIL] 同设备重连失败（回退扫开已退役；第 "
              f"{self._reconnect_attempts}/{RECONNECT_BUDGET} 次，退避 {delay:.1f}s，"
              f"冷却按目标 [{target}] 登记），等待手动通过 Godot 下拉框选择")

    def _release_camera_only(self):
        """批次 U（U4，spec §6.2）：仅释放摄像头设备，不动 running/三端口循环。

        持 _camera_lock 释放 cap 并清 _latest_frame；同步置 _camera_intentionally_released=True
        （_process_frame 重连触发处与 _read_camera 见标志跳过 _attempt_reconnect——双审 P0-2；
        _switch_camera 成功路径清标志恢复自动重连常态）。
        """
        with self._camera_lock:
            if self.cap is not None:
                try:
                    self.cap.release()
                except Exception:
                    pass
                self.cap = None
            self._latest_frame = None
        self._camera_intentionally_released = True
        # 批次 Y（Y-A17）：RELEASE 实际释放 → camera_closed(reason="release")（边沿触发）
        self._emit_camera_closed("release")
        print("[OK] 摄像头已释放（RELEASE_CAMERA），服务循环常驻")

    # ------------------------------------------------------------------
    # 批次 AA（W4-8，spec §7.3/§22 裁决 5）：CAP 可用性懒探测（独立线程）
    # ------------------------------------------------------------------

    def _spawn_enum_probe_thread(self) -> bool:
        """W4-8：启动期候选为空（WMI 全链失效）时的懒枚举——GET_CAMERAS（下拉打开/
        桥 READY 拉取）触发，独立线程跑完整 CAP 可用性探测，不阻塞主循环/首开。"""
        t = self._enum_probe_thread
        if t is not None and t.is_alive():
            return False
        self._enum_probe_thread = threading.Thread(target=self._enum_probe_worker,
                                                   daemon=True, name="enum-probe")
        self._enum_probe_thread.start()
        print("[枚举] 懒探测线程已启动（W4-8：CAP 可用性探测延后到下拉打开，零启动期开镜）")
        return True

    def _rescan_cameras_on_demand(self) -> bool:
        """批次 AC（领域二，spec §4.2-4）：GET_CAMERAS 空名单**按需重扫**（热插拔识别）。

        病灶：旧版 `_cameras` 为空时若 `_enum_probe_started` 已置真（启动期跑过一次探针），
        GET_CAMERAS 走 else 分支只重发空名单——用户外接摄像头后点下拉刷新永远看不到新设备
        （`_enum_probe_started` 一次性门从未复位）。

        处置（与 spec §4.2-4 逐条对应）：
        - 重新调用 `_enumerate_cameras_step()` 刷新 WMI 名单（零开镜：走 `_startup_probe_open`
          受门桩，默认恒不真开镜）；
        - 若重扫得到设备 → 名单已刷新，发最新 init#1（含 cameras，Godot 侧 zero 边沿自动开）；
        - 若仍为空 → **复位 `_enum_probe_started = False`** 并 `_spawn_enum_probe_thread()`
          重起懒探测线程（扫描完成后由其自身发最新 init#1）；
        - 重扫期间不动当前流设备、零 SWITCH（待命/流开两态皆安全）。

        Returns:
            bool: True=重扫后已有名单（已发 init#1）；False=仍空（已重起懒探测线程）。
        """
        print("[CTRL] GET_CAMERAS: 名单为空 → 重扫物理硬件（热插拔识别）")
        try:
            _cameras, _auto = self._enumerate_cameras_step()
            # 防御性回写：_enumerate_cameras_step 生产路径已自赋值 self._cameras，
            # 此处再以返回值兜底（异常/替身路径下名单不丢），零语义增量。
            if _cameras:
                self._cameras = _cameras
        except Exception as e:
            print(f"[枚举] 按需重扫异常（已忽略）: {e}")
        if self._cameras:
            self._send_camera_list_init()
            if self.cap is not None and self.cap.isOpened():
                self._send_init2()
            return True
        # 仍空：复位一次性门 + 重起懒探测线程（旧「跑过一次永不重扫」根除）。
        # 一次性门保持复位态（False）——下次用户再点下拉刷新仍会走本重扫路径，
        # 并发风暴由 _spawn_enum_probe_thread 自身「线程在忙即拒」护栏兜住。
        self._enum_probe_pending = True
        self._enum_probe_started = False
        self._spawn_enum_probe_thread()
        return False

    def _enum_probe_worker(self) -> None:
        """W4-8 懒枚举 worker：CAP 试探（open_fn=受门桩 _lazy_probe_open，回修3——
        与启动桩同一把 AA_ALLOW_REAL_CAMERA 门，默认零开镜）→ WMI 名回填建表 →
        替换候选并重发 init#1。异常兜底不抛（finally 清线程位）。"""
        try:
            results = enumerate_cameras(max_index=3, open_fn=self._lazy_probe_open)
            entries = build_camera_entries(results, getattr(self, "_camera_names", None) or {})
            if entries:
                self._cameras = entries
            self._enum_probe_pending = False
            print(f"[枚举] 懒探测完成: {[(c['id'], c['name']) for c in self._cameras]}")
            self._send_camera_list_init()
        except Exception as e:
            print(f"[枚举] 懒探测异常: {e}")
        finally:
            self._enum_probe_thread = None

    def _spawn_probe_thread(self, pid: int) -> bool:
        """Z5-8 探测线程收敛单点入口：同时刻至多 PROBE_THREAD_MAX=1 条探测线程。

        在忙（上一条未结束）→ 拒绝并发创建（打印并返回 False；worker 自身另有
        _probe_lock/_probe_in_flight_id 双保险）；空闲 → 创建 name="probe-matrix" 线程。
        _probe_spawn_count 累计 spawn 次数（selftest 长跑命令风暴断言用）。
        """
        t = self._probe_thread
        if t is not None and t.is_alive():
            print(f"[CTRL] 探测线程在忙（在飞 id={self._probe_in_flight_id}），"
                  f"忽略并发 PROBE_MATRIX:{pid}（Z5-8 线程收敛）")
            return False
        self._probe_spawn_count += 1
        self._probe_thread = threading.Thread(target=self._probe_matrix_worker,
                                              args=(pid,), daemon=True,
                                              name="probe-matrix")
        self._probe_thread.start()
        return True

    def _probe_matrix_worker(self, pid: int):
        """批次 U（U2，spec §6.2）→ 批次 AD-5b（需求 §4.6）：后台按需探测设备 pid 的
        RES/FPS 矩阵，9876 回 probe_result。

        两类路径（AD-5b 实测 `ad5b_probe_block_measure.txt` 段 D 裁定）：
        - **`pid == current_camera_id 且流在开` → 复用 live 句柄**（二选一 (b)）：
          实测另开句柄跑探测风暴会**抢流**（活流 5 帧/5.4s、5×>0.5s 间隔，且释放后
          2s 活流仍未恢复）→ 对当前流设备绝不另开：探测前记住当前 res/fps，逐档
          set/get（每档持 `_camera_lock` 与读线程互斥），探测后恢复；绝不 release
          live 句柄（画面不灭）；
        - 其余（`pid ≠ 当前` 或流未开）：沿用另开句柄 `_acquire_camera_handle(pid,
          640, 480)`（Z4-④ 单入口；探测目标≠当前流设备），用完即释放（零泄漏）；
        - 例外（批次 AD-5d，P2-A）：`pid == 当前` 且用户**已主动释放**（`_release_latch`
          / `_camera_intentionally_released` 在位）→ 拒绝开镜（cap 保持 None → 回
          `ok=false`），指示灯绝不因矩阵探测被点亮（项目铁律「主动关不复活」；
          Godot 发送端同名闸门为第一道，本处句柄侧为第二道防线）。
        两路径共同纪律：
        - 探测全程置 `_matrix_probe_active` 抑制无帧看门狗（finally 必清；探测期
          绝不产生 release/`camera_closed`）；
        - **主流命令让位**：以探测起点纪元 `epoch0` 为基准逐档比对 `_probe_cmd_epoch`
          （收线程接收点/执行漏斗已 bump），变化即尽快中止——中止**不回 probe_result**
          （Godot 缓存不被污染，下次 hover 重探；回包 ok=false 会把设备标失败）；
        - 软预算 `PROBE_BUDGET_SEC` 超时收尾（部分结果照回，既有口径）；
        - 收尾补起算看门狗基线（探测窗不计「无帧」，防陈旧基线恢复后被误判）。
        同 id 在探则忽略；`_probe_lock` 全局串行；`PROBE_THREAD_MAX` 线程收敛不变。
        （双审回修②：`PROBE_BUDGET_SEC` 系模块级常量——worker 内直接引用不带
        self. 前缀；误写 self.PROBE_BUDGET_SEC 会 AttributeError。）
        """
        if self._probe_in_flight_id == pid:
            return
        if not self._probe_lock.acquire(blocking=False):
            return
        self._probe_in_flight_id = pid
        epoch0 = self._probe_cmd_epoch           # AD-5b：探测起点让位纪元（陈旧令不误判）
        self._matrix_probe_active = True         # AD-5b：抑制无帧看门狗（finally 必清）
        resolutions = []
        fps_options = []
        ok = False
        aborted = False
        cap = None
        live_mode = False
        saved_w = saved_h = None
        saved_fps = 0.0
        try:
            deadline = time.monotonic() + PROBE_BUDGET_SEC
            try:
                # ---- 路径判定（AD-5b）：pid==当前流设备且句柄在开 → 复用 live 句柄 ----
                with self._camera_lock:
                    cap = self.cap
                    live_mode = (cap is not None and cap.isOpened()
                                 and self.current_camera_id is not None
                                 and int(pid) == int(self.current_camera_id))
                    if live_mode:
                        # 探测前记住当前生效 res/fps（探测后恢复）
                        try:
                            saved_w = int(cap.get(cv.CAP_PROP_FRAME_WIDTH))
                            saved_h = int(cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                            saved_fps = float(cap.get(cv.CAP_PROP_FPS))
                        except Exception:
                            saved_w = saved_h = None
                if not live_mode:
                    # 批次 AD-5d（P2-A，项目铁律「用户显式关闭后任何自动路径不得重开」）：
                    # 探测目标==当前设备 且 用户已主动释放（RELEASE 闩/粘滞释放标志在位）→
                    # **绝不**为矩阵探测重新开镜（`_acquire_camera_handle` 一开指示灯就亮）。
                    # Godot 侧 camera_menu 已在发送端加同名闸门（主动关后零 PROBE_MATRIX），
                    # 本处=句柄侧第二道防线（防任何未来发送方漏门）。cap 置 None：收尾段
                    # `elif not live_mode and cap is not None` 不得触碰 self.cap。
                    # 锁存清除=显式再开（`_switch_camera` 双点清），用户显式重开后探测照常可达。
                    if self.current_camera_id is not None \
                            and int(pid) == int(self.current_camera_id) \
                            and (self._release_latch or self._camera_intentionally_released):
                        print(f"  [PROBE] {pid} 为主动关闭的当前设备 → 拒绝开镜探测"
                              f"（主动关不复活；指示灯不点亮）")
                        cap = None
                    else:
                        # 批次 Z（Z4-④）：探测开镜经句柄单入口（_acquire_lock 与流开镜互斥）
                        cap = self._acquire_camera_handle(pid, 640, 480)
                ok = cap is not None and cap.isOpened()
                if ok and live_mode and saved_w is None:
                    # AD-5 终验回修（P1，2026-09-28）：live 路径「探测前参数不可记」
                    # （`cap.get(W/H)` 异常 → saved_w 置 None）→ **保守跳过探测**：
                    # 归位值不可得时跑逐档 set 风暴会把 live 流参数遗弃在探测中间态
                    # （恢复段无从恢复），与「现有流优先/探测绝不伤画面」纪律冲突。
                    # 回包 ok=false 如实上报（不伪造矩阵）；绝不动 live 句柄（见下方 elif 条件）。
                    print(f"  [PROBE] {pid} live 探测前参数不可读 → 保守跳过探测"
                          f"（不改动 live 流参数；绝不 release live 句柄）")
                    ok = False

                # ---- 逐档探测步（live 步：等锁期让位 + 锁内操作；另开步：自有句柄直操） ----
                def _res_step(tw, th):
                    if not live_mode:
                        cap.set(cv.CAP_PROP_FRAME_WIDTH, tw)
                        cap.set(cv.CAP_PROP_FRAME_HEIGHT, th)
                        return (int(cap.get(cv.CAP_PROP_FRAME_WIDTH)),
                                int(cap.get(cv.CAP_PROP_FRAME_HEIGHT)))
                    while True:
                        if self._probe_cmd_epoch != epoch0:
                            return None          # 让位：不再与主流命令争锁
                        if time.monotonic() > deadline:
                            return None          # 等锁超软预算 → 让位收尾（不与锁僵持）
                        if self._camera_lock.acquire(timeout=0.25):
                            break
                    try:
                        if self.cap is not cap or not cap.isOpened():
                            return None          # 句柄已被主流命令换掉 → 让位
                        cap.set(cv.CAP_PROP_FRAME_WIDTH, tw)
                        cap.set(cv.CAP_PROP_FRAME_HEIGHT, th)
                        return (int(cap.get(cv.CAP_PROP_FRAME_WIDTH)),
                                int(cap.get(cv.CAP_PROP_FRAME_HEIGHT)))
                    finally:
                        self._camera_lock.release()

                def _fps_step(f):
                    if not live_mode:
                        cap.set(cv.CAP_PROP_FPS, f)
                        return float(cap.get(cv.CAP_PROP_FPS))
                    while True:
                        if self._probe_cmd_epoch != epoch0:
                            return None
                        if time.monotonic() > deadline:
                            return None
                        if self._camera_lock.acquire(timeout=0.25):
                            break
                    try:
                        if self.cap is not cap or not cap.isOpened():
                            return None
                        cap.set(cv.CAP_PROP_FPS, f)
                        return float(cap.get(cv.CAP_PROP_FPS))
                    finally:
                        self._camera_lock.release()

                if ok:
                    for tw, th in RES_PROBE_LIST:
                        if self._probe_cmd_epoch != epoch0:
                            aborted = True        # AD-5b：主流命令已到 → 尽快让位
                            break
                        if time.monotonic() > deadline:
                            break
                        got = _res_step(tw, th)
                        if got is None:
                            aborted = True
                            break
                        if got not in resolutions:
                            resolutions.append(got)
                    for f in FPS_PROBE_LIST:
                        if aborted:
                            break
                        if self._probe_cmd_epoch != epoch0:
                            aborted = True
                            break
                        if time.monotonic() > deadline:
                            break
                        af = _fps_step(f)
                        if af is None:
                            aborted = True
                            break
                        if abs(af - f) <= 1.0 and f not in fps_options:
                            fps_options.append(f)
            except Exception as e:
                print(f"  [PROBE] {pid} 探测异常: {e}")
                ok = False
            finally:
                # ---- 收尾归位（正常/超时/异常/中止一视同仁）；嵌套 finally 保证 ----
                # ---- 抑制标志/在探 id/串行锁**绝不**因归位段异常而泄漏          ----
                try:
                    if live_mode and cap is not None and saved_w is not None:
                        # live 路径：恢复探测前记住的 res/fps（中止也恢复——主流命令
                        # 尚未实际改配时（如幂等空转 START）不把流遗弃在探测中间态）
                        _restore_deadline = time.monotonic() + 5.0
                        _got_lock = False
                        while time.monotonic() < _restore_deadline:
                            if self._camera_lock.acquire(timeout=0.25):
                                _got_lock = True
                                break
                        if not _got_lock:
                            print(f"  [PROBE] {pid} 恢复等锁超时 → 跳过参数恢复")
                        else:
                            try:
                                if self.cap is cap and cap.isOpened():
                                    cap.set(cv.CAP_PROP_FRAME_WIDTH, saved_w)
                                    cap.set(cv.CAP_PROP_FRAME_HEIGHT, saved_h)
                                    if 0.0 < saved_fps <= FPS_SEED_MAX:
                                        cap.set(cv.CAP_PROP_FPS, saved_fps)
                            except Exception as e:
                                print(f"  [PROBE] {pid} 恢复探测前参数失败（已忽略）: {e}")
                            finally:
                                self._camera_lock.release()
                    elif not live_mode and cap is not None:
                        try:
                            cap.release()         # 另开句柄：用完/中止均即释放（零泄漏）
                        except Exception:
                            pass
                    # AD-5 终验回修（P1，2026-09-28）：本 elif 必须带 `not live_mode` 条件——
                    # live 路径即使 saved 不可得（saved_w is None，上方已保守跳过探测）也
                    # **绝不** release live 句柄。红态=漏条件落本分支误放流句柄 → 画面灭
                    # 且 `camera_closed` 真值未翻（须等 3×3s 看门狗才自愈），正是本批要根除的
                    # 「画面+手势 HUD 全灭」形态（回归锚 selftest_ad5b E2）。
                    # 看门狗基线补起算（探测窗不计「无帧」，防恢复瞬间被误判）
                    self._last_camera_read_time = time.time()
                    self._no_frame_count = 0
                    self._no_frame_last_mark = 0.0
                    self._rearm_first_frame_window_if_pending()
                except Exception:
                    print(f"  [PROBE] {pid} 收尾归位异常（已忽略）: {traceback.format_exc()}")
                finally:
                    # 清抑制标志 → 清在探 id → 释放串行锁（无论归位成败，锁绝无泄漏）
                    self._matrix_probe_active = False
                    self._probe_in_flight_id = None
                    self._probe_lock.release()
            # ---- 回包（flags 已清；中止不回，缓存不污染）----
            if aborted:
                print(f"  [PROBE] {pid} 收到主流命令 → 让位中止"
                      f"（res 已探 {len(resolutions)} 档；不回 probe_result）")
            else:
                payload = {"type": "probe_result", "id": int(pid), "ok": ok}
                if ok:
                    payload["resolutions"] = [list(r) for r in resolutions]
                    payload["fps_options"] = [int(f) for f in fps_options]
                self.udp_sender.send(payload)
                print(f"  [PROBE] {pid} -> ok={ok} res={resolutions} fps={fps_options}"
                      f"{'（live 复用）' if live_mode else '（另开句柄）'}")
        except Exception:
            # 回包段兜底（send 异常等）：标志已由内层 finally 清理，线程不带栈死
            print(f"  [PROBE] {pid} 收尾异常（已忽略）: {traceback.format_exc()}")
            if self._matrix_probe_active:
                self._matrix_probe_active = False
            if self._probe_in_flight_id == pid:
                self._probe_in_flight_id = None

    def switch_camera(self):
        """键盘 C：切到枚举中的下一个设备（批次 Z Z4-④）。

        旧「无 id 交互选择」路径（读配置→失效则 list_cameras 扫描→交互式选择）随
        句柄单入口收敛退役——其内部多点开镜/交互扫描与「获取单点」冲突；现按下一颗
        枚举设备经 _switch_camera（内部走 _acquire_camera_handle 单入口，closed/opened
        边沿事件、释放时延、CAP_DSHOW 单后端重试等语义原样复用）。枚举空 → 目标 0。
        """
        print("\n[服务器] 切换摄像头...")
        cams = getattr(self, "_cameras", None) or []
        ids = []
        for c in cams:
            try:
                ids.append(int(c.get("id")))
            except (TypeError, ValueError, AttributeError):
                continue
        target = 0
        if ids:
            cur = int(self.current_camera_id) if self.current_camera_id is not None else None
            pos = ids.index(cur) if cur in ids else -1
            target = ids[(pos + 1) % len(ids)]
        # 批次 AA（W4-3）：键盘切换同样登记目标单一真值（防被更晚的 SWITCH 取代语义失配）
        self._note_switch_target(target)
        self._switch_camera(target)

    # ------------------------------------------------------------------
    # 键盘处理
    # ------------------------------------------------------------------

    def _handle_key(self, key: int):
        """处理键盘输入。"""
        if key == 27:  # ESC
            print("\n[服务器] 用户退出")
            self.running = False
        elif key == ord('c') or key == ord('C'):
            self.switch_camera()
        elif key == ord('f') or key == ord('F'):
            self.flip_image = not self.flip_image
            print(f"[服务器] 镜像: {'ON' if self.flip_image else 'OFF'}")

    # ------------------------------------------------------------------
    # 工具
    # ------------------------------------------------------------------

    def _get_fps(self) -> float:
        """计算并返回当前帧率。"""
        now = time.time()
        dt = now - self._last_frame_time
        self._last_frame_time = now

        if dt > 0:
            self.fps_counter.append(1.0 / dt)

        if len(self.fps_counter) > 0:
            return sum(self.fps_counter) / len(self.fps_counter)
        return 0.0

    def _cleanup_camera(self, reason: str = "release"):
        """释放摄像头资源。

        批次 Y（Y-A17）：实际释放发生（cap 非 None）时发 camera_closed(reason)
        事件（边沿触发；cap 已是 None 的幂等调用不产生事件）。
        """
        released = False
        with self._camera_lock:
            if self.cap is not None:
                try:
                    self.cap.release()
                except Exception:
                    pass
                self.cap = None
                released = True
        if released:
            self._emit_camera_closed(reason)

    def _cleanup(self):
        """清理所有资源。"""
        print("\n[服务器] 正在清理资源...")

        # 停止后台采集线程
        self.running = False
        # 批次 Z（Z4-③）：停收线程（标志先行；socket 关闭后其 OSError 分支自行退出，
        # daemon 线程无需强等——CONTROL_RECV_POLL_SEC 轮询窗 ≤0.25s 自然收尾）
        self._control_recv_stop = True
        self._cap_configuring = False
        if self._stream_thread and self._stream_thread.is_alive():
            self._stream_thread.join(timeout=1.0)
            print("[线程] 摄像头采集线程已停止")

        # 停止独立读取线程
        if self._read_thread and self._read_thread.is_alive():
            self._read_thread.join(timeout=1.0)
            print("[Thread] Camera read thread stopped")

        self._cleanup_camera()

        if self.landmarker is not None:
            try:
                self.landmarker.close()
            except Exception:
                pass
            self.landmarker = None

        self.udp_sender.close()

        if self.frame_socket:
            self.frame_socket.close()

        if self.control_socket:
            self.control_socket.close()

        if not self.headless:
            cv.destroyAllWindows()
        print("[服务器] 已退出。")


# ======================================================================
# 命令行入口
# ======================================================================

def main(port: int = None, frame_port: int = None, control_port: int = None,
         camera=None, headless: bool = False, owner_pid=None):
    """入口（批次 R spec §3.1/§3.4）：main.py 以 main(port=…, camera=…) 编程调用；
    直接命令行运行本文件时走原 argparse 兼容路径。"""
    if port is None:
        parser = argparse.ArgumentParser(
            description="手势跟踪服务器 - 通过 UDP 将识别结果发送到 Godot")
        parser.add_argument("--camera", type=int, default=None,
                            help="摄像头索引 (默认自动选择)")
        parser.add_argument("--udp-ip", type=str, default=UDP_IP,
                            help=f"UDP 目标 IP (默认 {UDP_IP})")
        parser.add_argument("--udp-port", type=int, default=UDP_PORT,
                            help=f"UDP 目标端口 (默认 {UDP_PORT})")
        parser.add_argument("--width", type=int, default=640,
                            help="摄像头宽度 (默认 640)")
        parser.add_argument("--height", type=int, default=480,
                            help="摄像头高度 (默认 480)")
        parser.add_argument("--detection-confidence", type=float,
                            default=MIN_DETECTION_CONFIDENCE,
                            help=f"最小检测置信度 (默认 {MIN_DETECTION_CONFIDENCE}，Z5-4)")
        parser.add_argument("--tracking-confidence", type=float,
                            default=MIN_TRACKING_CONFIDENCE,
                            help=f"最小跟踪置信度 (默认 {MIN_TRACKING_CONFIDENCE}，Z5-4)")
        parser.add_argument("--max-hands", type=int, default=2,
                            help="最大检测手数 (默认 2)")
        parser.add_argument("--headless", action="store_true",
                            help="无窗口模式：不显示 OpenCV 摄像头画面窗口")
        parser.add_argument("--no-flip", action="store_true",
                            help="禁用镜像翻转")
        args = parser.parse_args()
        port = args.udp_port
        camera = args.camera
        headless = args.headless
        no_flip = args.no_flip
        width, height = args.width, args.height
        min_det = args.detection_confidence
        min_trk = args.tracking_confidence
        max_hands = args.max_hands
    else:
        no_flip = False
        width, height = 640, 480
        min_det, min_trk, max_hands = MIN_DETECTION_CONFIDENCE, MIN_TRACKING_CONFIDENCE, 2

    server = HandTrackingServer(
        camera_id=camera,
        udp_ip=UDP_IP,
        udp_port=port,
        frame_port=frame_port,
        control_port=control_port,
        width=width,
        height=height,
        min_detection_confidence=min_det,
        min_tracking_confidence=min_trk,
        max_num_hands=max_hands,
        owner_pid=owner_pid,   # 批次 Z（Z4-①）：宿主 PID → 看门狗主判据
    )

    server.headless = headless

    if no_flip:
        server.flip_image = False

    try:
        server.start()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"[ERROR] Server error: {e}")
    finally:
        server._cleanup()


if __name__ == "__main__":
    main()
