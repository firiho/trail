extends CanvasLayer

@export var proximity_bar_range_meters: float = 8.0

@onready var health_bar = $HealthBar
@onready var damage_bar = $DamageBar
@onready var start_screen = $StartScreen
@onready var game_over_screen = $GameOverScreen

var _proximity_bar_root: Control = null
var _proximity_bar_bg: ColorRect = null
var _proximity_bar_fill: ColorRect = null
var _proximity_bar_frame: ColorRect = null
var _idle_timer_label: Label = null

var _active_tween: Tween = null

func _ready():
	_ensure_proximity_bar()
	_layout_proximity_bar()
	_proximity_bar_root.visible = false
	_ensure_idle_timer_label()
	_idle_timer_label.visible = false

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
	if _proximity_bar_root: _proximity_bar_root.visible = false
	if _idle_timer_label: _idle_timer_label.visible = false
	
	_fade_in(start_screen)
	_animate_start_screen()

func show_game_over():
	# Reset state
	game_over_screen.modulate.a = 0
	game_over_screen.visible = true
	start_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	if _proximity_bar_root: _proximity_bar_root.visible = false
	if _idle_timer_label: _idle_timer_label.visible = false
	
	_fade_in(game_over_screen)
	_animate_game_over_screen()

func show_hud():
	if _active_tween: _active_tween.kill()
	
	start_screen.visible = false
	game_over_screen.visible = false
	health_bar.visible = true
	damage_bar.visible = true
	if _proximity_bar_root: _proximity_bar_root.visible = true
	if _idle_timer_label: _idle_timer_label.visible = true

func update_transform_info(enemy_meters: float, friendly_meters: float, enemy_color_key: String = "", full_range_meters: float = -1.0):
	_ensure_proximity_bar()

	var enemy_dist = enemy_meters if enemy_meters >= 0.0 else INF
	var friendly_dist = friendly_meters if friendly_meters >= 0.0 else INF
	var nearest_dist = min(enemy_dist, friendly_dist)
	var has_entity = nearest_dist < INF
	var fill_ratio = 0.0
	var display_range = max(0.001, proximity_bar_range_meters)
	var full_range = full_range_meters if full_range_meters > 0.0 else display_range
	full_range = clamp(full_range, 0.0, display_range)
	if has_entity:
		if nearest_dist <= full_range:
			fill_ratio = 1.0
		elif display_range > full_range:
			fill_ratio = clamp(1.0 - ((nearest_dist - full_range) / (display_range - full_range)), 0.0, 1.0)

	var is_enemy_nearest = enemy_dist <= friendly_dist
	var fill_color = Color(0.78, 0.73, 0.55, 0.9) # khaki / sand
	if has_entity:
		if is_enemy_nearest:
			fill_color = _get_enemy_bar_color(enemy_color_key)
		else:
			fill_color = Color(0.65, 0.96, 0.78, 0.95) # white-green

	_proximity_bar_fill.color = fill_color
	_proximity_bar_fill.size = Vector2(_proximity_bar_bg.size.x * fill_ratio, _proximity_bar_bg.size.y)
	_update_proximity_bar_glow(fill_color, has_entity, fill_ratio)
	_proximity_bar_root.visible = health_bar and health_bar.visible

func update_idle_timer(time_left: float, max_time: float):
	_ensure_idle_timer_label()
	var safe_max = max(0.001, max_time)
	var ratio = clamp(time_left / safe_max, 0.0, 1.0)
	var display_value = ceil(max(time_left, 0.0))
	_idle_timer_label.text = str(int(display_value))
	_idle_timer_label.visible = health_bar and health_bar.visible

	# Green -> amber -> red as time runs out
	if ratio > 0.5:
		_idle_timer_label.modulate = Color(0.85, 1.0, 0.85, 1.0)
	elif ratio > 0.25:
		_idle_timer_label.modulate = Color(1.0, 0.88, 0.55, 1.0)
	else:
		_idle_timer_label.modulate = Color(1.0, 0.35, 0.35, 1.0)

func _ensure_proximity_bar():
	if _proximity_bar_root:
		return

	_proximity_bar_root = Control.new()
	_proximity_bar_root.name = "ProximityBarRoot"
	_proximity_bar_root.position = Vector2.ZERO
	_proximity_bar_root.size = Vector2(200, 10)
	add_child(_proximity_bar_root)

	_proximity_bar_bg = ColorRect.new()
	_proximity_bar_bg.name = "BarBG"
	_proximity_bar_bg.position = Vector2.ZERO
	_proximity_bar_bg.size = _proximity_bar_root.size
	_proximity_bar_bg.color = Color(0.08, 0.08, 0.10, 0.55)
	_proximity_bar_root.add_child(_proximity_bar_bg)

	_proximity_bar_frame = ColorRect.new()
	_proximity_bar_frame.name = "BarFrame"
	_proximity_bar_frame.position = Vector2(-2, -2)
	_proximity_bar_frame.size = _proximity_bar_root.size + Vector2(4, 4)
	_proximity_bar_frame.color = Color(0.95, 0.95, 0.95, 0.10)
	_proximity_bar_root.add_child(_proximity_bar_frame)
	_proximity_bar_root.move_child(_proximity_bar_frame, 0)

	_proximity_bar_fill = ColorRect.new()
	_proximity_bar_fill.name = "BarFill"
	_proximity_bar_fill.position = Vector2.ZERO
	_proximity_bar_fill.size = Vector2.ZERO
	_proximity_bar_fill.color = Color(0.78, 0.73, 0.55, 0.9)
	_proximity_bar_root.add_child(_proximity_bar_fill)

func _layout_proximity_bar():
	if !_proximity_bar_root or !health_bar:
		return

	var health_pos = health_bar.position
	var health_size = health_bar.size
	if health_size.x <= 0.0:
		health_size = Vector2(health_bar.offset_right - health_bar.offset_left, health_bar.offset_bottom - health_bar.offset_top)
		health_pos = Vector2(health_bar.offset_left, health_bar.offset_top)

	_proximity_bar_root.position = Vector2(health_pos.x, health_pos.y + health_size.y + 8.0)
	_proximity_bar_root.size = Vector2(health_size.x, 10.0)
	_proximity_bar_bg.position = Vector2.ZERO
	_proximity_bar_bg.size = _proximity_bar_root.size
	_proximity_bar_fill.position = Vector2.ZERO
	_proximity_bar_fill.size = Vector2(0.0, _proximity_bar_root.size.y)
	if _proximity_bar_frame:
		_proximity_bar_frame.position = Vector2(-2, -2)
		_proximity_bar_frame.size = _proximity_bar_root.size + Vector2(4, 4)

func _ensure_idle_timer_label():
	if _idle_timer_label:
		return

	_idle_timer_label = Label.new()
	_idle_timer_label.name = "IdleTimerLabel"
	_idle_timer_label.anchor_left = 1.0
	_idle_timer_label.anchor_right = 1.0
	_idle_timer_label.offset_left = -96.0
	_idle_timer_label.offset_top = 18.0
	_idle_timer_label.offset_right = -20.0
	_idle_timer_label.offset_bottom = 54.0
	_idle_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_idle_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_idle_timer_label.add_theme_font_size_override("font_size", 32)
	_idle_timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_idle_timer_label.add_theme_constant_override("shadow_outline_size", 6)
	_idle_timer_label.text = "5"
	add_child(_idle_timer_label)

func _update_proximity_bar_glow(fill_color: Color, has_entity: bool, fill_ratio: float):
	if !_proximity_bar_frame:
		return
	if !has_entity or fill_ratio <= 0.0:
		_proximity_bar_frame.color = Color(0.95, 0.95, 0.95, 0.10)
		return

	var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
	var glow_alpha = lerp(0.18, 0.42, pulse) * lerp(0.5, 1.0, fill_ratio)
	_proximity_bar_frame.color = Color(fill_color.r, fill_color.g, fill_color.b, glow_alpha)

func _get_enemy_bar_color(enemy_color_key: String) -> Color:
	match enemy_color_key:
		"opp_1":
			return Color(0.18, 0.46, 0.26, 0.95) # darker green
		"opp_2":
			return Color(0.58, 0.40, 0.24, 0.95) # brownish
		"opp_3":
			return Color(0.50, 0.22, 0.68, 0.95) # dark purple
		_:
			return Color(0.50, 0.22, 0.68, 0.95)

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
