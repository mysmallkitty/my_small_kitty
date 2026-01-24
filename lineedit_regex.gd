
extends LineEdit

@export var ALLOWED_RE := "^[A-Za-z0-9 _-]*$" 

var _re := RegEx.new()

func _ready() -> void:
	_re.compile(ALLOWED_RE)
	text_changed.connect(_on_text_changed)

func _on_text_changed(new_text: String) -> void:
	if _re.search(new_text) != null:
		return

	var filtered := ""
	for ch in new_text:
		var s := String(ch)
		if _re.search(filtered + s) != null:
			filtered += s

	var caret := caret_column
	text = filtered
	caret_column = min(caret, text.length())
