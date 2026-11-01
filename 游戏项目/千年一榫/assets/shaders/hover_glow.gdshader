shader_type canvas_item;
// L-A（L6-1/L6-2，spec §5.5 定稿）：收敛式双档掩码径向光斑（原满屏无掩码加色废弃）。
// 按钮/全局钮档=矩形掩码（向外 u_fade_radius 渐隐、之外恒 0）；容器档=与面板材质同源
// 椭圆 SDF 掩码（弧外楔形区恒 0）。g=exp(-d²/r²) 径向渐变（中心亮→边缘暗）。
// 坐标系：u_rects/u_ellipses/u_mouse_px 同一窗口屏幕像素坐标系（K-A 校准沿用，y 同向）。
// L-D 二轮修3（用户 L4 邻近联动诉求）：光斑中心改 **per-rect 最近点口径**——
// 中心 = clamp(u_mouse_px, rect_min, rect_max)（主目标内=光标本位；邻居钮=光标在该 rect
// 上的最近点）。原全目标共用「光标本位」单一中心时，邻居钮距光标 ~210px 处
// exp(-(210/65)²)≈4e-5 几乎无光（28:1 不可辨）；最近点口径下邻居近边距光标仅
// 半间隙（~100px，主钮 160 宽 52 高 → 中心到近边 ~77px），exp(-(77/65)²)≈0.25，
// 邻居近边带可见弱光、主>邻居次序不变（验收：邻居 mean 增量 ≥ 主钮 1/8，走查 L02）。
const int MAX_RECTS = 8;
uniform sampler2D screen_tex : hint_screen_texture;
uniform vec2 u_mouse_px = vec2(-1.0);
uniform vec4 u_rects[8];
uniform int u_rect_count = 0;
uniform float u_rect_strength[8];
uniform float u_fade_radius = 12.0;
// L-D 走查定档（spec §14-13 径向半径，档 按钮 60~120 / 容器 100~180）：90→65、140→110——
// ① 53px 高的按钮在 r=90 下 exp 面内变化仅 ~8%（exp(-(26/90)²)=0.92），观感是「平光斑」
//    而非用户要的「中心亮→边缘暗」径向渐变（网页 hover 光晕参照）；
// ② r=90 时按钮 37% 面积被加色推到 ≥0.97 近白（analyze_img 实测 3172/8480 px），
//    收半径把曝白区从「整块钮」缩到「光标邻域」，标签对比度得以保留。
// M-C（spec §3.3，2026-09-07，HTML 原型定档 tools_m_prototype/参数定档.md）：按钮档
// 65→85（光斑过小再放大，保留径向形状）；加色系数 0.26→0.16 uniform 化（降强保字，
// 验收红线=hover 态按钮文字与底亮度差 ≥0.18、曝白像素较基线降 ≥60%）。
uniform float u_glow_radius_btn = 85.0;
uniform float u_glow_radius_panel = 110.0;
uniform float u_glow_k = 0.16;
uniform vec4 u_ellipses[8];
uniform int u_mask_type[8];
uniform vec3 u_glow_color = vec3(1.0, 0.95, 0.8); // 浅色主题由 main.gd 写 (1.0,0.98,0.9)
uniform float u_strength = 1.0; // 0.12s 淡入淡出总幅（main.gd 维护）

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float sd_ellipse(vec2 p, vec2 c, vec2 ab) {
	vec2 q = (p - c) / ab;
	return (length(q) - 1.0) * ab.x * ab.y / length(vec2(ab.y * q.x, ab.x * q.y));
}
void fragment() {
	vec4 screen = texture(screen_tex, SCREEN_UV);
	float glow = 0.0;
	for (int i = 0; i < MAX_RECTS; i++) {
		if (i >= u_rect_count) { continue; }
		vec4 rc = u_rects[i];
		float mask = 0.0;
		if (u_mask_type[i] == 1) {
			vec4 el = u_ellipses[i];
			float md = sd_ellipse(FRAGCOORD.xy, el.xy, el.zw);
			mask = 1.0 - smoothstep(-1.5, 1.5, md); // 轮廓内=1、外=0、1.5px AA（spec §5.5 档二）
		} else {
			float md = sd_round_box(FRAGCOORD.xy - (rc.xy + rc.zw * 0.5), rc.zw * 0.5, 10.0);
			mask = 1.0 - smoothstep(0.0, u_fade_radius, md); // 矩形内=1、向外 12px 渐隐、之外恒 0
		}
		float rad = (u_mask_type[i] == 1) ? u_glow_radius_panel : u_glow_radius_btn;
		// L-D 二轮修3：per-rect 最近点中心（rc.xy=左上、rc.zw=尺寸；椭圆掩码档=容器包围 rect，
		// u_rects/u_mask_type/u_ellipses 数据布局与对齐关系不变）——光标在目标内=光标本位，
		// 光标在外=夹到 rect 边缘的最近点，邻居钮近边随之点亮（见文件头注释）。
		vec2 center = clamp(u_mouse_px, rc.xy, rc.xy + rc.zw);
		float d = distance(FRAGCOORD.xy, center);
		glow += exp(-d * d / (rad * rad)) * u_rect_strength[i] * mask;
	}
	glow *= u_strength;
	// M-C（spec §3.3-3）：加色系数 0.26→0.16（uniform u_glow_k，main.gd 每帧写入同值）——
	// hover「亮瞎」根因=加色主导项过强（L-D DECOMP 实证光斑 mean +0.206），降档保住
	// 「中心亮→边缘暗」形状只削亮度上限，按钮文字可读（红线 0.18 见 test_m_cursor_glow/走查）。
	COLOR = vec4(screen.rgb + u_glow_color * glow * u_glow_k, screen.a);
}
