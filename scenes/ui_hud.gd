extends CanvasLayer

@onready var health_bar = $HealthBar
@onready var damage_bar = $DamageBar
@onready var start_screen = $StartScreen
@onready var game_over_screen = $GameOverScreen

var _transform_label: Label = null

var _active_tween: Tween = null

func update_health(current_hp, max_hp):
	health_bar.max_value = max_hp
	damage_bar.max_value = max_hp
	
	health_bar.value = current_hp
	
	# Animate damage bar
	var tween = create_tween()
	tween.tween_interval(0.2) # Small delay
	tween.tween_property(damage_bar, "value", current_hp, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func show_start_screen():
	# Reset state
	start_screen.modulate.a = 0
	start_screen.visible = true
	game_over_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	
	_fade_in(start_screen)
	_animate_start_screen()

func show_game_over():
	# Reset state
	game_over_screen.modulate.a = 0
	game_over_screen.visible = true
	start_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	
	_fade_in(game_over_screen)
	_animate_game_over_screen()

func show_hud():
	if _active_tween: _active_tween.kill()
	
	start_screen.visible = false
	game_over_screen.visible = false
	health_bar.visible = true
	damage_bar.visible = true
	if _transform_label: _transform_label.visible = true

func update_transform_info(meters: float):
	if !_transform_label:
		_transform_label = Label.new()
		_transform_label.name = "TransformLabel"
		_transform_label.add_theme_font_size_override("font_size", 24)
		_transform_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		_transform_label.position = Vector2(40, 60)
		add_child(_transform_label)
	
	_transform_label.text = "Entity Proximity: %.1f m" % meters
	if health_bar:
		_transform_label.visible = (health_bar.visible)
	else:
		_transform_label.visible = false

# =====================================================================
# ANIMATIONS
# =====================================================================

func _fade_in(node: Control):
	var tween = create_tween()
	tween.tween_property(node, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)

func _animate_start_screen():
	if _active_tween: _active_tween.kill()
	_active_tween = create_tween().set_loops()
	
	var label = start_screen.get_node("Label")
	var instructions = start_screen.get_node("Instructions")
	
	# Title Floating
	_active_tween.tween_property(label, "position:y", label.position.y - 10, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.parallel().tween_property(instructions, "modulate:a", 0.3, 1.0)
	
	_active_tween.tween_property(label, "position:y", label.position.y, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.parallel().tween_property(instructions, "modulate:a", 1.0, 1.0)

func _animate_game_over_screen():
	if _active_tween: _active_tween.kill()
	_active_tween = create_tween().set_loops()
	
	var label = game_over_screen.get_node("Label")
	var instructions = game_over_screen.get_node("Instructions")
	
	# Shake/Scaling for Failure
	_active_tween.tween_property(label, "scale", Vector2(1.1, 1.1), 1.5).set_trans(Tween.TRANS_SINE)
	_active_tween.parallel().tween_property(instructions, "modulate:a", 0.4, 0.8)
	
	_active_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 1.5).set_trans(Tween.TRANS_SINE)
	_active_tween.parallel().tween_property(instructions, "modulate:a", 1.0, 0.8)
