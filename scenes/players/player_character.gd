extends CharacterBody2D

@export var player_folder: String = "player_1"
@export var default_animation: String = "idle_blinking"
@export var move_speed: float = 400.0
@export var is_controllable: bool = false

@export_group("Offsets")
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var hitbox_offset_x: float = 40.0

signal health_changed(current, max)
signal died



const PLAYER_FPS = 20.0
const PLAYER_SCALE = Vector2(0.15, 0.15)

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

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _hitbox: Area2D = $Hitbox
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _current_anim: String = ""
var _loaded_anims: Array[String] = []

# Trail tracking for logic
var trail_points: Array[Vector2] = []
var _last_trail_pos: Vector2 = Vector2.ZERO
const TRAIL_MIN_SPACING = 30.0 
const MAX_TRAIL_POINTS = 100

var group_target_pos: Vector2 = Vector2.ZERO
var is_joining_group: bool = false

func _ready():
	_build_sprite()
	# _setup_collision() # Now set in scene
	add_to_group("player" if is_controllable else "friendly_npc")
	if is_controllable:
		_create_trail()
		_last_trail_pos = global_position

func _create_trail():
	var trail = CPUParticles2D.new()
	trail.amount = 80
	trail.lifetime = 5.0
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
	
	# Gradient for color (Pure White to transparent)
	var grad = Gradient.new()
	grad.colors = [
		Color(1, 1, 1, 1), # Start Opaque
		Color(1, 1, 1, 0.8),
		Color(1, 1, 1, 0.0)  # End
	]
	grad.offsets = [0.0, 0.8, 1.0]
	trail.color_ramp = grad
	
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
	
	# Position at base
	trail.position = Vector2(0, 0)
	add_child(trail)
	move_child(trail, 0) # Behind sprite

func _build_sprite():
	var base_path = "res://assets/players/" + player_folder + "/"
	var sf = SpriteFrames.new()
	if sf.has_animation("default"): sf.remove_animation("default")
	
	for anim_name in ALL_ANIMATIONS:
		var anim_path = base_path + anim_name + "/"
		var frames = _load_frames(anim_path)
		if frames.size() > 0:
			sf.add_animation(anim_name)
			sf.set_animation_loop(anim_name, true)
			sf.set_animation_speed(anim_name, PLAYER_FPS)
			for tex in frames:
				sf.add_frame(anim_name, tex)
			_loaded_anims.append(anim_name)
	
	# _sprite = AnimatedSprite2D.new() # Already in scene
	_sprite.sprite_frames = sf
	_sprite.scale = PLAYER_SCALE
	
	# Offset sprite so its "position" is at its feet
	if sprite_offset != Vector2.ZERO:
		_sprite.offset = sprite_offset
	else:
		var sample_tex = sf.get_frame_texture(default_animation, 0)
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
	_play_anim(default_animation)

# func _setup_collision(): ... removed

func _process(delta):
	if is_dead: return
	
	# Gravity / Z-axis simulation? Top-down usually no gravity.
	# Combat Input
	if is_controllable and Input.is_action_just_pressed("attack") and !is_attacking:
		attack()
	
	if is_attacking:
		return # Lock movement
		
	if !is_controllable:
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

		_play_anim(default_animation)
		return
	
	# Movement
	var dir = Vector2.ZERO
	if Input.is_action_pressed("ui_right"): dir.x += 1
	if Input.is_action_pressed("ui_left"): dir.x -= 1
	if Input.is_action_pressed("ui_up"): dir.y -= 1
	if Input.is_action_pressed("ui_down"): dir.y += 1
	
	if dir.length() > 0:
		velocity = dir.normalized() * move_speed
		move_and_slide()
		
		# Update trail points
		if global_position.distance_to(_last_trail_pos) >= TRAIL_MIN_SPACING:
			_last_trail_pos = global_position
			trail_points.push_front(global_position)
			if trail_points.size() > MAX_TRAIL_POINTS:
				trail_points.pop_back()
		
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
		_play_anim(default_animation)

func attack():
	if _play_anim_once("slashing") or _play_anim_once("kicking"):
		is_attacking = true
		_hitbox.monitoring = true
		
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
				body.take_damage(20)
			# Can also hit friendly NPCs if controllable player attacks
			if is_controllable and body.is_in_group("friendly_npc") and body != self and body.has_method("take_damage"):
				body.take_damage(20)

func _on_anim_finished():
	if is_attacking:
		is_attacking = false
		_hitbox.monitoring = false
		_play_anim(default_animation)
	
	if _current_anim == "hurt":
		is_attacking = false # interrupt attack
		# return to idle
		_play_anim(default_animation)

func set_input_enabled(enabled: bool):
	set_process(enabled)
	set_physics_process(enabled)
	if !enabled:
		_play_anim("idle")
		velocity = Vector2.ZERO

func take_damage(amount):
	if is_dead: return
	health -= amount
	emit_signal("health_changed", health, 100) # Assuming max 100
	print("Player took damage: ", amount, " HP: ", health)
	
	if health <= 0:
		die()
	else:
		_play_anim_once("hurt")

func die():
	if is_dead: return
	is_dead = true
	emit_signal("died")
	_play_anim_once("dying")
	# Disable collision
	if _collision_shape:
		_collision_shape.call_deferred("set_disabled", true)
	if is_controllable:
		print("GAME OVER")
	else:
		print("Friendly NPC died")
		# Fade out?
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 2.0)
		tween.tween_callback(queue_free)

func join_group_behavior(target_pos: Vector2):
	group_target_pos = target_pos
	is_joining_group = true

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
