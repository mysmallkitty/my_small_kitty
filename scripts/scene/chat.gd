extends Label

var floating_time := 3.0
var floating_time_timer := 0.0
var fade_meter := 5.0
@onready var sfx_player := AudioStreamPlayer.new()

func _ready() -> void:
	sfx_player.stream = load("res://audio/chat.wav")
	add_child(sfx_player)
	sfx_player.play()

func _process(delta: float) -> void:
	floating_time_timer += delta
	if floating_time < floating_time_timer:
		modulate.a -= fade_meter * delta
		if modulate.a < 0:
			self.queue_free()
