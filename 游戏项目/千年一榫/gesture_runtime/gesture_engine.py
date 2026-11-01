#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
增强手势引擎 - 基于 MediaPipe 21 关键点的高精度手势识别。

功能特性：
1. 几何归一化（旋转不变性、尺度不变性）
2. 23 种手势分类（规则+几何特征）
3. 每根手指弯曲程度检测 (0.0~1.0)
4. Pinch 捏合距离检测
5. 手腕角度检测 (roll/pitch/yaw)
6. 时间平滑（7帧滑窗投票 + 滞后阈值）
7. 置信度指数移动平均 (α=0.3)
8. 几何 Reranker 二次校验防混淆
9. 手部空间坐标与深度
"""

import math
from collections import Counter, deque
from typing import Optional

import numpy as np

# ======================================================================
# 常量定义
# ======================================================================

# MediaPipe Hand Landmark 索引 (共 21 个关键点)
#      0: 腕关节 (WRIST)
# 拇指:  1: CMC,  2: MCP,  3: IP,  4: TIP
# 食指:  5: MCP,  6: PIP,  7: DIP,  8: TIP
# 中指:  9: MCP, 10: PIP, 11: DIP, 12: TIP
# 无名指: 13: MCP, 14: PIP, 15: DIP, 16: TIP
# 小指: 17: MCP, 18: PIP, 19: DIP, 20: TIP

WRIST = 0
THUMB_CMC, THUMB_MCP, THUMB_IP, THUMB_TIP = 1, 2, 3, 4
INDEX_MCP, INDEX_PIP, INDEX_DIP, INDEX_TIP = 5, 6, 7, 8
MIDDLE_MCP, MIDDLE_PIP, MIDDLE_DIP, MIDDLE_TIP = 9, 10, 11, 12
RING_MCP, RING_PIP, RING_DIP, RING_TIP = 13, 14, 15, 16
PINKY_MCP, PINKY_PIP, PINKY_DIP, PINKY_TIP = 17, 18, 19, 20

# 每根手指的关键点索引 (用于弯曲检测)
FINGER_INDICES = {
    "thumb":  [THUMB_MCP, THUMB_IP, THUMB_TIP],
    "index":  [INDEX_MCP, INDEX_PIP, INDEX_DIP, INDEX_TIP],
    "middle": [MIDDLE_MCP, MIDDLE_PIP, MIDDLE_DIP, MIDDLE_TIP],
    "ring":   [RING_MCP, RING_PIP, RING_DIP, RING_TIP],
    "pinky":  [PINKY_MCP, PINKY_PIP, PINKY_DIP, PINKY_TIP],
}

# 23 种手势定义
GESTURE_NAMES = {
    0:  "Open_Palm",        # 五指张开
    1:  "Closed_Fist",      # 握拳
    2:  "Point",            # 食指指
    3:  "Peace",            # V字/剪刀手
    4:  "OK",               # OK手势
    5:  "Thumbs_Up",        # 竖大拇指
    6:  "Thumbs_Down",      # 倒大拇指
    7:  "Three",            # 三指(食指+中指+无名指)
    8:  "Four",             # 四指(除拇指外)
    9:  "Rock",             # 摇滚角(食指+小拇指)
    10: "Heart",            # 比心/ILY手语
    11: "Pinch",            # 捏合(拇指+食指)
    12: "Call_Me",          # 打电话手势
     13: "Gun",              # 手枪手势
     18: "Fingers_Spread",   # 手指张开
    19: "Claw",             # 爪形
    20: "Cross",            # 交叉手指
     21: "Rest",             # 自然放松(无手势)
     22: "Only_Thumb",        # 只伸拇指（其余四指弯曲）
     23: "Only_Index",        # 只伸食指（其余四指弯曲）
     24: "Only_Middle",       # 只伸中指（其余四指弯曲）
     25: "Only_Ring",         # 只伸无名指（其余四指弯曲）
     26: "Only_Pinky",        # 只伸小指（其余四指弯曲）
}

# 反向映射：名称 → ID
GESTURE_IDS = {v: k for k, v in GESTURE_NAMES.items()}

# 时间平滑参数
SMOOTH_WINDOW_SIZE = 5          # 批次 U（U8，spec §4-U8-2）：7→5（快速动作群延迟 ~230ms→~165ms）；本批唯一内核豁免行（批次 T「内核零改动」红线的显式豁免，其余 0.55/0.40/EMA 0.3 维持）
CONFIDENCE_ENTER = 0.55          # 进入阈值（滞后方差）
CONFIDENCE_EXIT = 0.40           # 退出阈值
EMA_ALPHA = 0.3                  # 指数移动平均系数

# 批次 Y（Y-A7，spec §2/§3.1 值语义升级/§4-4 常量集中）：输出平滑常量。
# 作用域红线：仅平滑「输出数值」（hand_rotation_x/y/z 与 fingers[5]，键名不变），
# 分类内核（_classify_gesture/_geometric_rerank/_detect_single_finger 与既有
# gesture/confidence 滑窗+EMA）一律消费原始值、零改动。
# α 取值偏保守（α 大=响应快、平滑弱）：0.5 在 30fps 下仅引入 ≈1 帧相位滞后，
# 防手感延迟；真手复验后一次性调参，不散落魔改（spec §4-4）。
ROTATION_EMA_ALPHA = 0.5         # hand_rotation_x/y/z（roll/pitch/yaw，度）输出 EMA 系数
FINGERS_EMA_ALPHA = 0.5          # fingers[5]（0~1）输出 EMA 系数

# 批次 AA（W2-6，spec §5.3/§15#7）：分指伸直阈——四指 extend 公式归一基**逐指独立**：
# 无名指 0.45【暂定值·待用户复验】（解剖学最难独立伸展：真手无名指 extend≈0.592 对旧
# 共用 0.55 余量仅 8%，raw 稳态 <0.55 则 FINGERS_EMA_ALPHA 平滑后永远爬不过）；
# 食/中/小维持 0.55。与 GDScript gesture_map.FINGER_EXTEND_TH **同源同值**（协议
# fingers[] 数值即本公式产出），单侧改动=双轨漂移，两侧必须同步。
# 批次 AC（领域五 §4.5-1，2026-09-27）：中指 0.55→0.48、无名指 0.45→0.48——食指瞄准后
# 竖中指单击时中指常落 0.48~0.54 越不过 0.55（用户「点不动」根因之一）；无名指随之上调
# 0.03 与中指同档（GDScript 侧同值 [0.55, 0.55, 0.48, 0.48, 0.55]；跨语言切点护栏
# selftest_aa_finger_thresholds 已同步等价改写）。
# 批次 AD（§4.1.4 实施口径，2026-09-27）：**中指 0.48→0.55 收回安全区间**——AC 下调后
# 食指瞄准时中指因肌腱连带常落 0.48~0.54，越阈即被判 two → 误合成左键按下/进 ORBIT
#（用户实机反馈「瞄准时中指微伸被误判为双指」）。现要求中指**明显竖起**（生效 curl 切点
# 0.55+0.30×0.55=0.715）才算二指；无名指 0.48 不变（连带解耦仍由 GDScript `_classify`
# 的 TWO_RING_COUPLE_MAX/GAP 差值判据承担）。两侧**同源同值**联动（跨语言切点护栏
# selftest_aa_finger_thresholds 已同步登记新值）。
FINGER_EXTEND_TH = {"index": 0.55, "middle": 0.55, "ring": 0.48, "pinky": 0.55}
FINGER_EXTEND_SPAN = 0.30        # extend 归一跨度（原公式 0.30 不变；改的只是逐指基 th）

# 批次 Y（Y-A5，spec §2/§4-4 常量集中）：roll 盲区空间先验外推参数。
# 盲区成因：侧立/朝向镜头位姿下掌向量 lm9−lm0 的 XY 投影模长≈0，
# atan2(≈0,≈0) 输出由噪声决定 → roll 随机跳变（spec §1 域二根因）。
# 取值依据：正常摊平手 XY 模长 ≈0.1~0.3（归一坐标），MediaPipe 噪声 ≈0.005~0.01，
# 门限取 0.045 兼顾「不误伤有效帧」与「盲区不漏进噪声」；真手复验后一次性调参。
BLIND_ZONE_XY_MIN = 0.045        # 盲区门限：palm_vec XY 模长低于此值视为侧立盲区
BLIND_ZONE_MAX_RATE_DPS = 720.0  # 角速度限幅（度/秒；≈2 圈/秒；差分估计进 EMA 前（P2-5）与盲区外推共用同一上限）
BLIND_ZONE_RATE_ALPHA = 0.3      # 角速度估计 EMA 系数（输入已经过 MAX_RATE_DPS 限幅）


# ======================================================================
# 核心类
# ======================================================================

class GestureEngine:
    """
    增强手势引擎。

    用法：
        engine = GestureEngine()
        result = engine.process(landmarks_3d, handedness="Right")
        # result 包含手势、手指状态、位置等所有信息
    """

    def __init__(self):
        # 时间平滑器
        self._gesture_history = deque(maxlen=SMOOTH_WINDOW_SIZE)
        self._confidence_history = deque(maxlen=SMOOTH_WINDOW_SIZE)
        self._smoothed_gesture_id: int = 21  # Rest
        self._smoothed_confidence: float = 0.0
        self._ema_confidence: float = 0.0

        # 批次 Y（Y-A7）：输出平滑状态（仅作用于输出数值，分类内核零改动）
        self._rotation_ema: dict = {}      # {"roll"/"pitch"/"yaw": 上次平滑输出}
        self._fingers_ema: Optional[list] = None

        # 批次 Y（Y-A5）：roll 盲区外推状态（仅 roll 通道；pitch/yaw 无此盲区问题）
        self._roll_last_valid: Optional[float] = None   # 最后有效 raw roll（度，[0,360)）
        self._roll_last_t: Optional[float] = None       # 该锚点帧的 timestamp
        self._roll_rate_dps: float = 0.0                # 角速度估计（输入限幅后 EMA，度/秒）

        # 状态缓存
        self._last_result = None

    # ------------------------------------------------------------------
    # 主处理入口
    # ------------------------------------------------------------------

    def process(self,
                landmarks_3d: np.ndarray,
                handedness: str = "Right") -> dict:
        """
        处理 21 个关键点，返回完整的识别结果。

        Args:
            landmarks_3d: shape (21, 3) 的数组，
                          每行为 (x, y, z)，x/y 归一化到 0~1，z 为深度。
            handedness: "Left" 或 "Right"

        Returns:
            dict: 包含以下字段：
                - gesture (str): 手势名称
                - gesture_id (int): 手势 ID
                - confidence (float): 置信度 0~1
                - hand_x, hand_y, hand_z (float): 手部中心坐标
                - hand_rotation_x/y/z (float): 手腕旋转角度
                - fingers (list[float]): [拇指~小指] 弯曲程度 0~1
                - pinch_distance (float): 捏合距离 0~1
                - handedness (str): 左右手
                - is_detected (bool): 是否检测到手
                - timestamp (float): 时间戳
        """
        timestamp = self._get_timestamp()

        if landmarks_3d is None or len(landmarks_3d) != 21:
            return self._empty_result(timestamp)

        # 1. 提取归一化特征
        features = self._extract_features(landmarks_3d)

        # 2. 手指弯曲程度
        #    （Y-A7：原始值供分类内核判定；输出经 _smooth_fingers EMA 平滑）
        finger_states_raw = self._compute_finger_states(landmarks_3d, features)

        # 3. 手势分类（消费原始 finger_states——判定内核零改动红线）
        raw_gesture_id, raw_confidence = self._classify_gesture(
            landmarks_3d, features, finger_states_raw)

        # 4. 几何 Reranker 二次校验
        gesture_id = self._geometric_rerank(
            raw_gesture_id, landmarks_3d, features, finger_states_raw)

        # 4.5 单指后处理：恰好一根手指伸出时覆盖为新手势
        single_finger_id = self._detect_single_finger(finger_states_raw)
        if single_finger_id is not None:
            gesture_id = single_finger_id
            raw_confidence = 0.95  # 几何检测置信度高

        # 5. 时间平滑
        smoothed_id, smoothed_conf = self._temporal_smooth(
            gesture_id, raw_confidence)

        # 6. 手腕角度（Y-A5：roll 盲区先经空间先验外推稳定化；Y-A7：再经
        #    wrap-aware EMA 平滑——外推线性段+EMA 衔接，轨迹全程连续可判）
        rotation = self._smooth_rotation(
            self._stabilize_roll_blind_zone(
                self._compute_wrist_angles(landmarks_3d), landmarks_3d, timestamp))

        # 6.5 输出平滑（Y-A7）：fingers 在位升级为平滑后值（键名不变）
        finger_states = self._smooth_fingers(finger_states_raw)

        # 7. 捏合距离
        pinch_dist = self._compute_pinch_distance(
            landmarks_3d, features["palm_size"])

        # 8. 手部中心
        hand_center = self._compute_hand_center(landmarks_3d)

        # 8.5 批次 R 新增（spec §3.3/§3.4）：palm_size——腕点0到中指根9的归一坐标欧氏距离
        #     hypot(lm0.x-lm9.x, lm0.y-lm9.y)，供 Godot 侧推拉缩放；判定内核其余零改动
        palm_size_norm = float(np.hypot(
            landmarks_3d[0][0] - landmarks_3d[9][0],
            landmarks_3d[0][1] - landmarks_3d[9][1]))

        # 9. 构建结果
        result = {
            "gesture": GESTURE_NAMES.get(smoothed_id, "Unknown"),
            "gesture_id": int(smoothed_id),
            "confidence": round(float(smoothed_conf), 4),
            "hand_x": round(float(hand_center[0]), 4),
            "hand_y": round(float(hand_center[1]), 4),
            "hand_z": round(float(hand_center[2]), 4),
            "hand_rotation_x": round(float(rotation["roll"]), 4),
            "hand_rotation_y": round(float(rotation["pitch"]), 4),
            "hand_rotation_z": round(float(rotation["yaw"]), 4),
            "fingers": [round(float(v), 4) for v in finger_states],
            "pinch_distance": round(float(pinch_dist), 4),
            "handedness": handedness,
            "fps": 0,
            "is_detected": True,
            "timestamp": timestamp,
            "palm_size": round(float(palm_size_norm), 4),
            # 附加调试信息
            "_raw_gesture_id": int(raw_gesture_id),
            "_raw_confidence": round(float(raw_confidence), 4),
        }

        self._last_result = result
        return result

    # ------------------------------------------------------------------
    # 特征提取（几何归一化）
    # ------------------------------------------------------------------

    def _extract_features(self, lm: np.ndarray) -> dict:
        """
        从 21 个关键点提取几何不变特征。

        处理流程：
        1. 以腕关节(0)为原点平移
        2. 除以掌心尺度归一化（中指根部到腕关节距离）
        3. 计算相邻关节向量角度
        4. 计算关键点间距离比

        Args:
            lm: shape (21, 3) 关键点

        Returns:
            dict: 包含归一化特征
        """
        wrist = lm[WRIST]
        palm_center = lm[MIDDLE_MCP]

        # 平移：以腕关节为原点
        translated = lm - wrist

        # 掌心尺度：腕关节到中指根部的距离
        palm_size = np.linalg.norm(palm_center - wrist)
        if palm_size < 1e-6:
            palm_size = 1.0

        # 尺度归一化
        normalized = translated / palm_size

        # 相邻关节向量
        bone_vectors = []
        # MediaPipe 手部连接关系
        connections = [
            (0, 1), (1, 2), (2, 3), (3, 4),       # 拇指
            (0, 5), (5, 6), (6, 7), (7, 8),       # 食指
            (0, 9), (9, 10), (10, 11), (11, 12),  # 中指
            (0, 13), (13, 14), (14, 15), (15, 16), # 无名指
            (0, 17), (17, 18), (18, 19), (19, 20), # 小指
            (5, 9), (9, 13), (13, 17),            # 掌骨间连接
        ]
        for i, j in connections:
            vec = normalized[j] - normalized[i]
            bone_vectors.append(vec)

        # 计算向量角度（对旋转不变）
        angles = []
        for v in bone_vectors:
            angle = math.atan2(v[1], v[0])  # 相对于 x 轴的角度
            angles.append(angle)

        # 计算关键点间的距离比（对尺度+旋转不变）
        distances = []
        # 手指尖到腕关节的距离比
        tip_indices = [THUMB_TIP, INDEX_TIP, MIDDLE_TIP, RING_TIP, PINKY_TIP]
        for tip in tip_indices:
            d = np.linalg.norm(normalized[tip])
            distances.append(d)

        # 相邻指尖距离
        for i in range(len(tip_indices) - 1):
            d = np.linalg.norm(normalized[tip_indices[i]] -
                               normalized[tip_indices[i + 1]])
            distances.append(d)

        return {
            "palm_size": palm_size,
            "normalized": normalized,
            "bone_vectors": bone_vectors,
            "angles": angles,
            "distances": distances,
        }

    # ------------------------------------------------------------------
    # 手指弯曲程度检测
    # ------------------------------------------------------------------

    def _compute_finger_states(self, lm: np.ndarray,
                                features: dict) -> list[float]:
        """
        计算每根手指的弯曲程度。

        Returns:
            list[float]: [拇指, 食指, 中指, 无名指, 小指] 0.0~1.0
                         0.0 = 完全弯曲，1.0 = 完全伸直
        """
        nlm = features["normalized"]

        # 拇指: 骨骼链长度比法 + IP关节角度双因子检测
        # 骨骼链: CMC(1) → MCP(2) → IP(3) → TIP(4)
        thumb_cmc = nlm[THUMB_CMC]
        thumb_mcp = nlm[THUMB_MCP]
        thumb_ip = nlm[THUMB_IP]
        thumb_tip_n = nlm[THUMB_TIP]
        bone_chain = (np.linalg.norm(thumb_cmc - thumb_mcp) +
                      np.linalg.norm(thumb_mcp - thumb_ip) +
                      np.linalg.norm(thumb_ip - thumb_tip_n))
        direct_dist = np.linalg.norm(thumb_cmc - thumb_tip_n)
        if bone_chain < 1e-6:
            thumb_state = 0.0
        else:
            curl_ratio = direct_dist / bone_chain
            # 基础映射：curl_ratio >0.85 伸出, <0.70 弯曲（拇指特殊处理，阈值大幅降低）
            base_state = max(0.0, min(1.0, (curl_ratio - 0.75) / 0.10))

            # IP关节角度因子：MCP-IP-TIP 夹角
            # 完全伸直时约 170-180°，弯曲时 < 140°
            v1 = thumb_mcp - thumb_ip
            v2 = thumb_tip_n - thumb_ip
            cos_angle = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-8)
            ip_angle_deg = math.degrees(math.acos(np.clip(cos_angle, -1.0, 1.0)))

            # IP关节弯曲时强制降低：角度 < 175° 开始衰减，< 160° 完全弯曲（更敏感）
            if ip_angle_deg < 175.0:
                ip_factor = max(0.0, (ip_angle_deg - 160.0) / 15.0)  # 0.0~1.0
                thumb_state = base_state * ip_factor
            else:
                thumb_state = base_state

        # 食指~小指: 骨骼链长度比法（与拇指一致，旋转/尺度不变）
        finger_states = [thumb_state]
        for name, indices in [
            ("index", [INDEX_MCP, INDEX_PIP, INDEX_DIP, INDEX_TIP]),
            ("middle", [MIDDLE_MCP, MIDDLE_PIP, MIDDLE_DIP, MIDDLE_TIP]),
            ("ring", [RING_MCP, RING_PIP, RING_DIP, RING_TIP]),
            ("pinky", [PINKY_MCP, PINKY_PIP, PINKY_DIP, PINKY_TIP]),
        ]:
            mcp, pip, dip, tip = indices
            # 骨骼链总长（恒定不变）
            bone_chain = (np.linalg.norm(nlm[mcp] - nlm[pip]) +
                          np.linalg.norm(nlm[pip] - nlm[dip]) +
                          np.linalg.norm(nlm[dip] - nlm[tip]))
            # 直线距离（弯曲时缩短）
            direct_dist = np.linalg.norm(nlm[mcp] - nlm[tip])
            if bone_chain < 1e-6:
                finger_states.append(0.0)
            else:
                curl_ratio = direct_dist / bone_chain
                # 映射：>0.85 完全伸直；完全弯曲基 th 逐指（批次 AA W2-6 分指阈值：
                # 无名指 0.45，其余 0.55——旧「四指共用 (curl−0.55)/0.30」退役留痕）
                th = FINGER_EXTEND_TH.get(name, 0.55)
                extend = max(0.0, min(1.0, (curl_ratio - th) / FINGER_EXTEND_SPAN))
                finger_states.append(extend)

        # 握拳补偿：四指中 >= 3 指弯曲时，检查拇指 MCP 关节角度
        # 握拳时拇指包裹在拳头外，curl_ratio 偏高导致误判为伸直
        # 通过 MCP 关节角度（CMC-MCP-IP 三点夹角）修正
        bent_count = sum(1 for s in finger_states if s < 0.4)
        if bent_count >= 3 and thumb_state > 0.5:
            # 计算 MCP 关节角度：CMC(1) - MCP(2) - IP(3)
            v1 = thumb_cmc - thumb_mcp
            v2 = thumb_ip - thumb_mcp
            cos_a = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-8)
            mcp_angle = math.degrees(math.acos(np.clip(cos_a, -1.0, 1.0)))
            # MCP 角度 < 140 度时开始衰减，120 度时完全弯曲
            if mcp_angle < 140.0:
                mcp_factor = max(0.0, (mcp_angle - 120.0) / 20.0)
                finger_states[0] = thumb_state * mcp_factor

        return finger_states

    # ------------------------------------------------------------------
    # 手势分类（基于几何规则）
    # ------------------------------------------------------------------

    def _classify_gesture(self, lm: np.ndarray, features: dict,
                           finger_states: list[float]) -> tuple[int, float]:
        """
        基于几何特征分类手势。

        Returns:
            tuple[int, float]: (gesture_id, confidence)
        """
        nlm = features["normalized"]
        thumb_s, index_s, middle_s, ring_s, pinky_s = finger_states

        # 基础判定
        extended_count = sum(1 for s in finger_states if s > 0.6)
        folded_count = sum(1 for s in finger_states if s < 0.4)
        all_extended = all(s > 0.6 for s in finger_states)
        all_folded = all(s < 0.4 for s in finger_states)

        # 指尖位置
        thumb_tip = nlm[THUMB_TIP]
        index_tip = nlm[INDEX_TIP]
        middle_tip = nlm[MIDDLE_TIP]
        ring_tip = nlm[RING_TIP]
        pinky_tip = nlm[PINKY_TIP]
        wrist_pos = nlm[WRIST]

        # 拇指尖到食指尖距离
        thumb_index_dist = np.linalg.norm(thumb_tip - index_tip)
        thumb_middle_dist = np.linalg.norm(thumb_tip - middle_tip)

        # 指尖到手腕的角度（判断手指是否指向特定方向）
        def tip_angle(tip_idx):
            v = nlm[tip_idx] - wrist_pos
            return math.atan2(v[1], v[0])

        angles_deg = [math.degrees(tip_angle(i))
                      for i in [THUMB_TIP, INDEX_TIP, MIDDLE_TIP,
                                RING_TIP, PINKY_TIP]]

        # ----- 逐个手势判定 -----

        # Rest (21) - 所有手指半弯曲，放松状态
        if 0.35 <= thumb_s <= 0.65 and all(0.3 <= s <= 0.7
                                            for s in finger_states[1:]):
            return 21, 0.6

        # Closed_Fist (1) - 所有手指弯曲
        # 增强：更宽松阈值，支持任意角度握拳（不受手掌朝向影响）
        all_fingers_bent = all(s < 0.6 for s in finger_states)
        if all_fingers_bent:
            return 1, 0.95
        # 严格阈值备选（传统方式）
        if all_folded:
            return 1, 0.9
        # 增强备选：4指（拇指除外）弯曲 + 指尖聚拢于掌心
        # 握拳时拇指可能因遮挡/MP检测误差显示"半伸直"，但其他4指肯定弯曲
        fingers_no_thumb = finger_states[1:]  # [食指, 中指, 无名指, 小指]
        bent_no_thumb = sum(1 for s in fingers_no_thumb if s < 0.6)
        if bent_no_thumb >= 3 and all(s < 0.75 for s in fingers_no_thumb):
            # 几何验证：所有指尖到腕关节的距离（握拳时显著缩短）
            tip_indices_local = [THUMB_TIP, INDEX_TIP, MIDDLE_TIP, RING_TIP, PINKY_TIP]
            wrist_pos_local = nlm[WRIST]
            tip_dists_local = [np.linalg.norm(nlm[i] - wrist_pos_local) for i in tip_indices_local]
            avg_tip_dist = np.mean(tip_dists_local)
            # 张开手掌时 avg_tip_dist ≈ 0.5~0.8，握拳时 ≈ 0.15~0.35
            if avg_tip_dist < 0.4:
                return 1, 0.85
            # 或者所有指尖到中指MCP的距离也很小
            mid_mcp = nlm[MIDDLE_MCP]
            tip_to_palm = [np.linalg.norm(nlm[i] - mid_mcp) for i in tip_indices_local]
            if np.mean(tip_to_palm) < 0.3:
                return 1, 0.8

        # Open_Palm (0) - 所有手指伸直；批次 AA（W2-6，spec §5.3/§5.4-7）小指泄漏守卫：
        # 小指 >0.70 才认掌（≤0.70 视为三指形泄漏 → 回落 Three(7)，与 GDScript
        # gesture_map.PALM_PINKY_TH 同口径）——根治「小指泄漏致 palm」双轨背离
        # （旧 all(s>0.6) 把 0.63 泄漏小指算进张掌，三指形显示成 Open_Palm）。
        if all_extended and thumb_s > 0.5 and pinky_s > 0.70:
            return 0, 0.95

        # Fingers_Spread (18) - 手指张开（指尖间距大）
        tip_distances = [
            np.linalg.norm(index_tip - middle_tip),
            np.linalg.norm(middle_tip - ring_tip),
            np.linalg.norm(ring_tip - pinky_tip),
        ]
        if (all_extended and
                all(d > 0.15 for d in tip_distances) and
                all(s > 0.7 for s in finger_states)):
            return 0, 0.9  # Open_Palm 和 Fingers_Spread 类似

        # Point (2) - 仅食指伸直
        if (index_s > 0.7 and
                middle_s < 0.5 and ring_s < 0.5 and pinky_s < 0.5):
            return 2, _confidence_from_fingers(
                [thumb_s, index_s, middle_s, ring_s, pinky_s],
                [None, 1.0, 0.0, 0.0, 0.0])

        # Peace (3) - 食指+中指V字，其他弯曲
        if (index_s > 0.7 and middle_s > 0.7 and
                ring_s < 0.5 and pinky_s < 0.5):
            # 检查两根手指是否张开
            im_dist = np.linalg.norm(index_tip - middle_tip)
            if im_dist > 0.08:
                return 3, _confidence_from_fingers(
                    finger_states, [None, 1.0, 1.0, 0.0, 0.0])
            else:
                # 靠在一起可能是 Gun
                return 13, _confidence_from_fingers(
                    finger_states, [None, 1.0, 1.0, 0.0, 0.0])

        # Three (7) - 食指+中指+无名指伸直；批次 AA（W2-6）小指泄漏带 ≤0.70 仍判三指
        #（与 Open_Palm 守卫配对的回落分支；旧 pinky<0.5 过严——泄漏 0.55~0.70 既不进
        # Three 也被旧 Open_Palm 截走，三指形显示双轨背离）
        if (index_s > 0.7 and middle_s > 0.7 and ring_s > 0.7 and
                pinky_s < 0.70):
            return 7, _confidence_from_fingers(
                finger_states, [None, 1.0, 1.0, 1.0, 0.0])

        # Four (8) - 四指伸直（除拇指）
        if (all(s > 0.7 for s in finger_states[1:]) and
                thumb_s < 0.6):
            return 8, _confidence_from_fingers(
                finger_states, [None, 1.0, 1.0, 1.0, 1.0])

        # Rock (9) - 食指+小拇指伸直，其他弯曲
        if (index_s > 0.6 and pinky_s > 0.6 and
                middle_s < 0.5 and ring_s < 0.5):
            return 9, _confidence_from_fingers(
                finger_states, [None, 1.0, 0.0, 0.0, 1.0])

        # Gun (13) - 食指+中指伸直并靠拢，拇指可能伸直
        if (index_s > 0.7 and middle_s > 0.7 and
                ring_s < 0.5 and pinky_s < 0.5):
            im_dist = np.linalg.norm(index_tip - middle_tip)
            if im_dist < 0.1:
                return 13, _confidence_from_fingers(
                    finger_states, [None, 1.0, 1.0, 0.0, 0.0])

        # OK (4) - 拇指+食指捏合，其他伸直
        thumb_index_dist_3d = np.linalg.norm(thumb_tip - index_tip)
        if (thumb_index_dist_3d < 0.12 and
                middle_s > 0.6 and ring_s > 0.6 and pinky_s > 0.6):
            return 4, max(0.0, 1.0 - thumb_index_dist_3d / 0.12)

        # Pinch (11) - 拇指+食指捏合（其他可能任意）
        if (thumb_index_dist_3d < 0.1 and
                not (middle_s > 0.6 and ring_s > 0.6 and pinky_s > 0.6)):
            return 11, max(0.0, 1.0 - thumb_index_dist_3d / 0.1)

        # Thumbs_Up (5) - 拇指伸直向上，其他弯曲
        if (thumb_s > 0.7 and
                all(s < 0.5 for s in finger_states[1:])):
            # 拇指指尖在手腕上方（y 坐标小 = 上方，因为图像 y 轴向下）
            thumb_y_rel = thumb_tip[1] - wrist_pos[1]
            if thumb_y_rel < 0:
                return 5, _confidence_from_fingers(
                    finger_states, [1.0, 0.0, 0.0, 0.0, 0.0])

        # Thumbs_Down (6) - 拇指伸直向下，其他弯曲
        if (thumb_s > 0.7 and
                all(s < 0.5 for s in finger_states[1:])):
            thumb_y_rel = thumb_tip[1] - wrist_pos[1]
            if thumb_y_rel > 0:
                return 6, _confidence_from_fingers(
                    finger_states, [1.0, 0.0, 0.0, 0.0, 0.0])

        # Heart/ILY (10) - 拇指+小拇指伸直，食指+中指+无名指弯曲
        # 与 Call_Me 区别：Heart 要求无名指和中指靠近（距离小）
        if (thumb_s > 0.7 and pinky_s > 0.7 and
                index_s < 0.5 and middle_s < 0.5 and ring_s < 0.5):
            # 检查无名指和中指是否靠拢（ILV手势特征）
            ring_middle_dist = np.linalg.norm(ring_tip - middle_tip)
            if ring_middle_dist < 0.08:
                return 10, _confidence_from_fingers(
                    finger_states, [1.0, 0.0, 0.0, 0.0, 1.0])

        # Call_Me (12) - 拇指+小拇指伸直，其他弯曲，手放在耳边
        # 与 Heart 区别：无名指和中指分开
        if (thumb_s > 0.7 and pinky_s > 0.7 and
                index_s < 0.5 and middle_s < 0.5 and ring_s < 0.5):
            ring_middle_dist = np.linalg.norm(ring_tip - middle_tip)
            if ring_middle_dist >= 0.08:
                return 12, _confidence_from_fingers(
                    finger_states, [1.0, 0.0, 0.0, 0.0, 1.0])

        # Claw (19) - 所有手指弯曲但指尖聚集
        if all(s < 0.5 for s in finger_states):
            # 计算指尖是否聚集
            tips = np.array([thumb_tip, index_tip, middle_tip,
                             ring_tip, pinky_tip])
            centroid = np.mean(tips, axis=0)
            spread = np.mean([np.linalg.norm(t - centroid) for t in tips])
            if spread < 0.15:
                return 19, max(0.0, 1.0 - spread / 0.15)

        # Cross (20) - 交叉手指（食指和中指交叉）
        if index_s > 0.6 and middle_s > 0.6:
            cross_dist = np.linalg.norm(index_tip - middle_tip)
            if cross_dist < 0.05:
                return 20, 0.7

        # 返回 Rest (21) 作为默认
        return 21, 0.5

    # ------------------------------------------------------------------
    # 几何 Reranker（二次校验）
    # ------------------------------------------------------------------

    def _geometric_rerank(self, gesture_id: int, lm: np.ndarray,
                           features: dict,
                           finger_states: list[float]) -> int:
        """
        几何 Reranker：对容易混淆的手势进行二次校验。

        混淆对：
        - Pinch ↔ Fist: pinch 判定时如果手指弯曲过多 → Fist
        - Peace ↔ Three: 无名指弯曲程度区分
        - Thumbs_Up ↔ Point: 拇指伸展度区分
        """
        nlm = features["normalized"]
        thumb_s, index_s, middle_s, ring_s, pinky_s = finger_states

        # 1. Pinch (11) ↔ Fist (1)
        if gesture_id == 11 and all(s < 0.35 for s in finger_states):
            # Pinch 但所有手指弯曲 → 可能是 Fist
            return 1

        # 2. Peace (3) ↔ Three (7)
        if gesture_id == 3:
            # Peace 但无名指也伸直了 → Three
            if ring_s > 0.6:
                return 7

        # 3. Three (7) ↔ Peace (3)
        if gesture_id == 7:
            # Three 但无名指弯曲 → Peace
            if ring_s < 0.5:
                return 3

        # 4. Thumbs_Up (5) ↔ Point (2)
        if gesture_id == 5 and index_s > 0.6:
            # Thumbs_Up 但食指也伸直 → 可能是 Point
            # 检查拇指是否明显外展
            thumb_angle = math.degrees(
                math.atan2(nlm[THUMB_TIP][1] - nlm[WRIST][1],
                           nlm[THUMB_TIP][0] - nlm[WRIST][0]))
            if abs(thumb_angle) < 30:
                return 2  # 拇指与手腕角度小 → 更像 Point

        # 5. Point (2) ↔ Thumbs_Up (5)
        if gesture_id == 2 and thumb_s > 0.7:
            # Point 但拇指也伸直 → 检查拇指方向
            thumb_y_rel = nlm[THUMB_TIP][1] - nlm[WRIST][1]
            if thumb_y_rel < -0.1:
                return 5  # 拇指明显向上 → Thumbs_Up

        # 6. Heart (10) ↔ Call_Me (12)
        # 两者手势相同，根据语境保留原始判断

        # 7. 通用兜底：任何手势 → Fist(1)，如果除拇指外所有手指极度弯曲
        #    处理 MediaPipe 偶尔把握拳识别为其他手势的问题
        if gesture_id not in (1, 21):  # 不是已经是握拳或静止
            fingers_no_thumb = finger_states[1:]  # 食指~小指
            if all(s < 0.3 for s in fingers_no_thumb):
                return 1  # 所有非拇指手指极度弯曲 → 基本是握拳

        return gesture_id

    # ------------------------------------------------------------------
    # 单指后处理
    # ------------------------------------------------------------------

    def _detect_single_finger(self,
                               finger_states: list[float]) -> int | None:
        """
        单指检测后处理：如果恰好只有一根手指伸出，返回对应新手势 ID。

        Uses:
            finger_states: [拇指, 食指, 中指, 无名指, 小指] 0.0~1.0

        Returns:
            int | None: 手势 ID (22~26)，非单指场景返回 None
        """
        extended_threshold = 0.6
        extended = [s > extended_threshold for s in finger_states]
        extended_count = sum(extended)

        if extended_count == 1:
            if extended[0]:
                return 22  # Only_Thumb
            if extended[1]:
                return 23  # Only_Index
            if extended[2]:
                return 24  # Only_Middle
            if extended[3]:
                return 25  # Only_Ring
            if extended[4]:
                return 26  # Only_Pinky

        return None

    # ------------------------------------------------------------------
    # 时间平滑
    # ------------------------------------------------------------------

    def _temporal_smooth(self, gesture_id: int,
                           confidence: float) -> tuple[int, float]:
        """
        时间平滑：7帧滑窗投票 + 滞后阈值 + 置信度 EMA。

        Args:
            gesture_id: 当前帧的手势 ID
            confidence: 当前帧的置信度

        Returns:
            tuple[int, float]: (平滑后的手势 ID, 平滑后的置信度)
        """
        # 更新历史
        self._gesture_history.append(gesture_id)
        self._confidence_history.append(confidence)

        # 如果历史不足，使用原始值
        if len(self._gesture_history) < 3:
            self._smoothed_gesture_id = gesture_id
            self._smoothed_confidence = confidence
            return gesture_id, confidence

        # 滑动窗口投票
        counter = Counter(self._gesture_history)
        most_common = counter.most_common()

        top_id, top_count = most_common[0]
        top_ratio = top_count / len(self._gesture_history)

        # 置信度 EMA
        if self._ema_confidence == 0.0:
            self._ema_confidence = confidence
        else:
            self._ema_confidence = (EMA_ALPHA * confidence +
                                    (1 - EMA_ALPHA) * self._ema_confidence)

        # 滞后阈值：使用不同的阈值进入/退出
        current = self._smoothed_gesture_id

        if top_id == current:
            # 保持当前手势：只需超过退出阈值
            if top_ratio >= CONFIDENCE_EXIT or self._ema_confidence >= CONFIDENCE_EXIT:
                self._smoothed_gesture_id = top_id
                self._smoothed_confidence = self._ema_confidence
        else:
            # 切换手势：需要超过进入阈值
            if top_ratio >= CONFIDENCE_ENTER and \
               self._ema_confidence >= CONFIDENCE_ENTER:
                self._smoothed_gesture_id = top_id
                self._smoothed_confidence = self._ema_confidence
            # 否则保持原手势

        return self._smoothed_gesture_id, self._smoothed_confidence

    # ------------------------------------------------------------------
    # 输出平滑（批次 Y，Y-A7：spec §3.1 值语义升级——键名不变、数值为平滑后值）
    # ------------------------------------------------------------------

    def _stabilize_roll_blind_zone(self, rotation: dict, lm: np.ndarray,
                                   timestamp: float) -> dict:
        """Y-A5 空间先验：roll 盲区稳定化（仅 roll 通道；spec §2 Y-A5）。

        盲区判定：掌向量 palm_vec=lm[9]−lm[0] 的 XY 模长 < BLIND_ZONE_XY_MIN
        （侧立/朝向镜头位姿，atan2(≈0,≈0) 输出由噪声决定）。

        方案取舍（补派口径二选一）：采用「上一有效 roll + 角速度外推」而非纯
        hold 上一有效值——
        - 纯 hold：盲区段轨迹平直，出盲区时面对 180° 级真实变化，wrap-aware EMA
          把该差值按 ±180° 边界处理，轨迹出现 180° 级快速跳变，破坏 GDScript
          FlipDetector（1.0s 窗 |Δroll|>90°）依赖的连续轨迹；
        - 角速度外推：盲区段沿运动方向线性延续，出盲区时与真实 roll 小偏差衔接，
          全程无跳变、净位移按运动方向累计——与 spec Y-A5 原文「空间位置+运动
          方向外推翻转进度」口径一致，故选之。

        协同关系：外推值再经 wrap-aware EMA（Y-A7）二次平滑；server 层
        hold-last（Y-A4）针对「整帧丢失」，本函数针对「帧内在检但数值盲区」，
        两者正交——盲区帧仍是正常检出帧（is_detected=True、held=False），
        不产生任何 held 语义。不新增协议键（仅 roll 数值经外推稳定，键名不变）。

        冷启动即盲区（无锚点）透传 raw roll 一帧（下帧起建锚），备案：无可外推
        基准时透传噪声，属可接受的首帧瞬态。
        """
        out = dict(rotation)
        palm_vec = lm[MIDDLE_MCP] - lm[WRIST]
        xy_len = float(math.hypot(palm_vec[0], palm_vec[1]))
        if xy_len < BLIND_ZONE_XY_MIN:
            if self._roll_last_valid is None or self._roll_last_t is None:
                return out  # 冷启动即盲区：无锚点透传（备案见 docstring）
            dt = max(float(timestamp) - self._roll_last_t, 1e-3)
            rate = max(-BLIND_ZONE_MAX_RATE_DPS,
                       min(BLIND_ZONE_MAX_RATE_DPS, self._roll_rate_dps))
            extrap = (self._roll_last_valid + rate * dt) % 360.0
            out["roll"] = extrap
            # 逐帧滚动锚点（线性积分等价累计外推；盲区期间不更新速度估计，
            # 保持进入前的运动方向锚）
            self._roll_last_valid = extrap
            self._roll_last_t = float(timestamp)
            return out
        # 有效帧：wrap-aware 差分估计角速度（EMA 平滑毛刺）+ 更新锚点
        raw_roll = float(rotation["roll"])
        if self._roll_last_valid is not None and self._roll_last_t is not None:
            dt = max(float(timestamp) - self._roll_last_t, 1e-3)
            diff = ((raw_roll - self._roll_last_valid + 180.0) % 360.0) - 180.0
            rate = diff / dt
            # 批次 Y 扫描回修 P2-5：单帧 wrap 噪声差可达 ~180°（rate≈5400dps；xy 门限
            # 边界抖动/盲区锚点衔接帧高发），原值进 EMA 会以 α=0.3 比例污染估计 → 盲区
            # 外推沿错误方向漂移。进 EMA 前先按 ±BLIND_ZONE_MAX_RATE_DPS 限幅（治本在
            # 源头；外推侧既有二次限幅保留，符号方向不受损）。
            rate = max(-BLIND_ZONE_MAX_RATE_DPS,
                       min(BLIND_ZONE_MAX_RATE_DPS, rate))
            self._roll_rate_dps = (BLIND_ZONE_RATE_ALPHA * rate
                                   + (1.0 - BLIND_ZONE_RATE_ALPHA)
                                   * self._roll_rate_dps)
        else:
            self._roll_rate_dps = 0.0
        self._roll_last_valid = raw_roll
        self._roll_last_t = float(timestamp)
        return out

    def _smooth_rotation(self, rotation: dict) -> dict:
        """roll/pitch/yaw 输出 EMA（Y-A7，常量 ROTATION_EMA_ALPHA）。

        wrap-aware：角度差归一到 [-180,180) 走短弧——roll 359°→3° 沿 4° 方向平滑
        而非爆出 180° 级跳变（盲区侧立场景 Y-A5 的前置保护）。roll 输出归一 [0,360)
        与 _compute_wrist_angles 现状口径一致；pitch/yaw 区间不动。
        """
        out = {}
        for key, val in rotation.items():
            val = float(val)
            prev = self._rotation_ema.get(key)
            if prev is None:
                out[key] = val
            else:
                diff = ((val - prev + 180.0) % 360.0) - 180.0
                out[key] = prev + ROTATION_EMA_ALPHA * diff
            self._rotation_ema[key] = out[key]
        if "roll" in out:
            out["roll"] = (out["roll"] + 360.0) % 360.0
            self._rotation_ema["roll"] = out["roll"]
        return out

    def _smooth_fingers(self, states: list) -> list:
        """fingers[5] 输出 EMA（Y-A7，常量 FINGERS_EMA_ALPHA，轻量一阶低通）。

        分类内核始终消费原始值（见 process），本函数只影响 result["fingers"]。
        """
        if self._fingers_ema is None or len(self._fingers_ema) != len(states):
            self._fingers_ema = [float(v) for v in states]
        else:
            a = FINGERS_EMA_ALPHA
            self._fingers_ema = [
                prev + a * (float(v) - prev)
                for prev, v in zip(self._fingers_ema, states)]
        return list(self._fingers_ema)

    def reset(self) -> None:
        """重置全部时序状态（Y-A6：新手进入该侧时由 server 调用——id 变化=新手，
        老手的滑窗投票/EMA/输出平滑历史不得污染新手判定与输出）。"""
        self._gesture_history.clear()
        self._confidence_history.clear()
        self._smoothed_gesture_id = 21
        self._smoothed_confidence = 0.0
        self._ema_confidence = 0.0
        self._last_result = None
        self._rotation_ema = {}
        self._fingers_ema = None
        # Y-A5：盲区外推状态一并清零（新手进入该侧后按新锚点重建）
        self._roll_last_valid = None
        self._roll_last_t = None
        self._roll_rate_dps = 0.0

    # ------------------------------------------------------------------
    # Pinch 检测
    # ------------------------------------------------------------------

    def _compute_pinch_distance(self, lm: np.ndarray,
                                 palm_size: float) -> float:
        """
        计算归一化捏合距离。

        拇指尖到食指尖的 3D 距离 / 掌心尺度。

        Returns:
            float: 0~1 范围内的归一化距离（0 = 完全捏合）
        """
        thumb_tip = lm[THUMB_TIP]
        index_tip = lm[INDEX_TIP]
        middle_tip = lm[MIDDLE_TIP]

        d1 = np.linalg.norm(thumb_tip - index_tip)
        d2 = np.linalg.norm(thumb_tip - middle_tip)
        min_dist = min(d1, d2)

        if palm_size < 1e-6:
            return 1.0

        normalized = min_dist / (palm_size * 2.0)
        return min(float(normalized), 1.0)

    # ------------------------------------------------------------------
    # 手腕角度检测
    # ------------------------------------------------------------------

    def _compute_wrist_angles(self, landmarks_3d: np.ndarray) -> dict:
        """
        计算手腕3D旋转角度（度）。

        使用手掌平面法向量和宽度向量估算。

        Returns:
            dict: {"roll": 0~360, "pitch": -90~90, "yaw": -180~180}
                roll: 手腕左右旋转
                pitch: 手腕上下翻转
                yaw: 手腕水平旋转（朝向）
        """
        wrist = landmarks_3d[WRIST]
        index_mcp = landmarks_3d[INDEX_MCP]
        middle_mcp = landmarks_3d[MIDDLE_MCP]
        pinky_mcp = landmarks_3d[PINKY_MCP]

        # 手掌平面法向量（中指MCP → 手腕）
        palm_vec = middle_mcp - wrist

        # 手掌宽度向量（食指MCP → 小指MCP）
        width_vec = pinky_mcp - index_mcp

        # roll: 手掌法向量在 XY 平面的角度
        roll = math.degrees(math.atan2(palm_vec[1], palm_vec[0]))

        # pitch: 手掌法向量与 Z 轴夹角（判断手掌朝向）
        pitch = math.degrees(math.atan2(abs(palm_vec[2]),
                           math.sqrt(palm_vec[0]**2 + palm_vec[1]**2)))

        # yaw: 手掌宽度向量与水平面夹角
        yaw = math.degrees(math.atan2(width_vec[2],
                          math.sqrt(width_vec[0]**2 + width_vec[1]**2)))

        return {
            "roll": (roll + 360) % 360,
            "pitch": max(-90, min(90, pitch)),
            "yaw": max(-180, min(180, yaw))
        }

    # ------------------------------------------------------------------
    # 辅助方法
    # ------------------------------------------------------------------

    def _compute_hand_center(self, lm: np.ndarray) -> np.ndarray:
        """计算手部中心（所有关键点的平均位置）。"""
        return np.mean(lm, axis=0)

    @staticmethod
    def _get_timestamp() -> float:
        """获取当前时间戳。"""
        import time
        return time.time()

    @staticmethod
    def _empty_result(timestamp: float) -> dict:
        """返回空结果（未检测到手时）。"""
        return GestureEngine.get_empty_result(timestamp)

    @staticmethod
    def get_empty_result(timestamp: float = None) -> dict:
        """
        公开方法：返回空结果（未检测到手时）。

        Args:
            timestamp: 时间戳，None 时自动生成

        Returns:
            dict: 空结果字典
        """
        if timestamp is None:
            import time
            timestamp = time.time()
        return {
            "gesture": "None",
            "gesture_id": -1,
            "confidence": 0.0,
            "hand_x": 0.0,
            "hand_y": 0.0,
            "hand_z": 0.0,
            "hand_rotation_x": 0.0,
            "hand_rotation_y": 0.0,
            "hand_rotation_z": 0.0,
            "fingers": [0.0, 0.0, 0.0, 0.0, 0.0],
            "pinch_distance": 1.0,
            "palm_size": 0.0,
            "handedness": "Unknown",
            "fps": 0,
            "is_detected": False,
            "timestamp": timestamp,
        }


# ======================================================================
# 工具函数
# ======================================================================

def _confidence_from_fingers(actual: list[float],
                              expected: list[Optional[float]]) -> float:
    """
    根据手指状态计算置信度。

    比较实际手指状态和期望状态，返回 0~1 的置信度。
    expected 中为 None 的项表示不参与评分。

    Args:
        actual: 实际手指状态 [5]
        expected: 期望状态，None 表示忽略
    """
    total_weight = 0.0
    weighted_score = 0.0

    weights = [0.25, 0.25, 0.2, 0.15, 0.15]  # 拇指权重高

    for a, e, w in zip(actual, expected, weights):
        if e is None:
            continue
        # 值越接近，得分越高
        score = 1.0 - min(abs(a - e), 1.0)
        weighted_score += score * w
        total_weight += w

    if total_weight == 0:
        return 0.5

    return weighted_score / total_weight


# ======================================================================
# 独立测试入口
# ======================================================================

if __name__ == "__main__":
    print("=" * 50)
    print("   GestureEngine 单元测试")
    print("=" * 50)

    engine = GestureEngine()

    # 模拟 MediaPipe 格式的关键点 (21, 3)
    # 使用合理的默认值（所有关键点在原点附近）
    dummy_landmarks = np.zeros((21, 3), dtype=np.float32)
    # 设置腕关节
    dummy_landmarks[WRIST] = [0.5, 0.5, 0.0]
    # 中指根部
    dummy_landmarks[MIDDLE_MCP] = [0.5, 0.45, 0.0]
    # 其他关键点粗略填充
    for i in range(1, 21):
        if dummy_landmarks[i].sum() == 0:
            dummy_landmarks[i] = [0.5 + (i % 5 - 2) * 0.02,
                                  0.5 + (i // 5 - 2) * 0.02,
                                  0.0]

    # 测试处理
    result = engine.process(dummy_landmarks, "Right")

    print(f"\n手势: {result['gesture']} (ID: {result['gesture_id']})")
    print(f"置信度: {result['confidence']}")
    print(f"手指状态: {result['fingers']}")
    print(f"手部位置: ({result['hand_x']:.3f}, "
          f"{result['hand_y']:.3f}, {result['hand_z']:.3f})")
    print(f"捏合距离: {result['pinch_distance']:.3f}")
    print(f"旋转角度: ({result['hand_rotation_x']:.3f}, "
          f"{result['hand_rotation_y']:.3f}, "
          f"{result['hand_rotation_z']:.3f})")
    print(f"检测到: {result['is_detected']}")
    print(f"所有字段: {list(result.keys())}")
    print("\n✓ GestureEngine 导入与基础测试通过")

    # ------------------------------------------------------------------
    # 单指后处理测试
    # ------------------------------------------------------------------
    print("\n" + "=" * 50)
    print("   单指后处理单元测试")
    print("=" * 50)

    _all_ok = True

    # 测试1：只伸拇指 [1.0, 0.0, 0.0, 0.0, 0.0]
    fs1 = [0.85, 0.1, 0.1, 0.1, 0.1]
    sid1 = engine._detect_single_finger(fs1)
    expected1 = 22
    if sid1 == expected1:
        print("  ✓ 只伸拇指 → Only_Thumb (22)")
    else:
        print(f"  ✗ 只伸拇指期望 {expected1}，得到 {sid1}")
        _all_ok = False

    # 测试2：只伸食指 [0.0, 1.0, 0.0, 0.0, 0.0]
    fs2 = [0.2, 0.9, 0.1, 0.1, 0.1]
    sid2 = engine._detect_single_finger(fs2)
    expected2 = 23
    if sid2 == expected2:
        print("  ✓ 只伸食指 → Only_Index (23)")
    else:
        print(f"  ✗ 只伸食指期望 {expected2}，得到 {sid2}")
        _all_ok = False

    # 测试3：只伸中指 [0.0, 0.0, 1.0, 0.0, 0.0]
    fs3 = [0.1, 0.2, 0.85, 0.1, 0.1]
    sid3 = engine._detect_single_finger(fs3)
    expected3 = 24
    if sid3 == expected3:
        print("  ✓ 只伸中指 → Only_Middle (24)")
    else:
        print(f"  ✗ 只伸中指期望 {expected3}，得到 {sid3}")
        _all_ok = False

    # 测试4：只伸无名指 [0.0, 0.0, 0.0, 1.0, 0.0]
    fs4 = [0.1, 0.1, 0.2, 0.85, 0.1]
    sid4 = engine._detect_single_finger(fs4)
    expected4 = 25
    if sid4 == expected4:
        print("  ✓ 只伸无名指 → Only_Ring (25)")
    else:
        print(f"  ✗ 只伸无名指期望 {expected4}，得到 {sid4}")
        _all_ok = False

    # 测试5：只伸小指 [0.0, 0.0, 0.0, 0.0, 1.0]
    fs5 = [0.1, 0.1, 0.1, 0.2, 0.85]
    sid5 = engine._detect_single_finger(fs5)
    expected5 = 26
    if sid5 == expected5:
        print("  ✓ 只伸小指 → Only_Pinky (26)")
    else:
        print(f"  ✗ 只伸小指期望 {expected5}，得到 {sid5}")
        _all_ok = False

    # 测试6：两指伸出 → 不应触发
    fs6 = [0.85, 0.85, 0.1, 0.1, 0.1]
    sid6 = engine._detect_single_finger(fs6)
    if sid6 is None:
        print("  ✓ 两指伸出 → 不触发 (None)")
    else:
        print(f"  ✗ 两指伸出期望 None，得到 {sid6}")
        _all_ok = False

    # 测试7：全弯 → 不应触发
    fs7 = [0.1, 0.1, 0.1, 0.1, 0.1]
    sid7 = engine._detect_single_finger(fs7)
    if sid7 is None:
        print("  ✓ 全弯曲 → 不触发 (None)")
    else:
        print(f"  ✗ 全弯曲期望 None，得到 {sid7}")
        _all_ok = False

    # 测试8：边界值 → 阈值边界检测
    fs8 = [0.61, 0.1, 0.1, 0.1, 0.1]  # 拇指刚好超过阈值
    sid8 = engine._detect_single_finger(fs8)
    if sid8 == 22:
        print("  ✓ 边界值(0.61) → 正确触发 Only_Thumb")
    else:
        print(f"  ✗ 边界值(0.61)期望 22，得到 {sid8}")
        _all_ok = False

    # 测试9：0.6 阈值不触发
    fs9 = [0.6, 0.1, 0.1, 0.1, 0.1]  # 刚好等于阈值（不应触发）
    sid9 = engine._detect_single_finger(fs9)
    if sid9 is None:
        print("  ✓ 边界值(0.6 = 阈值) → 不触发")
    else:
        print(f"  ✗ 边界值(0.6)期望 None，得到 {sid9}")
        _all_ok = False

    # 验证 GESTURE_NAMES 有所有新手势
    expected_names = {22: "Only_Thumb", 23: "Only_Index", 24: "Only_Middle",
                      25: "Only_Ring", 26: "Only_Pinky"}
    for gid, gname in expected_names.items():
        if GESTURE_NAMES.get(gid) == gname:
            print(f"  ✓ GESTURE_NAMES[{gid}] = {gname}")
        else:
            print(f"  ✗ GESTURE_NAMES[{gid}] 缺失或错误")
            _all_ok = False

    # 总结果
    if _all_ok:
        print("\n✅ 所有单指测试通过！")
    else:
        print("\n❌ 部分单指测试失败！")

    print("\n✅ 所有测试完成")
