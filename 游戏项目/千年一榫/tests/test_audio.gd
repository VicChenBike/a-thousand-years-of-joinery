extends "res://tests/test_base.gd"

func _initialize() -> void:
	print("== test_audio ==")
	# 1 总线布局：Master 存在，Music/SFX 挂在 Master 下，不存在 Voice
	var bus_count: int = AudioServer.bus_count
	var names: Array[String] = []
	for i: int in bus_count:
		names.append(AudioServer.get_bus_name(i))
	check(names.has("Master"), "存在 Master 总线")
	check(names.has("Music"), "存在 Music 总线")
	check(names.has("SFX"), "存在 SFX 总线")
	check(not names.has("Voice"), "无 Voice 总线")
	if names.has("Music"):
		check_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")), "Master", "Music 发送到 Master")

	# 2 AudioManager 接口可用、文件缺失不崩溃
	var am: Node = load("res://autoload/audio_manager.gd").new()
	add_child(am)
	am.name = "AudioManager"
	am.start_bgm()
	am.apply_volumes()
	check(true, "start_bgm/apply_volumes 在无音频文件时不崩溃")
	am.stop_bgm()
	check(true, "stop_bgm 不崩溃")

	# 3 淡出渐停/恢复接口（2026-08-27 开场动画 BGM 联动）
	# 经 Variant 动态调用：新接口在本测试编译时尚未入全局，须运行时分发
	var amp: Variant = am
	amp.start_bgm()
	check_eq(bool(amp.is_bgm_playing()), true, "前置：start_bgm 后 BGM 播放中")
	amp.fade_out_bgm()
	check_eq(bool(amp.is_bgm_playing()), false, "fade_out_bgm 后渐停（_playing=false）")
	amp.fade_out_bgm()
	check(true, "重复 fade_out_bgm 幂等不崩溃")
	check_eq(bool(amp.is_bgm_playing()), false, "重复 fade_out_bgm 后仍为停止")
	amp.fade_in_bgm()
	check_eq(bool(amp.is_bgm_playing()), true, "fade_in_bgm 后恢复播放（_playing=true）")
	amp.fade_in_bgm()
	check(true, "重复 fade_in_bgm 幂等不崩溃")
	check_eq(bool(amp.is_bgm_playing()), true, "重复 fade_in_bgm 后仍为播放")

	# 4 BGM 轮转不越界（2026-08-27 批次A P2 修复回归）：
	# 无头测试在 _initialize 阶段 quit 于首帧前，引擎不会触发 _ready，
	# 手动调用一次以镜像生产环境的 _players/_streams 初始化
	amp.call("_ready")
	# _next_track 连续轮转后 _current 必须恒在 [0, 1]，不得存未取模的原始 index
	for i: int in 5:
		amp.call("_next_track")
		var cur: int = int(amp.get("_current"))
		check(cur >= 0 and cur < 2, "第 %d 次 _next_track 后 _current=%d 恒在 [0,1] 内" % [i + 1, cur])
	check_eq(bool(amp.is_bgm_playing()), true, "连续轮转后 is_bgm_playing 仍正常")
	amp.fade_out_bgm()
	check_eq(bool(amp.is_bgm_playing()), false, "连续轮转后 fade_out_bgm 仍正常渐停")
	amp.fade_in_bgm()
	check_eq(bool(amp.is_bgm_playing()), true, "连续轮转后 fade_in_bgm 仍正常恢复")

	amp.stop_bgm()
	check(true, "fade 接口后 stop_bgm 硬停兜底不崩溃")
	finish()
