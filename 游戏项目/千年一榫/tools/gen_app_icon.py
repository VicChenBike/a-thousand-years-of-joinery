# -*- coding: utf-8 -*-
"""批次 AC（2026-09-27）领域一：从真透明 icon.png 生成标准多尺寸 Windows .ico。

产物（唯一图标源，供三处消费）：
  assets/icons/app_icon.ico
    ① Godot 导出：export_presets.cfg  application/icon + application/console_wrapper_icon
    ② 安装包本体：tools/千年一榫_setup.iss  [Setup] SetupIconFile
    ③ 全部快捷方式：tools/千年一榫_setup.iss  [Icons] IconFilename（含「手势版」快捷方式）

输入：icon.png（RGBA 1024×1024，圆角方块外 alpha == 0 真透明）。

硬约束（批次 AC spec §4.1.1 与 §7.1）：
  ① 六档尺寸齐全：16 / 32 / 48 / 64 / 128 / 256；
  ② 每帧四角像素 (0,0)/(w-1,0)/(0,h-1)/(w-1,h-1) alpha == 0（真透明）；
  ③ alpha == 0 区域 RGB 必须清零（(0,0,0,0)）——历史「灰白棋盘格 / 白角」伪透明
     的根因正是 (255,255,255,0)：任何忽略 alpha 的解码路径都会把白底画出来；
  ④ LANCZOS 重采样（每档由 256 主图直出，单次重采样，避免多级插值糊边）。

帧编码选型（留痕）：全部 6 帧用 PNG 压缩帧——Pillow ICO 写入器默认且唯一免手工
拼容器的方式；Windows Vista+ 原生支持 PNG 帧 ICO（PE RT_ICON 内含 PNG 帧同样被
Explorer/DWM/任务栏 解码）。与已拍板的原始图标交付件
（确定）千年一榫_桌面图标_candidate1.ico 编码逐帧一致（6 帧全 PNG），
亦即用户实机已验收过的形态。PNG 帧可让无头 GDScript 测试逐帧解码验四角 alpha，
避免 DIB 帧在 GDScript 侧不可解码导致的验证盲区（spec §7.1 判定项无法落地）。

用法：
  python tools/gen_app_icon.py            # 生成 + 自校验（失败非零退出）
  python tools/gen_app_icon.py --verify   # 只校验既有产物（CI / 回归用）
"""

import argparse
import os
import struct
import sys

from PIL import Image, ImageFile

SIZES = (16, 32, 48, 64, 128, 256)
MASTER = 256                      # 中间主图边长（其余各档由它单次 LANCZOS 直出）
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)      # 游戏项目/千年一榫/
SRC = os.path.join(ROOT, "icon.png")
OUT = os.path.join(ROOT, "assets", "icons", "app_icon.ico")

ImageFile.LOAD_TRUNCATED_IMAGES = False


def clean_transparent(img: Image.Image) -> Image.Image:
    """把 alpha == 0 的像素 RGB 清零（消除白角/灰白棋盘伪透明残留）。"""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0 and (r, g, b) != (0, 0, 0):
                px[x, y] = (0, 0, 0, 0)
    return img


def audit_source(path: str) -> Image.Image:
    """审计图源：alpha 通道完整性 + 透明区 RGB 洁净度。返回净化后的图。"""
    im = Image.open(path)
    print("[源] %s  mode=%s size=%s" % (path, im.mode, im.size))
    if im.mode != "RGBA":
        print("[源] 非 RGBA（%s），强制转 RGBA 后继续" % im.mode)
    im = im.convert("RGBA")
    alpha = im.getchannel("A")
    lo, hi = alpha.getextrema()
    total = im.size[0] * im.size[1]
    print("[源] alpha 全域极值 = (%d, %d)；alpha == 0 像素 = %d/%d"
          % (lo, hi, sum(1 for v in alpha.get_flattened_data() if v == 0), total))
    print("[源] 内容 bbox（alpha 非零包围盒） = %s" % (alpha.getbbox(),))
    # 网格伪透明检测：透明区若出现深浅交替的规律色块（棋盘格），即非纯色 → 报出
    seen = {}
    px = im.load()
    w, h = im.size
    for y in range(0, h, 7):
        for x in range(0, w, 11):
            r, g, b, a = px[x, y]
            if a == 0:
                seen[(r, g, b)] = seen.get((r, g, b), 0) + 1
    top = sorted(seen.items(), key=lambda kv: -kv[1])[:6]
    print("[源] 透明区 RGB 采样分布 top6 = %s" % (top,))
    if len(seen) > 1:
        print("[源] 提示：透明区 RGB 非单一值（%d 种）——若为规律深浅交替即棋盘伪透明；"
              "本脚本一律在产物中清零。已用 Pillow 重采样前净化。" % len(seen))
    return clean_transparent(im)


def build(src_img: Image.Image) -> None:
    master = src_img.resize((MASTER, MASTER), Image.LANCZOS)
    master = clean_transparent(master)
    frames = []
    for s in SIZES:
        fr = master.resize((s, s), Image.LANCZOS)
        frames.append(clean_transparent(fr))     # 重采样后复净化，锁死 ③
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # 基准图必须是最大帧（256）：Pillow ICO 写入器对 `size > 基准图尺寸` 的档位直接
    # `continue` 丢弃（IcoImagePlugin._save 内 `if size[0] > width ... continue`）——
    # 若以 16 帧为基准则只剩 1 帧。故以 master(256) 为基准、六档全量作 append_images，
    # 写入器按尺寸各取首个匹配帧（无重复帧）。
    master.save(
        OUT,
        format="ICO",
        sizes=[(s, s) for s in SIZES],
        append_images=frames,
    )
    print("[出] %s  bytes=%d" % (OUT, os.path.getsize(OUT)))
    n = patch_icondir_conformance()
    print("[出] ICONDIRENTRY wPlanes 规范纠正：%d/%d 条（Pillow 硬写 0 → 规范值 1）" % (n, len(SIZES)))


def patch_icondir_conformance() -> int:
    """把 ICONDIRENTRY 的 wPlanes 从 Pillow 硬编码的 0 纠正为 1（Windows 规范值）。

    Pillow 的 ICO 写入器对 wPlanes 直接硬写 b"\\0\\0"（IcoImagePlugin._save），而
    Windows ICONDIRENTRY 规范要求 wPlanes == 1。留 wPlanes=0 虽被实测可用
    （PrivateExtractIcons / ISCC / GDI 均接受），但 Godot 导出时会把该字段原样
    转抄进 PE 的 RT_GROUP_ICON，故此处纠正以保「符合 Windows 规范」。
    返回纠正的条目数。
    """
    with open(OUT, "rb") as f:
        blob = bytearray(f.read())
    _, itype, count = struct.unpack_from("<HHH", blob, 0)
    patched = 0
    for i in range(count):
        off = 6 + i * 16
        w, h, colors, reserved, planes, bpp = struct.unpack_from("<BBBBHH", blob, off)
        if planes != 1:
            struct.pack_into("<H", blob, off + 4, 1)
            patched += 1
    if patched:
        with open(OUT, "wb") as f:
            f.write(blob)
    return patched


def _frame_report() -> list:
    """逐帧判定：返回 [(size, ok, detail)]。

    注意：必须每档新开一次 Image.open（IcoImageFile 的帧选择靠 size setter 触发重载，
    同一句柄反复改 size 会复用已解码的 `im`，导致后档拿到前档像素=假绿）。
    """
    rows = []
    for s in SIZES:
        frame = Image.open(OUT)
        frame.size = (s, s)           # IcoImageFile.size setter：按帧加载
        frame = frame.convert("RGBA")
        w, h = frame.size
        if (w, h) != (s, s):
            rows.append((s, False, "实际帧尺寸 %dx%d" % (w, h)))
            continue
        px = frame.load()
        corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
        alphas = [px[c][3] for c in corners]
        rgb_bad = 0
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0 and (r, g, b) != (0, 0, 0):
                    rgb_bad += 1
        center_a = px[w // 2, h // 2][3]
        ok = (max(alphas) == 0) and rgb_bad == 0 and center_a == 255
        detail = ("四角alpha=%s 透明区RGB非零=%d 中心alpha=%d" % (alphas, rgb_bad, center_a))
        rows.append((s, ok, detail))
    return rows


def verify() -> bool:
    if not os.path.isfile(OUT):
        print("[验] 失败：产物不存在 %s" % OUT)
        return False
    with open(OUT, "rb") as f:
        head = f.read(6)
    reserved, itype, count = struct.unpack("<HHH", head)
    print("[验] %s  ICONDIR reserved=%d type=%d count=%d  bytes=%d"
          % (os.path.basename(OUT), reserved, itype, count, os.path.getsize(OUT)))
    ok_all = (reserved == 0 and itype == 1 and count == len(SIZES))
    print("[验] 容器头判定 = %s（reserved==0 / type==1 / count==%d）"
          % ("PASS" if ok_all else "FAIL", len(SIZES)))

    ico = Image.open(OUT)
    have = set(ico.info.get("sizes", set()))
    want = {(s, s) for s in SIZES}
    print("[验] 内含尺寸 = %s" % (sorted(have),))
    if have != want:
        print("[验] 尺寸集合不符：缺 %s，多 %s" % (sorted(want - have), sorted(have - want)))
        ok_all = False
    else:
        print("[验] 尺寸集合判定 = PASS（恰含 %s）" % (sorted(want),))

    with open(OUT, "rb") as f:
        blob = f.read()
    planes_bad = 0
    for i in range(count):
        planes = struct.unpack_from("<H", blob, 6 + i * 16 + 4)[0]
        if planes != 1:
            planes_bad += 1
    print("[验] 六帧 wPlanes 规范判定 = %s（非 1 的条目数=%d）"
          % ("PASS" if planes_bad == 0 else "FAIL", planes_bad))
    ok_all = ok_all and planes_bad == 0

    for s, ok, detail in _frame_report():
        print("[验]   %3dx%-3d %s  %s" % (s, s, "PASS" if ok else "FAIL", detail))
        ok_all = ok_all and ok

    print("[验] ===== 真透明多尺寸 ICO 判定：%s =====" % ("VERIFY PASSED" if ok_all else "VERIFY FAILED"))
    return ok_all


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="只校验既有产物，不重新生成")
    args = ap.parse_args()
    if not args.verify:
        if not os.path.isfile(SRC):
            print("[源] 失败：图源不存在 %s" % SRC)
            return 2
        build(audit_source(SRC))
    return 0 if verify() else 1


if __name__ == "__main__":
    sys.exit(main())
