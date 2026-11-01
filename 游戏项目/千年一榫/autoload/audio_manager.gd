extends Node
## AudioManager：两首 BGM 全场景交替循环 + 淡入淡出 + 三总线音量。依据 spec 7.5。

signal bgm_track_changed(track_index: int)

const BGM_PATHS: Array[String] = ["res://assets/bgm/bgm_1.mp3", "res://assets/bgm/bgm_2.mp3"]
const FADE_SECONDS := 1.5
const FADE_MIN_DB := -40.0

var _players: Array[AudioStreamPlayer] = []
var _streams: Array[AudioStream] = []
var _current: int = -1
var _playing: bool = false
var _fade_tween: Tween

func _ready() -> void:
	for p: String in BGM_PATHS:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		_players.append(player)
		if ResourceLoader.exists(p):
			_streams.append(load(p))
		else:
			_streams.append(null)
			push_warning("BGM 缺失（静默运行）: %s" % p)
	# 设置变更联动
	var save_node: Node = get_node_or_null("/root/SaveManager")
	if save_node != null and save_node.has_signal("settings_changed"):
		save_node.settings_changed.connect(apply_volumes)

func start_bgm() -> void:
	if _playing:
		return
	_playing = true
	_play_track(0)

func stop_bgm() -> void:
	_playing = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	for player: AudioStreamPlayer in _players:
		player.stop()

func is_bgm_playing() -> bool:
	return _playing

## 淡出渐停（非硬停）：进入开场动画等场景把当前曲目渐弱后停止。幂等：已停止时只保持标志。
func fade_out_bgm(duration: float = FADE_SECONDS) -> void:
	if not _playing:
		return
	_playing = false
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
		# 交叉淡入淡出被打断时，旧曲残留仍在响：直接停掉防漏音
		for player: AudioStreamPlayer in _players:
			if player.playing and not (player == _current_player()):
				player.stop()
	var cur: AudioStreamPlayer = _current_player()
	if cur == null or not cur.playing:
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(cur, "volume_db", FADE_MIN_DB, duration)
	_fade_tween.tween_callback(cur.stop)

## 淡入恢复播放：离开开场动画等场景，从上次曲目续播（曲 0 起播请用 start_bgm）。幂等。
func fade_in_bgm() -> void:
	if _playing:
		return
	_playing = true
	_play_track(_current if _current >= 0 else 0)

func _current_player() -> AudioStreamPlayer:
	if _current >= 0 and _current < _players.size():
		return _players[_current]
	return null

func _play_track(index: int) -> void:
	if not _playing:
		return
	if _streams.is_empty():
		# _ready 尚未执行或无任何曲目资源：静默返回，不崩溃（spec 7.5）
		return
	var stream: AudioStream = _streams[index % _streams.size()]
	if stream == null:
		# 文件缺失：按曲目时长占位（180s）继续轮转，保持静默
		get_tree().create_timer(180.0).timeout.connect(_next_track)
		# 归一化再存 _current：原始 index 未取模会导致越界读 _players（BGM 轮转死亡）
		_current = index % _streams.size()
		bgm_track_changed.emit(_current)
		return
	var old: AudioStreamPlayer = _players[_current] if _current >= 0 else null
	# 归一化再存 _current：保证恒在 [0, _streams.size())，_players[_current] 与 _current_player() 永不越界
	_current = index % _streams.size()
	var player: AudioStreamPlayer = _players[_current]
	player.stream = stream
	player.volume_db = FADE_MIN_DB
	player.play()
	bgm_track_changed.emit(_current)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(player, "volume_db", 0.0, FADE_SECONDS)
	if old != null and old != player and old.playing:
		_fade_tween.tween_property(old, "volume_db", FADE_MIN_DB, FADE_SECONDS)
		_fade_tween.chain().tween_callback(old.stop)
	# 去重守卫：fade_out→fade_in 往返时 ONE_SHOT 连接未被消费，重复 connect 会导致
	# 播完一次触发两次 _next_track（连跳两曲/双轨齐响）
	if not player.finished.is_connected(_next_track):
		player.finished.connect(_next_track, CONNECT_ONE_SHOT)

func _next_track() -> void:
	if _playing:
		_play_track(_current + 1)

func apply_volumes() -> void:
	if not is_inside_tree():
		# 未入树（如无头测试 _initialize 阶段）不能用绝对路径 get_node，静默返回
		return
	var save_node: Node = get_node_or_null("/root/SaveManager")
	if save_node == null:
		return
	var settings: Dictionary = save_node.get_settings()
	# W9-6（批次 AA 规格 §12 P3-7）：volume 容器/子键双层类型防御——归一段（save_manager
	# _normalize_loaded_data）负责 load 路径，本处负责运行期路径（update_settings 合并可把非
	# 字典整体替换进 settings）；typed Dictionary 赋值遇 `[]` 会「Trying to assign Array to
	# Dictionary」运行期中止（4.7 探针实证），子键非数值同族。非字典→全默认；子键非数值→1.0。
	var vol_v: Variant = settings.get("volume", {})
	var volume: Dictionary = vol_v if typeof(vol_v) == TYPE_DICTIONARY else {}
	_set_bus("Master", _bus_linear(volume, "master"))
	_set_bus("Music", _bus_linear(volume, "music"))
	_set_bus("SFX", _bus_linear(volume, "sfx"))

static func _bus_linear(volume: Dictionary, key: String) -> float:
	## volume 子键取值：int/float 原样（clamp 交 _set_bus），其余（字符串/null/容器）回落 1.0。
	var v: Variant = volume.get(key, 1.0)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return 1.0

func _set_bus(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear) if linear > 0.0 else -80.0)
