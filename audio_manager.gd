extends Node

var cat_sound_player: AudioStreamPlayer
var item_sound_player: AudioStreamPlayer
var typing_sound_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer

var sound_enabled = true
var bgm_enabled = true
var volume = 1.0

func _ready():
	cat_sound_player = AudioStreamPlayer.new()
	cat_sound_player.name = "CatSoundPlayer"
	cat_sound_player.stream = load("res://assets/sounds/cat.wav")
	add_child(cat_sound_player)

	item_sound_player = AudioStreamPlayer.new()
	item_sound_player.name = "ItemSoundPlayer"
	item_sound_player.stream = load("res://assets/sounds/item.wav")
	add_child(item_sound_player)

	typing_sound_player = AudioStreamPlayer.new()
	typing_sound_player.name = "TypingSoundPlayer"
	typing_sound_player.stream = load("res://assets/sounds/typing.wav")
	add_child(typing_sound_player)

	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BgmPlayer"
	var bgm_stream = load("res://assets/sounds/bgm.mp3")
	if bgm_stream:
		bgm_stream.loop = true
	bgm_player.stream = bgm_stream
	add_child(bgm_player)

	set_volume(volume)

	# 自动播放背景音乐
	if bgm_enabled and bgm_player.stream:
		bgm_player.play()

func play_cat_sound():
	if not sound_enabled:
		return
	if cat_sound_player and cat_sound_player.stream:
		cat_sound_player.play()

func play_item_sound():
	if not sound_enabled:
		return
	if item_sound_player and item_sound_player.stream:
		item_sound_player.play()

func play_typing_sound():
	if not sound_enabled:
		return
	if typing_sound_player and typing_sound_player.stream:
		typing_sound_player.play()

func set_volume(value):
	volume = clamp(value, 0.0, 1.0)
	var db = linear_to_db(volume)
	if cat_sound_player:
		cat_sound_player.volume_db = db
	if item_sound_player:
		item_sound_player.volume_db = db
	if typing_sound_player:
		typing_sound_player.volume_db = db
	if bgm_player:
		bgm_player.volume_db = db
