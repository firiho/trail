extends CharacterBody2D

static var _SPRITE_BUILD_CACHE := {}
const CharacterCatalog = preload("res://scenes/character_catalog.gd")

@export var player_folder: String = "player_1"
@export var player_family: String = "warriors"
@export var default_animation: String = "idle_blinking"
@export var move_speed: float = 400.0
@export var is_controllable: bool = false
@export var trail_fade_lifetime_seconds: float = 1.5
@export var trail_color_proximity_meters: float = 3.0
@export var trail_particle_amount: int = 48
@export var trail_point_spacing_px: float = 42.0
@export var trail_color_blend_speed: float = 8.0
@export var trail_visual_enabled: bool = false
@export var idle_death_timeout_seconds: float = 5.0
@export var attack_buffer_seconds: float = 0.25

@export_group("Dash")
@export var dash_speed: float = 1200.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.8
@export var dash_invincible: bool = true

@export_group("Offsets")
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var hitbox_offset_x: float = 40.0

signal health_changed(current, max)
signal died
signal idle_timer_changed(time_left, max_time)
signal attack_started(is_controllable_attack)
signal damage_taken(amount, is_controllable_target)
signal idle_clock_active_changed(active)
signal enemy_killed(enemy)
signal dash_performed



const PLAYER_FPS = 20.0
const PLAYER_TARGET_DISPLAY_HEIGHT = 140.0
const ASSIST_ATTACK_RANGE = 60.0
const PIXELS_PER_METER = 40.0

const ALL_ANIMATIONS = [
	"idle", "idle_blinking", "walking", "running", "dying", "falling_down",
	"hurt", "jump_loop", "jump_start", "kicking", "run_slashing", 
	"run_throwing", "slashing", "slashing_in_the_air", "sliding",
	"throwing", "throwing_in_the_air"
]

# States
var health = 100
var is_dead = false
var is_attacking = false
var _is_dashing: bool = false
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
var _queued_attack_count: int = 0
var _attack_buffer_timer: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _hitbox: Area2D = $Hitbox
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _current_anim: String = ""
var _loaded_anims: Array = []
var _attack_animations: Array = []
var _resolved_default_animation: String = ""
var _last_attack_animation: String = ""
var _attack_chain_timer: float = 0.0
var _trail_particles: CPUParticles2D = null
var _trail_highlight_texture: Texture2D = null
var _trail_gradient_runtime: Gradient = null
var _trail_gradient_neutral: Gradient = null
var _trail_gradient_enemy_opp1: Gradient = null
var _trail_gradient_enemy_opp2: Gradient = null
var _trail_gradient_enemy_opp3: Gradient = null
var _trail_gradient_friendly: Gradient = null
var _trail_color_mode: String = "neutral"
var _trail_target_enemy_color_key: String = ""
var _trail_current_start_color: Color = Color.WHITE
var _trail_current_mid_color: Color = Color.WHITE
var _trail_target_start_color: Color = Color.WHITE
var _trail_target_mid_color: Color = Color.WHITE
var _hit_flash_tween: Tween = null
var _enemy_spawn_highlight_points: Array[Vector2] = []
var _friendly_spawn_highlight_points: Array[Vector2] = []
var _idle_clock_audio_active: bool = false
var _stealth_hidden: bool = false

# Trail tracking for logic
var trail_points: Array[Vector2] = []
var trail_point_spawn_times: Array[float] = []
var _last_trail_pos: Vector2 = Vector2.ZERO
const MAX_TRAIL_POINTS = 100

var group_target_pos: Vector2 = Vector2.ZERO
var is_joining_group: bool = false
var assist_target: CharacterBody2D = null
var idle_death_time_left: float = 0.0

func set_player_family(next_family: String):
	var resolved_family = CharacterCatalog.resolve_player_family(next_family)
	if resolved_family == "":
		return
	if player_family == resolved_family and _sprite and _sprite.sprite_frames:
		return
	player_family = resolved_family
	if is_inside_tree():
		_build_sprite()

func _ready():
	_build_sprite()
	# _setup_collision() # Now set in scene
	add_to_group("player" if is_controllable else "friendly_npc")
	if is_controllable:
		if trail_visual_enabled:
			_create_trail()
		_last_trail_pos = global_position
		idle_death_time_left = idle_death_timeout_seconds
		emit_signal("idle_timer_changed", idle_death_time_left, idle_death_timeout_seconds)

func _create_trail():
	var trail = CPUParticles2D.new()
	_trail_particles = trail
	trail.amount = trail_particle_amount
	trail.lifetime = trail_fade_lifetime_seconds
	trail.local_coords = false # World space for trail effect
	trail.gravity = Vector2.ZERO
	trail.direction = Vector2.ZERO
	trail.spread = 0.0
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.0
	
	# Curve: Start small (0.2) -> Grow (1.5) -> Shrink to 0 at end
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.2))
	curve.add_point(Vector2(0.3, 1.5))
	curve.add_point(Vector2(0.8, 1.2))
	curve.add_point(Vector2(1, 0))
	trail.scale_amount_curve = curve
	
	# Base trail is khaki/sand; nearby entities recolor the whole trail.
	_trail_gradient_neutral = _make_trail_gradient(
		Color(0.93, 0.88, 0.70, 1.0),
		Color(0.80, 0.73, 0.50, 0.85)
	)
	_trail_gradient_enemy_opp1 = _make_trail_gradient(
		Color(0.20, 0.46, 0.28, 1.0), # darker green
		Color(0.32, 0.66, 0.40, 0.85)
	)
	_trail_gradient_enemy_opp2 = _make_trail_gradient(
		Color(0.48, 0.33, 0.20, 1.0), # brownish
		Color(0.66, 0.48, 0.28, 0.85)
	)
	_trail_gradient_enemy_opp3 = _make_trail_gradient(
		Color(0.30, 0.12, 0.42, 1.0), # dark purple
		Color(0.50, 0.22, 0.68, 0.85)
	)
	_trail_gradient_friendly = _make_trail_gradient(
		Color(0.92, 1.0, 0.96, 1.0),
		Color(0.65, 0.96, 0.78, 0.85)
	)
	_trail_gradient_runtime = _make_trail_gradient(
		_trail_gradient_neutral.colors[0],
		_trail_gradient_neutral.colors[1]
	)
	_trail_current_start_color = _trail_gradient_neutral.colors[0]
	_trail_current_mid_color = _trail_gradient_neutral.colors[1]
	_trail_target_start_color = _trail_current_start_color
	_trail_target_mid_color = _trail_current_mid_color
	trail.color_ramp = _trail_gradient_runtime
	
	# Texture (Small sharp dot/crystal)
	var tex = GradientTexture2D.new()
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.8, 0.5) # Sharper edge than before
	var g = Gradient.new()
	g.colors = [Color.WHITE, Color(1, 1, 1, 0)]
	tex.gradient = g
	trail.texture = tex
	_trail_highlight_texture = tex
	
	# Position at base
	trail.position = Vector2(0, 0)
	add_child(trail)
	move_child(trail, 0) # Behind sprite

func _make_trail_gradient(start_color: Color, mid_color: Color) -> Gradient:
	var grad = Gradient.new()
	grad.colors = [
		start_color,
		mid_color,
		Color(mid_color.r, mid_color.g, mid_color.b, 0.0)
	]
	grad.offsets = [0.0, 0.8, 1.0]
	return grad

func _build_sprite():
	var sprite_data = CharacterCatalog.get_player_sprite_data(player_family, player_folder)
	if sprite_data.is_empty():
		return

	player_family = String(sprite_data.get("family_id", player_family))
	_loaded_anims = (sprite_data.get("loaded_anims", []) as Array).duplicate()
	_attack_animations = (sprite_data.get("attack_animations", []) as Array).duplicate()
	_resolved_default_animation = String(sprite_data.get("default_animation", default_animation))
	_current_anim = ""

	var sf: SpriteFrames = sprite_data.get("sprite_frames", null)
	if sf == null:
		return

	var default_anim = _get_default_animation_name()
	var sample_anim = default_anim
	if sample_anim == "" and !_loaded_anims.is_empty():
		sample_anim = String(_loaded_anims[0])
	var sample_tex = sf.get_frame_texture(sample_anim, 0) if sample_anim != "" and sf.has_animation(sample_anim) else null

	_sprite.sprite_frames = sf
	_sprite.scale = _get_runtime_sprite_scale(sample_tex)
	
	# Offset sprite so its "position" is at its feet
	if sprite_offset != Vector2.ZERO:
		_sprite.offset = sprite_offset
	else:
		if sample_tex:
			_sprite.offset.y = -sample_tex.get_height() / 2.0
	
	_hitbox.position.x = hitbox_offset_x

	# Connected in _ready via code or scene? 
	# Connect frame_changed to detect attack hit frame
	if not _sprite.frame_changed.is_connected(_on_frame_changed):
		_sprite.frame_changed.connect(_on_frame_changed)
	if not _sprite.animation_finished.is_connected(_on_anim_finished):
		_sprite.animation_finished.connect(_on_anim_finished)
	
	# add_child(_sprite) # Already in scene
	if default_anim != "":
		_play_anim(default_anim)

# func _setup_collision(): ... removed

func _process(delta):
	if is_controllable:
		_prune_faded_trail_points()
		_update_trail_color_from_nearby(delta)
		if !_enemy_spawn_highlight_points.is_empty() or !_friendly_spawn_highlight_points.is_empty():
			_enemy_spawn_highlight_points.clear()
			_friendly_spawn_highlight_points.clear()
			queue_redraw()
	if is_dead: return

	_attack_chain_timer = max(0.0, _attack_chain_timer - delta)
	if _attack_chain_timer == 0.0:
		_last_attack_animation = ""
	
	# Dash update
	if is_controllable:
		_dash_cooldown_timer = max(0.0, _dash_cooldown_timer - delta)
		_attack_buffer_timer = max(0.0, _attack_buffer_timer - delta)
		if _attack_buffer_timer == 0.0 and !is_attacking:
			_queued_attack_count = 0
		if _is_dashing:
			_update_dash(delta)
			return
	
	if assist_target and !is_instance_valid(assist_target):
		assist_target = null
		
	# Gravity / Z-axis simulation? Top-down usually no gravity.
	# Combat Input
	var move_input = Vector2.ZERO
	if is_controllable:
		move_input = _get_move_input_vector()
		_update_idle_death_timer(delta, move_input.length() > 0.0)
		if is_dead:
			return
	if is_controllable and Input.is_action_just_pressed("dash") and !_is_dashing and _dash_cooldown_timer <= 0.0 and !is_attacking:
		_perform_dash(move_input)
		return
	if is_controllable and Input.is_action_just_pressed("attack"):
		if is_attacking:
			_queue_attack()
		else:
			attack()
	
	if is_attacking:
		return # Lock movement
		
	if !is_controllable:
		# Friendly assist behavior (called via help input)
		if assist_target and is_instance_valid(assist_target):
			var assist_dist = global_position.distance_to(assist_target.global_position)
			if assist_dist <= ASSIST_ATTACK_RANGE:
				velocity = Vector2.ZERO
				if !is_attacking:
					attack()
			else:
				var assist_dir = (assist_target.global_position - global_position).normalized()
				velocity = assist_dir * move_speed * 0.9
				move_and_slide()
				if assist_dir.x < 0:
					_sprite.flip_h = true
					_hitbox.position.x = -hitbox_offset_x
				else:
					_sprite.flip_h = false
					_hitbox.position.x = hitbox_offset_x
				if _loaded_anims.has("running"): _play_anim("running")
				elif _loaded_anims.has("walking"): _play_anim("walking")
			return

		# NPC Idle behavior
		# Face nearest player
		var nearest = self
		var min_dist = 99999.0
		var players = get_tree().get_nodes_in_group("player")
		for p in players:
			if p == self: continue
			var d = global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				nearest = p
		
		if nearest != self and min_dist < 400.0:
			var dir_to = (nearest.global_position - global_position).normalized()
			if dir_to.x < 0:
				_sprite.flip_h = true
				_hitbox.scale.x = -1
			else:
				_sprite.flip_h = false
				_hitbox.scale.x = 1
		
		if is_joining_group:
			var dist = global_position.distance_to(group_target_pos)
			if dist < 60.0:
				is_joining_group = false
			else:
				var dir = (group_target_pos - global_position).normalized()
				velocity = dir * move_speed * 0.7 # NPCs move slightly slower when joining
				move_and_slide()
				if _loaded_anims.has("walking"): _play_anim("walking")
				return

		var idle_anim = _get_default_animation_name()
		if idle_anim != "":
			_play_anim(idle_anim)
		return
	
	# Movement
	var dir = _get_move_input_vector()
	
	if dir.length() > 0:
		velocity = dir.normalized() * move_speed
		move_and_slide()
		
		# Update trail points
		if global_position.distance_to(_last_trail_pos) >= trail_point_spacing_px:
			_last_trail_pos = global_position
			trail_points.push_front(global_position)
			trail_point_spawn_times.push_front(_get_time_seconds())
			if trail_points.size() > MAX_TRAIL_POINTS:
				trail_points.pop_back()
			if trail_point_spawn_times.size() > MAX_TRAIL_POINTS:
				trail_point_spawn_times.pop_back()
		
		# Flip AND move hitbox side
		if dir.x < 0:
			_sprite.flip_h = true
			_hitbox.position.x = -hitbox_offset_x
		elif dir.x > 0:
			_sprite.flip_h = false
			_hitbox.position.x = hitbox_offset_x
			
		if _loaded_anims.has("running"): _play_anim("running")
		elif _loaded_anims.has("walking"): _play_anim("walking")
	else:
		var idle_anim = _get_default_animation_name()
		if idle_anim != "":
			_play_anim(idle_anim)

func _get_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0

func _prune_faded_trail_points():
	while trail_points.size() > trail_point_spawn_times.size():
		trail_points.pop_back()
	while trail_point_spawn_times.size() > trail_points.size():
		trail_point_spawn_times.pop_back()

	var now = _get_time_seconds()
	while !trail_points.is_empty() and !trail_point_spawn_times.is_empty():
		var oldest_idx = trail_point_spawn_times.size() - 1
		if now - trail_point_spawn_times[oldest_idx] <= trail_fade_lifetime_seconds:
			break
		trail_points.pop_back()
		trail_point_spawn_times.pop_back()

func attack(force_chain: bool = false):
	var attack_anim = _get_next_attack_animation(force_chain)
	if attack_anim != "" and _play_anim_once(attack_anim):
		is_attacking = true
		_hitbox.monitoring = true
		_last_attack_animation = attack_anim
		_attack_chain_timer = _get_attack_chain_window(attack_anim)
		emit_signal("attack_started", is_controllable)
		_set_idle_clock_audio_active(false)
		
		# Check hitting enemies immediately or per frame? 
		# Let's check overlap on specific frames in _on_frame_changed
		# For simplicity, activate monitoring, check in physics_process loop?
		# Or just check overlaps once now:
		# Actually, better to check in a short timer or frame.

func _on_frame_changed():
	if is_attacking and _hitbox.monitoring:
		# Check for overlapping bodies
		for body in _hitbox.get_overlapping_bodies():
			if body.is_in_group("enemy") and body.has_method("take_damage"):
				var prev_hp = body.health
				body.take_damage(20, self)
				if prev_hp > 0 and body.health <= 0 and is_controllable:
					emit_signal("enemy_killed", body)

func _on_anim_finished():
	if is_attacking:
		is_attacking = false
		_hitbox.monitoring = false
		if _queued_attack_count > 0:
			_queued_attack_count -= 1
			if _attack_buffer_timer <= 0.0:
				_attack_buffer_timer = attack_buffer_seconds
			attack(true)
		else:
			var idle_anim = _get_default_animation_name()
			if idle_anim != "":
				_play_anim(idle_anim)
	
	if _current_anim == "hurt":
		is_attacking = false # interrupt attack
		_queued_attack_count = 0
		_attack_buffer_timer = 0.0
		_attack_chain_timer = 0.0
		_last_attack_animation = ""
		# return to idle
		var idle_anim = _get_default_animation_name()
		if idle_anim != "":
			_play_anim(idle_anim)

func set_input_enabled(enabled: bool):
	set_process(enabled)
	set_physics_process(enabled)
	if enabled and is_controllable:
		idle_death_time_left = idle_death_timeout_seconds
		emit_signal("idle_timer_changed", idle_death_time_left, idle_death_timeout_seconds)
		_set_idle_clock_audio_active(false)
	if !enabled:
		_queued_attack_count = 0
		_attack_buffer_timer = 0.0
		_attack_chain_timer = 0.0
		_last_attack_animation = ""
		_set_idle_clock_audio_active(false)
		var idle_anim = _get_default_animation_name()
		if idle_anim != "":
			_play_anim(idle_anim)
		velocity = Vector2.ZERO

func take_damage(amount, _attacker: Node2D = null):
	if is_dead: return
	if _is_dashing and dash_invincible: return
	health -= amount
	emit_signal("damage_taken", amount, is_controllable)
	emit_signal("health_changed", health, 100) # Assuming max 100
	_play_hit_flash()
	
	if health <= 0:
		die()
	else:
		_play_anim_once("hurt")

func die():
	if is_dead: return
	is_dead = true
	_queued_attack_count = 0
	_attack_buffer_timer = 0.0
	_attack_chain_timer = 0.0
	_last_attack_animation = ""
	_set_idle_clock_audio_active(false)
	emit_signal("died")
	_play_anim_once("dying")
	# Disable collision
	if _collision_shape:
		_collision_shape.call_deferred("set_disabled", true)
	if is_controllable:
		pass
	else:
		# Fade out?
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 2.0)
		tween.tween_callback(queue_free)

func join_group_behavior(target_pos: Vector2):
	group_target_pos = target_pos
	assist_target = null
	is_joining_group = true

func set_assist_target(target: CharacterBody2D):
	if is_controllable:
		return
	if !target or !is_instance_valid(target):
		return
	assist_target = target
	is_joining_group = false

func _update_trail_color_from_nearby(delta: float):
	if !_trail_particles:
		return

	var proximity_px = trail_color_proximity_meters * PIXELS_PER_METER
	var nearest_enemy = _get_nearest_node_in_group("enemy")
	var nearest_friendly = _get_nearest_node_in_group("friendly_npc")
	var nearest_enemy_dist = INF
	var nearest_friendly_dist = INF
	if nearest_enemy:
		nearest_enemy_dist = global_position.distance_to(nearest_enemy.global_position)
	if nearest_friendly:
		nearest_friendly_dist = global_position.distance_to(nearest_friendly.global_position)
	var next_mode = "neutral"
	var enemy_color_key := ""
	if nearest_enemy and "opp_folder" in nearest_enemy:
		enemy_color_key = str(nearest_enemy.opp_folder)

	var enemy_near = nearest_enemy_dist <= proximity_px
	var friendly_near = nearest_friendly_dist <= proximity_px
	if enemy_near and (!friendly_near or nearest_enemy_dist <= nearest_friendly_dist):
		next_mode = "enemy"
	elif friendly_near:
		next_mode = "friendly"

	if next_mode != _trail_color_mode or enemy_color_key != _trail_target_enemy_color_key:
		_trail_color_mode = next_mode
		_trail_target_enemy_color_key = enemy_color_key
		match _trail_color_mode:
			"enemy":
				_set_trail_target_gradient(_get_enemy_trail_gradient(enemy_color_key))
			"friendly":
				_set_trail_target_gradient(_trail_gradient_friendly)
			_:
				_set_trail_target_gradient(_trail_gradient_neutral)

	_update_trail_gradient_blend(delta)

func _set_trail_target_gradient(grad: Gradient):
	if !grad:
		return
	var colors = grad.colors
	if colors.size() < 2:
		return
	_trail_target_start_color = colors[0]
	_trail_target_mid_color = colors[1]

func _update_trail_gradient_blend(delta: float):
	if !_trail_gradient_runtime:
		return
	var t = clamp(delta * trail_color_blend_speed, 0.0, 1.0)
	_trail_current_start_color = _trail_current_start_color.lerp(_trail_target_start_color, t)
	_trail_current_mid_color = _trail_current_mid_color.lerp(_trail_target_mid_color, t)
	_apply_runtime_trail_gradient()

func _apply_runtime_trail_gradient():
	if !_trail_gradient_runtime:
		return
	_trail_gradient_runtime.colors = [
		_trail_current_start_color,
		_trail_current_mid_color,
		Color(_trail_current_mid_color.r, _trail_current_mid_color.g, _trail_current_mid_color.b, 0.0)
	]
	_trail_gradient_runtime.offsets = [0.0, 0.8, 1.0]

func _get_enemy_trail_gradient(enemy_color_key: String) -> Gradient:
	match enemy_color_key:
		"opp_1":
			return _trail_gradient_enemy_opp1
		"opp_2":
			return _trail_gradient_enemy_opp2
		"opp_3":
			return _trail_gradient_enemy_opp3
		_:
			return _trail_gradient_enemy_opp3

func _get_nearest_node_in_group(group_name: String) -> Node2D:
	var nearest: Node2D = null
	var min_dist = INF
	for n in get_tree().get_nodes_in_group(group_name):
		if !is_instance_valid(n) or n == self or n.is_queued_for_deletion():
			continue
		var d = global_position.distance_to(n.global_position)
		if d < min_dist:
			min_dist = d
			nearest = n
	return nearest

func _draw():
	if !is_controllable:
		return

	for p in _friendly_spawn_highlight_points:
		_draw_trail_highlight_point(
			p,
			Color(0.62, 0.98, 0.74, 0.28),
			Color(0.90, 1.0, 0.95, 0.55)
		)

	for p in _enemy_spawn_highlight_points:
		_draw_trail_highlight_point(
			p,
			Color(0.35, 0.14, 0.50, 0.30),
			Color(0.62, 0.28, 0.80, 0.58)
		)

func _draw_trail_highlight_point(world_pos: Vector2, glow_color: Color, core_color: Color):
	if !_trail_highlight_texture:
		return

	var local_pos = to_local(world_pos)
	var glow_size = Vector2(26.0, 26.0)
	var core_size = Vector2(16.0, 16.0)
	var glow_rect = Rect2(local_pos - glow_size * 0.5, glow_size)
	var core_rect = Rect2(local_pos - core_size * 0.5, core_size)

	draw_texture_rect(_trail_highlight_texture, glow_rect, false, glow_color)
	draw_texture_rect(_trail_highlight_texture, core_rect, false, core_color)

func _update_trail_spawn_highlights():
	_enemy_spawn_highlight_points.clear()
	_friendly_spawn_highlight_points.clear()

	if !is_controllable:
		return

	var target_proximity_px = _get_world_spawn_target_proximity_px()
	var min_player_distance_px = _get_world_spawn_min_distance_px()
	var now = _get_time_seconds()

	for i in range(trail_points.size()):
		if i >= trail_point_spawn_times.size():
			break

		var p = trail_points[i]
		if now - trail_point_spawn_times[i] > trail_fade_lifetime_seconds:
			continue
		if global_position.distance_to(p) < min_player_distance_px:
			continue

		var enemy_dist = _get_nearest_distance_to_group_at_pos("enemy", p)
		var friendly_dist = _get_nearest_distance_to_group_at_pos("friendly_npc", p)
		var enemy_near = enemy_dist <= target_proximity_px
		var friendly_near = friendly_dist <= target_proximity_px

		if enemy_near and (!friendly_near or enemy_dist <= friendly_dist):
			_enemy_spawn_highlight_points.append(p)
		elif friendly_near:
			_friendly_spawn_highlight_points.append(p)

func _get_nearest_distance_to_group_at_pos(group_name: String, at_pos: Vector2) -> float:
	var min_dist = INF
	for n in get_tree().get_nodes_in_group(group_name):
		if !is_instance_valid(n) or n == self or n.is_queued_for_deletion():
			continue
		var d = at_pos.distance_to(n.global_position)
		if d < min_dist:
			min_dist = d
	return min_dist

func _get_world_spawn_target_proximity_px() -> float:
	var world = get_tree().current_scene
	if world and "trail_spawn_target_proximity_meters" in world:
		return float(world.trail_spawn_target_proximity_meters) * PIXELS_PER_METER
	return trail_color_proximity_meters * PIXELS_PER_METER

func _get_world_spawn_min_distance_px() -> float:
	var world = get_tree().current_scene
	if world and "trail_spawn_min_distance_from_player_meters" in world:
		return float(world.trail_spawn_min_distance_from_player_meters) * PIXELS_PER_METER
	return 1.0 * PIXELS_PER_METER

func _play_hit_flash():
	if !_sprite:
		return
	if _hit_flash_tween:
		_hit_flash_tween.kill()

	_sprite.modulate = Color.WHITE
	_hit_flash_tween = create_tween()
	for i in range(3):
		_hit_flash_tween.tween_property(_sprite, "modulate", Color(1.0, 0.25, 0.25, 1.0), 0.06)
		_hit_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.08)

func _perform_dash(input_dir: Vector2):
	if input_dir.length() > 0.1:
		_dash_direction = input_dir.normalized()
	elif _sprite.flip_h:
		_dash_direction = Vector2.LEFT
	else:
		_dash_direction = Vector2.RIGHT
	
	_is_dashing = true
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	
	# Disable collision so dash phases through enemies
	if _collision_shape:
		_collision_shape.set_deferred("disabled", true)
	
	if _loaded_anims.has("jump_start"):
		_play_anim("jump_start")
	elif _loaded_anims.has("jump_loop"):
		_play_anim("jump_loop")
	elif _loaded_anims.has("sliding"):
		_play_anim("sliding")
	
	if _dash_direction.x < 0:
		_sprite.flip_h = true
		_hitbox.position.x = -hitbox_offset_x
	elif _dash_direction.x > 0:
		_sprite.flip_h = false
		_hitbox.position.x = hitbox_offset_x
	
	_spawn_dash_ghost()
	emit_signal("dash_performed")
	_set_idle_clock_audio_active(false)

func _update_dash(delta: float):
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_is_dashing = false
		# Re-enable collision after dash ends
		if _collision_shape:
			_collision_shape.set_deferred("disabled", false)
		return
	
	velocity = _dash_direction * dash_speed
	move_and_slide()
	
	if global_position.distance_to(_last_trail_pos) >= trail_point_spacing_px * 0.5:
		_last_trail_pos = global_position
		trail_points.push_front(global_position)
		trail_point_spawn_times.push_front(_get_time_seconds())
		if trail_points.size() > MAX_TRAIL_POINTS:
			trail_points.pop_back()
		if trail_point_spawn_times.size() > MAX_TRAIL_POINTS:
			trail_point_spawn_times.pop_back()

func _spawn_dash_ghost():
	if !_sprite:
		return
	var ghost = Sprite2D.new()
	ghost.texture = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	ghost.global_position = global_position
	ghost.scale = _sprite.scale
	ghost.offset = _sprite.offset
	ghost.flip_h = _sprite.flip_h
	ghost.modulate = Color(0.6, 0.85, 1.0, 0.6)
	ghost.z_index = z_index - 1
	get_parent().add_child(ghost)
	var tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.4)
	tween.tween_callback(ghost.queue_free)

func _get_move_input_vector() -> Vector2:
	var dir = Vector2.ZERO
	if Input.is_action_pressed("ui_right"): dir.x += 1
	if Input.is_action_pressed("ui_left"): dir.x -= 1
	if Input.is_action_pressed("ui_up"): dir.y -= 1
	if Input.is_action_pressed("ui_down"): dir.y += 1
	return dir

func _update_idle_death_timer(_delta: float, _is_moving_input: bool):
	# Idle death disabled — player no longer dies from standing still
	_set_idle_clock_audio_active(false)
	return

func _set_idle_clock_audio_active(active: bool):
	if !is_controllable:
		return
	if _idle_clock_audio_active == active:
		return
	_idle_clock_audio_active = active
	emit_signal("idle_clock_active_changed", active)

func set_stealth_hidden(hidden: bool):
	if _stealth_hidden == hidden:
		return
	_stealth_hidden = hidden
	modulate.a = 0.52 if hidden else 1.0

func is_stealth_hidden() -> bool:
	return _stealth_hidden

func spawn_effect():
	# Scale in and blink
	scale = Vector2.ZERO
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.2)
	
	# Blinking effect
	for i in range(5):
		tween.tween_property(self, "modulate:a", 0.3, 0.1)
		tween.tween_property(self, "modulate:a", 1.0, 0.1)

func _play_anim(anim: String):
	if _current_anim != anim and _sprite and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
		_current_anim = anim

func _play_anim_once(anim: String) -> bool:
	if _sprite and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
		_sprite.sprite_frames.set_animation_loop(anim, false)
		_current_anim = anim
		return true
	return false

func _get_runtime_sprite_scale(sample_tex: Texture2D) -> Vector2:
	if sample_tex == null:
		return Vector2.ONE
	var tex_height = max(1.0, float(sample_tex.get_height()))
	var uniform_scale = PLAYER_TARGET_DISPLAY_HEIGHT / tex_height
	return Vector2.ONE * uniform_scale

func _get_default_animation_name() -> String:
	if _resolved_default_animation != "" and _loaded_anims.has(_resolved_default_animation):
		return _resolved_default_animation
	if default_animation != "" and _loaded_anims.has(default_animation):
		return default_animation
	if _loaded_anims.has("idle"):
		return "idle"
	return "" if _loaded_anims.is_empty() else String(_loaded_anims[0])

func _get_next_attack_animation(force_chain: bool = false) -> String:
	if _attack_animations.is_empty():
		if _loaded_anims.has("slashing"):
			return "slashing"
		if _loaded_anims.has("kicking"):
			return "kicking"
		return ""

	if _attack_animations.size() == 1:
		return String(_attack_animations[0])

	if (!force_chain and _attack_chain_timer <= 0.0) or _last_attack_animation == "":
		return String(_attack_animations[0])

	var last_idx = _attack_animations.find(_last_attack_animation)
	if last_idx == -1:
		return String(_attack_animations[0])

	return String(_attack_animations[(last_idx + 1) % _attack_animations.size()])

func _queue_attack():
	var max_queue = max(1, _attack_animations.size() - 1)
	_queued_attack_count = min(_queued_attack_count + 1, max_queue)
	_attack_buffer_timer = attack_buffer_seconds

func _get_attack_chain_window(anim_name: String) -> float:
	return max(attack_buffer_seconds + _get_animation_duration_seconds(anim_name) + 0.12, 0.42)

func _get_animation_duration_seconds(anim_name: String) -> float:
	if !_sprite or !_sprite.sprite_frames or anim_name == "" or !_sprite.sprite_frames.has_animation(anim_name):
		return 0.0
	var fps = max(1.0, _sprite.sprite_frames.get_animation_speed(anim_name))
	var frame_count = max(1, _sprite.sprite_frames.get_frame_count(anim_name))
	return float(frame_count) / fps

func _load_frames(dir_path: String) -> Array:
	var result = []
	var dir = DirAccess.open(dir_path)
	if dir == null: return result
	dir.list_dir_begin()
	var f = dir.get_next()
	var files = []
	while f != "":
		if !dir.current_is_dir():
			var file_name = f
			if file_name.ends_with(".import"):
				file_name = file_name.replace(".import", "")
			if file_name.ends_with(".remap"):
				file_name = file_name.replace(".remap", "")
				
			if file_name.ends_with(".png"):
				if not file_name in files:
					files.append(file_name)
		f = dir.get_next()
	files.sort()
	for n in files:
		var t = load(dir_path + n)
		if t: result.append(t)
	return result
