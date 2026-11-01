class_name PortraitMetrics
extends RefCounted
## M-D（批次 M spec §3.4，2026-09-07）：立绘可见内容度量共享工具（静态方法类）。
## 根因背景：立绘 PNG 底部存在大片透明边（default_witness 实测 1966 高中 used_rect 仅到
## y=1418，透明边 548px）——历史上按「盒底=面板顶」对齐，可见脚部实际悬空过高且从未修对。
## 本工具读纹理 Image 的 used_rect（非透明像素包围盒），返回归一化与绝对像素两口径，
## 供 talk 立绘落位 / level 见证者气泡贴头统一按「可见内容」计算（47 皮肤同吃一套算法）。

## 路径级缓存（同路径二次调用不重复读盘解码；cache_hit_count 供测试断言缓存生效）
static var _cache: Dictionary = {}
static var cache_hit_count: int = 0

## 度量纹理可见内容包围盒。
## 返回 {"valid": bool, "rect_px": Rect2(绝对像素), "ratio": Rect2(归一化 0~1), "size": Vector2(纹理尺寸)}。
## 全 1 透明图 / 不可读路径 → valid=false 且 rect_px 为空 Rect2（防御，调用方回落旧锚）。
static func measure(texture_path: String) -> Dictionary:
	if _cache.has(texture_path):
		cache_hit_count += 1
		return _cache[texture_path]
	var out: Dictionary = {"valid": false, "rect_px": Rect2(), "ratio": Rect2(), "size": Vector2.ZERO}
	var img: Image = _read_image(texture_path)
	if img != null:
		var r: Rect2i = img.get_used_rect()
		var ts := Vector2(img.get_width(), img.get_height())
		if r.size.x > 0 and r.size.y > 0:
			out["valid"] = true
			out["rect_px"] = Rect2(Vector2(r.position), Vector2(r.size))
			out["ratio"] = Rect2(Vector2(r.position) / ts, Vector2(r.size) / ts)
		out["size"] = ts
	_cache[texture_path] = out
	return out

## KEEP_ASPECT_CENTERED 适配解算：纹理在盒内的显示布局与可见头顶/脚底盒内坐标。
## 返回 {"scale": float, "dx": float, "dy": float, "head_local_y": float, "foot_local_y": float}。
## 头/脚盒内 y 均为「纹理显示区」内坐标（乘 witness.scale 前的未缩放值）。
static func fit_in_box(tex_size: Vector2, used_rect: Rect2, box_size: Vector2) -> Dictionary:
	var sc := 1.0
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		sc = minf(box_size.x / tex_size.x, box_size.y / tex_size.y)
	var dx := (box_size.x - tex_size.x * sc) * 0.5
	var dy := (box_size.y - tex_size.y * sc) * 0.5
	return {
		"scale": sc, "dx": dx, "dy": dy,
		"head_local_y": dy + used_rect.position.y * sc,
		"foot_local_y": dy + used_rect.end.y * sc,
	}

## 读图：优先走导入纹理（打包导出后 res:// 内 png 为 .ctex，必须 load()），
## 回退 Image.load_from_file（user:// 运行时动态图，无导入系统场景）。
static func _read_image(path: String) -> Image:
	var img: Image = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	elif not path.begins_with("res://") and FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img != null and img.is_compressed():
		img.decompress()
	return img
