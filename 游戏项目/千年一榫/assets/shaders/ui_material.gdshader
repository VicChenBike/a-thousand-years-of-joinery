shader_type canvas_item;
// L-A（L7/L6-1，spec §5.3/§5.4 定稿）：统一 UI 模拟光影材质——非破坏叠加在主题 StyleBox
// 之上（COLOR=主题四态已绘样式）。左上方向光+右下内阴影+边缘伪法线+鼠标第二点光
// +磨砂噪声。面板档（u_panel_mode=1）：SDF 形状裁剪（u_ellipse_use=1 为
// D 形椭圆弧容器、=0 为圆角矩形卡片）+材质外投影(offset 3,5)。
// M-C（2026-09-07，spec §3.3）：鼠标第二点光重做——删 Blinn 镜射（m03 射线根因）、
// 衰减改高斯 exp(−d²/r²)（手电筒柔光）、按钮档 140/0.30·0.26、容器档 280。
uniform vec2 u_rect_size = vec2(100.0, 40.0);
uniform vec2 u_light_dir = vec2(-0.85, -0.5);
uniform float u_dir_energy = 0.55;
uniform vec3 u_light_color = vec3(1.0, 0.96, 0.88);
uniform vec2 u_mouse_screen = vec2(-9999.0); // L-D 二轮修4：第二光源中心=屏幕像素口径（原局部 UV 口径实测不可见，见下）
uniform vec2 u_viewport_size = vec2(1152.0, 648.0); // L-D 二轮修4：main.gd 每帧随 hover 写入
uniform float u_hover = 0.0;
uniform float u_hover_metal = 0.0; // M-D 追1（spec §3.4 目标行为 4）：悬停金属反光能量 0~1，
// 专用 hover 高光路径——由消费方（talk_controller）渐入渐出驱动，非悬停恒 0 高光不出现。
// 不取 SDF 伪法线、无 Blinn 半程向量（M-C 根除的镜射系不复活）：纯几何带状高斯衰减。
uniform float u_mouse_energy = 0.30;   // M-C 定档（HTML 原型复核采纳 spec 暂定 0.50→0.30，浅档 0.26 由 linker 覆写）
uniform float u_mouse_radius = 140.0;  // M-C 定档（按钮档 160→140；容器档 280 由 linker PANEL_PARAMS 覆写）
uniform float u_inner_shadow = 0.25;
uniform float u_frost = 0.06;
uniform vec3 u_edge_glow_color = vec3(1.0, 0.922, 0.706);
uniform int u_panel_mode = 0;
uniform int u_ellipse_use = 0;
uniform vec4 u_ellipse = vec4(0.0, 324.0, 440.0, 324.0); // M-B：xy=弧心局部像素，左贴弧口径 (0,H/2)、zw=(rx,ry)=(440,H/2)（端点顶满上下角；linker 每控件覆写同口径）
const float BEVEL = 6.0;
const float CORNER = 12.0; // M-A：按钮档圆角 10→12（与主题 Button StyleBox 圆角对齐，spec §3.1）
const float CORNER_PANEL = 12.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float sd_ellipse(vec2 p, vec2 c, vec2 ab) {
	// scale space 一阶近似（spec §5.3 提示；轴点精确，1.5px AA/掩码精度足够）
	// L-D 二轮修6：内部深度钳制 max(d, -min(ab)+8)——scale-space 在 q→0（椭圆中心）方向未定义，
	// 被本材质当伪法线用时会在容器中部渲染出「鱼嘴」状明暗伪影（第一轮走查 L05/L01b 实证）。
	// 钳成平台后内区梯度恒 0 → 伪法线取正 z（平坦面受光均匀），伪影消除；
	// 掩码/AA/外投影只看 d≈0 与 d>0 侧（钳制值 -272 远离 0），行为完全不变。
	vec2 q = (p - c) / ab;
	float d = (length(q) - 1.0) * ab.x * ab.y / max(length(vec2(ab.y * q.x, ab.x * q.y)), 1e-4);
	return max(d, -min(ab.x, ab.y) + 8.0);
}
float shape_d(vec2 p) {
	if (u_panel_mode == 1 && u_ellipse_use == 1) {
		// M-B（spec §3.2-2 凸块根除）：删除原「通高左缘窄条 ∪ 椭圆」并集——原窄条宽仅
		// (W-rx)/2≈5.85px 且覆盖 y 全高，在弧线端点之外上/下探出两块金色小条
		//（m01 左上/左下「凸块」根因）。现左贴弧口径下弧线端点严格顶满 (0,0)/(0,H)，
		// 形状仅由 sd_ellipse 承担；外投影分支（fragment 内 d_sh）不受影响。
		return sd_ellipse(p, u_ellipse.xy, u_ellipse.zw);
	}
	return sd_round_box(p - u_rect_size * 0.5, u_rect_size * 0.5,
		(u_panel_mode == 1) ? CORNER_PANEL : CORNER);
}
void fragment() {
	vec2 p = UV * u_rect_size;
	float d = shape_d(p);
	vec4 col = COLOR;
	bool in_shadow = false; // 面板档外投影提前出分支（4.7 实证：fragment() 内 return 非法，改旗标等价重构）
	if (u_panel_mode == 1) {
		float d_sh = shape_d(p - vec2(3.0, 5.0)); // 外投影（StyleBox shadow 已置 0，材质承担）
		if (d_sh > 0.0) {
			COLOR = vec4(vec3(0.0), (1.0 - smoothstep(0.0, 12.0, d_sh)) * 0.45);
			in_shadow = true;
		} else {
			col.a *= smoothstep(1.5, -1.5, d); // SDF 外全透明、边界 1.5px AA
		}
	}
	if (!in_shadow) {
		// M-B（spec §3.2-3 删双色圆）：容器档光照口径收敛——sd_ellipse 内部深度钳制平台
		//（d=-min(ab)+8）与边界带之间是一圈伪法线渐变环带（外向梯度），方向光 dot(n,L) 在环带
		// 上亮、中心平台均匀 → 椭圆内「一圈更亮内环+平坦内芯」两层色域（m01「内嵌双色圆」根因）。
		// 容器档禁用一切伪法线衍生项（方向光/内阴影/rim/镜射），只保留「底色×SDF 裁剪×
		// 平坦受光（法线恒 (0,0,1) 常量项）+点光平面漫反射（非伪法线衍生）+低幅噪声」；
		// 按钮档不动（方向光/内阴影/rim/M-A lum_w 暗像素衰减全保留）。旗标等价重构
		//（4.7 实证 fragment() 内 return 非法，spec §六坑 2）。
		bool is_container = (u_panel_mode == 1 && u_ellipse_use == 1);
		float e = 1.0;
		vec2 grad = vec2(shape_d(p + vec2(e, 0.0)) - shape_d(p - vec2(e, 0.0)),
			shape_d(p + vec2(0.0, e)) - shape_d(p - vec2(0.0, e)));
		float gl = length(grad);
		vec2 nxy = (gl > 0.0001) ? grad / gl : vec2(0.0);
		vec3 n = normalize(vec3(nxy, clamp(abs(d) / BEVEL, 0.0, 1.0)));
		vec2 ldn = normalize(u_light_dir); // 4.7 实证修正：u_light_dir 为 vec2，normalize 返回 vec2（计划稿 vec3 编译错）
		// M-A 回修（用户验收「常态金字叠金底看不清」，2026-09-07）：方向光原对按钮整个渲染结果
		// （含文字像素）恒定 +≈0.48 提亮，把深墨棕字洗成灰金、字底对比崩塌。加暗像素亮度权重
		// lum_w：深字（lum≈0.08）几乎不受方向光、金底（lum≈0.63）全额受光——字恢复深墨棕本色，
		// 底面立体光保留（印刷图案不参与表面受光，材质语义也更正确）。
		float lum_w = smoothstep(0.0, 0.45, dot(col.rgb, vec3(0.299, 0.587, 0.114)));
		if (is_container) {
			// 平坦受光常量项：法线恒 (0,0,1) 与光向 dot 对容器内所有像素同值——整面均匀受光，
			// 无环带无方向相干（双色圆物理上不可能再出现）；lum_w 对金底恒 ≈1，语义一致。
			float flat_lit = clamp(dot(vec3(0.0, 0.0, 1.0), normalize(vec3(u_light_dir, 0.6))), 0.0, 1.0);
			col.rgb += u_light_color * flat_lit * u_dir_energy * lum_w;
		} else {
			col.rgb += u_light_color * clamp(dot(n, normalize(vec3(u_light_dir, 0.6))), 0.0, 1.0) * u_dir_energy * lum_w; // 3)方向光（按钮档不动）
			float shade = clamp(dot(nxy, -ldn), 0.0, 1.0) * (1.0 - clamp(abs(d) / BEVEL, 0.0, 1.0)); // 4)右下内阴影
			col.rgb *= 1.0 - shade * u_inner_shadow;
			float rim = smoothstep(2.0, 0.0, abs(d)) * clamp(dot(nxy, ldn), 0.0, 1.0); // 5)受光缘 1px 亮线
			col.rgb += ((u_panel_mode == 1) ? u_edge_glow_color : u_light_color) * rim * 0.20; // M-A：0.35→0.20 受光缘收敛（按钮立体微修，spec §3.1）
		}
		// 6)鼠标第二点光（高斯衰减，M-C 手电筒化）。L-D 二轮修4：点光坐标改**屏幕像素口径**——
		//   当前像素屏幕坐标 = SCREEN_UV·u_viewport_size（与 u_mouse_screen/u_viewport_size 同口径，
		//   main.gd _process 每帧写视口尺寸）。原 UV·u_rect_size 局部坐标 vs 屏幕 u_mouse_screen
		//   口径错位（点光中心几乎永远落在控件外远处），分解探针实测 mean +0.00015 不可见。
		vec2 spx = SCREEN_UV * u_viewport_size;
		float d2 = distance(spx, u_mouse_screen);
		// M-C（spec §3.3，2026-09-07）：衰减 1/(1+(d/r)²)→高斯 exp(−d²/r²)（与 hover_glow 同族）——
		// 旧曲线长尾拖光、中心亮核小而锐（「一团亮点」观感，m03）；高斯边缘收束快，手电筒柔光形。
		float atten = u_mouse_energy * exp(-d2 * d2 / (u_mouse_radius * u_mouse_radius));
		// L-D 二轮走查四轮实证（DECOMP|L02）：漫反射改**平面法线口径** diff2=L2.z——
		// 原 dot(n,L2) 用 SDF 楔形伪法线（钮内 nxy=(0,±0.707,0.707) 横躺），与径向点光
		// 相干抵消：贡献只在光标水平 ±h 像素窄带内非零（h=0.8→mean 0.0043/h=2→0.0057/
		// h=8→0.0154，且呈横条状伪影观感）。平面法线（钮面朝上）diff2=h/√(d²+h²) 纯径向，
		// 观感=中心亮核+径向柔光（网页 hover 光晕形）。
		// M-C 删镜射（spec §3.3 根因 1）：原 Blinn 镜射项（半程向量 pow 32 次）与 SDF
		// 楔形伪法线相干——伪法线在「钳制平台外环」取外向梯度，镜射只在「光标位于该像素
		// 外向梯度方向」的像素带非零 → 沿「椭圆弧心→光标」径向线形成窄亮线（m03「朝左下
		// 角射线」根因；批次 L 漫反射已改平面法线，镜射仍用伪法线故射线残留；M-B 曾以
		// 旗标在容器档归零，本批连按钮档一并连根删除）——点光只剩「平面法线漫反射
		// diff2 × 高斯径向衰减 × hover」，纯径向无方向相干，射线物理上不可能再出现。
		vec3 L2 = normalize(vec3(u_mouse_screen - spx, 2.0));
		float diff2 = clamp(L2.z, 0.0, 1.0);
		col.rgb += u_light_color * diff2 * atten * u_hover;
		// 6b) M-D 追1：悬停金属反光带（专用 hover 高光路径，spec §3.4 目标行为 4）——
		// 过光标的斜向窄幅高光带（金属拉丝各向异性观感）：横向高斯 σ28px（窄幅）、
		// 沿带方向高斯 σ170px 柔焦，能量受 u_hover_metal 控制（非悬停恒 0 不出现）。
		// 纯几何带状衰减——不取 SDF 伪法线、无 Blinn 镜射（M-C 根除的镜射系不复活），
		// 各向平滑衰减无相干锐线，「射线/条带伪影」物理上不可能复现（M-C 同款验收）。
		vec2 hl_dir = normalize(vec2(0.94, -0.34));
		vec2 rel_m = spx - u_mouse_screen;
		float across_m = dot(rel_m, vec2(-hl_dir.y, hl_dir.x));
		float along_m = dot(rel_m, hl_dir);
		float metal = exp(-across_m * across_m / 784.0) * exp(-along_m * along_m / 28900.0);
		col.rgb += u_light_color * metal * u_hover_metal * 0.28;
		float noise = fract(sin(dot(floor(p / 3.0), vec2(127.1, 311.7))) * 43758.5453); // 7)磨砂颗粒
		col.rgb += (noise - 0.5) * u_frost;
		COLOR = col;
	}
}
