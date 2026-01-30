class_name MapSelectDetailEditor
extends Control

signal play_pressed
signal edit_pressed
signal delete_pressed
signal upload_pressed
signal title_changed(title: String)

var _entry: Dictionary = {}
var _ignore_title := false

@onready var _title: LineEdit = $Panel/Title
@onready var _file_name: Label = $Panel/FileName
@onready var _verified: Label = $Panel/Verified
@onready var _difficulty_icon: TextureRect = $Panel/DifficultyIcon
@onready var _play_button: BaseButton = $Panel/PlayButton
@onready var _edit_button: BaseButton = $Panel/EditButton
@onready var _delete_button: BaseButton = $Panel/DeleteMap
@onready var _upload_button: BaseButton = $UploadButton

func _ready() -> void:
	if _play_button != null and not _play_button.pressed.is_connected(_on_play_pressed):
		_play_button.pressed.connect(_on_play_pressed)
	if _edit_button != null and not _edit_button.pressed.is_connected(_on_edit_pressed):
		_edit_button.pressed.connect(_on_edit_pressed)
	if _delete_button != null and not _delete_button.pressed.is_connected(_on_delete_pressed):
		_delete_button.pressed.connect(_on_delete_pressed)
	if _upload_button != null and not _upload_button.pressed.is_connected(_on_upload_pressed):
		_upload_button.pressed.connect(_on_upload_pressed)
	if _title != null:
		if not _title.text_submitted.is_connected(_on_title_submitted):
			_title.text_submitted.connect(_on_title_submitted)
		if not _title.focus_exited.is_connected(_on_title_focus_exited):
			_title.focus_exited.connect(_on_title_focus_exited)
	_apply_entry(false, "", false)

func set_state(entry: Dictionary, file_name: String, is_verified: bool, can_upload: bool) -> void:
	_entry = entry
	_apply_entry(is_verified, file_name, can_upload)

func _apply_entry(is_verified: bool, file_name: String, can_upload: bool) -> void:
	if _entry.is_empty():
		return
	var meta = _entry.get("metadata", null)
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	var title := str(_entry.get("title", meta.get("title", "")))
	if _title != null:
		_ignore_title = true
		_title.text = title
		_ignore_title = false
	if _file_name != null:
		_file_name.text = file_name
	if _verified != null:
		_verified.text = "verified" if is_verified else "unverified"
	if _upload_button != null:
		_upload_button.disabled = not can_upload
	_update_difficulty_icon(int(_entry.get("rating", meta.get("rating", 1))))

func _update_difficulty_icon(difficulty: int) -> void:
	if _difficulty_icon == null:
		return
	var diff := clampi(difficulty, 1, 8)
	var path := "res://graphics/ui/16px/difficulty/%s.png" % str(diff)
	if ResourceLoader.exists(path):
		_difficulty_icon.texture = load(path)

func _on_title_submitted(new_text: String) -> void:
	if _ignore_title:
		return
	title_changed.emit(new_text)

func _on_title_focus_exited() -> void:
	if _ignore_title:
		return
	if _title == null:
		return
	title_changed.emit(_title.text)

func _on_play_pressed() -> void:
	play_pressed.emit()

func _on_edit_pressed() -> void:
	edit_pressed.emit()

func _on_delete_pressed() -> void:
	delete_pressed.emit()

func _on_upload_pressed() -> void:
	upload_pressed.emit()
