class_name MapSelectStatsPanel
extends "res://scripts/ui/popup_panel.gd"

signal close_pressed

@onready var _play_count: Label = $Panel/PlayCount
@onready var _death_count: Label = $Panel/DeathCount
@onready var _best_time: Label = $Panel/BestTime
@onready var _close_button: BaseButton = $Panel/CloseButton

func _ready() -> void:
	super()
	if _close_button != null and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)

func set_stats(total_attempts: int, total_deaths: int, best_time: String) -> void:
	if _play_count != null:
		_play_count.text = str(total_attempts)
	if _death_count != null:
		_death_count.text = str(total_deaths)
	if _best_time != null:
		_best_time.text = best_time if best_time != "" else "--:--"

func _on_close_pressed() -> void:
	close_pressed.emit()
