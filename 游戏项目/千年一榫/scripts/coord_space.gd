extends RefCounted
## 窗口缩放坐标修复批（2026-09-18）：content(逻辑)↔device(设备) 坐标换算纯函数收口。
## 无 class_name（工程纪律：消费方 preload/load 规避 class_name 时序，settings_panel WM 同款）。
##
## ── 口径契约：逻辑论证+生产反证+窗口探针实测三重定案（探针为临时件已清理，结论留痕于
## 本注释与 AI工作记录/打包版实测修复批_探针证据摘要_20260918.md；勿再改动方向）──
## 1) 本工程 stretch=canvas_items/aspect=expand 下，root 视口 visible_rect 恒 (1152,648)，
##    content→渲染设备 = 逐轴 ×(window/visible)（probe2 绿标 content(780,300)→渲染(913,351)
##    = ×(1.170139,1.169753) 实测；渲染目标=窗口尺寸 1348×758）。
## 2) ui_material.gdshader 族（u_mouse_screen/u_ellipse/u_rect_size/u_viewport_size）：
##    全 content 逻辑系——shader 端 spx=SCREEN_UV×u_viewport_size 恒等于 content 坐标
##    （SCREEN_UV=设备px/整屏，×visible 恒还原 content，与窗口尺寸无关），故鼠标必须喂
##    content（修复1）；u_ellipse/u_rect_size 本就 content 系不动，rx 保持逻辑值不乘 scale。
## 3) hover_glow.gdshader 族（u_rects/u_ellipses/u_mouse_px）：全设备系——FRAGCOORD=渲染目标
##    像素（窗口相对设备 px），u_mouse_px 经 Viewport.get_screen_transform()（含拉伸）×content
##    =同系（probe2 实测 vp_xf origin=(0,0) 窗口相对、无桌面原点项，与 FRAGCOORD 恒一致；
##    若未来引擎版本引入桌面原点语义须重验，实机留待项）。u_rects/u_ellipses 原经
##    CanvasItem.get_screen_transform() 产出（不含拉伸=content）系同族失配——2026-09-18
##    追加批已按授权补修：window_manager._push 与 level_scene 气泡光晕产出统一经
##    rect_device_from_content 换设备系（第三处供给点同批分流）。
## 4) 嵌入式 PopupPanel.position（修复2）：消费「根窗口 content 坐标」（probe2 D1 实测：
##    position=(780,300) → 渲染设备恰=×s=行 content 右缘；若按设备系换算（probe1 B 式）
##    反而右漂 (s−1)×锚点x ≈ +132px）。Control.get_screen_transform()（CanvasItem 版，
##    不含拉伸）的 origin 即根 content 系坐标——现行「origin+逻辑宽」公式坐标正确，
##    本批收口到 popup_anchor_px 单一漏斗并锁死口径。
## 5) 两族禁止混乘。CanvasItem.get_screen_transform()（content，不含拉伸）与
##    Viewport.get_screen_transform()（device，含拉伸）同名异义，系本批诊断误判的根因级
##    陷阱：诊断把前者当设备值（后者才是）。

## 光斑 ui_material 族口径选择：手势光标可见 → 光标 content 坐标；否则真实鼠标 content 坐标
## （键鼠零感知：null 回落，main.gd _resolve_pointer_content 消费）。
static func hover_pointer_content(cursor_pos: Variant, mouse_content: Vector2) -> Vector2:
	if cursor_pos != null:
		return cursor_pos
	return mouse_content

## content→渲染设备像素（hover_glow 族）：stretch 变换由调用方经
## Viewport.get_screen_transform() 取得（与 main.gd _resolve_pointer_px 同源口径）。
static func device_from_content(p: Vector2, stretch: Transform2D) -> Vector2:
	return stretch * p

## content 矩形→渲染设备矩形（hover_glow 修复批追加）：两角过 device_from_content、
## 尺寸乘拉伸 scale 对应轴（逐轴，expand 下 sx≠sy 恒正确）。消费方：window_manager._push
## （u_rects/u_ellipses）、level_scene._tick_bubble_hover（气泡光晕 u_rects）。
static func rect_device_from_content(r: Rect2, stretch: Transform2D) -> Rect2:
	return Rect2(stretch * r.position, r.size * stretch.get_scale())

## 嵌入式 PopupPanel.position 锚（修复2 单一漏斗）：锚控件「根 content 系」origin + content 偏移。
## Vector2i 截断口径与旧式 Vector2i(origin+offset) 逐位一致（任意 s 行为不变）。
## 消费方：camera_menu.gd _open_res_sub/_open_fps_sub、settings_panel.gd _on_arrow_pressed。
static func popup_anchor_px(origin_content: Vector2, offset: Vector2) -> Vector2i:
	return Vector2i(origin_content + offset)
