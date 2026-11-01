#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
摄像头选择器 - 枚举所有可用摄像头设备并提供交互式选择功能。

功能：
- 使用 OpenCV 枚举所有可用的摄像头设备（批次 AD：单后端 `CAP_DSHOW` 一次性直启）
- 列出每个摄像头的索引和名称（Windows 下尝试读取设备名称）
- 提供交互式选择界面（CLI）
- 支持保存上次选择的摄像头索引到配置文件（生产路径停写，见 save_camera_id）
- 错误处理：摄像头断开时自动尝试重连

批次 AD（spec §4.2）口径：
- 手机/虚拟摄像头黑名单关键词过滤已**彻底移除**（不再按名称猜测设备类型）；
- 设备启停由「存档设备名 → 查名直启（`pick_camera_by_name`）」驱动，未命中/空名降级
  列表首项，列表空则保持未启动（由调用方回传 0 摄像头状态）；
- Windows 恒 `cv.CAP_DSHOW` 单后端 + `MJPG` + `BUFFERSIZE=1`，废除后端轮换
  （`rotate_backend_chain` 已退役），消除反复 open/release 引起的硬件指示灯闪烁。
"""

import json
import os
import threading
import time
from pathlib import Path
from typing import Optional

import cv2 as cv


# 配置文件路径
CONFIG_DIR = Path.home() / ".hand_tracking"
CONFIG_FILE = CONFIG_DIR / "camera_config.json"

# 批次 AA（W4-11，spec §7.3）：_open_camera 每后端单次打开超时（秒）——坏设备的
# VideoCapture 构造/读帧验证可挂数秒，逐后端超时截断（超时后端视为失败并协作弃置，
# 迟到打开的句柄自行 release 零泄漏）。【暂定值·待用户复验】
OPEN_BACKEND_TIMEOUT_SEC = 5.0

# 批次 AD（spec §4.2.1）：手机/虚拟摄像头黑名单关键词元组与 `is_virtual_or_phone_camera`
# 判定函数**彻底退役**——不再依靠名称字符串猜测设备类型（用户外接设备名一旦含品牌词即被
# 一刀切误杀；新手机互联驱动出现即失效），也不再有「自动缺省设备」这条私自开镜通路。
# 设备启停一律由用户配置（存档设备名）与时序驱动（Godot 握手 → 查名直启）决定。


# ======================================================================
# 纯函数探测层（可注入 prober，selftest_enum_probe.py 断言对象）
# ======================================================================

def decode_console_bytes(raw) -> str:
    """子进程控制台字节输出显式解码（P0 回修）：先 GBK 严格解码，失败转 UTF-8 严格
    解码，再失败 GBK+replace 兜底——配合字节模式捕获（捕获侧不做编码解码），
    子进程读取线程绝无 UnicodeDecodeError，本函数自身也绝不抛异常。

    None/空入参返回 ""；str 入参原样透传。注意 GBK 优先语义下，若子进程确以
    UTF-8 输出中文，可能得到可显示的乱码名（仅影响显示名，不影响可用性判定）。
    """
    if raw is None:
        return ""
    if isinstance(raw, str):
        return raw
    if not isinstance(raw, (bytes, bytearray)):
        return str(raw)
    data = bytes(raw)
    if not data:
        return ""
    for enc in ("gbk", "utf-8"):
        try:
            return data.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return data.decode("gbk", errors="replace")


def try_read_frames(reader, tries: int = 3, frame_wait: float = 0.08,
                    sleeper=None) -> bool:
    """重试读帧判定：DSHOW/MSMF 首帧常超时假阴性——连续 tries 次读帧，失败帧间短 sleep。

    Args:
        reader: 无参可调用，返回 (ret, frame)（如 cap.read）。
        tries: 最大读帧尝试次数（≥1）。
        frame_wait: 失败帧间等待秒数。
        sleeper: 等待函数可注入（默认 time.sleep）。

    Returns:
        bool: 任一次读帧成功即 True；全部失败或 reader 抛异常返回 False（不抛出）。
    """
    if sleeper is None:
        sleeper = time.sleep
    tries = max(1, int(tries))
    for attempt in range(tries):
        try:
            ret, _frame = reader()
        except Exception:
            return False
        if ret:
            return True
        if attempt < tries - 1:
            sleeper(frame_wait)
    return False


def build_camera_entries(probe_results, name_backfill=None) -> list:
    """探测结果 → init 消息 cameras 条目列表。

    契约（修复批次）：cameras=[{"id": int(CAP索引), "name": str}]——设备 id 语义统一为
    OpenCV CAP 索引，WMI 名单序不再充当设备索引。

    Args:
        probe_results: 可迭代的 (index: int, usable: bool)，仅 usable=True 入列。
        name_backfill: {index: 显示名}（WMI 多链回填结果，可空/None）；
                       无回填名时显示名回退「摄像头 N」。

    Returns:
        list[dict]: 按 id 升序的 [{"id": int, "name": str}]。
    """
    backfill = name_backfill if isinstance(name_backfill, dict) else {}
    entries = []
    for item in probe_results:
        index, usable = int(item[0]), bool(item[1])
        if not usable:
            continue
        raw_name = backfill.get(index)
        # P0 回修：显示名逐条 isinstance(str) 过滤（防 None/防非字符串），缺省「摄像头 N」
        name = (raw_name if (isinstance(raw_name, str) and raw_name.strip())
                else f"摄像头 {index}")
        entries.append({"id": index, "name": name})
    entries.sort(key=lambda c: int(c["id"]))
    return entries


def backfill_camera_entry(entries: list, camera_id: int, name: str = None) -> list:
    """打开成功后把实际设备回填进条目列表（幂等；含空枚举兜底 auto=0 成功的场景）。

    Args:
        entries: 现有条目列表（原地修改并返回）。
        camera_id: 实际打开设备的 CAP 索引。
        name: 显示名（None 时用「摄像头 N」）。

    Returns:
        list: 同一 entries 引用（按 id 升序）。
    """
    camera_id = int(camera_id)
    for cam in entries:
        try:
            if int(cam.get("id", -1)) == camera_id:
                return entries
        except (TypeError, ValueError):
            continue
    # P0 回修：显示名防 None/防非字符串
    display = name if (isinstance(name, str) and name.strip()) else f"摄像头 {camera_id}"
    entries.append({"id": camera_id, "name": display})
    entries.sort(key=lambda c: int(c["id"]))
    return entries


def pick_camera_by_name(entries: list, preferred_name=None) -> Optional[int]:
    """设备名 → 首启目标 CAP 索引（批次 AD，spec §4.2.2-4 查名直启纯函数）。

    口径（批次 AD 拍板，黑名单退役后的唯一自动选择规则）：
    - `entries` 为空/None → 返回 `None`（**保持未启动**，由调用方回传 0 摄像头状态）；
    - `match_camera_by_name` 命中（忽略首尾空格与大小写差异）→ 返回命中设备 id；
    - 未命中或名称为空 → **降级返回 `entries[0]`（列表首项物理设备）的 id**；
    - 条目 id 不可解析（脏条目）→ 跳过，取首个可解析条目；全部不可解析 → None。

    纯函数、无副作用，供无头 selftest 直测（**绝不打开任何设备**）。

    Args:
        entries: init#1 同款条目列表 [{"id": int(CAP索引), "name": str}]（可空/None）。
        preferred_name: 存档记忆设备名（可空/None）。

    Returns:
        Optional[int]: 目标 CAP 索引；列表空/无可解析条目时 None（保持未启动）。
    """
    items = [c for c in (entries or []) if isinstance(c, dict)]
    first_id = None
    for cam in items:
        try:
            cid = int(cam.get("id", -1))
        except (TypeError, ValueError):
            continue
        if cid >= 0:
            first_id = cid
            break
    if first_id is None:
        return None
    matched = match_camera_by_name(items, preferred_name)
    if matched is not None:
        return matched
    return first_id


def match_camera_by_name(entries: list, preferred_name) -> Optional[int]:
    """设备名 → 枚举条目中的目标设备 id（批次 Y Y-A16 → 批次 AD §4.2.2-4 口径修订）。

    匹配口径（批次 AD 修订：**忽略大小写与首尾空格**，与 GDScript 侧
    `_resolve_target_camera_id` 及 `match_camera_by_name` 同源）：
    - 名称 strip + casefold 后与枚举条目显示名同口径比对，命中返回该条目 id；
    - 未记忆/匹配不到返回 None（调用方回退缺省=列表首项，见 `pick_camera_by_name`）；
    - **纯数字串不再按旧 CAP 索引语义解释**（spec §4.2.2-2：禁止存储或依赖 CAP 索引
      数字，防热插拔或重排序失效）——旧档纯数字残留视同未命中，走首项降级。

    纯函数、无副作用，供无头 selftest 直测。

    Args:
        entries: init 消息同款条目列表 [{"id": int, "name": str}]。
        preferred_name: 记忆设备名（可空/None）。

    Returns:
        Optional[int]: 命中的 CAP 索引；未命中 None。
    """
    key = str(preferred_name if preferred_name is not None else "").strip().casefold()
    if not key:
        return None
    for cam in entries or []:
        if not isinstance(cam, dict):
            continue
        try:
            entry_name = str(cam.get("name") or "").strip().casefold()
        except Exception:
            continue
        if entry_name and entry_name == key:
            try:
                cid = int(cam.get("id", -1))
            except (TypeError, ValueError):
                continue
            return cid if cid >= 0 else None
    return None


def _probe_open_backends(index: int) -> Optional[cv.VideoCapture]:
    """探测用临时单后端直开（批次 AD §4.2.3）：恒 `cv.CAP_DSHOW` 一次，零后端轮换。

    旧实现 DSHOW→MSMF 逐后端试探开镜/释放（探测期反复 open/release = 硬件指示灯
    频闪来源之一）已随批次日 AD 退役；探测方（probe_camera_usable）负责 release。
    """
    try:
        cap = cv.VideoCapture(index, cv.CAP_DSHOW)
    except Exception:
        return None
    if cap is not None and cap.isOpened():
        return cap
    if cap is not None:
        try:
            cap.release()
        except Exception:
            pass
    return None


def probe_camera_usable(index: int, open_fn=None, verify_fn=None,
                        sleeper=None, tries: int = 3,
                        frame_wait: float = 0.08) -> bool:
    """临时打开指定 CAP 索引摄像头 → 重试读帧验证 → 立即 release（纯探测，不保存配置）。

    Args:
        index: CAP 索引。
        open_fn: index -> cap|None 可注入（默认 `_probe_open_backends` 单后端直开）。
        verify_fn: cap -> bool 可注入（默认 try_read_frames(cap.read) 重试读帧）。
        sleeper: 等待函数可注入。
        tries/frame_wait: 重试读帧参数（仅默认 verify_fn 生效）。

    Returns:
        bool: 可用 True；任何失败返回 False（不抛出）。
    """
    if open_fn is None:
        open_fn = _probe_open_backends
    cap = None
    try:
        cap = open_fn(index)
        if cap is None or not cap.isOpened():
            return False
        if verify_fn is None:
            if sleeper is None:
                sleeper = time.sleep
            verify_fn = (lambda c: try_read_frames(c.read, tries=tries,
                                                   frame_wait=frame_wait,
                                                   sleeper=sleeper))
        return bool(verify_fn(cap))
    except Exception:
        return False
    finally:
        if cap is not None:
            try:
                cap.release()
            except Exception:
                pass


def _probe_index_with_budget(index: int, open_fn, verify_fn, sleeper,
                             budget: float) -> bool:
    """单索引探测，带超时上限（探测线程超预算即放弃等待，线程本身为 daemon 自行收尾）。"""
    box = {"usable": False}

    def _run():
        try:
            box["usable"] = bool(probe_camera_usable(
                index, open_fn=open_fn, verify_fn=verify_fn, sleeper=sleeper))
        except Exception:
            box["usable"] = False

    t = threading.Thread(target=_run, daemon=True)
    t.start()
    t.join(max(0.0, budget))
    if t.is_alive():
        print(f"[枚举] CAP 索引 {index} 探测超时（>{budget:.1f}s），跳过")
        return False
    return box["usable"]


def enumerate_cameras(max_index: int = 3, open_fn=None, verify_fn=None,
                      sleeper=None, per_index_budget: float = 3.0,
                      total_budget: float = 15.0) -> list:
    """按 CAP 索引 0..max_index 逐个探测（临时开-验证-立即 release，不并发）。

    每索引超时上限 per_index_budget、总时长上限 total_budget，防卡死循环。
    枚举完成后才进入正式打开步骤（server.start 第 2 步），两阶段不并发。

    Returns:
        list[tuple[int, bool]]: [(index, usable), ...]，按索引升序（含不可用索引的标记）。
    """
    if sleeper is None:
        sleeper = time.sleep
    results = []
    started = time.monotonic()
    for index in range(max_index + 1):
        if time.monotonic() - started > max(0.0, total_budget):
            print(f"[枚举] 总时长超上限（{total_budget:.0f}s），停止于 CAP 索引 {index}")
            break
        usable = _probe_index_with_budget(index, open_fn, verify_fn, sleeper,
                                          per_index_budget)
        print(f"[枚举] CAP 索引 {index}: {'可用' if usable else '不可用'}")
        results.append((index, usable))
        if usable:
            sleeper(0.05)  # 释放句柄缓冲，避免紧接的正式打开撞上设备未释放
    return results


class CameraSelector:
    """摄像头选择器，用于枚举、选择和重连摄像头。"""

    # Windows 下 DShow 后端可能的最大摄像头数量
    MAX_CAMERAS_TO_CHECK = 10

    def __init__(self, config_file: str = None):
        """
        初始化摄像头选择器。

        Args:
            config_file: 配置文件路径，默认使用 ~/.hand_tracking/camera_config.json
        """
        self.config_file = Path(config_file) if config_file else CONFIG_FILE
        self._ensure_config_dir()

    # ------------------------------------------------------------------
    # 公开接口
    # ------------------------------------------------------------------

    def list_cameras(self) -> list[dict]:
        """
        枚举所有可用摄像头。

        Returns:
            list[dict]: 摄像头信息列表，每项含：
                - id (int): 摄像头索引
                - name (str): 设备名称（Windows 下尝试读取，否则显示 "Camera {id}"）
                - status (str): "available" 或 "error"
        """
        cameras = []
        for i in range(self.MAX_CAMERAS_TO_CHECK):
            info = self._probe_camera(i)
            cameras.append(info)
        # 过滤掉完全不可用的（但保留连续区间）
        available = [c for c in cameras if c["status"] == "available"]
        if not available:
            # 如果没有找到可用摄像头，最多再多检查几个
            for i in range(self.MAX_CAMERAS_TO_CHECK,
                           self.MAX_CAMERAS_TO_CHECK + 10):
                info = self._probe_camera(i)
                cameras.append(info)
                if info["status"] == "available":
                    available.append(info)
                elif len(available) == 0 and len(cameras) > 15:
                    # 已经检查很多了还没找到，停止
                    break
        return cameras

    def select_camera(self, camera_id: int = None,
                      backend_shift: int = 0) -> cv.VideoCapture:
        """
        选择并打开摄像头。

        如果未指定 camera_id，则：
        1. 尝试读取上次保存的摄像头 ID
        2. 如果无效，显示交互式选择列表
        3. 如果交互失败，默认使用 0

        Args:
            camera_id: 摄像头索引，None 时自动选择
            backend_shift: 已退役参数（批次 V-B1 后端轮换使用）——API 兼容占位，
                取值被忽略（批次 AD §4.2.3：恒单后端 CAP_DSHOW 一次性直启）

        Returns:
            cv.VideoCapture: 打开的摄像头对象

        Raises:
            RuntimeError: 无法打开任何摄像头
        """
        if camera_id is not None:
            cap = self._open_camera(camera_id, backend_shift=backend_shift)
            if cap is not None:
                self.save_camera_id(camera_id)
                return cap
            raise RuntimeError(f"无法打开摄像头 [{camera_id}]")

        # 尝试保存的 ID
        saved_id = self.get_saved_camera_id()
        if saved_id is not None:
            cap = self._open_camera(saved_id)
            if cap is not None:
                return cap
            print(f"[摄像头选择器] 上次保存的摄像头 [{saved_id}] 不可用，"
                  f"将扫描可用设备...")

        # 扫描并交互选择
        cameras = self.list_cameras()
        available = [c for c in cameras if c["status"] == "available"]

        if not available:
            # 返回到 0 的常规尝试
            cap = self._open_camera(0)
            if cap is not None:
                self.save_camera_id(0)
                return cap
            raise RuntimeError("未找到任何可用摄像头")

        if len(available) == 1:
            cam = available[0]
            print(f"[摄像头选择器] 自动选择唯一可用摄像头: "
                  f"[{cam['id']}] {cam['name']}")
            cap = self._open_camera(cam["id"])
            if cap is not None:
                self.save_camera_id(cam["id"])
                return cap
            raise RuntimeError(f"无法打开摄像头 [{cam['id']}]")

        # 多个摄像头，交互选择
        print("\n可用的摄像头设备:")
        print("-" * 50)
        for cam in available:
            marker = " [上次选择的]" if cam["id"] == saved_id else ""
            print(f"  [{cam['id']}] {cam['name']}{marker}")
        print("-" * 50)

        default = saved_id if saved_id is not None else available[0]["id"]
        try:
            user_input = input(
                f"请选择摄像头索引 (默认 {default}): ").strip()
            choice = int(user_input) if user_input else default
        except (ValueError, EOFError):
            choice = default

        # 验证选择
        chosen = None
        for cam in available:
            if cam["id"] == choice:
                chosen = cam
                break
        if chosen is None:
            print(f"[摄像头选择器] 无效选择 {choice}，使用默认 {default}")
            chosen = available[0]

        cap = self._open_camera(chosen["id"])
        if cap is not None:
            self.save_camera_id(chosen["id"])
            return cap
        raise RuntimeError(f"无法打开摄像头 [{chosen['id']}]")

    def save_camera_id(self, camera_id: int):
        """保存摄像头 ID 到配置文件——批次 AA（W4-9，spec §7.3）起**停写 no-op**。

        理由：`~/.hand_tracking/camera_config.json` 记的是 CAP 索引（0/1/2/3），而用户
        语义/存档记忆是**设备显示名**（save_manager `settings.gesture_camera_device`）——
        该文件生产路径只写不读，属第二套脏记忆（R4-1）。停止写入后旧档文件原样保留、
        读取路径 get_saved_camera_id 兼容不变；方法体保留为 API 兼容占位（CLI 亦不再写）。
        """
        return None

    def get_saved_camera_id(self) -> Optional[int]:
        """
        读取上次保存的摄像头 ID。

        Returns:
            Optional[int]: 保存的摄像头 ID，不存在时返回 None
        """
        try:
            if self.config_file.exists():
                data = json.loads(self.config_file.read_text(encoding="utf-8"))
                return int(data.get("camera_id", -1))
        except (json.JSONDecodeError, ValueError, OSError):
            pass
        return None

    # ------------------------------------------------------------------
    # 内部方法
    # ------------------------------------------------------------------

    def _ensure_config_dir(self):
        """确保配置目录存在。"""
        self.config_file.parent.mkdir(parents=True, exist_ok=True)

    def _get_windows_camera_name(self, index: int) -> Optional[str]:
        """
        通过多重 WMI 查询获取 Windows 摄像头设备的真实名称。
        依次尝试多个 PNPClass 分类，兼容不同 Windows 版本。
        """
        import subprocess

        # 多组 WMI 查询策略，按优先级排列
        queries = [
            # 策略1：Win32_PnPEntity + PNPClass = Camera（最常见）
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'Camera' } | Select-Object -ExpandProperty Name",
            # 策略2：Win32_PnPEntity + PNPClass = Image（部分笔记本）
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'Image' } | Select-Object -ExpandProperty Name",
            # 策略3：Win32_PnPEntity + 名称含 camera/webcam（兜底）
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.Name -match 'camera|webcam|hd' } | Select-Object -ExpandProperty Name",
            # 策略4：Win32_USBControllerDevice 级联查询 USB 摄像头
            "Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'USB' -and $_.Name -match 'camera|webcam|video' } | Select-Object -ExpandProperty Name",
        ]

        for query in queries:
            try:
                cmd = ["powershell", "-NoProfile", "-Command", query]
                # P0 回修：字节模式捕获+显式解码——读取线程不做编码解码，绝无
                # UnicodeDecodeError；解码失败经 replace 兜底绝不 None
                result = subprocess.run(cmd, capture_output=True, timeout=5)
                text = decode_console_bytes(getattr(result, "stdout", None))
                if result.returncode == 0 and text.strip():
                    names = [line.strip() for line in text.split('\n') if line.strip()]
                    if index < len(names):
                        return names[index]
            except Exception:
                continue

        return None

    def _probe_camera(self, index: int) -> dict:
        """
        探测单个摄像头。

        尝试在 Windows 下通过 DShow 获取设备名称。

        Args:
            index: 摄像头索引

        Returns:
            dict: 摄像头信息 {id, name, status}
        """
        name = f"Camera {index}"
        status = "error"

        # 尝试通过 WMI 获取摄像头真实设备名（Windows）
        real_name = self._get_windows_camera_name(index)
        has_real_name = real_name is not None
        if real_name:
            name = real_name

        # 尝试打开（批次 AD §4.2.3：单后端 CAP_DSHOW 一次，零 MSMF/默认轮换）
        cap = cv.VideoCapture(index, cv.CAP_DSHOW)
        if cap is None or not cap.isOpened():
            if cap is not None:
                try:
                    cap.release()
                except Exception:
                    pass
            return {"id": index, "name": name, "status": status}

        # 获取设备名称（Windows DShow 支持）
        if os.name == "nt":
            try:
                backend = cap.get(cv.CAP_PROP_BACKEND)
                # DShow backend = 700 (CAP_DSHOW)
                if backend == 700:
                    # 如果已通过 WMI 获取到真实名称，不再覆盖
                    if has_real_name:
                        pass  # 保留真实设备名
                    else:
                        width = int(cap.get(cv.CAP_PROP_FRAME_WIDTH))
                        height = int(cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                        fps = cap.get(cv.CAP_PROP_FPS)
                        name = f"Camera {index} ({width}x{height} @ {fps:.0f}fps)"
                else:
                    if not has_real_name:
                        width = int(cap.get(cv.CAP_PROP_FRAME_WIDTH))
                        height = int(cap.get(cv.CAP_PROP_FRAME_HEIGHT))
                        name = f"Camera {index} ({width}x{height})"
            except Exception:
                if not has_real_name:
                    name = f"Camera {index}"
        else:
            # Linux 下尝试读取设备名称
            try:
                device_path = f"/dev/video{index}"
                if os.path.exists(device_path):
                    name = f"Camera {index} ({device_path})"
            except Exception:
                pass

        # 尝试读取一帧验证可用性（修复批次：加重试——DSHOW/MSMF 首帧常超时假阴性）
        if try_read_frames(cap.read):
            status = "available"
        else:
            status = "error"

        cap.release()
        return {"id": index, "name": name, "status": status}

    @staticmethod
    def _open_camera(camera_id: int,
                     width: int = 640,
                     height: int = 480,
                     preferred_backend: int = None,
                     backend_shift: int = 0) -> Optional[cv.VideoCapture]:
        """
        打开摄像头（批次 AD §4.2.3：**单一稳定后端一次性直启**）。

        Args:
            camera_id: 摄像头索引
            width: 期望宽度
            height: 期望高度
            preferred_backend: 首选后端（缺省 `cv.CAP_DSHOW`；仅此一处后端选择）
            backend_shift: 已退役参数（批次 V-B1 后端轮换使用）——保留为 API 兼容占位，
                取值被忽略（**不再有任何后端轮换语义**）

        Returns:
            Optional[cv.VideoCapture]: 成功返回摄像头对象，否则 None

        批次 AD（spec §4.2.3）定档：
        - Windows 平台恒 `cv.VideoCapture(device_index, cv.CAP_DSHOW)` **单后端一次直启**；
        - 固定配置 `MJPG` + `BUFFERSIZE=1`（打开成功后立即设置，消除排队延迟）；
        - **废除** DSHOW/MSMF/默认 三后端轮换（`rotate_backend_chain` 已退役）——旧实现
          在失败时反复 release/open 换后端，直接造成物理摄像头硬件指示灯疯狂闪烁；
        - 失败即失败（单次尝试返回 None），不再换后端重开第二次。

        保留批次 AA（W4-11）的**每后端单次超时**：单后端构造/读帧在坏设备上可挂数秒，
        独立线程执行 + join(超时)；超时即弃置（abandoned 协作标志 + 锁内交接：迟到
        打开的句柄自行 release，零泄漏）。
        """
        backend = cv.CAP_DSHOW if preferred_backend is None else preferred_backend
        timeout = float(globals().get("OPEN_BACKEND_TIMEOUT_SEC", 5.0))
        box: dict = {"cap": None, "abandoned": False}
        box_lock = threading.Lock()

        def _worker(box=box, box_lock=box_lock, backend=backend) -> None:
            cap = None
            try:
                cap = cv.VideoCapture(camera_id, backend)
                if cap is not None and cap.isOpened():
                    cap.set(cv.CAP_PROP_FRAME_WIDTH, width)
                    cap.set(cv.CAP_PROP_FRAME_HEIGHT, height)
                    # 批次 AD（spec §4.2.3）：单后端直启的固定配置——MJPG 明显降低 USB
                    # 相机逐帧解码延迟；BUFFERSIZE=1 消除「读到的是 N 帧前画面」的排队延迟。
                    # 不支持 MJPG 的相机 set 后 get 回 0，OpenCV 自动回退默认格式，无回归风险。
                    cap.set(cv.CAP_PROP_FOURCC, cv.VideoWriter_fourcc(*"MJPG"))
                    cap.set(cv.CAP_PROP_BUFFERSIZE, 1)
                    ret, _ = cap.read()
                    if ret:
                        with box_lock:
                            if box["abandoned"]:
                                # 超时弃置后迟到成功 → 自行 release（零泄漏）
                                try:
                                    cap.release()
                                except Exception:
                                    pass
                            else:
                                box["cap"] = cap
                        return
                if cap is not None:
                    cap.release()
            except Exception:
                if cap is not None:
                    try:
                        cap.release()
                    except Exception:
                        pass

        t = threading.Thread(target=_worker, daemon=True, name="open-backend")
        t.start()
        t.join(max(0.0, timeout))
        with box_lock:
            got = box.get("cap")
            if got is not None:
                return got
            if t.is_alive():
                box["abandoned"] = True   # 超时：标记弃置（worker 迟到成功即自释放）
        if t.is_alive():
            print(f"[摄像头选择器] 后端 {backend} 打开超时（>{timeout:.1f}s），"
                  f"弃置（AD：单后端一次性直启，不再轮换重开）")
        return None


# ======================================================================
# CLI 入口
# ======================================================================
def main():
    """交互式摄像头选择命令行工具。"""
    selector = CameraSelector()

    print("=" * 50)
    print("   摄像头选择器 v1.0")
    print("=" * 50)

    # 显示已保存的配置
    saved = selector.get_saved_camera_id()
    if saved is not None:
        print(f"已保存的摄像头 ID: {saved}")

    # 列出所有摄像头
    print("\n正在扫描摄像头...")
    cameras = selector.list_cameras()
    available = [c for c in cameras if c["status"] == "available"]

    print(f"\n找到 {len(available)} 个可用摄像头:")
    for cam in cameras:
        status_icon = "✓" if cam["status"] == "available" else "✗"
        saved_mark = " [已保存]" if cam["id"] == saved else ""
        print(f"  [{cam['id']}] {status_icon} {cam['name']}{saved_mark}")

    if not available:
        print("\n未找到可用摄像头！")
        return

    # 选择
    print("\n--- 测试摄像头 ---")
    try:
        inp = input("输入摄像头索引测试 (直接回车跳过): ").strip()
        if inp:
            test_id = int(inp)
            # 验证
            for cam in available:
                if cam["id"] == test_id:
                    cap = selector._open_camera(test_id)
                    if cap and cap.isOpened():
                        print(f"✓ 摄像头 [{test_id}] 打开成功，正在捕获..."
                              f"(按 ESC 或 Q 退出)")
                        _show_preview(cap)
                    else:
                        print(f"✗ 无法打开摄像头 [{test_id}]")
                    break
            else:
                print(f"摄像头 [{test_id}] 不在可用列表中")
    except (ValueError, EOFError):
        pass

    # 保存选择
    print("\n--- 保存默认摄像头 ---")
    try:
        inp = input("输入要保存为默认的摄像头索引 (直接回车跳过): ")
        if inp:
            save_id = int(inp)
            selector.save_camera_id(save_id)
            print(f"✓ 已保存摄像头 [{save_id}] 为默认")
    except (ValueError, EOFError):
        pass


def _show_preview(cap: cv.VideoCapture):
    """显示摄像头预览窗口。"""
    window_name = "Camera Preview - Press ESC or Q to exit"
    while True:
        ret, frame = cap.read()
        if not ret:
            print("摄像头读取失败")
            break

        cv.imshow(window_name, frame)
        key = cv.waitKey(1) & 0xFF
        if key == 27 or key == ord('q') or key == ord('Q'):
            break

    cap.release()
    cv.destroyAllWindows()


if __name__ == "__main__":
    main()
