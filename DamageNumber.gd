extends Label

@export var float_speed: float = 60.0
@export var fade_duration: float = 0.6

func _ready() -> void:
	z_index = 100
	scale = Vector2(0.8, 0.8)
	
	# Animate float up, scale burst, and fade out
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 35.0, fade_duration)
	tween.tween_property(self, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Pop effect
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

	get_tree().create_timer(fade_duration).timeout.connect(queue_free)

func setup(amount: int, is_critical: bool = false) -> void:
	text = str(amount)
	if is_critical:
		label_settings = LabelSettings.new()
		label_settings.font_color = Color(1.0, 0.85, 0.2) # Gold
		label_settings.font_size = 20
	else:
		label_settings = LabelSettings.new()
		label_settings.font_color = Color(1.0, 0.25, 0.25) # Red/Orange
		label_settings.font_size = 16
