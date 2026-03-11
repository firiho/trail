extends CharacterBody2D

static var _SPRITE_BUILD_CACHE := {}

@export var opp_folder: String = "opp_1"
@export var group_id: int = 0



const BASE_SPEED = 250.0
const ATTACK_RANGE = 55.0
const DETECT_RANGE = 400.0
const PIXELS_PER_METER = 40.0
const MIN_CHASE_SPACING = 30.0

# Per-instance randomness (set in _ready)
var _speed: float = BASE_SPEED
var _aggro_delay: float = 0.0
var _attack_pause: float = 0.0
var _strafe_offset: Vector2 = Vector2.ZERO
var _strafe_timer: float = 0.0
var _dodge_chance: float = 0.0

@export_group("Offsets")
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var hitbox_offset_x: float = 30.0
@export_group("Aggro")
@export var proximity_aggro_enabled: bool = true
@export var proximity_aggro_range_meters: float = 5.0
@export var proximity_aggro_linger_seconds: float = 1.0
@export_group("Attack Telegraph")
@export var attack_tell_enabled: bool = true
@export var attack_tell_duration_seconds: float = 0.35
@export_group("Stealth")
@export var forced_disengage_cooldown_seconds: float = 3.2

# State
enum State { IDLE, CHASE, ATTACK, HURT, DYING, JOIN_GROUP }
var current_state = State.IDLE
var target_body: CharacterBody2D = null
var group_target_pos: Vector2 = Vector2.ZERO
var health = 60

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _hitbox: Area2D = $Hitbox
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _current_anim: String = ""
var _loaded_anims: Array[String] = []
var _proximity_aggro_timer: float = 0.0
var _attack_tell_progress: float = 0.0
var _attack_tell_visible: bool = false
var _attack_tell_tween: Tween = null
var _attack_tell_particles: CPUParticles2D = null
var _attack_tell_label: Label = null
var _attack_tell_label_tween: Tween = null
var _forced_disengage_timer: float = 0.0

func _ready():
	add_to_group("enemy")
	add_to_group("opp_group_" + str(group_id))
	# _setup_collision()
	_build_sprite()
	_setup_attack_tell_particles()
	_setup_attack_tell_label()
	_randomize_personality()
	
	if not _hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		_hitbox.body_entered.connect(_on_hitbox_body_entered)

func _randomize_personality():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	# Speed varies ±30%
	_speed = BASE_SPEED * rng.randf_range(0.7, 1.3)
	# Some enemies hesitate before chasing (0-1s)
	_aggro_delay = rng.randf_range(0.0, 1.0)
	# Pause between attacks (0-0.8s)
	_attack_pause = rng.randf_range(0.0, 0.8)
	# Some enemies strafe while chasing
	_strafe_offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.0, 40.0)
	# Dodge chance 0-20%
	_dodge_chance = rng.randf_range(0.0, 0.2)
	# Randomize aggro linger too
	proximity_aggro_linger_seconds = rng.randf_range(0.3, 2.0)
	# Randomize attack telegraph speed
	attack_tell_duration_seconds = rng.randf_range(0.15, 0.5)

# func _setup_collision(): ... removed

func _build_sprite():
	var base = "res://assets/opps/" + opp_folder + "/"
	var anims = ["idle", "walking", "attacking", "dying", "hurt", "taunt"]
	_loaded_anims.clear()

	var sf: SpriteFrames = null
	if _SPRITE_BUILD_CACHE.has(opp_folder):
		var cached = _SPRITE_BUILD_CACHE[opp_folder]
		sf = (cached["sprite_frames"] as SpriteFrames).duplicate(true)
		_loaded_anims = cached["loaded_anims"].duplicate()
	else:
		var template_sf = SpriteFrames.new()
		if template_sf.has_animation("default"): template_sf.remove_animation("default")
		var built_anims: Array[String] = []
		
		for anim in anims:
			var dir = base + anim + "/"
			var frames = _load_frames(dir)
			if frames.size() > 0:
				template_sf.add_animation(anim)
				template_sf.set_animation_loop(anim, true)
				template_sf.set_animation_speed(anim, 15.0)
				for t in frames:
					template_sf.add_frame(anim, t)
				built_anims.append(anim)
		
		_SPRITE_BUILD_CACHE[opp_folder] = {
			"sprite_frames": template_sf,
			"loaded_anims": built_anims.duplicate()
		}
		sf = template_sf.duplicate(true)
		_loaded_anims = built_anims
				
	# _sprite = AnimatedSprite2D.new() # Already in scene
	_sprite.sprite_frames = sf
	_sprite.scale = Vector2(0.25, 0.25)
	
	# Offset sprite so its "position" is at its feet
	if sprite_offset != Vector2.ZERO:
		_sprite.offset = sprite_offset
	else:
		var sample_tex = sf.get_frame_texture("idle", 0)
		if sample_tex:
			_sprite.offset.y = -sample_tex.get_height() / 2.0
	
	_hitbox.position.x = hitbox_offset_x
	
	if not _sprite.animation_finished.is_connected(_on_anim_finished):
		_sprite.animation_finished.connect(_on_anim_finished)
	# add_child(_sprite)
	_play_anim("idle")
	_sprite.play("idle") # Force play

func _process(delta):
	if current_state == State.DYING: return
	_forced_disengage_timer = max(0.0, _forced_disengage_timer - max(0.0, delta))
	if _attack_tell_visible:
		queue_redraw()

	# Safety check for target
	if target_body and not is_instance_valid(target_body):
		target_body = null
		current_state = State.IDLE
	elif target_body and _is_target_hidden(target_body):
		force_forget_player(target_body, 140.0)
	
	# AI Logic
	match current_state:
		State.IDLE:
			_play_anim("idle")
			if target_body:
				current_state = State.CHASE
			else:
				# Face nearest player if close
				var nearest = null
				var min_dist = 99999.0
				var players = get_tree().get_nodes_in_group("player")
				for p in players:
					var d = global_position.distance_to(p.global_position)
					if d < min_dist:
						min_dist = d
						nearest = p
				
				if nearest and min_dist < DETECT_RANGE:
					var dir_to = (nearest.global_position - global_position).normalized()
					if dir_to.x < 0:
						_sprite.flip_h = true
						_hitbox.scale.x = -1
					else:
						_sprite.flip_h = false
						_hitbox.scale.x = 1
				
				_try_proximity_aggro(delta)
		
		State.CHASE:
			if target_body:
				var to_target = target_body.global_position - global_position
				var dist = to_target.length()
				if dist <= ATTACK_RANGE:
					if dist < MIN_CHASE_SPACING:
						_push_off_from_target(target_body.global_position)
					else:
						# Random pause before attacking
						if _attack_pause > 0.0:
							_attack_pause -= delta
							velocity = Vector2.ZERO
						else:
							velocity = Vector2.ZERO
							current_state = State.ATTACK
				else:
					var dir = to_target.normalized()
					# Strafe while chasing for unpredictable movement
					_strafe_timer += delta
					var strafe = Vector2(-dir.y, dir.x) * sin(_strafe_timer * 2.5) * _strafe_offset.length()
					velocity = dir * _speed + strafe
					move_and_slide()
					
					if dir.x < 0: 
						_sprite.flip_h = true
						_hitbox.position.x = -hitbox_offset_x
					else:
						_sprite.flip_h = false
						_hitbox.position.x = hitbox_offset_x
					
					_play_anim("walking")
			else:
				current_state = State.IDLE
		
		State.JOIN_GROUP:
			var dist = global_position.distance_to(group_target_pos)
			if dist < 60.0:
				current_state = State.IDLE
			else:
				var dir = (group_target_pos - global_position).normalized()
				velocity = dir * _speed
				move_and_slide()
				
				if dir.x < 0: 
					_sprite.flip_h = true
					_hitbox.position.x = -hitbox_offset_x
				else:
					_sprite.flip_h = false
					_hitbox.position.x = hitbox_offset_x
				
				_play_anim("walking")
			_try_proximity_aggro(delta)

		State.ATTACK:
			if target_body:
				var dir_to_target = (target_body.global_position - global_position).normalized()
				if dir_to_target.x < 0:
					_sprite.flip_h = true
					_hitbox.scale.x = -1
				else:
					_sprite.flip_h = false
					_hitbox.scale.x = 1
			
			if _play_anim_once("attacking"):
				_hitbox.monitoring = true
			# Wait for anim finish
		
		State.HURT:
			# Stunned
			pass

func _push_off_from_target(target_pos: Vector2):
	var away = global_position - target_pos
	if away.length_squared() <= 0.0001:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if away.length_squared() <= 0.0001:
		away = Vector2.RIGHT
	away = away.normalized()

	velocity = away * _speed * 0.6
	move_and_slide()

	if away.x < 0:
		_sprite.flip_h = true
		_hitbox.position.x = -hitbox_offset_x
	else:
		_sprite.flip_h = false
		_hitbox.position.x = hitbox_offset_x
	_play_anim("walking")

func _on_anim_finished():
	if current_state == State.ATTACK:
		_hitbox.monitoring = false
		_clear_attack_tell()
		_current_anim = "" # Reset so we can attack again immediately
		# Random post-attack pause before re-engaging
		_attack_pause = randf_range(0.0, 0.8)
		current_state = State.CHASE # check range
	elif current_state == State.HURT:
		_clear_attack_tell()
		current_state = State.IDLE # recover
		if target_body: current_state = State.CHASE

func _on_hitbox_body_entered(body):
	if body.is_in_group("player") or body.is_in_group("friendly_npc"):
		if body.has_method("take_damage"):
			body.take_damage(7)

func take_damage(amount):
	if current_state == State.DYING: return
	# Dodge chance — sometimes sidestep instead of taking full damage
	if randf() < _dodge_chance and current_state != State.HURT:
		var dodge_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		velocity = dodge_dir * _speed * 2.0
		move_and_slide()
		amount = int(amount * 0.5) # half damage on dodge
	health -= amount
	current_state = State.HURT
	_play_anim_once("hurt")
	
	# Alert group - DELAYED
	get_tree().call_group("opp_group_" + str(group_id), "on_ally_attacked", get_tree().get_first_node_in_group("player")) 
	
	if health <= 0:
		die()

func on_ally_attacked(target):
	if _forced_disengage_timer > 0.0:
		return
	if target and _is_target_hidden(target):
		return
	if target and !target_body:
		# Delayed reaction
		await get_tree().create_timer(randf_range(0.5, 1.5)).timeout
		if is_instance_valid(self) and is_instance_valid(target) and !target_body and _forced_disengage_timer <= 0.0 and !_is_target_hidden(target):
			target_body = target
			_start_attack_tell()
			current_state = State.CHASE

func _try_proximity_aggro(delta: float):
	if !proximity_aggro_enabled:
		_proximity_aggro_timer = 0.0
		return
	if target_body:
		_proximity_aggro_timer = 0.0
		return
	if _forced_disengage_timer > 0.0:
		_proximity_aggro_timer = 0.0
		return

	var player = get_tree().get_first_node_in_group("player")
	if !player or !is_instance_valid(player):
		_proximity_aggro_timer = 0.0
		return
	if _is_target_hidden(player):
		_proximity_aggro_timer = 0.0
		return

	var aggro_range_px = proximity_aggro_range_meters * PIXELS_PER_METER
	if global_position.distance_to(player.global_position) > aggro_range_px:
		_proximity_aggro_timer = 0.0
		return

	_proximity_aggro_timer += delta
	if _proximity_aggro_timer >= proximity_aggro_linger_seconds:
		target_body = player
		_start_attack_tell()
		current_state = State.CHASE
		_proximity_aggro_timer = 0.0

func _draw():
	if !_attack_tell_visible:
		return

	var center = Vector2(0, -48)
	var radius = 18.0
	var start_angle = -PI * 0.5
	var end_angle = start_angle + TAU * clamp(_attack_tell_progress, 0.0, 1.0)
	var base_color = _get_attack_tell_color()
	var pulse = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 80.0)
	var marker_color = Color(base_color.r, base_color.g, base_color.b, 1.0)
	var outline_color = Color(0, 0, 0, 0.85)

	draw_arc(center, radius + 2.0 * pulse, 0.0, TAU, 24, Color(base_color.r, base_color.g, base_color.b, 0.16), 5.0, true)
	if _attack_tell_progress > 0.01:
		draw_arc(center, radius, start_angle, end_angle, 24, Color(base_color.r, base_color.g, base_color.b, 0.95), 4.0, true)
		draw_circle(center, 3.5, Color(base_color.r, base_color.g, base_color.b, 0.75))

	# Guaranteed-visible exclamation marker above the ring.
	var ex_center = center + Vector2(0, -26)
	var ex_height = 20.0 + 3.0 * pulse
	var ex_top = ex_center + Vector2(0, -ex_height * 0.55)
	var ex_bottom = ex_center + Vector2(0, ex_height * 0.15)
	draw_line(ex_top, ex_bottom, outline_color, 7.0)
	draw_line(ex_top, ex_bottom, marker_color, 4.0)
	draw_circle(ex_center + Vector2(0, ex_height * 0.42), 4.2, outline_color)
	draw_circle(ex_center + Vector2(0, ex_height * 0.42), 2.7, marker_color)

func _start_attack_tell():
	if !attack_tell_enabled:
		return
	if _attack_tell_tween:
		_attack_tell_tween.kill()
	_attack_tell_visible = true
	_attack_tell_progress = 0.0
	_emit_attack_tell_particles()
	_show_attack_tell_label()
	_attack_tell_tween = create_tween()
	_attack_tell_tween.tween_method(_set_attack_tell_progress, 0.0, 1.0, max(0.05, attack_tell_duration_seconds))

func _set_attack_tell_progress(v: float):
	_attack_tell_progress = v
	queue_redraw()

func _clear_attack_tell():
	if _attack_tell_tween:
		_attack_tell_tween.kill()
		_attack_tell_tween = null
	if _attack_tell_label_tween:
		_attack_tell_label_tween.kill()
		_attack_tell_label_tween = null
	if _attack_tell_label:
		_attack_tell_label.visible = false
	_attack_tell_visible = false
	_attack_tell_progress = 0.0
	queue_redraw()

func _get_attack_tell_color() -> Color:
	match opp_folder:
		"opp_1":
			return Color(0.20, 0.55, 0.28, 1.0)
		"opp_2":
			return Color(0.62, 0.42, 0.24, 1.0)
		"opp_3":
			return Color(0.55, 0.28, 0.78, 1.0)
		_:
			return Color(1.0, 0.35, 0.35, 1.0)

func _setup_attack_tell_particles():
	if _attack_tell_particles:
		return

	_attack_tell_particles = CPUParticles2D.new()
	_attack_tell_particles.name = "AttackTellParticles"
	_attack_tell_particles.one_shot = true
	_attack_tell_particles.explosiveness = 1.0
	_attack_tell_particles.amount = 34
	_attack_tell_particles.lifetime = max(0.18, attack_tell_duration_seconds)
	_attack_tell_particles.emitting = false
	_attack_tell_particles.local_coords = true
	_attack_tell_particles.position = Vector2(0, -48)
	_attack_tell_particles.direction = Vector2.UP
	_attack_tell_particles.spread = 180.0
	_attack_tell_particles.gravity = Vector2.ZERO
	_attack_tell_particles.initial_velocity_min = 30.0
	_attack_tell_particles.initial_velocity_max = 64.0
	_attack_tell_particles.scale_amount_min = 0.7
	_attack_tell_particles.scale_amount_max = 1.35
	_attack_tell_particles.z_index = 20

	var tex = GradientTexture2D.new()
	tex.width = 16
	tex.height = 16
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.9, 0.5)
	var tex_grad = Gradient.new()
	tex_grad.colors = [Color.WHITE, Color(1, 1, 1, 0)]
	tex.gradient = tex_grad
	_attack_tell_particles.texture = tex

	add_child(_attack_tell_particles)

func _setup_attack_tell_label():
	if _attack_tell_label:
		return
	_attack_tell_label = Label.new()
	_attack_tell_label.name = "AttackTellLabel"
	_attack_tell_label.text = "!"
	_attack_tell_label.visible = false
	_attack_tell_label.position = Vector2(-10, -96)
	_attack_tell_label.z_index = 50
	_attack_tell_label.add_theme_font_size_override("font_size", 28)
	_attack_tell_label.add_theme_color_override("font_color", Color.WHITE)
	_attack_tell_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_attack_tell_label.add_theme_constant_override("shadow_outline_size", 8)
	add_child(_attack_tell_label)

func _show_attack_tell_label():
	if !_attack_tell_label:
		return
	if _attack_tell_label_tween:
		_attack_tell_label_tween.kill()

	var c = _get_attack_tell_color()
	_attack_tell_label.visible = true
	_attack_tell_label.modulate = Color(c.r, c.g, c.b, 1.0)
	_attack_tell_label.scale = Vector2(0.7, 0.7)
	_attack_tell_label.position = Vector2(-10, -92)

	_attack_tell_label_tween = create_tween()
	_attack_tell_label_tween.tween_property(_attack_tell_label, "scale", Vector2(1.2, 1.2), 0.08)
	_attack_tell_label_tween.parallel().tween_property(_attack_tell_label, "position:y", -108.0, 0.08)
	_attack_tell_label_tween.tween_property(_attack_tell_label, "scale", Vector2(1.0, 1.0), 0.10)
	_attack_tell_label_tween.parallel().tween_property(_attack_tell_label, "position:y", -100.0, 0.10)

func _emit_attack_tell_particles():
	if !_attack_tell_particles:
		return
	_attack_tell_particles.lifetime = max(0.18, attack_tell_duration_seconds)
	var c = _get_attack_tell_color()
	var grad = Gradient.new()
	grad.colors = [
		Color(c.r, c.g, c.b, 1.0),
		Color(c.r, c.g, c.b, 0.85),
		Color(c.r, c.g, c.b, 0.0)
	]
	grad.offsets = [0.0, 0.75, 1.0]
	_attack_tell_particles.color_ramp = grad
	_attack_tell_particles.emitting = false
	_attack_tell_particles.restart()
	_attack_tell_particles.emitting = true

func die():
	current_state = State.DYING
	_clear_attack_tell()
	_play_anim_once("dying")
	# Disable collision
	if _collision_shape:
		_collision_shape.call_deferred("set_disabled", true)
	await get_tree().create_timer(1.0).timeout
	queue_free()

func force_forget_player(player: Node2D, disengage_distance_px: float = 220.0):
	_clear_attack_tell()
	_hitbox.monitoring = false
	target_body = null
	_forced_disengage_timer = max(0.2, forced_disengage_cooldown_seconds)

	var origin = global_position
	if player and is_instance_valid(player):
		origin = player.global_position
	var away = global_position - origin
	if away.length_squared() <= 0.0001:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if away.length_squared() <= 0.0001:
		away = Vector2.RIGHT
	away = away.normalized()

	var retreat = max(80.0, disengage_distance_px) * randf_range(0.85, 1.2)
	var lateral = Vector2(-away.y, away.x) * randf_range(-60.0, 60.0)
	group_target_pos = global_position + away * retreat + lateral
	current_state = State.JOIN_GROUP

func _is_target_hidden(target: Node) -> bool:
	if !target or !is_instance_valid(target):
		return false
	if target.has_method("is_stealth_hidden"):
		return bool(target.is_stealth_hidden())
	return false

func join_group_behavior(target_pos: Vector2):
	group_target_pos = target_pos
	current_state = State.JOIN_GROUP

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

func _play_anim(anim):
	if _current_anim != anim and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
		_current_anim = anim

func _play_anim_once(anim) -> bool:
	if _current_anim != anim and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)
		_sprite.sprite_frames.set_animation_loop(anim, false) # Once
		_current_anim = anim
		return true
	return false

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
