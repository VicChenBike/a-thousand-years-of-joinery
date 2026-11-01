#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批次 AA（AA-A 波，spec §4 W1 手性域）——黄金判据 + 同手守卫 + 检出去重 + ghost 丢弃
+ `_initial_side` score 下限 + 心跳 `stale` 字段 + 诊断三字段透传。

零摄像头纪律（spec §2.1 / 用户 2026-09-24 硬性指示）：
  * `HandTrackingServer` 只构造不开镜（`start()` 不被调用，`cv2.VideoCapture` 不实例化）；
  * landmarker 为 MagicMock，或 MediaPipe **离线模型**读**本地 JPEG**（不取流）；
  * `UDPSender`/`CameraSelector` 全 mock，不触碰 9876/9877/9878 真端口。
  全程零真实摄像头设备调用。

黄金判据真值来源（**独立于本工程实现**，spec §21.1 附录 A）：
  1) MediaPipe 官方标注图 `left_hands.jpg` / `right_hands.jpg`，sha256 与 google/mediapipe
     `third_party/external_files.bzl` 声明值**全 64 位**比对（`thumb_up.jpg` 声明值前 8 位
     = `5d673c08`，本文件存全 64 位）；
  2) 人眼目视核验（实施方 2026-09-25，证据=仓库内原图）：两图均为**手背朝向镜头**的
     两只左手 / 两只右手（`right_hands.jpg` 是 `left_hands.jpg` 的水平镜像，像素级实测
     平均差 0.04）；
  3) **独立叉积手性算法**（腕 0 / 食指根 5 / 小指根 17 构成掌面 + 图像 y 向下坐标系）
     与模型标签逐只比对——同向才判通过。

TDD 口径：修复前跑本文件必须判红（红在 R1-a/b/c/d/e/f + stale + 诊断字段上）；
修复后全绿 + 退出码 0 = `SELFTEST PASSED`。
"""
import atexit
import hashlib
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np

_GESTURE_DIR = Path(__file__).resolve().parent.parent
if str(_GESTURE_DIR) not in sys.path:
    sys.path.insert(0, str(_GESTURE_DIR))

import cv2 as cv  # noqa: E402
import hand_tracking_server as hts  # noqa: E402
from mediapipe.tasks.python import vision as mp_vision  # noqa: E402

FIXTURE_DIR = Path(__file__).resolve().parent / "tests" / "fixtures" / "handedness"
MODEL_SRC = Path(__file__).resolve().parent / "models" / "hand_landmarker.task"

# google/mediapipe third_party/external_files.bzl 声明值（全 64 位；thumb_up 前 8 位=5d673c08）
SHA256_OFFICIAL = {
    "left_hands.jpg": "240c082e80128ff1ca8a83ce645e2ba4d8bc30f0967b7991cf5fa375bab489e1",
    "right_hands.jpg": "4b5134daa4cb60465535239535f9f74c2842aba3aa5fd30bf04ef5678f93d87f",
    "thumb_up.jpg": "5d673c081ab13b8a1812269ff57047066f9c33c07db5f4178089e8cb3fdc0291",
}

# 夹具视向（人眼核验，见文件头注）：两图均手背朝向镜头 → 叉积判据取「背面」分支。
PALM_FACING_CAMERA = False

# 模型工作目录必须为 ASCII 路径（C++ 层打不开中文路径，历次探针实证）
_TMP_DIR: Path | None = None
_DETECTORS: dict = {}
_VIDEO_TS = [1000]


def _ascii_workdir() -> Path:
    """把模型复制到 ASCII 临时目录（一次性；进程退出自动清理）。"""
    global _TMP_DIR
    if _TMP_DIR is None:
        d = Path(tempfile.mkdtemp(prefix="aa_handedness_"))
        shutil.copyfile(MODEL_SRC, d / "hand_landmarker.task")
        _TMP_DIR = d
        atexit.register(lambda: shutil.rmtree(str(d), ignore_errors=True))
    return _TMP_DIR


def _detector(running_mode):
    """按 running_mode 惰性创建 HandLandmarker（IMAGE / VIDEO 各一实例）。"""
    key = str(running_mode)
    if key not in _DETECTORS:
        from mediapipe.tasks import python as mp_python
        opts = mp_vision.HandLandmarkerOptions(
            base_options=mp_python.BaseOptions(
                model_asset_path=str(_ascii_workdir() / "hand_landmarker.task")),
            running_mode=running_mode,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5)
        det = mp_vision.HandLandmarker.create_from_options(opts)
        _DETECTORS[key] = det
        # 退出期 close 可能因线程池已停抛异常（仅打印不改退出码）——静默兜底
        atexit.register(lambda d=det: _safe_close(d))
    return _DETECTORS[key]


def _safe_close(det) -> None:
    try:
        det.close()
    except Exception:
        pass


def read_bgr(name: str) -> np.ndarray:
    """Python 侧读字节 + imdecode（避开 Windows 中文路径的 cv2.imread 编码坑）。"""
    raw = (FIXTURE_DIR / name).read_bytes()
    img = cv.imdecode(np.frombuffer(raw, dtype=np.uint8), cv.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(f"无法解码夹具: {name}")
    return img


def _mp_image(bgr: np.ndarray):
    import mediapipe as mp
    return mp.Image(image_format=mp.ImageFormat.SRGB,
                    data=cv.cvtColor(bgr, cv.COLOR_BGR2RGB))


def detect_image(bgr: np.ndarray):
    """IMAGE 模式检测 → (labels, landmarks)（labels=逐手 category_name）。"""
    res = _detector(mp_vision.RunningMode.IMAGE).detect(_mp_image(bgr))
    labels = [(cats[0].category_name if cats else None) for cats in (res.handedness or [])]
    return labels, list(res.hand_landmarks or [])


def detect_video(bgr: np.ndarray, frames: int = 4):
    """VIDEO 模式连续喂同一帧 frames 次 → 逐帧 labels 列表。"""
    det = _detector(mp_vision.RunningMode.VIDEO)
    out = []
    for _ in range(frames):
        _VIDEO_TS[0] += 33
        res = det.detect_for_video(_mp_image(bgr), _VIDEO_TS[0])
        out.append([(c[0].category_name if c else None) for c in (res.handedness or [])])
    return out


def _cz(lms) -> float:
    """掌面叉积 z 分量（腕 0 / 食指根 5 / 小指根 17；图像 y 向下）。"""
    w, i5, p17 = lms[0], lms[5], lms[17]
    return (i5.x - w.x) * (p17.y - w.y) - (i5.y - w.y) * (p17.x - w.x)


def cross_handedness(lms, palm_facing_camera: bool = PALM_FACING_CAMERA) -> str:
    """独立叉积手性算法（不依赖 MediaPipe handedness 分类头）。

    掌面朝向 + 图像 x 轴（y 向下）：cz 对**面内旋转不变**（同图两手一正一倒仍同号），
    对**镜像/翻面变号**。掌面朝镜时 cz>0 → 左手；手背朝镜（本夹具）→ 取反。
    """
    left = (_cz(lms) > 0.0) if palm_facing_camera else (_cz(lms) < 0.0)
    return "Left" if left else "Right"


def simple_landmarks(lms):
    """mediapipe NormalizedLandmark → SimpleNamespace（脱离 mediapipe 对象依赖）。"""
    return [SimpleNamespace(x=float(p.x), y=float(p.y), z=float(p.z)) for p in lms]


def make_results(hands):
    """构造 HandLandmarker 风格 results：hands=[(landmarks, label_mp, score), ...]。

    landmarks 支持两种夹具形态：SimpleNamespace 列表（.x/.y/.z）或 21×3 np.ndarray
    （自动转 SimpleNamespace——`_process_frame` 逐点读 lm.x/.y/.z）。
    """
    hand_landmarks, handedness = [], []
    for lm, label, score in hands:
        if isinstance(lm, np.ndarray):
            lm = [SimpleNamespace(x=float(p[0]), y=float(p[1]), z=float(p[2])) for p in lm]
        hand_landmarks.append(lm)
        if label is None:
            handedness.append([])
        else:
            handedness.append([SimpleNamespace(category_name=label, score=score)])
    return SimpleNamespace(hand_landmarks=hand_landmarks, handedness=handedness)


def make_server(flip: bool = True):
    with mock.patch.object(hts, "CameraSelector"), \
         mock.patch.object(hts, "UDPSender"):
        server = hts.HandTrackingServer(udp_port=4242)
    server.camera_selector = mock.MagicMock(name="camera_selector")
    server.udp_sender = mock.MagicMock(name="udp_sender")
    server.landmarker = mock.MagicMock(name="landmarker")
    server.headless = True
    server.flip_image = flip
    # 零摄像头硬保险：任何路径都不允许触发真实开镜/重连
    server.current_camera_id = 0
    server._camera_intentionally_released = True
    return server


def det(cx, cy, label_geo, label_mp=None, score=0.9, lm=None):
    return {
        "center": (cx, cy),
        "label_geo": label_geo,
        "label_mp": label_mp,
        "mp_score": score,
        "landmarks": lm if lm is not None else np.zeros((21, 3), dtype=np.float32),
    }


def packets(server):
    out = []
    for call in server.udp_sender.send.call_args_list:
        if call.args and isinstance(call.args[0], dict):
            out.append(call.args[0])
    return out


def run_frame(server, hands):
    """喂一帧 mock 检出 → 返回本帧顶层包。cv.cvtColor mock（零真实图像处理）。"""
    server.landmarker.detect_for_video.return_value = make_results(hands)
    server.udp_sender.send.reset_mock()
    if server._latest_frame is None:
        server._latest_frame = np.zeros((480, 640, 3), dtype=np.uint8)
    with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f), \
            mock.patch.object(server, "_attempt_reconnect"):
        server._process_frame()
    return packets(server)[-1]


def synth_landmarks(cx: float, cy: float, thumb_sign: int) -> np.ndarray:
    """21×3 合成 landmark：thumb_sign=+1 拇指在 pinky 右侧（几何判 Left）/ −1 左侧（Right）。"""
    lm = np.zeros((21, 3), dtype=np.float32)
    for i in range(21):
        lm[i] = [cx + (i % 5) * 0.01, cy + (i // 5) * 0.01, 0.0]
    lm[0] = [cx, cy + 0.05, 0.0]
    lm[4] = [cx + 0.05 * thumb_sign, cy + 0.04, 0.0]
    lm[17] = [cx - 0.05 * thumb_sign, cy + 0.02, 0.0]
    return lm


def raw_mp_label(physical: str, flip: bool = True) -> str:
    """MediaPipe 在该帧上的**原始输出**（与 `selftest_z_hand_parallel.raw_mp_label` 同口径）。

    真值入参=**物理侧别**：生产 flip=True 喂 cv.flip 后的镜像帧 → 镜像使手性外观翻转
    （本文件黄金判据实证）→ 原始输出 = 真手的**镜像身份** = swap(物理侧别)；
    flip=False（原图）→ 原始输出 = 物理侧别。喂 `_process_frame` 的夹具一律经此换算。
    """
    if not flip:
        return physical
    return "Right" if physical == "Left" else "Left"


def packet_side(pkt: dict) -> str:
    """包 → 侧别："left"/"right"/""（双侧同现或全空 → ""）。"""
    l, r = pkt.get("left"), pkt.get("right")
    if l is not None and r is None:
        return "left"
    if r is not None and l is None:
        return "right"
    return ""


# ======================================================================
# 段 ①：素材校验（恒绿前提——真值源可信）
# ======================================================================

class FixtureIntegrityTest(unittest.TestCase):
    def test_fixture_sha256_matches_official_declaration_full_64(self):
        for name, want in SHA256_OFFICIAL.items():
            got = hashlib.sha256((FIXTURE_DIR / name).read_bytes()).hexdigest()
            self.assertEqual(got, want, f"{name} sha256 须与官方 external_files.bzl 全 64 位一致")
        self.assertTrue(SHA256_OFFICIAL["thumb_up.jpg"].startswith("5d673c08"),
                        "thumb_up.jpg 声明值前 8 位=5d673c08（spec §21.1 A-3）")

    def test_right_hands_is_horizontal_mirror_of_left_hands(self):
        left, right = read_bgr("left_hands.jpg"), read_bgr("right_hands.jpg")
        diff = float(np.abs(cv.flip(left, 1).astype(int) - right.astype(int)).mean())
        self.assertLess(diff, 1.0, f"right_hands 应为 left_hands 水平镜像（实测平均差 {diff:.3f}）")


# ======================================================================
# 段 ②：黄金判据（模型标签 = 「画面中被描绘那只手」的手性；恒绿前提）
# ======================================================================

class GoldenModelLabelTest(unittest.TestCase):
    """spec §21.1 A-3.2/A-3.3/A-3.4——模型侧真值，独立于本工程实现。"""

    @classmethod
    def setUpClass(cls):
        cls.left = read_bgr("left_hands.jpg")
        cls.right = read_bgr("right_hands.jpg")
        cls.left_mirror = cv.flip(cls.left, 1)

    def test_image_mode_labels_describe_depicted_hand(self):
        labels_l, _ = detect_image(self.left)
        labels_r, _ = detect_image(self.right)
        labels_m, _ = detect_image(self.left_mirror)
        self.assertEqual(labels_l, ["Left", "Left"],
                         "官方 left_hands.jpg（两只左手）→ 模型输出 Left")
        self.assertEqual(labels_r, ["Right", "Right"],
                         "官方 right_hands.jpg（两只右手）→ 模型输出 Right")
        self.assertEqual(labels_m, ["Right", "Right"],
                         "left_hands 水平镜像（本工程生产路径输入形态）→ 模型输出 Right")

    def test_video_mode_consistent_with_image_mode(self):
        seq_raw = detect_video(self.left, frames=4)
        seq_mirror = detect_video(self.left_mirror, frames=4)
        for seq, want, tag in ((seq_raw, ["Left", "Left"], "原图"),
                               (seq_mirror, ["Right", "Right"], "镜像")):
            non_empty = [s for s in seq if s]
            self.assertTrue(non_empty, f"VIDEO 模式 {tag} 至少一帧须检出")
            for s in non_empty:
                self.assertEqual(s, want, f"VIDEO 模式 {tag} 与 IMAGE 模式须一致：{s}")
            self.assertEqual(seq[-1], want, f"VIDEO 模式 {tag} 末帧须检出且标签正确")

    def test_independent_cross_product_agrees_with_model(self):
        det = _detector(mp_vision.RunningMode.IMAGE)
        for name, img in (("left_hands.jpg", self.left),
                          ("right_hands.jpg", self.right),
                          ("left_hands.jpg(镜像)", self.left_mirror)):
            res = det.detect(_mp_image(img))
            labels = [(c[0].category_name if c else None) for c in (res.handedness or [])]
            for k, lms in enumerate(res.hand_landmarks):
                mine = cross_handedness(lms, PALM_FACING_CAMERA)
                self.assertEqual(mine, labels[k],
                                 f"{name} hand{k}：叉积={mine} vs 模型={labels[k]} 须同向")
            self.assertEqual(len(set(labels)), 1,
                             f"{name} 两只手标签须一致（面内旋转不变）：{labels}")

    def test_mirror_flips_both_model_label_and_chirality(self):
        det = _detector(mp_vision.RunningMode.IMAGE)
        res_a = det.detect(_mp_image(self.left))
        res_b = det.detect(_mp_image(self.left_mirror))
        lab_a = res_a.handedness[0][0].category_name
        lab_b = res_b.handedness[0][0].category_name
        self.assertNotEqual(lab_a, lab_b, "水平镜像必须翻转模型标签（镜像=镜像身份）")
        self.assertLess(_cz(res_a.hand_landmarks[0]) * _cz(res_b.hand_landmarks[0]), 0.0,
                        "水平镜像必须翻转叉积符号（手性外观翻转）")


# ======================================================================
# 段 ③：生产链黄金判据（R1-a/R1-b —— 修复前必红）
# ======================================================================

class ProductionChainGoldenTest(unittest.TestCase):
    """spec §21.1 A-3.6：物理左手 + flip_image=True（生产默认）→ 包内 left。"""

    @classmethod
    def setUpClass(cls):
        left = read_bgr("left_hands.jpg")
        right = read_bgr("right_hands.jpg")
        # 生产路径输入 = 采集线程 cv.flip 后的帧（读取线程镜像保持不变，只改标签映射）
        lab_ml, lmk_ml = detect_image(cv.flip(left, 1))
        lab_mr, lmk_mr = detect_image(cv.flip(right, 1))
        lab_lr, lmk_lr = detect_image(left)
        lab_rr, lmk_rr = detect_image(right)
        # 取 hand0（模型逐手同标签，见 GoldenModelLabelTest 旋转不变断言）
        cls.mirror_left = (simple_landmarks(lmk_ml[0]), lab_ml[0], 0.95)
        cls.mirror_right = (simple_landmarks(lmk_mr[0]), lab_mr[0], 0.95)
        cls.raw_left = (simple_landmarks(lmk_lr[0]), lab_lr[0], 0.95)
        cls.raw_right = (simple_landmarks(lmk_rr[0]), lab_rr[0], 0.95)

    def test_mirror_frame_model_label_is_mirrored_identity(self):
        """前提（恒绿）：生产路径输入（镜像帧）里模型给的是「被描绘手」= 镜像身份标签。"""
        self.assertEqual(self.mirror_left[1], "Right",
                         "物理左手在镜像帧中被描绘成右手 → 模型输出 Right")
        self.assertEqual(self.mirror_right[1], "Left",
                         "物理右手在镜像帧中被描绘成左手 → 模型输出 Left")
        self.assertEqual(self.raw_left[1], "Left", "非镜像帧物理左手 → 模型输出 Left")
        self.assertEqual(self.raw_right[1], "Right", "非镜像帧物理右手 → 模型输出 Right")

    def test_r1a_physical_left_in_mirror_frame_yields_left_packet(self):
        """R1-a：镜像帧输入「物理左手」→ 期望包内 left（现状得 right → 判红）。"""
        lm, label, score = self.mirror_left
        pkt = run_frame(make_server(flip=True), [(lm, label, score)])
        self.assertEqual(packet_side(pkt), "left",
                         f"物理左手（镜像帧）须落 left 槽；"
                         f"left={pkt.get('left') is not None} right={pkt.get('right') is not None}")
        self.assertEqual(pkt["left"].get("handedness"), "Left", "包内 handedness 须=物理侧别 Left")

    def test_r1a_physical_right_in_mirror_frame_yields_right_packet(self):
        lm, label, score = self.mirror_right
        pkt = run_frame(make_server(flip=True), [(lm, label, score)])
        self.assertEqual(packet_side(pkt), "right",
                         f"物理右手（镜像帧）须落 right 槽；"
                         f"left={pkt.get('left') is not None} right={pkt.get('right') is not None}")
        self.assertEqual(pkt["right"].get("handedness"), "Right",
                         "包内 handedness 须=物理侧别 Right")

    def test_r1b_side_consistent_across_flip_on_off(self):
        """R1-b：同一真手在 flip_image 开/关两配置下最终 side 一致。"""
        pkt_on = run_frame(make_server(flip=True), [self.mirror_left])
        pkt_off = run_frame(make_server(flip=False), [self.raw_left])
        self.assertEqual(packet_side(pkt_on), "left", "flip=True 生产默认 → left")
        self.assertEqual(packet_side(pkt_off), "left", "flip=False 非镜像 → 同一真手仍 left")
        self.assertEqual(packet_side(pkt_on), packet_side(pkt_off),
                         "R1-b：flip 开/关两配置同一真手 side 必须一致")
        # 对称锁：物理右手同样两配置一致
        self.assertEqual(packet_side(run_frame(make_server(flip=True), [self.mirror_right])),
                         packet_side(run_frame(make_server(flip=False), [self.raw_right])),
                         "R1-b：物理右手两配置 side 一致")

    def test_image_mirror_not_removed(self):
        """W1-1 附带约束：图像镜像保持（cv.flip 零改动，JPEG 自拍预览观感需要）。"""
        import inspect
        src = inspect.getsource(hts.HandTrackingServer._camera_read_thread)
        self.assertIn("cv.flip(frame, 1)", src, "读取线程 cv.flip 不得移除（只改标签映射）")
        self.assertTrue(make_server(flip=True).flip_image, "生产默认 flip_image=True 不变")


# ======================================================================
# 段 ④：同一只手守卫（W1-4，R1-c —— 修复前必红）
# ======================================================================

class SameHandGuardTest(unittest.TestCase):
    """spec §4.3 W1-4：两个检出属于同一只手 → 不拆 L/R，只留一条。"""

    @staticmethod
    def _dup_pair():
        lm = synth_landmarks(0.50, 0.40, thumb_sign=+1)
        lm2 = lm.copy()
        lm2[:, 0] += 0.005   # 微抖（逐点偏差 0.005 < 0.02 容差）
        a = det(0.52, 0.42, "Left", label_mp="Left", score=0.9, lm=lm)
        b = det(0.525, 0.42, "Left", label_mp="Left", score=0.7, lm=lm2)
        return a, b

    def test_r1c_same_hand_duplicate_not_split_into_two_sides(self):
        server = make_server()
        a, b = self._dup_pair()
        items, new_ids, _ = server._hand_tracker.update([a, b], time.monotonic())
        self.assertEqual(len(items), 1,
                         "同手重复检出须只出一条（现状左右各一份=双骨架）："
                         f"{[(i['id'], i['label']) for i in items]}")
        self.assertEqual(len(new_ids), 1, f"同手重复检出只应注册一个 track：{new_ids}")

    def test_r1c_packet_single_side_for_duplicate_detections(self):
        lm = synth_landmarks(0.50, 0.40, thumb_sign=+1)
        lm2 = lm.copy()
        lm2[:, 0] += 0.005
        server = make_server(flip=True)
        pkt = run_frame(server, [(lm, raw_mp_label("Left"), 0.9),
                                 (lm2, raw_mp_label("Left"), 0.7)])
        sides = (pkt.get("left") is not None, pkt.get("right") is not None)
        self.assertEqual(sum(1 for s in sides if s), 1,
                         f"同手重复检出的包只能有一侧非空（现状双骨架）：left={sides[0]} right={sides[1]}")
        self.assertEqual(len(server._hand_tracker.tracks()), 1,
                         f"同手重复检出只注册 1 条 track：{list(server._hand_tracker.tracks())}")

    def test_r1c_keeps_higher_mp_score_when_merging(self):
        server = make_server()
        a, b = self._dup_pair()
        items, _, _ = server._hand_tracker.update([a, b], time.monotonic())
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["detection"]["mp_score"], 0.9,
                         "同手合并保留 mp_score 高者（0.9 > 0.7）")

    def test_two_real_hands_still_split(self):
        """护栏反向：两只真手（中心距 > 阈值、landmark 不重合）必须照常拆 L/R。"""
        server = make_server()
        a = det(0.27, 0.42, "Left", label_mp="Left", score=0.9, lm=synth_landmarks(0.25, 0.40, 1))
        b = det(0.82, 0.42, "Right", label_mp="Right", score=0.9, lm=synth_landmarks(0.80, 0.40, -1))
        items, _, _ = server._hand_tracker.update([a, b], time.monotonic())
        self.assertEqual(len(items), 2, "两只真手不得被同手守卫合并")
        self.assertEqual(sorted(i["label"] for i in items), ["Left", "Right"])


# ======================================================================
# 段 ⑤：检出去重（W1-5，R1-d —— 修复前必红）
# ======================================================================

class DuplicateDedupTest(unittest.TestCase):
    """spec §4.3 W1-5：_process_frame 检出后去重，防同手占满 num_hands=2 名额。"""

    def test_r1d_duplicate_detections_do_not_consume_both_slots(self):
        lm_a = synth_landmarks(0.30, 0.40, thumb_sign=+1)
        lm_a2 = lm_a.copy()
        lm_a2[:, 0] += 0.006
        lm_b = synth_landmarks(0.82, 0.45, thumb_sign=-1)
        server = make_server(flip=True)
        pkt = run_frame(server, [
            (lm_a, raw_mp_label("Left"), 0.92),      # 同一只手（物理左手）第 1 个检出
            (lm_a2, raw_mp_label("Left"), 0.88),     # 同一只手重复检出
            (lm_b, raw_mp_label("Right"), 0.90),     # 第二只真手（物理右手）
        ])
        tracks = server._hand_tracker.tracks()
        self.assertEqual(len(tracks), 2,
                         f"去重后应恰 2 条 track（同手重复框 + 第二只真手）：{list(tracks)}")
        self.assertIsNotNone(pkt.get("left"), "第二只真手不得被吞（left 槽）")
        self.assertIsNotNone(pkt.get("right"), "第二只真手不得被吞（right 槽）")
        # 包内左右须是**两只不同**手（landmark 中心距 > 0.35），而非同手两份
        cl = np.array(pkt["left"]["landmarks"], dtype=float).mean(axis=0)
        cr = np.array(pkt["right"]["landmarks"], dtype=float).mean(axis=0)
        self.assertGreater(float(np.abs(cl - cr).sum()), 0.35,
                           f"左右槽必须是不同物理手：left_center={cl} right_center={cr}")

    def test_r1d_hand_tracker_keeps_one_track_for_same_hand(self):
        """去重判据直测：两同手检出 → HandTracker 只注册一条 track。"""
        server = make_server()
        lm_a = synth_landmarks(0.40, 0.40, thumb_sign=+1)
        lm_a2 = lm_a.copy()
        lm_a2[:, 0] += 0.006
        server._hand_tracker.update(
            [det(0.42, 0.42, "Left", label_mp="Left", lm=lm_a),
             det(0.426, 0.42, "Left", label_mp="Left", lm=lm_a2)],
            time.monotonic())
        self.assertEqual(len(server._hand_tracker.tracks()), 1)

    def test_r1d_dedup_marker_not_left_on_track_dicts(self):
        """审查回修 P3-2：`_aa_dedup_drop` 标记不得残留在**长生命周期** track dict 上。

        旧码把标记打在 `_resolve_sides` 命中的既有 track 上，而消费点只有 `update` 的
        tentative 注册循环 → 既有 track 的标记随 dict 存活终身（消费方永不复位，属潜在
        脚枪）。回修口径=标记改为「本帧 entry 级临时判定」，track dict 上零残留。
        """
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        # 帧 1：两只真手各自注册（L0 / R0）
        tr.update([det(0.22, 0.42, "Left", label_mp="Left", score=0.90,
                       lm=synth_landmarks(0.20, 0.40, +1)),
                   det(0.72, 0.42, "Right", label_mp="Right", score=0.90,
                       lm=synth_landmarks(0.70, 0.40, -1))], t0)
        self.assertEqual(sorted(tr.tracks()), ["L0", "R0"], "前置：两条既有 track")
        # 帧 2：两个检出实为同一只手（landmark 逐点近同）且**两条既有 track 都被分配到**
        #（绕开 _process_frame 的 _dedup_detections 前置去重——W1-4 守卫的既有 track 域）
        same_a = synth_landmarks(0.45, 0.40, +1)
        same_b = same_a.copy()
        same_b[:, 0] += 0.005
        items, changed, dead = tr.update(
            [det(0.45, 0.42, "Left", label_mp="Left", score=0.90, lm=same_a),
             det(0.455, 0.42, "Left", label_mp="Left", score=0.90, lm=same_b)],
            t0 + 0.033)
        self.assertEqual(len([i for i in items if not i["held"]]), 1,
                         "前置：同手守卫剔除一条 entry（仅一条 fresh）")
        self.assertEqual(changed, [], "前置：单条裁决不改侧（零改侧）")
        leaked = [k for k, t in tr.tracks().items() if "_aa_dedup_drop" in t]
        self.assertEqual(leaked, [],
                         f"_aa_dedup_drop 不得残留在 track dict 上（终身脚枪）：{leaked}")
        self.assertEqual(sorted(tr.tracks()), ["L0", "R0"],
                         "被剔除 entry 的既有 track 仍按 hold 语义留存（不因去重被删）")

    def test_r1d_size_ratio_constant_has_no_dead_lower_bound(self):
        """审查回修 P3-3：尺寸比 = max/min **恒 ≥ 1** → 旧常量 (0.7, 1.4) 的 0.7 下界
        永不可能命中（死元素）。回修=删死下界、只留上界，**行为等价**（ratio ≤ 1.4）。"""
        ratio = hts.HAND_DEDUP_SIZE_RATIO
        self.assertFalse(isinstance(ratio, (tuple, list)),
                         f"死下界已删（P3-3）：常量只保留上界，现状={ratio!r}")
        self.assertAlmostEqual(float(ratio), 1.4, places=6,
                               msg="上界值 1.4 不变（行为等价锚）")


# ======================================================================
# 段 ⑥：ghost 参与侧别裁决（W1-6，R1-e —— 修复前必红）
# ======================================================================

class GhostCriterionUnitTest(unittest.TestCase):
    """审查回修 P2-1：`_held_ghost_is_same_hand` 判据与 D1（`_is_same_hand`）口径统一——
    **landmark 逐点最大偏差 < HAND_SAME_HAND_LM_TOL(0.02) 为唯一判据**，landmark 缺失/退化
    才退回中心距（纯中心距在两真手交叉时会误杀丢检手的 ghost → 该侧置 None → GDScript
    teardown 清翻转配对/语义/缩放基准 = 症状②变体）。"""

    @staticmethod
    def _lm(cx: float, sign: int) -> np.ndarray:
        return synth_landmarks(cx, 0.40, sign)[:, :2]

    def test_landmark_usable_but_different_centers_close_returns_false(self):
        """**核心口径差**：landmark 可用且明显不同（两只真手交叉）→ 即便中心距 < 0.35 也判异手。"""
        track = {"center": (0.47, 0.40), "last_landmarks": self._lm(0.45, +1)}
        det = {"center": (0.57, 0.40), "landmarks": synth_landmarks(0.55, 0.40, -1)}
        self.assertFalse(hts._held_ghost_is_same_hand(track, [det]),
                         "landmark 可用且逐点不同 → 不得退回中心距判同手（交叉误杀根因）")

    def test_landmark_near_identical_returns_true(self):
        """真同手（逐点偏差 0.005 < 0.02）→ 判同手（丢弃 ghost）。"""
        track = {"center": (0.62, 0.40), "last_landmarks": self._lm(0.60, -1)}
        near = synth_landmarks(0.60, 0.40, -1).copy()
        near[:, 0] += 0.005
        det = {"center": (0.22, 0.40), "landmarks": near}   # 中心距 0.40 > 0.35（旧判据漏判）
        self.assertTrue(hts._held_ghost_is_same_hand(track, [det]),
                        "landmark 逐点近同 → 判同手（与 D1 同口径，中心距不作数）")

    def test_landmark_missing_falls_back_to_center_distance(self):
        """landmark 缺失/退化 → 中心距兜底（D1 口径第二档）。

        批次 AC（§4.3-1）等价改写：兜底阈值与 `HAND_MATCH_DIST` **共用同一常量**，
        0.35→0.65 后旧异手采样点（0.70）落入新同手带 → 等价外移到 0.90（≥0.65 判异手），
        并新增 0.50（<0.65 判同手）锁死放宽语义；同手采样点 0.10 不变。
        """
        near = {"center": (0.10, 0.40), "last_landmarks": None}
        far = {"center": (0.90, 0.40), "last_landmarks": None}
        mid = {"center": (0.70, 0.40), "last_landmarks": None}
        det = {"center": (0.20, 0.40), "landmarks": np.zeros((21, 3), dtype=np.float32)}
        self.assertTrue(hts._held_ghost_is_same_hand(near, [det]),
                        "landmark 缺失 → 中心距 0.10 < 0.65 兜底判同手")
        self.assertFalse(hts._held_ghost_is_same_hand(far, [det]),
                         "landmark 缺失且中心距 0.70 ≥ 0.65 → 异手（AC：兜底阈值随常量同步放宽）")
        self.assertTrue(hts._held_ghost_is_same_hand(mid, [det]),
                        "AC：中心距 0.50 < 0.65 → 判同手（新阈带内采样，锁死「阈值已放宽」语义）")

    def test_criterion_shared_with_is_same_hand(self):
        """D1 同源护栏：ghost 判据与 `_is_same_hand` 对同一对 landmark 必须同结论。"""
        a = {"center": (0.47, 0.40), "landmarks": synth_landmarks(0.45, 0.40, +1)}
        b = {"center": (0.57, 0.40), "landmarks": synth_landmarks(0.55, 0.40, -1)}
        self.assertEqual(
            hts._held_ghost_is_same_hand({"center": a["center"],
                                          "last_landmarks": a["landmarks"][:, :2]}, [b]),
            hts._is_same_hand(a, b),
            "ghost 判据必须与 _is_same_hand（W1-4/5 D1 口径）同源同结论")


class GhostDropTest(unittest.TestCase):
    """spec §4.3 W1-6 + 审查回修 P2-1：ghost 丢弃判据 = D1 口径（landmark 逐点 < 0.02）。

    本段由审查意见把旧用例 `test_r1e_held_ghost_near_fresh_detection_dropped` **拆成两条**
    ——旧用例标题称「同手」但夹具实为不同物理手（右手 ghost 0.616 vs 左手 fresh 0.316），
    断言的是「异手近距被丢弃」这一**错误**行为；现按 D1 口径拆为 ①真同手丢弃 ②异手近距保留。
    """

    def test_r1e_true_same_hand_ghost_dropped(self):
        """①真同手（landmark 逐点近同）→ 丢弃 ghost，该侧置 None。"""
        server = make_server(flip=True)
        run_frame(server, [(synth_landmarks(0.20, 0.40, +1), raw_mp_label("Left"), 0.92),
                           (synth_landmarks(0.60, 0.40, -1), raw_mp_label("Right"), 0.92)])
        tracks = server._hand_tracker.tracks()
        self.assertEqual(len(tracks), 2, "前置：帧 1 双侧 track 在")
        # 模拟 spec §4.2 R1-3-2 描述的组包态「同一物理手以 fresh 出现在左、以 ghost 出现在右」：
        # 右侧 track 的 hold 数据源就是左手本帧 landmark（fresh 与 ghost 中心 0.219 vs 0.619
        # → 中心距 0.40 > 0.35，纯中心距旧判据**漏判**；landmark 逐点偏差 0 < 0.02 → 判同手）
        tracks["R0"]["last_landmarks"] = synth_landmarks(0.20, 0.40, +1)[:, :2].copy()
        pkt = run_frame(server, [(synth_landmarks(0.20, 0.40, +1), raw_mp_label("Left"), 0.92)])
        self.assertIsNotNone(pkt.get("left"), "fresh 侧照常在")
        self.assertIsNone(pkt.get("right"),
                          "真同手（landmark 逐点近同）的 held ghost 必须丢弃（对侧置 None），"
                          f"现状 right={pkt.get('right')}")
        self.assertEqual(len(server._hand_tracker.tracks()), 2,
                         "ghost 丢弃只影响组包，不删除 track（hold 窗语义不变）")

    def test_r1e_crossing_close_center_ghost_kept(self):
        """②异手近距（两真手交叉形态）→ ghost **保留**，两侧都在场、id 与侧别稳定。"""
        server = make_server(flip=True)
        # 帧 1：交叉形态（两手中枢 0.469/0.569，仅 0.10 间隔）
        pkt1 = run_frame(server, [(synth_landmarks(0.45, 0.40, +1), raw_mp_label("Left"), 0.92),
                                  (synth_landmarks(0.55, 0.40, -1), raw_mp_label("Right"), 0.92)])
        self.assertEqual((pkt1["left"]["id"], pkt1["right"]["id"]), ("L0", "R0"),
                         "前置：帧 1 双侧 id 就位")
        # 帧 2：左手单帧丢检（交叉遮挡）→ 右手 fresh、左手 ghost；
        # ghost 中心 0.469 距 fresh 中心 0.569 = 0.10 < 0.35 → 旧纯中心距判据误杀（判红点）
        pkt2 = run_frame(server, [(synth_landmarks(0.55, 0.40, -1), raw_mp_label("Right"), 0.92)])
        self.assertIsNotNone(pkt2.get("left"),
                             "异手近距的 held ghost 必须保留（该侧不得置 None——"
                             "置 None 即 GDScript 整侧 teardown 清累计态）")
        self.assertIsNotNone(pkt2.get("right"), "fresh 侧照常在")
        self.assertEqual(pkt2["left"]["id"], "L0", "丢检帧左手 id 稳定")
        self.assertEqual(pkt2["left"].get("held"), True, "左手按 held 语义供帧")
        self.assertEqual(pkt2["right"]["id"], "R0", "丢检帧右手 id 稳定")
        self.assertTrue(pkt2["left"]["hand_index"] < pkt2["right"]["hand_index"],
                        "侧别稳定：left hand_index=0、right=1（零改侧）")
        # 帧 3：左手恢复 → id 与侧别零漂移（无新手注册、无改侧）
        pkt3 = run_frame(server, [(synth_landmarks(0.45, 0.40, +1), raw_mp_label("Left"), 0.92),
                                  (synth_landmarks(0.55, 0.40, -1), raw_mp_label("Right"), 0.92)])
        self.assertEqual((pkt3["left"]["id"], pkt3["right"]["id"]), ("L0", "R0"),
                         "恢复帧 id 零漂移")
        self.assertEqual(len(server._hand_tracker.tracks()), 2,
                         "全程恒 2 条 track（无误丢后重建新手）")

    def test_r1e_crossing_single_frame_loss_ids_stable(self):
        """**回归（审查指定）**：两真手交叉 + 单帧丢检 → 该手 id 与侧别稳定。

        红点=丢检帧该侧被误判同手置 None（旧码），GDScript 侧 `h.is_empty()` →
        `_teardown_side` 整侧清态（翻转配对/语义/缩放基准全丢 = 症状②变体）；
        判据统一后 ghost 保留 → 该侧持续 held 供帧 → id/侧别全链路稳定。
        """
        server = make_server(flip=True)
        both = [(synth_landmarks(0.45, 0.40, +1), raw_mp_label("Left"), 0.92),
                (synth_landmarks(0.55, 0.40, -1), raw_mp_label("Right"), 0.92)]
        run_frame(server, both)
        # 丢检帧：只出右手（左手被交叉遮挡单帧丢失）
        loss = run_frame(server, [both[1]])
        self.assertIsNotNone(loss.get("left"),
                             "丢检帧：左手 ghost 须保留供帧（置 None = 整侧清态回归）")
        self.assertEqual(loss["left"]["id"], "L0", "丢检帧左手 id 稳定")
        self.assertTrue(bool(loss["left"].get("held")), "丢检帧左手按 held 供帧")
        # 恢复帧：id/侧别零漂移（不因误丢 ghost 而清态重建）
        back = run_frame(server, both)
        self.assertEqual((back["left"]["id"], back["right"]["id"]), ("L0", "R0"),
                         "恢复帧 id 零漂移（误丢 ghost 会诱发重建/改侧）")
        self.assertEqual([t for t in server._hand_tracker.tracks()], ["L0", "R0"],
                         "track 集合恒定（无新增 id）")
        for i, tr in server._hand_tracker.tracks().items():
            self.assertIn(tr["side"], ("L", "R"), f"{i} 侧别稳定")
            self.assertEqual(i[0], tr["side"], f"{i} id 前缀与侧别一致（零改侧）")

    def test_r1e_ghost_far_from_fresh_kept(self):
        """**反向护栏**：远距 held track（另一只手）→ 保留（防改过头吞掉真正在场的第二只手）。"""
        server = make_server(flip=True)
        run_frame(server, [(synth_landmarks(0.10, 0.40, +1), raw_mp_label("Left"), 0.92),
                           (synth_landmarks(0.85, 0.40, -1), raw_mp_label("Right"), 0.92)])
        pkt = run_frame(server, [(synth_landmarks(0.12, 0.40, +1), raw_mp_label("Left"), 0.92)])
        self.assertIsNotNone(pkt.get("left"), "fresh 侧在")
        self.assertIsNotNone(pkt.get("right"),
                             "远距 held track 属另一只手，须保留（不误杀第二只手）")


# ======================================================================
# 段 ⑦：_initial_side score 下限（W1-7，R1-f —— 修复前必红）
# ======================================================================

class InitialSideScoreFloorTest(unittest.TestCase):
    """spec §4.3 W1-7：新手初始侧与 _mp_side_scored 同口径（低分标签视同缺失）。"""

    def test_score_floor_constant_shared(self):
        self.assertAlmostEqual(hts.MP_RELABEL_MIN_SCORE, 0.6,
                               msg="score 下限常量就位（与逐帧纠错同口径）")

    def test_r1f_low_score_mp_first_frame_falls_back_to_geometry(self):
        server = make_server()
        items, new_ids, _ = server._hand_tracker.update(
            [det(0.50, 0.40, "Left", label_mp="Right", score=0.30)],
            time.monotonic())
        self.assertEqual(len(new_ids), 1, "首帧新手注册")
        self.assertEqual(items[0]["label"], "Left",
                         f"低分 mp（0.30<0.6）首帧须走几何兜底（label_geo=Left），"
                         f"现状={items[0]['label']}")

    def test_r1f_high_score_mp_first_frame_wins(self):
        server = make_server()
        items, _, _ = server._hand_tracker.update(
            [det(0.50, 0.40, "Left", label_mp="Right", score=0.90)],
            time.monotonic())
        self.assertEqual(items[0]["label"], "Right",
                         "高分 mp（0.90≥0.6）首帧仍以 mp 为准（权威序不变）")

    def test_r1f_mp_missing_falls_back_to_geometry(self):
        server = make_server()
        items, _, _ = server._hand_tracker.update(
            [det(0.50, 0.40, "Left", label_mp=None)], time.monotonic())
        self.assertEqual(items[0]["label"], "Left", "mp 缺失 → 几何兜底（既有行为零回归）")


# ======================================================================
# 段 ⑧：稳定输入零改侧护栏（W1-12，R1-h —— 护栏型，恒绿须做真实性验证）
# ======================================================================

class StableNoRelabelGuardTest(unittest.TestCase):
    def test_r1h_stable_single_hand_30_frames_no_relabel(self):
        server = make_server()
        tr = server._hand_tracker
        t0 = time.monotonic()
        items, new_ids, _ = tr.update(
            [det(0.50, 0.40, "Left", label_mp="Left", score=0.90)], t0)
        self.assertEqual(len(new_ids), 1, "首帧注册一次")
        orig_id = items[0]["id"]
        for i in range(1, 30):
            items, changed, _ = tr.update(
                [det(0.50 + i * 1e-4, 0.40, "Left", label_mp="Left", score=0.90)],
                t0 + i * 0.033)
            self.assertEqual(changed, [], f"第 {i} 帧稳定输入不得改侧（换 id 清累计态）")
            self.assertEqual(items[0]["id"], orig_id, f"第 {i} 帧 id 必须稳定")
        self.assertEqual(len(server._hand_tracker.tracks()), 1, "稳定单手恒 1 条 track")


# ======================================================================
# 段 ⑨：心跳 stale 字段（W1-11 —— 修复前必红）
# ======================================================================

class HeartbeatStaleTest(unittest.TestCase):
    @staticmethod
    def _heartbeat(flip: bool = True) -> dict:
        server = make_server(flip=flip)
        server.cap = None
        server._latest_frame = None
        server._last_heartbeat = 0.0
        # 双保险零摄像头：置 RELEASE 标志 + mock 重连入口（绝不开任何采集设备）
        server._camera_intentionally_released = True
        with mock.patch.object(server, "_attempt_reconnect"):
            server._process_frame()
        pkts = [p for p in packets(server) if "left" in p]
        assert pkts, "无帧分支必须发心跳空包"
        return pkts[-1]

    def test_heartbeat_packet_carries_stale_true(self):
        pkt = self._heartbeat()
        self.assertIn("stale", pkt, "心跳空包须带向后兼容的 stale 顶层字段")
        self.assertIs(pkt["stale"], True, "stale 必须为 JSON true（GDScript 侧按 held 语义短路）")
        self.assertIn("camera_open", pkt, "既有 camera_open 电平字段不得丢（协议只增不改）")

    def test_normal_frame_packet_has_no_stale_field(self):
        server = make_server(flip=True)
        pkt = run_frame(server, [(synth_landmarks(0.5, 0.4, +1), "Left", 0.9)])
        self.assertNotIn("stale", pkt, "正常帧不带 stale（仅无帧期心跳携带）")

    def test_heartbeat_left_right_both_null(self):
        pkt = self._heartbeat()
        self.assertIsNone(pkt.get("left"))
        self.assertIsNone(pkt.get("right"))


# ======================================================================
# 段 ⑩：诊断三字段透传（W1-8 python 侧 —— 修复前必红）
# ======================================================================

class DiagnosticKeysTest(unittest.TestCase):
    def test_hand_dict_carries_label_mp_mp_score_label_geo(self):
        server = make_server(flip=True)
        pkt = run_frame(server, [(synth_landmarks(0.5, 0.4, +1), "Right", 0.9)])
        hand = pkt.get("left") or pkt.get("right")
        self.assertIsNotNone(hand, "前置：有手在包内")
        for key in ("label_mp", "mp_score", "label_geo"):
            self.assertIn(key, hand, f"手 dict 须携带诊断字段 {key}（gesture_map 诊断日志消费）")
        self.assertIsInstance(hand.get("mp_score"), (int, float), "mp_score 须为数值")

    def test_held_frame_carries_diagnostic_fields_too(self):
        server = make_server(flip=True)
        run_frame(server, [(synth_landmarks(0.5, 0.4, +1), "Right", 0.9)])
        server.landmarker.detect_for_video.return_value = make_results([])
        for tr in server._hand_tracker.tracks().values():
            tr["last_seen"] = time.monotonic() - (hts.HAND_HOLD_TTL_SEC - 0.1)
        server.udp_sender.send.reset_mock()
        with mock.patch.object(hts.cv, "cvtColor", side_effect=lambda f, c: f), \
                mock.patch.object(server, "_attempt_reconnect"):
            server._process_frame()
        pkt = packets(server)[-1]
        hand = pkt.get("left") or pkt.get("right")
        self.assertIsNotNone(hand, "前置：hold 窗内 held 包在")
        self.assertTrue(hand.get("held"), "前置：该包为 held")
        self.assertIn("label_mp", hand, "held 帧（hold-last 拷贝）须同样带诊断字段")


def main() -> int:
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    ok = result.wasSuccessful()
    print("SELFTEST PASSED" if ok else "SELFTEST FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
