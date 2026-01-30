class_name MapSelectDetailPlay
extends Control

signal play_pressed
signal leaderboard_pressed
signal stats_pressed

var _entry: Dictionary = {}

@onready var _title: Label = $Panel/Title
@onready var _creator: Label = $Panel/Creator
@onready var _play_count: Label = $Panel/PlayCount
@onready var _death_count: Label = $Panel/DeathCount
@onready var _clear_count: Label = $Panel/ClearCount
@onready var _upload_date: Label = $Panel/UploadDate
@onready var _difficulty_icon: TextureRect = $Panel/DifficultyIcon
@onready var _rating_label: Label = $Panel/Rating
@onready var _play_button: BaseButton = $Panel/PlayButton
@onready var _leaderboard_button: BaseButton = $Panel/LeaderBoardButton
@onready var _stats_button: BaseButton = $Panel/StatsButton

func _ready() -> void:
	if _play_button != null and not _play_button.pressed.is_connected(_on_play_pressed):
		_play_button.pressed.connect(_on_play_pressed)
	if _leaderboard_button != null and not _leaderboard_button.pressed.is_connected(_on_leaderboard_pressed):
		_leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	if _stats_button != null and not _stats_button.pressed.is_connected(_on_stats_pressed):
		_stats_button.pressed.connect(_on_stats_pressed)
	_apply_entry()

func set_entry(entry: Dictionary) -> void:
	_entry = entry
	_apply_entry()

func _apply_entry() -> void:
	if _entry.is_empty():
		return
	var meta = _entry.get("metadata", null)
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	var title := str(_entry.get("title", meta.get("title", "")))
	_title.text = title if title.strip_edges() != "" else "untitled"
	_creator.text = str(_entry.get("creator", ""))
	_play_count.text = str(int(_entry.get("total_attempts", 0)))
	_death_count.text = str(int(_entry.get("total_deaths", 0)))
	_clear_count.text = str(int(_entry.get("total_clears", 0)))
	_upload_date.text = _format_date(_entry.get("created_at", ""))
	_update_difficulty_icon(int(_entry.get("rating", meta.get("rating", 1))))
	if bool(_entry.get("is_ranked", false)):
		_update_ranked()
	else:
		_rating_label.visible = false
		_leaderboard_button.visible = false

func _update_ranked() -> void:
	_rating_label.visible = true
	_rating_label.text = str(_entry.get("rating", ""))
	_leaderboard_button.visible = true

func _format_date(value: Variant) -> String:
	var text := str(value)
	if text == "":
		return "--"
	var parts := text.split("T")
	if parts.size() > 0:
		return parts[0]
	return text

func _update_difficulty_icon(difficulty: int) -> void:
	if _difficulty_icon == null:
		return
	var diff := clampi(difficulty, 1, 8)
	var path := "res://graphics/ui/16px/difficulty/%s.png" % str(diff)
	if ResourceLoader.exists(path):
		_difficulty_icon.texture = load(path)

func _on_play_pressed() -> void:
	play_pressed.emit()

func _on_leaderboard_pressed() -> void:
	leaderboard_pressed.emit()

func _on_stats_pressed() -> void:
	stats_pressed.emit()
