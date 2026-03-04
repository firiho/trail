extends CanvasLayer

signal level_selected(level_id: int)
signal retry_pressed()
signal next_level_pressed()
signal back_to_levels_pressed()

@export var proximity_bar_range_meters: float = 8.0

@onready var health_bar = $HealthBar
@onready var damage_bar = $DamageBar
@onready var start_screen = $StartScreen
@onready var game_over_screen = $GameOverScreen
@onready var win_screen = $WinScreen

var _proximity_bar_root: Control = null
var _proximity_bar_bg: ColorRect = null
var _proximity_bar_fill: ColorRect = null
var _proximity_bar_frame: ColorRect = null
var _idle_timer_label: Label = null
var _score_label: Label = null
var _combo_label: Label = null
var _progress_bar_root: Control = null
var _progress_bar_bg: ColorRect = null
var _progress_bar_fill: ColorRect = null
var _progress_bar_icon: Label = null

var _active_tween: Tween = null
var _level_select_screen: Control = null
var _level_banner_label: Label = null
var _custom_font: Font = null

func _get_custom_font() -> Font:
	if !_custom_font:
		_custom_font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	return _custom_font

func _ready():
	_ensure_proximity_bar()
	_layout_proximity_bar()
	_proximity_bar_root.visible = false
	_ensure_score_label()
	_ensure_combo_label()
	if _score_label: _score_label.visible = false
	if _combo_label: _combo_label.visible = false

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
	win_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	if _proximity_bar_root: _proximity_bar_root.visible = false
	if _score_label: _score_label.visible = false
	if _combo_label: _combo_label.visible = false
	if _level_select_screen: _level_select_screen.visible = false
	
	_fade_in(start_screen)
	_animate_start_screen()

func show_game_over():
	# Reset state
	game_over_screen.modulate.a = 0
	game_over_screen.visible = true
	start_screen.visible = false
	win_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	if _proximity_bar_root: _proximity_bar_root.visible = false
	if _score_label: _score_label.visible = false
	if _combo_label: _combo_label.visible = false
	if _level_select_screen: _level_select_screen.visible = false
	
	_fade_in(game_over_screen)
	_animate_game_over_screen()

func show_hud():
	if _active_tween: _active_tween.kill()
	
	start_screen.visible = false
	game_over_screen.visible = false
	win_screen.visible = false
	health_bar.visible = true
	damage_bar.visible = true
	if _proximity_bar_root: _proximity_bar_root.visible = true
	if _score_label: _score_label.visible = true
	if _level_select_screen: _level_select_screen.visible = false

func show_win():
	# Reset state
	win_screen.modulate.a = 0
	win_screen.visible = true
	start_screen.visible = false
	game_over_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	if _proximity_bar_root: _proximity_bar_root.visible = false
	if _score_label: _score_label.visible = false
	if _combo_label: _combo_label.visible = false
	if _level_select_screen: _level_select_screen.visible = false

	_fade_in(win_screen)
	_animate_win_screen()

# =====================================================================
# LEVEL SELECT SCREEN
# =====================================================================

func show_level_select(max_unlocked: int, total_levels: int = 10):
	if _active_tween: _active_tween.kill()

	# Hide everything else
	start_screen.visible = false
	game_over_screen.visible = false
	win_screen.visible = false
	health_bar.visible = false
	damage_bar.visible = false
	if _proximity_bar_root: _proximity_bar_root.visible = false
	if _score_label: _score_label.visible = false
	if _combo_label: _combo_label.visible = false

	# Build or rebuild
	if _level_select_screen and is_instance_valid(_level_select_screen):
		_level_select_screen.queue_free()
		_level_select_screen = null

	_level_select_screen = Control.new()
	_level_select_screen.name = "LevelSelectScreen"
	_level_select_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_level_select_screen)

	# Dim background
	var bg = ColorRect.new()
	bg.name = "BG"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.06, 0.12, 0.92)
	_level_select_screen.add_child(bg)

	# Title
	var title = Label.new()
	title.name = "Title"
	title.text = "SELECT LEVEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.anchor_top = 0.0
	title.anchor_bottom = 0.0
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 60
	title.offset_bottom = 120
	var font = _get_custom_font()
	if font:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_outline_size", 6)
	_level_select_screen.add_child(title)

	# Level buttons — grid layout
	var cols = min(total_levels, 5)
	var rows_needed = ceili(float(total_levels) / float(cols))
	var btn_size = 72
	var btn_gap = 18
	var grid_w = cols * btn_size + (cols - 1) * btn_gap
	var grid_h = rows_needed * btn_size + (rows_needed - 1) * btn_gap
	var grid_x = -grid_w / 2.0
	var grid_y = -grid_h / 2.0 - 20

	var grid = Control.new()
	grid.name = "Grid"
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 0.5
	grid.anchor_bottom = 0.5
	grid.offset_left = grid_x
	grid.offset_right = grid_x + grid_w
	grid.offset_top = grid_y
	grid.offset_bottom = grid_y + grid_h
	_level_select_screen.add_child(grid)

	for i in range(total_levels):
		var level_num = i + 1
		var col = i % cols
		var row = i / cols
		var x = col * (btn_size + btn_gap)
		var y = row * (btn_size + btn_gap)
		var unlocked = level_num <= max_unlocked

		var btn = Button.new()
		btn.name = "Level%d" % level_num
		btn.text = str(level_num) if unlocked else "🔒"
		btn.position = Vector2(x, y)
		btn.size = Vector2(btn_size, btn_size)
		btn.disabled = !unlocked

		# Style the button
		var style_normal = StyleBoxFlat.new()
		var style_hover = StyleBoxFlat.new()
		var style_pressed = StyleBoxFlat.new()
		var style_disabled = StyleBoxFlat.new()

		for s in [style_normal, style_hover, style_pressed, style_disabled]:
			s.corner_radius_top_left = 12
			s.corner_radius_top_right = 12
			s.corner_radius_bottom_left = 12
			s.corner_radius_bottom_right = 12
			s.border_width_top = 2
			s.border_width_bottom = 2
			s.border_width_left = 2
			s.border_width_right = 2

		if unlocked:
			style_normal.bg_color = Color(0.12, 0.18, 0.32, 0.9)
			style_normal.border_color = Color(0.4, 0.7, 1.0, 0.7)
			style_hover.bg_color = Color(0.18, 0.28, 0.48, 0.95)
			style_hover.border_color = Color(0.5, 0.8, 1.0, 0.9)
			style_pressed.bg_color = Color(0.25, 0.4, 0.65, 1.0)
			style_pressed.border_color = Color(0.6, 0.9, 1.0, 1.0)
		else:
			style_disabled.bg_color = Color(0.08, 0.08, 0.12, 0.6)
			style_disabled.border_color = Color(0.3, 0.3, 0.35, 0.3)

		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_stylebox_override("disabled", style_disabled)

		if font:
			btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 22)
		if unlocked:
			btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		else:
			btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.45, 0.5))

		if unlocked:
			btn.pressed.connect(_on_level_btn_pressed.bind(level_num))

		grid.add_child(btn)

	# Hint text at the bottom
	var hint = Label.new()
	hint.name = "Hint"
	hint.text = "CHOOSE A LEVEL TO PLAY"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -300
	hint.offset_right = 300
	hint.offset_top = -80
	hint.offset_bottom = -50
	if font:
		hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("shadow_outline_size", 3)
	_level_select_screen.add_child(hint)

	# Fade in
	_level_select_screen.modulate.a = 0
	_fade_in(_level_select_screen)

	# Animate title
	_active_tween = create_tween().set_loops()
	_active_tween.tween_property(title, "position:y", title.position.y - 6, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(title, "position:y", title.position.y, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_level_btn_pressed(level_id: int):
	level_selected.emit(level_id)

# =====================================================================
# LEVEL BANNER (shows "LEVEL X" when starting)
# =====================================================================

func show_level_banner(level_id: int):
	if _level_banner_label and is_instance_valid(_level_banner_label):
		_level_banner_label.queue_free()
		_level_banner_label = null

	_level_banner_label = Label.new()
	_level_banner_label.name = "LevelBanner"
	_level_banner_label.text = "LEVEL %d" % level_id
	_level_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_banner_label.anchor_left = 0.5
	_level_banner_label.anchor_right = 0.5
	_level_banner_label.anchor_top = 0.3
	_level_banner_label.anchor_bottom = 0.3
	_level_banner_label.offset_left = -250
	_level_banner_label.offset_right = 250
	_level_banner_label.offset_top = -30
	_level_banner_label.offset_bottom = 30
	var banner_font = _get_custom_font()
	if banner_font:
		_level_banner_label.add_theme_font_override("font", banner_font)
	_level_banner_label.add_theme_font_size_override("font_size", 36)
	_level_banner_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
	_level_banner_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_level_banner_label.add_theme_constant_override("shadow_outline_size", 8)
	_level_banner_label.pivot_offset = Vector2(250, 30)
	_level_banner_label.modulate.a = 0
	add_child(_level_banner_label)

	var tween = create_tween()
	# Fade in + scale up
	_level_banner_label.scale = Vector2(0.6, 0.6)
	tween.tween_property(_level_banner_label, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_level_banner_label, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Hold
	tween.tween_interval(1.5)
	# Fade out up
	tween.tween_property(_level_banner_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_level_banner_label, "offset_top", -60, 0.5).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_level_banner_label, "offset_bottom", 0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(func():
		if _level_banner_label and is_instance_valid(_level_banner_label):
			_level_banner_label.queue_free()
			_level_banner_label = null
	)

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

func _animate_win_screen():
	if _active_tween: _active_tween.kill()
	_active_tween = create_tween().set_loops()

	var label = win_screen.get_node("Label")
	var instructions = win_screen.get_node("Instructions")

	# Gentle celebratory pulse
	_active_tween.tween_property(label, "scale", Vector2(1.06, 1.06), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.parallel().tween_property(instructions, "modulate:a", 0.5, 0.8)

	_active_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.parallel().tween_property(instructions, "modulate:a", 1.0, 0.8)

# =====================================================================
# STATS OVERLAY ON END SCREENS
# =====================================================================

var _stats_panel: PanelContainer = null

func show_game_over_with_stats(stats: Dictionary):
	show_game_over()
	_show_stats_panel(game_over_screen, stats, Color(1.0, 0.35, 0.35, 0.9), false)

func show_win_with_stats(stats: Dictionary):
	show_win()
	_show_stats_panel(win_screen, stats, Color(0.35, 1.0, 0.5, 0.9), true)

func _show_stats_panel(parent_screen: Control, stats: Dictionary, accent_color: Color, is_win: bool = false):
	if _stats_panel and is_instance_valid(_stats_panel):
		_stats_panel.queue_free()
		_stats_panel = null

	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.75)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.4)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	_stats_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_stats_panel.add_child(vbox)

	# Title
	var title_label = Label.new()
	title_label.text = "- STATS -"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", accent_color)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title_label.add_theme_constant_override("shadow_outline_size", 3)
	vbox.add_child(title_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	# Stat rows
	var stat_entries = [
		["LEVEL", str(stats.get("level", 1))],
		["SCORE", str(stats.get("score", 0))],
		["KILLS", str(stats.get("enemies_killed", 0))],
		["MAX COMBO", "x" + str(stats.get("max_combo", 0))],
		["COINS", str(stats.get("coins_collected", 0))],
		["APPLES", str(stats.get("apples_collected", 0))],
		["DMG TAKEN", str(stats.get("damage_taken", 0))],
		["TIME", str(stats.get("time", "0:00"))],
	]

	for entry in stat_entries:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var key_label = Label.new()
		key_label.text = entry[0]
		key_label.add_theme_font_size_override("font_size", 9)
		key_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.85))
		key_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		key_label.add_theme_constant_override("shadow_outline_size", 2)
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_label)

		var val_label = Label.new()
		val_label.text = entry[1]
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_label.add_theme_font_size_override("font_size", 10)
		val_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		val_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		val_label.add_theme_constant_override("shadow_outline_size", 2)
		val_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val_label)

		vbox.add_child(row)

	# ---- Action Buttons ----
	var btn_sep = HSeparator.new()
	btn_sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(btn_sep)

	var btn_row = HBoxContainer.new()
	btn_row.name = "ButtonRow"
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	if is_win:
		var next_btn = _create_action_button("NEXT LEVEL", Color(0.25, 0.65, 0.4, 1.0), Color(0.15, 0.45, 0.28, 0.9))
		next_btn.pressed.connect(func(): next_level_pressed.emit())
		btn_row.add_child(next_btn)
	else:
		var retry_btn = _create_action_button("RETRY", Color(0.8, 0.35, 0.3, 1.0), Color(0.55, 0.2, 0.18, 0.9))
		retry_btn.pressed.connect(func(): retry_pressed.emit())
		btn_row.add_child(retry_btn)

	var levels_btn = _create_action_button("LEVELS", Color(0.4, 0.55, 0.85, 1.0), Color(0.2, 0.3, 0.55, 0.9))
	levels_btn.pressed.connect(func(): back_to_levels_pressed.emit())
	btn_row.add_child(levels_btn)

	parent_screen.add_child(_stats_panel)

	# Move existing Instructions and Recap labels up to make room for stats
	var instructions_node = parent_screen.get_node_or_null("Instructions")
	var recap_node = parent_screen.get_node_or_null("Recap")
	if instructions_node:
		instructions_node.visible = false
	if recap_node:
		recap_node.visible = false

	# Position stats panel below the title
	_stats_panel.anchor_left = 0.5
	_stats_panel.anchor_right = 0.5
	_stats_panel.anchor_top = 0.5
	_stats_panel.anchor_bottom = 0.5
	_stats_panel.offset_left = -130
	_stats_panel.offset_right = 130
	_stats_panel.offset_top = -80
	_stats_panel.offset_bottom = 180

	# Fade in the stats
	_stats_panel.modulate.a = 0
	var tween = create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(_stats_panel, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)

func _create_action_button(text: String, text_color: Color, bg_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(110, 32)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_color = Color(text_color.r, text_color.g, text_color.b, 0.5)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(bg_color.r + 0.1, bg_color.g + 0.1, bg_color.b + 0.1, 1.0)
	style_hover.border_color = Color(text_color.r, text_color.g, text_color.b, 0.8)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(bg_color.r + 0.2, bg_color.g + 0.2, bg_color.b + 0.2, 1.0)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	var btn_font = _get_custom_font()
	if btn_font:
		btn.add_theme_font_override("font", btn_font)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

	return btn

# =====================================================================
# SCORE, COMBO & PROGRESS
# =====================================================================

func update_score(score: int):
	_ensure_score_label()
	_score_label.text = str(score)
	if _score_label.visible:
		var tween = create_tween()
		tween.tween_property(_score_label, "scale", Vector2(1.3, 1.3), 0.08)
		tween.tween_property(_score_label, "scale", Vector2(1.0, 1.0), 0.12)

func update_combo(combo: int, multiplier: float):
	_ensure_combo_label()
	if combo > 1:
		_combo_label.text = "x%d COMBO" % combo
		_combo_label.visible = health_bar and health_bar.visible
		_combo_label.modulate = Color(1.0, 0.95, 0.4, 1.0)
		var tween = create_tween()
		tween.tween_property(_combo_label, "scale", Vector2(1.4, 1.4), 0.06)
		tween.tween_property(_combo_label, "scale", Vector2(1.0, 1.0), 0.1)
	else:
		_combo_label.visible = false

func update_progress(ratio: float):
	_ensure_progress_bar()
	ratio = clamp(ratio, 0.0, 1.0)
	var bar_width = 240.0
	_progress_bar_fill.size = Vector2(bar_width * ratio, _progress_bar_bg.size.y)
	var color = Color(0.3, 0.6, 1.0, 0.9).lerp(Color(0.3, 1.0, 0.5, 0.9), ratio)
	_progress_bar_fill.color = color
	_progress_bar_root.visible = health_bar and health_bar.visible

func _ensure_score_label():
	if _score_label:
		return
	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.anchor_left = 1.0
	_score_label.anchor_right = 1.0
	_score_label.offset_left = -200.0
	_score_label.offset_top = 18.0
	_score_label.offset_right = -20.0
	_score_label.offset_bottom = 50.0
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 22)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	_score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_score_label.add_theme_constant_override("shadow_outline_size", 6)
	_score_label.text = "0"
	_score_label.pivot_offset = Vector2(180, 16)
	add_child(_score_label)

func _ensure_combo_label():
	if _combo_label:
		return
	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.anchor_left = 0.5
	_combo_label.anchor_right = 0.5
	_combo_label.offset_left = -100.0
	_combo_label.offset_top = 80.0
	_combo_label.offset_right = 100.0
	_combo_label.offset_bottom = 112.0
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 20)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4, 1.0))
	_combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_combo_label.add_theme_constant_override("shadow_outline_size", 6)
	_combo_label.text = ""
	_combo_label.pivot_offset = Vector2(100, 16)
	_combo_label.visible = false
	add_child(_combo_label)

func _ensure_progress_bar():
	if _progress_bar_root:
		return

	_progress_bar_root = Control.new()
	_progress_bar_root.name = "ProgressBarRoot"
	_progress_bar_root.position = Vector2(520, 16)
	_progress_bar_root.size = Vector2(240, 12)
	add_child(_progress_bar_root)

	_progress_bar_bg = ColorRect.new()
	_progress_bar_bg.name = "ProgressBG"
	_progress_bar_bg.position = Vector2.ZERO
	_progress_bar_bg.size = Vector2(240, 12)
	_progress_bar_bg.color = Color(0.08, 0.08, 0.10, 0.55)
	_progress_bar_root.add_child(_progress_bar_bg)

	_progress_bar_fill = ColorRect.new()
	_progress_bar_fill.name = "ProgressFill"
	_progress_bar_fill.position = Vector2.ZERO
	_progress_bar_fill.size = Vector2(0, 12)
	_progress_bar_fill.color = Color(0.3, 0.6, 1.0, 0.9)
	_progress_bar_root.add_child(_progress_bar_fill)

	_progress_bar_icon = Label.new()
	_progress_bar_icon.name = "ProgressIcon"
	_progress_bar_icon.text = "BUSH >"
	_progress_bar_icon.position = Vector2(248, -2)
	_progress_bar_icon.size = Vector2(60, 16)
	_progress_bar_icon.add_theme_font_size_override("font_size", 10)
	_progress_bar_icon.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8, 0.8))
	_progress_bar_icon.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_progress_bar_icon.add_theme_constant_override("shadow_outline_size", 4)
	_progress_bar_root.add_child(_progress_bar_icon)
