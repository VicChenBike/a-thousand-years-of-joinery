extends "res://tests/test_base.gd"
## 批次 W（W5）摄像头菜单两处修复（P2-5a/P2-5b，spec §6；只增不减增量件）：
##   A（P2-5a）EMPTY 态接受后续 init#1——8s 超时置 EMPTY 后枚举到达照常重建下拉退出 EMPTY
##     （打包实测 t≈17s 才绑端口，8s 内无枚举 → 旧口径定格「未检测到摄像头」永不刷新）。
##   B（P2-5b）probe_result/matrix 回包按设备 id 匹配行——_rows 行 meta cam_id 查找，取代
##     数组下标（CAP 索引不连续如 [0,2] 时旧下标错位/越界回退 null → 子列恒「检测中…」）。
## 风格与夹具沿 test_v_camera_menu.gd：菜单段直操 GestureBridge autoload 私有缓存注入枚举/矩阵。
## 清档纪律：本测试零写档（不点设备/分辨率/帧率行 → _remember_camera_choice 零调用；open_menu
## 预热与 PROBE_MATRIX 发送为 UDP 旁路，无 user:// 触碰）→ 无需备份还原组（规范第 1 条不触发）。
## 零摄像头纪律：全程无头，不真拉起手势子进程。MenuState 序 EMPTY=0/LOADING=1/LOADED=2。

var bridge: Node   # autoload 实例（菜单段数据源）

func _abs_bridge_caches_reset() -> void:
	bridge.set("_camera_enum", {})
	bridge.set("_camera_matrix", {})
	bridge.set("_camera_errors", [])
	bridge.set("_probe_matrix_cache", {})

func _make_menu() -> Control:
	var m: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	add_child(m)
	await process_frame
	return m

func _label_texts(node: Node) -> Array:
	var out: Array = []
	for c: Variant in node.get_children():
		if c is Label:
			out.append(String((c as Label).text))
		out.append_array(_label_texts(c as Node))
	return out

func _res_box_texts(menu: Control) -> Array:
	var out: Array = []
	var box: Variant = menu.get("_res_box")
	if box == null or not is_instance_valid(box):
		return out
	for n: Variant in ((box as Container).get_children()):
		if n is Button:
			out.append(String((n as Button).text))
	return out

func _initialize() -> void:
	print("== test_w_camera_menu（批次 W5：P2-5a EMPTY 刷新 / P2-5b 按 id 匹配行；W2 追加段 C：P2-3b 记忆名解析纯函数缝；W3 追加段 E：N3 摄像头窗占位常驻） ==")
	bridge = get_root().get_node("GestureBridge")
	_abs_bridge_caches_reset()
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	await _a_empty_accepts_enum()
	await _b_row_match_by_id()
	await _c_resolve_memory_name_pure()
	await _d_device_memory_writes_display_name()
	await _e_camera_placeholder_always()
	_abs_bridge_caches_reset()
	finish()

# ================= 段 A（P2-5a）：EMPTY 态接受后续 init#1 刷新 =================
func _a_empty_accepts_enum() -> void:
	var menu: Control = await _make_menu()
	# A1 前置：无缓存打开 → LOADING → 注入 9s 前时间戳 → 超时 EMPTY（既有语义回归锚）。
	bridge._camera_enum = {}
	menu.call("open_menu")
	check_eq(int(menu.get("state")), 1, "A1: 无缓存 LOADING（MenuState.LOADING=1，回归锚）")
	menu.set("_open_at", Time.get_ticks_msec() / 1000.0 - 9.0)
	menu.call("_check_timeout")
	check_eq(int(menu.get("state")), 0, "A2: 8s 超时 → EMPTY（回归锚）")
	check(_label_texts(menu.get("_root_box") as Node).has("未检测到摄像头"),
		"A3: EMPTY 占位文案在场（回归锚）")
	# A4 修复点：EMPTY 态收到 init#1 → 重建下拉退出 EMPTY（旧口径只接受 LOADING/LOADED，必红）。
	var cams: Array = [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}]
	bridge._camera_enum = {"cameras": cams, "current_camera": 0}
	menu.call("_on_enum", cams, 0)
	check_eq(int(menu.get("state")), 2,
		"A4: EMPTY 态 init#1 → LOADED（红：旧口径 _on_enum 对 EMPTY 零操作，下拉定格「未检测到摄像头」）")
	check_eq((menu.get("_rows") as Array).size(), 2, "A5: EMPTY 刷新后设备列表 2 行（重建生效）")
	check(not _label_texts(menu.get("_root_box") as Node).has("未检测到摄像头"),
		"A6: EMPTY 占位文案清除（实际 %s）" % [_label_texts(menu.get("_root_box") as Node)])
	check_eq(float(menu.get("_open_at")), -1.0,
		"A7: 退出 EMPTY 清超时哨兵 _open_at（防残留时间戳参与后续 LOADING 超时误判）")
	# A8 回归锚：LOADED 态 init#1 再到达仍照常刷新（旧语义零回归）。
	var cams2: Array = [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}, {"id": 2, "name": "CamC"}]
	bridge._camera_enum = {"cameras": cams2, "current_camera": 1}
	menu.call("_on_enum", cams2, 1)
	check_eq(int(menu.get("state")), 2, "A8: LOADED 态 init#1 照常刷新（回归锚）")
	check_eq((menu.get("_rows") as Array).size(), 3, "A9: 刷新后设备列表 3 行（列表随枚举更新）")
	menu.free()

# ================= 段 B（P2-5b）：probe/matrix 回包按设备 id 匹配行（不连续 id 集 [0,2]） =================
func _b_row_match_by_id() -> void:
	var menu: Control = await _make_menu()
	# B1 前置：不连续 id 集（0,2）——置灰缺席场景等价的 id 空洞；行 meta 绑定设备 id。
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 2, "name": "C"}], "current_camera": 0}
	bridge._camera_matrix = {}
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	check_eq(rows.size(), 2, "B1: 设备列表 2 行（ids 0/2，前置）")
	check_eq(int((rows[0] as Button).get_meta("cam_id", -1)), 0, "B2: 行 0 meta cam_id==0（行数据绑 id）")
	check_eq(int((rows[1] as Button).get_meta("cam_id", -1)), 2, "B3: 行 1 meta cam_id==2（id 空洞在场）")
	# B4 新缝直测：_row_for_id 按 meta 查行（红：P2-5b 前无本方法）。
	if menu.has_method("_row_for_id"):
		check((menu.call("_row_for_id", 2) as Control) == (rows[1] as Control),
			"B4: _row_for_id(2)==meta 匹配行（红：P2-5b 前无本方法）")
		check(menu.call("_row_for_id", 1) == null, "B5: _row_for_id(1) 无匹配→null（id 不在列表）")
	else:
		check(false, "B4: _row_for_id 缺失（红）")
		check(false, "B5: _row_for_id 缺失（红）")
	# B6 修复点①：probe_result(id=2) 到达 → id=2 行锚定重建（旧下标 rows[2] 越界→null→恒「检测中…」）。
	menu.call("_open_res_sub", 2, rows[1] as Control)
	check_eq(int(menu.get("_res_for_id")), 2, "B6: 子列服务设备 id=2（前置）")
	check(_res_box_texts(menu).has("检测中…"), "B7: 无探测缓存 →「检测中…」等待态（前置）")
	bridge._probe_matrix_cache[2] = {"ok": true, "resolutions": [[1280, 720], [640, 480]], "fps_options": [30]}
	menu.call("_on_probe_result", 2, true, [], [])
	check(_res_box_texts(menu).has("1280x720"),
		"B8: probe_result(id=2) → id=2 行锚定重建出矩阵（红：旧 rows[2] 下标越界回退 null 零重建）")
	check(not _res_box_texts(menu).has("检测中…"), "B9: 等待态消除（回包已消费）")
	# B10 修复点②：matrix 回包（id==current=2 的等待瞬时窗）→ 按 id 匹配行重建（旧 rows[2] 同病）。
	menu.call("_close_res")
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 2, "name": "C"}], "current_camera": 2}
	bridge._camera_matrix = {}
	menu.call("_open_res_sub", 2, rows[1] as Control)
	check(_res_box_texts(menu).has("检测中…"), "B11: current=2 矩阵瞬时窗等待态（init#2 未到，前置）")
	bridge._camera_matrix = {"resolutions": [[800, 600]], "fps_options": [60]}
	menu.call("_on_matrix", [], [])
	check(_res_box_texts(menu).has("800x600"),
		"B12: matrix 回包 → _res_for_id=2 按 id 匹配行重建（红：旧 rows[2] 越界回退 null 零重建）")
	# B13 负路径：未知 id 回包零重建零崩（.get/meta 防御，坑⑪纪律）。
	menu.call("_on_probe_result", 99, true, [], [])
	check(_res_box_texts(menu).has("800x600"), "B13: 未知 id=99 回包 → 子列不受扰（防御路径）")
	menu.call("_close_subs")
	menu.free()

# ================= 段 C（批次 W2 追加，P2-3b）：桥侧记忆名→id 解析纯函数缝 =================
## 契约（批次 W 规格 §3 P2-3b）：GestureBridge._resolve_target_camera_id(枚举缓存 cameras 数组,
## 记忆名) → id 或 -1 的静态纯函数（无副作用，无头直测）——记忆名 trim 后按显示名精确匹配枚举
## 条目；旧档纯数字残留按旧 CAP 索引语义解释一次（id 在枚举中才命中）；未记忆/匹配不到 → -1
## （调用方 ensure_camera_open 走既有回落链：枚举首项→0；回落逻辑归 W4/N5，本段只锁解析缝）。
## 零写档纪律不变（纯函数直测，不触碰 user://）。
func _c_resolve_memory_name_pure() -> void:
	# 静态方法经实例调用（GDScript 4 允许；bridge=autoload 实例，本文件既有夹具）
	var cams: Array = [{"id": 0, "name": "HD Camera"}, {"id": 3, "name": "USB Camera"}]
	# C1 名字精确命中（红：P2-3b 前无本方法 → Missing method 中止断言段，has_method 守卫防挂死）
	if not bridge.has_method("_resolve_target_camera_id"):
		check(false, "C1: _resolve_target_camera_id 方法缺失（红）")
		check(false, "C2: 纯函数缝未实现（红）")
		return
	check_eq(int(bridge._resolve_target_camera_id(cams, "HD Camera")), 0,
		"C1: 记忆名命中 → 对应设备 id 0")
	check_eq(int(bridge._resolve_target_camera_id(cams, "USB Camera")), 3,
		"C2: 记忆名命中第二设备 → id 3")
	# C3 trim 语义：记忆名与条目名两侧空白不敏感（规格「名字 trim→枚举匹配」）
	check_eq(int(bridge._resolve_target_camera_id(cams, "  HD Camera  ")), 0,
		"C3: 记忆名带首尾空格 trim 后命中")
	# C4 旧档纯数字残留命中：按旧 CAP 索引语义解释一次（id 在枚举中）
	check_eq(int(bridge._resolve_target_camera_id(cams, "3")), -1,
		"C4（AD 等价替换）: 数字残留不再按 CAP 索引解释 → -1（禁止依赖 CAP 索引；旧断言为 3）")
	# C5 旧档数字残留不命中：id 不在枚举 → -1（回落判定交调用方）
	check_eq(int(bridge._resolve_target_camera_id(cams, "9")), -1,
		"C5: 数字残留 \"9\" 亦不命中 → -1（AD：数字一律不按 CAP 索引解释）")
	# C6 名字不在枚举 → -1
	check_eq(int(bridge._resolve_target_camera_id(cams, "Ghost Cam")), -1,
		"C6: 记忆名不在枚举 → -1")
	# C7 未记忆（空串/纯空格）→ -1
	check_eq(int(bridge._resolve_target_camera_id(cams, "")), -1, "C7: 空记忆名 → -1（未记忆）")
	check_eq(int(bridge._resolve_target_camera_id(cams, "   ")), -1, "C8: 纯空格记忆名 trim 后 → -1")
	# C9 旧字符串条目契约（normalize_cam_entry 同源：名即值）——数字条目走旧语义命中
	var legacy_cams: Array = ["0", "1"]
	check_eq(int(bridge._resolve_target_camera_id(legacy_cams, "1")), -1,
		"C9（AD 等价替换）: 旧字符串条目 + 数字记忆 → 数字语义退役 → -1（旧断言为 1）")
	check_eq(int(bridge._resolve_target_camera_id(legacy_cams, "HD Camera")), -1,
		"C10: 旧字符串条目枚举 + 名字记忆 → 无名可匹 -1")
	# C11 脏条目防御：名字命中但 id 缺失/不可解析 → -1（坑⑪ .get 纪律）
	check_eq(int(bridge._resolve_target_camera_id([{"name": "X"}], "X")), -1,
		"C11: 名字命中但 id 缺失 → -1（脏条目防御）")
	# C12 空枚举 + 任意记忆 → -1
	check_eq(int(bridge._resolve_target_camera_id([], "HD Camera")), -1,
		"C12: 枚举缓存空 → -1")

# ================= 段 D（批次 W2 追加，P2-3b/N10 写入端）：设备行点击记显示名 =================
## 契约（批次 W 规格 §3 P2-3b/N10）：camera_menu 设备行点击写档 gesture_camera_device=设备
## **显示名**（String 契约保持，id 语义由 CAP 索引升级为名字）；显示名空（旧条目异常态）回落
## str(id)（旧数字语义仍可经桥 _resolve_target_camera_id 兼容路径解析一次）。
## ⚠ 清档纪律例外（相对本文件 A/B/C 段零写档口径）：本段点击设备行触发 _remember_camera_choice
## → SaveManager.update_settings → save_game 落盘 user://save.json——段内自含备份/还原组
## （test_w_save_resilience 四件组先例：备份→测试域操作→还原+load_game 重同步+逐字节等价断言）。
const D_SAVE_PATH := "user://save.json"
const D_FLAG_PATH := "user://first_launch.flag"
const D_TMP_PATH := "user://save.json.tmp"
const D_BAK_PATH := "user://save.json.bak"
const D_BK_PREFIX := "user://_w2_cammenu_"
const D_WATCHED: Array = [D_SAVE_PATH, D_FLAG_PATH, D_TMP_PATH, D_BAK_PATH]
var _d_pre_save_text: String = ""

func _d_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _d_del(p: String) -> void:
	var a: String = _d_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _d_backup_user() -> void:
	if FileAccess.file_exists(D_SAVE_PATH):
		_d_pre_save_text = FileAccess.get_file_as_string(D_SAVE_PATH)
	for p: String in D_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = D_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_d_abs(p), _d_abs(bk))
			check(FileAccess.file_exists(bk), "D0 备份落位自检：%s" % bk)

func _d_restore_user() -> void:
	for p: String in D_WATCHED:
		_d_del(p)
		var bk: String = D_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_d_abs(bk), _d_abs(p))
			DirAccess.remove_absolute(_d_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(D_SAVE_PATH) if FileAccess.file_exists(D_SAVE_PATH) else ""
	check_eq(post, _d_pre_save_text, "D 清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|w_camera_menu_d|files=%d" % D_WATCHED.size())

func _d_device_memory_writes_display_name() -> void:
	_d_backup_user()
	var save: Node = root.get_node_or_null(NodePath("SaveManager"))
	if save != null:
		save.call("load_game")  # --script 模式 autoload _ready 延迟（test_gesture_bridge_ports 先例）
	var menu: Control = await _make_menu()
	# D1 点击非当前设备行 → 写档=显示名（红：旧实现写 str(id)="2"）
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 2, "name": "USB Cam"}], "current_camera": 0}
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	check_eq(rows.size(), 2, "D1 前置：设备列表 2 行")
	(rows[1] as Button).pressed.emit()
	if save != null:
		check_eq(String(save.call("get_settings").get("gesture_camera_device", "")), "USB Cam",
			"D1：点设备行写档=显示名「USB Cam」（红：旧实现写 CAP 索引 \"2\"）")
		var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(D_SAVE_PATH)) \
			if FileAccess.file_exists(D_SAVE_PATH) else null
		var disk_ok: bool = typeof(disk) == TYPE_DICTIONARY \
			and String((disk as Dictionary).get("settings", {}).get("gesture_camera_device", "")) == "USB Cam"
		check(disk_ok, "D2：写档即时落盘（save.json settings.gesture_camera_device=USB Cam）")
	# D3 显示名空（旧条目异常态）→ 回落 str(id)（旧数字语义可解析）
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": ""}], "current_camera": 0}
	menu.call("open_menu")
	var rows2: Array = menu.get("_rows")
	check_eq(rows2.size(), 2, "D3 前置：重建列表 2 行（含空名条目）")
	(rows2[1] as Button).pressed.emit()
	if save != null:
		check_eq(String(save.call("get_settings").get("gesture_camera_device", "")), "1",
			"D3：空显示名回落 str(id)=\"1\"（旧数字语义兼容锚）")
	menu.free()
	_d_restore_user()

# ================= 段 E（批次 W3 追加，N3）：摄像头窗占位常驻 + 状态文案 =================
## 契约（批次 W 规格 §4 N3）：HUD 停靠组可见时 camera_window 恒 visible（旧 V7 子件门
## 「整组 ∧ gesture_camera_enabled」废止留痕——门控链存在 falsy 路径、精确源依 save.json
## 形态而定；W3 探针在无头首启模拟复现窗隐，勿按单一根因回溯排查）。恒显后占位区不再受
## 设置态门控，窗内文案按桥连接态自述（消费 W2 §3 支撑项只读态 API is_camera_intentionally_released）：主动关=「摄像头已关闭」/ 枚举空=
## 「未检出摄像头」/ LOADING·READY 无帧=「摄像头启动中…」/ 其余 UNAVAILABLE=「摄像头暂未打开」
## （既有文案回归锚）。READY 有帧时 _on_camera_frame 隐占位（S13 语义不变）。
## 清档纪律：E 段仅直改内存 settings（不 update_settings 不落盘），尾段还原；桥态注入后全量复位。
func _e_camera_placeholder_always() -> void:
	var save: Node = root.get_node_or_null(NodePath("SaveManager"))
	# AF 同步批（2026-11-01）：段首内存钉 gesture_input=true（同段 E1 的内存直改惯例，不落盘；
	# 尾段还原）。实证：apply_dock_state 可见门 `gesture_hud_visible ∧ gesture_input` 在用户存档
	# Q3 双关（gesture_input=false）时整组 visible=false 提前 return，其尾段 W-N3 占位刷新
	# `_refresh_camera_placeholder()` 不可达——E3/E4 文案断言依赖该刷新路径（E2/E5/E6 走
	# load_state_changed 信号路径侥幸绿），属夹具对存档环境敏感，非代码回归。
	var gi_saved_e: bool = true
	if save != null:
		gi_saved_e = bool((save.call("get_settings") as Dictionary).get("gesture_input", true))
		(save.call("get_settings") as Dictionary)["gesture_input"] = true
	var hud: Control = (load("res://scenes/shared/gesture_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	# E1 恒显：设置键 false（内存直改不落盘）→ 窗仍显（红：旧子件门 false 窗隐）
	var cam_saved: bool = true
	if save != null:
		var st: Dictionary = save.call("get_settings")
		cam_saved = bool(st.get("gesture_camera_enabled", true))
		st["gesture_camera_enabled"] = false
	hud.call("apply_dock_state", 1, false, false)   # 1=Game.State.MAIN_MENU（直驱停靠）
	check_eq(bool(hud.camera_window.visible), true,
		"E1: 设置关时摄像头窗仍显（占位常驻；红：旧子件门=设置键，窗隐）")
	if save != null:
		(save.call("get_settings") as Dictionary)["gesture_camera_enabled"] = cam_saved
	# E2 LOADING → 启动中…
	bridge._set_state(0)
	hud.call("apply_dock_state", 1, false, false)
	check(String(hud.camera_hint.text).contains("启动中"),
		"E2: LOADING 占位文案「启动中…」（实测 %s）" % hud.camera_hint.text)
	check(bool(hud.camera_hint.visible) and bool(hud.camera_bg.visible), "E2 前置：占位/bg 可见")
	# E3 UNAVAILABLE + 主动关 → 已关闭（消费桥只读态 API）
	bridge._set_state(2)
	bridge.set("_intentional_stop", true)
	hud.call("apply_dock_state", 1, false, false)
	check(String(hud.camera_hint.text).contains("已关闭"),
		"E3: 主动关后占位文案「已关闭」（红：旧恒「摄像头暂未打开」；实测 %s）" % hud.camera_hint.text)
	# E4 UNAVAILABLE + 未主动关 + 枚举空 → 未检出
	bridge.set("_intentional_stop", false)
	bridge.set("_camera_enum", {})
	hud.call("apply_dock_state", 1, false, false)
	check(String(hud.camera_hint.text).contains("未检出"),
		"E4: 枚举空占位文案「未检出摄像头」（实测 %s）" % hud.camera_hint.text)
	# E5 UNAVAILABLE + 枚举非空 → 暂未打开（既有文案回归锚）
	bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}], "current_camera": -1})
	hud.call("apply_dock_state", 1, false, false)
	check_eq(String(hud.camera_hint.text), "摄像头暂未打开",
		"E5: 枚举非空 UNAVAILABLE 维持「摄像头暂未打开」（既有文案回归锚）")
	# E6 READY 无帧 → 占位可见且文案复位为启动中（防旧文案残留跨态带出）
	bridge._set_state(1)
	hud.call("apply_dock_state", 1, false, false)
	check(bool(hud.camera_hint.visible) and String(hud.camera_hint.text).contains("启动中"),
		"E6: READY 无帧占位可见+文案复位（实测 %s）" % hud.camera_hint.text)
	# E7 整组隐（手势关）时窗随组隐（整组门不受 N3 影响——恒显仅限停靠组可见时）
	if save != null:
		(save.call("get_settings") as Dictionary)["gesture_input"] = false
	hud.call("apply_dock_state", 1, false, false)
	check_eq(bool(hud.visible), false, "E7 前置：手势关整组隐（整组门回归锚）")
	if save != null:
		(save.call("get_settings") as Dictionary)["gesture_input"] = true
	# AF 同步批：段首钉住的 gesture_input 还原（E7 自身的 false→true 演练已在上两行完成；
	# 此处恢复为段前真实存档值，保持「E 段仅直改内存、尾段全还原」纪律）
	if save != null:
		(save.call("get_settings") as Dictionary)["gesture_input"] = gi_saved_e
	# 复位桥态（A~D 段既有口径）
	bridge._set_state(1)
	_abs_bridge_caches_reset()
	hud.free()
	await process_frame
