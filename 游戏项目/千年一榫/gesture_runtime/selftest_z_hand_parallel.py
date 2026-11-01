#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 Z（Z-C 波，spec §5-2/3/4 python 侧）——双手并行识别 + handedness 交叉验证 + 丢手补偿。

批次 AA（AA-A 波，spec §4 W1-3）修订：**自证式断言改写为「物理手性真值」口径**——
旧版把「夹具自定义的 label_mp 原样透传」当断言（等于把 W1-1 反向映射的 bug 锁死）。
现口径：夹具给的是 **MediaPipe 模型在该帧上的原始输出**（=「画面中被描绘那只手」的
手性，官方标注图黄金判据 `selftest_aa_handedness.py` 实证），生产 flip=True 喂的是
**cv.flip 后的镜像帧** → 原始输出 = 真手的**镜像身份** = swap(物理侧别)；抽取层
（`_extract_handedness`）须在 flip_image=True 时交换回来。真值来源=物理侧别，
**不取自本工程实现**。

零摄像头纪律：cv/camera_selector/UDPSender 全 mock、landmarker 注入假 results、不开真实设备、
不触碰 9876/9877/9878 真端口（udp_sender 为 MagicMock）。

断言口径（spec §5 验收②③④ + 批次 AA §4.4）：
  ② 双手并行：注入「几何判定同侧冲突」（label_geo 双 Right）而 MediaPipe handedness 相异的
     双手帧 → 两侧均上报（同一包 left/right 非 None）、**槽位 == 物理侧别**、
     两侧 id 不同、**首帧即双侧在场**（无单侧空窗）。
  ③ 左右手判定：MediaPipe handedness 为准（几何降兜底）——注入**物理侧别序列** →
     逐帧输出 100% 等于物理真值；flip_image=True（镜像帧）与 False（原图）两配置
     结论一致（同一真手同一侧别）。
  ④ 丢手补偿：HAND_HOLD_TTL_SEC=0.6——连续零手帧在 hold 窗内 → track held（不判死、
     组包非 null）；超窗 → dead + 组包 null（GDScript 侧才 teardown）。检测/跟踪置信度
     常量 MIN_DETECTION_CONFIDENCE/MIN_TRACKING_CONFIDENCE 就位（竖掌丢手概率下调）。

判绿：unittest 全过，末行输出 SELFTEST PASSED，退出码 0。
"""
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import hand_tracking_server as hts  # noqa: E402


def make_server(flip=True):
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.headless = True
    server.flip_image = flip
    return server


def fake_landmarks(cx=0.5, cy=0.5, thumb_x=0.35, pinky_x=0.55):
    """MediaPipe 形状夹具：21×3 NormalizedLandmark 风格对象（.x/.y/.z）。

    thumb(4)/pinky(17) 的 x 关系供几何判定使用（批次 AA 起可注入）：
      默认 thumb<pinky → `_determine_handedness(mirrored=True)` 判 **Right**
      （=「掌心朝镜、手指朝上」姿态的右手，几何口径与物理侧别同向）；
      thumb>pinky → 几何判 Left。
    """
    pts = [SimpleNamespace(x=cx, y=cy, z=0.0) for _ in range(21)]
    for i in range(21):
        pts[i].x = cx + (i % 5) * 0.01
        pts[i].y = cy + (i // 5) * 0.01
    pts[4].x = thumb_x
    pts[17].x = pinky_x
    return pts


def geo_label(landmarks, mirrored=True):
    """复算几何判定期望（与 _determine_handedness 同式，供夹具构造用）。"""
    return hts.HandTrackingServer._determine_handedness(landmarks, mirrored=mirrored)


def raw_mp_label(physical: str, flip: bool) -> str:
    """MediaPipe 在该帧上的**原始输出**（=「画面中被描绘那只手」的手性）。

    真值入参是**物理侧别**（由夹具声明，不由本工程实现推导）：
      * 生产 flip=True 喂 `cv.flip` 后的**镜像帧** → 镜像使手性外观翻转（官方标注图
        黄金判据 `selftest_aa_handedness.py` 实证：left_hands.jpg → 模型 Left、
        其水平镜像 → 模型 Right）→ 原始输出 = 真手的**镜像身份** = swap(物理侧别)；
      * flip=False（--no-flip 原图）→ 原始输出 = 物理侧别。
    抽取层（`_extract_handedness`）须把原始输出映射回物理侧别（flip=True 时交换）。
    """
    if not flip:
        return physical
    return "Right" if physical == "Left" else "Left"


def make_results(hands):
    """构造 HandLandmarker 风格 results：hands=[(landmarks, label_mp, score), ...]。"""
    hand_landmarks = []
    handedness = []
    for lm, label, score in hands:
        hand_landmarks.append(lm)
        if label is None:
            handedness.append([])
        else:
            handedness.append([SimpleNamespace(category_name=label, score=score)])
    return SimpleNamespace(hand_landmarks=hand_landmarks, handedness=handedness)


def det(cx, cy, label_geo, label_mp=None, score=0.9, lm=None):
    """HandTracker detection 夹具。"""
    return {
        "center": (cx, cy),
        "label_geo": label_geo,
        "label_mp": label_mp,
        "mp_score": score,
        "landmarks": lm if lm is not None else np.zeros((21, 3), dtype=np.float32),
    }


def synth(cx: float, cy: float, thumb_sign: int) -> np.ndarray:
    """21×3 合成 landmark（**镜像形状**：thumb_sign=+1 拇指在图像右侧）。

    批次 AC（2026-09-27）新增：`HAND_MATCH_DIST` 0.35→0.65（spec §4.3-1）后，
    `_is_same_hand` 的 D1 第二档（landmark 缺失/退化 → 中心距兜底）会把中心距 <0.65 的
    **全零 landmark 夹具**判成同一只手（`_landmark_extent`=0 → 无形状信息分支）。双手夹具
    一律改用本函数生成**镜像形状** ndarray：D1 第一档（逐点最大偏差 <0.02）成为唯一判据，
    两只真手（左右互为镜像）即便中心相近也判异手（与 selftest_aa_handedness 同口径）。
    """
    lm = np.zeros((21, 3), dtype=np.float32)
    for i in range(21):
        lm[i] = [cx + (i % 5) * 0.01, cy + (i // 5) * 0.01, 0.0]
    lm[0] = [cx, cy + 0.05, 0.0]
    lm[4] = [cx + 0.05 * thumb_sign, cy + 0.04, 0.0]
    lm[17] = [cx - 0.05 * thumb_sign, cy + 0.02, 0.0]
    return lm


def packets(server):
    out = []
    for call in server.udp_sender.send.call_args_list:
        if call.args and isinstance(call.args[0], dict):
            out.append(call.args[0])
    return out


# ======================================================================
# 段 ②：同侧冲突修正 + 双手并行（首帧即双侧在场）
# ======================================================================

class SameSideConflictTest(unittest.TestCase):
    """几何判定同侧冲突 → 按 MediaPipe handedness 修正 → 两侧均上报。"""

    def test_conflict_resolved_by_mediapipe_handedness(self):
        server = make_server()
        # 几何判定：两只手 thumb 都在 pinky 左侧 → 双双 label_geo="Right"（同侧冲突）；
        # MediaPipe handedness：Left/Right 相异（权威值）。
        # 批次 AC 等价改写：landmark 由全零改**镜像形状**（见 `synth` 函数注）——全零在
        # HAND_MATCH_DIST 0.35→0.65 后会被 D1 第二档按中心距 0.4<0.65 判同手并合并。
        lm_a = fake_landmarks(0.3, 0.4)
        lm_b = fake_landmarks(0.7, 0.4)
        self.assertEqual(geo_label(lm_a)[0], geo_label(lm_b)[0],
                         "前置：几何判定确实同标（冲突构造自检）")
        items, new_ids, dead = server._hand_tracker.update(
            [det(0.3, 0.4, "Right", label_mp="Left", lm=synth(0.30, 0.40, +1)),
             det(0.7, 0.4, "Right", label_mp="Right", lm=synth(0.70, 0.40, -1))],
            time.monotonic())
        sides = sorted(it["label"] for it in items)
        self.assertEqual(sides, ["Left", "Right"],
                         f"同侧冲突须修正为两侧：{[(it['id'], it['label']) for it in items]}")
        idxs = sorted(it["hand_index"] for it in items)
        self.assertEqual(idxs, [0, 1], "两侧 hand_index 必须不同（0/1）")
        ids = {it["id"] for it in items}
        self.assertEqual(len(ids), 2, f"两侧 id 必须不同：{ids}")
        labels = {it["label"]: it["detection"]["label_mp"] for it in items}
        self.assertEqual(labels, {"Left": "Left", "Right": "Right"},
                         "侧别必须与 label_mp 一致（抽取层映射后的**物理侧别**）")
        self.assertGreaterEqual(len(new_ids), 1, "冲突修正的新手须以新 id 注册")

    def test_first_frame_both_sides_in_single_packet(self):
        """首帧即双侧在场：单包 left/right 均非 None，且**槽位 == 物理侧别**（无单侧空窗）。

        批次 AA（W1-3）改写：旧版断言「handedness == 夹具 label_mp 原样」（自证式——
        把 W1-1 反向映射锁死）。现以**几何口径声明的物理侧别**为锚（「掌心朝镜+手指朝上」
        姿态下 `_determine_handedness` 与物理侧别同向，spec §4.2 R1-1：换 mp 权威前几何
        恰好正确），夹具 label_mp 按 `raw_mp_label(物理, flip)` 推导（镜像帧=镜像身份）。
        """
        server = make_server(flip=True)
        server.current_camera_id = 0
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        server.landmarker = mock.MagicMock(name="landmarker")
        lm_left = fake_landmarks(0.3, 0.4, thumb_x=0.55, pinky_x=0.35)
        lm_right = fake_landmarks(0.7, 0.4, thumb_x=0.35, pinky_x=0.55)
        self.assertEqual(geo_label(lm_left, mirrored=True)[0], "Left", "前置：几何判 Left")
        self.assertEqual(geo_label(lm_right, mirrored=True)[0], "Right", "前置：几何判 Right")
        server.landmarker.detect_for_video.return_value = make_results(
            [(lm_left, raw_mp_label("Left", True), 0.92),
             (lm_right, raw_mp_label("Right", True), 0.88)])
        with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f):
            server._process_frame()
        pkts = packets(server)
        self.assertTrue(pkts, "首帧必须发包")
        p0 = pkts[-1]
        self.assertIsNotNone(p0.get("left"), f"首帧左包缺失（单侧空窗）：{p0.keys()}")
        self.assertIsNotNone(p0.get("right"), f"首帧右包缺失（单侧空窗）：{p0.keys()}")
        self.assertEqual(p0["left"].get("handedness"), "Left",
                         "左手 handedness 必须 == 物理侧别 Left")
        self.assertEqual(p0["right"].get("handedness"), "Right",
                         "右手 handedness 必须 == 物理侧别 Right")
        # 槽位 ↔ landmark 身份锚：防「标签对了但手放错槽」
        self.assertAlmostEqual(float(p0["left"]["landmarks"][8][0]), lm_left[8].x, places=3,
                               msg="左槽必须是「物理左手」那只手的 landmark")
        self.assertAlmostEqual(float(p0["right"]["landmarks"][8][0]), lm_right[8].x, places=3,
                               msg="右槽必须是「物理右手」那只手的 landmark")
        self.assertNotEqual(p0["left"].get("id"), p0["right"].get("id"),
                            "两侧 id 必须不同")
        self.assertEqual(p0["left"].get("hand_index"), 0)
        self.assertEqual(p0["right"].get("hand_index"), 1)


# ======================================================================
# 段 ③：handedness 映射（物理侧别真值 / MediaPipe 为准 / 几何兜底 / 镜像交换）
# ======================================================================

class HandednessSequenceTest(unittest.TestCase):
    def _feed_one(self, physical, score, flip=True):
        """单帧单手 → 该帧输出侧别（每帧独立 server：手性映射按帧独立评估）。"""
        server = make_server(flip=flip)
        server.landmarker = mock.MagicMock()
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        server.landmarker.detect_for_video.return_value = make_results(
            [(fake_landmarks(0.5, 0.4), raw_mp_label(physical, flip), score)])
        with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f):
            server._process_frame()
        p = packets(server)[-1]
        hand = p.get("left") or p.get("right")
        return None if hand is None else hand.get("handedness")

    _PHYSICAL = [("Left", 0.9), ("Right", 0.85), ("Left", 0.95),
                 ("Right", 0.7), ("Left", 0.9), ("Left", 0.99)]

    def test_physical_sequence_100pct_flip_true(self):
        """生产默认（flip=True 镜像帧）：逐帧输出须 100% 等于**物理侧别**序列。

        批次 AC（§4.3-2）等价改写留痕：旧版在**同一 server 上连续喂同一只手的 6 帧**并
        断言逐帧侧别跟随 mp 标签翻转（Left→Right→Left…）——该前提在 AC 起不再成立：
        「单手连续跟踪期间 side 与 id 严格锁定」（单帧 mp 分类跳变不得翻转手性，防红蓝双
        骨架）。物理上同一只手也不会逐帧变性，故改为**逐帧独立 server**（等价于每帧一只
        新手）验证手性映射正确性，并另加「连续单手侧别锁定」反向断言（见
        `test_continuous_single_hand_side_locked`）——断言强度不降（6 帧映射逐一校验）。
        """
        got = [self._feed_one(p, s, flip=True) for p, s in self._PHYSICAL]
        self.assertEqual(got, [p for p, _ in self._PHYSICAL],
                         f"物理侧别序列须 100% 正确（镜像帧 raw=镜像身份）：{got}")

    def test_physical_sequence_100pct_flip_false(self):
        """flip=False（原图）：同一物理序列结论必须一致（两配置同真手同侧别）。"""
        got = [self._feed_one(p, s, flip=False) for p, s in self._PHYSICAL]
        self.assertEqual(got, [p for p, _ in self._PHYSICAL],
                         f"非镜像配置下物理侧别序列同样 100% 正确：{got}")

    def test_continuous_single_hand_side_locked(self):
        """批次 AC（§4.3-2）：同一 server 上连续 6 帧单手，mp 标签翻转不得改变输出侧别。"""
        server = make_server(flip=True)
        server.landmarker = mock.MagicMock()
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        got = []
        for physical, score in self._PHYSICAL:
            server.landmarker.detect_for_video.return_value = make_results(
                [(fake_landmarks(0.5, 0.4), raw_mp_label(physical, flip=True), score)])
            server.udp_sender.send.reset_mock()
            with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f):
                server._process_frame()
            p = packets(server)[-1]
            hand = p.get("left") or p.get("right")
            got.append(None if hand is None else hand.get("handedness"))
        self.assertEqual(got[0], "Left", "首帧按 mp 判定=物理左手")
        self.assertEqual(set(got), {"Left"},
                         f"AC §4.3-2：连续单手侧别必须全程锁定（旧版逐帧 mp 翻转=红蓝双骨架）：{got}")

    def test_geometry_only_fallback_without_mediapipe(self):
        """MediaPipe handedness 缺失（None）→ 几何判定兜底仍可用（镜像口径 Right）。"""
        server = make_server(flip=True)
        items, _, _ = server._hand_tracker.update(
            [det(0.5, 0.4, geo_label(fake_landmarks(0.5, 0.4))[0], label_mp=None)],
            time.monotonic())
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["label"], "Right",
                         "mp 缺失 → 几何兜底（thumb<pinky 镜像口径=Right）")

    def test_extraction_maps_raw_label_to_physical_side(self):
        """W1-1 映射口径（批次 AA 重写，spec §4.3 W1-1）：**镜像输入 → 交换采用**。

        旧断言 `test_no_flip_swaps_mediapipe_label` 把反向映射（flip=True 原样采用、
        flip=False 才交换）写成预期 = 自证式锁死 bug，已按物理真值口径重写：
          * flip=True（生产默认，帧已 cv.flip）→ 模型原始标签是**镜像身份** → 抽取层交换；
          * flip=False（原图）→ 模型原始标签即物理侧别 → 原样采用。
        真值来源=官方标注图黄金判据（`selftest_aa_handedness.py`），非本实现推导。
        """
        results = make_results([(fake_landmarks(0.5, 0.4), "Right", 0.9)])
        s_flip = make_server(flip=True)
        self.assertEqual(s_flip._extract_handedness(results)[0][0], "Left",
                         "镜像输入（生产 cv.flip 后）：模型原始 Right = 物理左手 → 须交换为 Left")
        s_raw = make_server(flip=False)
        self.assertEqual(s_raw._extract_handedness(results)[0][0], "Right",
                         "非镜像输入：模型原始 Right = 物理右手 → 原样采用")
        # 全链路一致：抽取 → HandTracker 侧别
        items, _, _ = s_flip._hand_tracker.update(
            [det(0.5, 0.4, "Left", label_mp=s_flip._extract_handedness(results)[0][0])],
            time.monotonic())
        self.assertEqual(items[0]["label"], "Left", "交换后 mp 值成为 track 侧别（物理 Left）")


# ======================================================================
# 段 ⑤：修复5（批次Z走查 P2）——mp 改判 score 下限（低分抖动帧不得换 id）
# ======================================================================

class MpScoreFloorTest(unittest.TestCase):
    """mp 主判改判须过 score 下限（MP_RELABEL_MIN_SCORE=0.6）。

    缺陷：_resolve_sides 的 mp 主判改判**无 score 门槛**——低分 mp 标签一帧抖动即
    _relabel_track 换 id → GDScript 据 id 变化清该侧累计态 → 翻转配对/缩放被打断。
    处置选 score 下限（非 2 帧确认）：零新增状态、零纠错延迟、判据单一（MediaPipe
    handedness score 本身即分类置信度，低于 0.6 视同缺失走粘性/几何兜底）。

    批次 AC（§4.3-2）等价改写：**单手**分支自本批起完全锁定侧别（零 relabel，不论
    score 高低）——旧「高分纠错照常换 id」断言随拍板退役（单手连续跟踪期间手性强
    连续锁定=用户症状主治）；**多手**域的 score 门语义逐条保持（本类新增多手段落）。
    """

    def test_relabel_score_floor_constant(self):
        self.assertAlmostEqual(hts.MP_RELABEL_MIN_SCORE, 0.6,
                               msg="修复5：mp 改判 score 下限=0.6（<0.6 视同 mp 缺失）")

    def test_low_score_mp_single_hand_no_relabel(self):
        """单手：低分（0.3<0.6）**与高分（0.9）**抖动帧均不得换 id（AC 强连续锁定）。"""
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        items, new_ids, _ = tr.update(
            [det(0.5, 0.4, "Left", label_mp="Left", score=0.9)], t0)
        self.assertEqual(len(new_ids), 1, "首帧新手注册")
        orig_id = items[0]["id"]
        self.assertEqual(items[0]["label"], "Left")
        # 抖动帧：mp 标签翻到 Right 但 score=0.3 < 0.6 → 不得 relabel（换 id 清累计态）
        items2, changed2, _ = tr.update(
            [det(0.5, 0.4, "Left", label_mp="Right", score=0.3)], t0 + 0.033)
        self.assertEqual(changed2, [],
                         f"低分 mp（0.3<0.6）不得触发改判换 id：{changed2}")
        self.assertEqual(items2[0]["id"], orig_id, "低分抖动帧 id 必须保持")
        self.assertEqual(items2[0]["label"], "Left",
                         "低分 mp 视同缺失 → 粘性保持原侧（翻转配对/缩放累计态不被打断）")
        # 批次 AC（§4.3-2）等价改写：**高分**（0.9≥0.6）单手抖动帧同样不得改判——
        # 旧断言「高分纠错照常换 id（mp 权威契约零回归）」在单手域退役（用户 2026-09-27 拍板：
        # 单手连续跟踪强锁手性，防红蓝双骨架）；多手域 mp 权威不受影响（见下条）。
        items3, changed3, _ = tr.update(
            [det(0.5, 0.4, "Left", label_mp="Right", score=0.9)], t0 + 0.066)
        self.assertEqual(changed3, [],
                         f"AC §4.3-2：单手连续跟踪期间高分 mp 亦不得改判：{changed3}")
        self.assertEqual(items3[0]["id"], orig_id, "AC：单身高分抖动帧 id 必须保持")
        self.assertEqual(items3[0]["label"], "Left", "AC：单手侧别强连续锁定")
        self.assertEqual(len(tr.tracks()), 1, "全程恒 1 条 track（零 ghost 双骨架）")

    def test_high_score_mp_two_hand_correction_kept(self):
        """批次 AC 反向护栏：**多手**域 mp 权威纠错零回归（单手锁不越界）。"""
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        items, _, _ = tr.update(
            [det(0.2, 0.4, "Left", label_mp="Left", score=0.9, lm=synth(0.2, 0.4, +1)),
             det(0.85, 0.4, "Right", label_mp="Right", score=0.9, lm=synth(0.85, 0.4, -1))],
            t0)
        self.assertEqual(len([it for it in items if not it["held"]]), 2, "首帧双侧注册")
        items2, changed2, _ = tr.update(
            [det(0.2, 0.4, "Left", label_mp="Right", score=0.9, lm=synth(0.2, 0.4, +1)),
             det(0.85, 0.4, "Right", label_mp="Left", score=0.9, lm=synth(0.85, 0.4, -1))],
            t0 + 0.033)
        self.assertEqual(len(changed2), 2,
                         f"多手域 mp 高分交换必须照常纠错换 id：{changed2}")
        labels = sorted(it["label"] for it in items2 if not it["held"])
        self.assertEqual(labels, ["Left", "Right"], "改判后两侧仍在（hand_index 相异）")

    def test_low_score_mp_two_hand_no_swap(self):
        """低分双侧交换抖动帧 → 两侧均不得换 id（分支① mp 权威同样过下限）。"""
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        items, _, _ = tr.update(
            [det(0.3, 0.4, "Left", label_mp="Left", score=0.9, lm=synth(0.30, 0.40, +1)),
             det(0.7, 0.4, "Left", label_mp="Right", score=0.9, lm=synth(0.70, 0.40, -1))], t0)
        ids0 = {it["id"]: it["label"] for it in items if not it["held"]}
        self.assertEqual(len(ids0), 2, "首帧双侧注册")
        items2, changed2, _ = tr.update(
            [det(0.3, 0.4, "Left", label_mp="Right", score=0.3, lm=synth(0.30, 0.40, +1)),
             det(0.7, 0.4, "Left", label_mp="Left", score=0.3, lm=synth(0.70, 0.40, -1))],
            t0 + 0.033)
        self.assertEqual(changed2, [], f"低分双侧交换不得换 id：{changed2}")
        ids1 = {it["id"]: it["label"] for it in items2 if not it["held"]}
        self.assertEqual(ids1, ids0, "低分抖动后两侧 id/侧别逐一对比保持")


# ======================================================================
# 段 ④：丢手补偿（HAND_HOLD_TTL_SEC=0.6 + 置信度常量）
# ======================================================================

class HoldCompensationTest(unittest.TestCase):
    def test_hold_ttl_constant_0p6(self):
        self.assertAlmostEqual(hts.HAND_HOLD_TTL_SEC, 0.6,
                               msg="Z5-4：HAND_HOLD_TTL_SEC 0.3→0.6（竖掌整帧丢手补偿窗）")

    def test_detection_confidence_constants(self):
        self.assertLessEqual(hts.MIN_DETECTION_CONFIDENCE, 0.55,
                             "Z5-4：min_hand_detection 置信度下调（竖掌检不出概率）")
        self.assertLessEqual(hts.MIN_TRACKING_CONFIDENCE, 0.45,
                             "Z5-4：min_tracking 置信度下调")
        with mock.patch.object(hts, "CameraSelector"), \
             mock.patch.object(hts, "UDPSender"):
            s = hts.HandTrackingServer(udp_port=4242)
        self.assertAlmostEqual(s.min_detection_confidence, hts.MIN_DETECTION_CONFIDENCE)
        self.assertAlmostEqual(s.min_tracking_confidence, hts.MIN_TRACKING_CONFIDENCE)

    def test_zero_hand_frames_hold_within_window(self):
        """连续零手帧（时长 < hold 窗）→ track 保留 held 数据（不判死、组包非 null）。"""
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        items, new_ids, _ = tr.update(
            [det(0.5, 0.4, "Left", label_mp="Left")], t0)
        self.assertEqual(len(new_ids), 1)
        # 回写 last_result（server 组包数据源）
        track = items[0]["track"]
        track["last_result"] = {"handedness": "Left", "hand_index": 0,
                                "is_detected": True, "held": False,
                                "fingers": [0.0] * 5,
                                "landmarks": [[0.0, 0.0]] * 21}
        # 窗内零手帧（0.55s < 0.6s）：held 保留、非 dead
        items2, _, dead2 = tr.update([], t0 + 0.55)
        self.assertEqual(dead2, [], f"0.55s<0.6s 窗内不得判死：{dead2}")
        self.assertEqual(len(items2), 1)
        self.assertTrue(items2[0]["held"], "窗内零手帧 → held=True（GDScript 不 teardown）")
        self.assertIsNotNone(items2[0]["track"]["last_result"],
                             "held 帧组包数据源在位（非 null）")

    def test_zero_hand_frames_beyond_window_dead_and_null(self):
        """超窗（0.65s>0.6s）→ dead（组包侧 left/right 置 null 的前置）。"""
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        items, new_ids, _ = tr.update(
            [det(0.5, 0.4, "Left", label_mp="Left")], t0)
        self.assertEqual(len(new_ids), 1)
        items2, _, dead2 = tr.update([], t0 + 0.65)
        self.assertEqual([d["id"] for d in dead2], [items[0]["id"]],
                         "超窗 → track 判死（组包 null / 滤波器复位前置）")
        self.assertEqual(items2, [], "判死后无 items")


# ======================================================================
# 段 ④+：_process_frame 级零手帧组包（held→非 null，超窗→null）
# ======================================================================

class PacketLevelHoldTest(unittest.TestCase):
    def test_packets_held_then_null(self):
        server = make_server()
        server.current_camera_id = 0
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        server.landmarker = mock.MagicMock()
        # 批次 AA（W1-3）：夹具按物理真值「左手」声明 → 镜像帧原始标签 = 镜像身份 Right
        server.landmarker.detect_for_video.return_value = make_results(
            [(fake_landmarks(0.5, 0.4), raw_mp_label("Left", True), 0.9)])
        with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f):
            server._process_frame()
        p_first = packets(server)[-1]
        self.assertIsNotNone(p_first.get("left"), "首帧左手在")
        self.assertIsNone(p_first.get("right"), "首帧仅左手")
        # 连续零手帧：窗内 held（非 null），跨窗 null
        server.landmarker.detect_for_video.return_value = make_results([])
        server.udp_sender.send.reset_mock()
        # 拨 track 时钟模拟 0.5s 整帧丢手（窗内）
        for tr in server._hand_tracker.tracks().values():
            tr["last_seen"] = time.monotonic() - (hts.HAND_HOLD_TTL_SEC - 0.1)
        with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f):
            server._process_frame()
        p_hold = packets(server)[-1]
        self.assertIsNotNone(p_hold.get("left"),
                             "hold 窗内整帧零手 → 左包仍非 null（held；GDScript 不 teardown）")
        self.assertTrue(p_hold["left"].get("held"), "held 标记在位")
        # 超窗（拨到 0.7s 前）→ dead → null
        server.udp_sender.send.reset_mock()
        for tr in server._hand_tracker.tracks().values():
            tr["last_seen"] = time.monotonic() - (hts.HAND_HOLD_TTL_SEC + 0.1)
        with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f):
            server._process_frame()
        p_over = packets(server)[-1]
        self.assertIsNone(p_over.get("left"),
                          "超 hold 窗整帧零手 → 左包 null（GDScript 才 teardown）")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
