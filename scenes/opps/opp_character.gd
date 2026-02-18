extends CharacterBody2D

@export var opp_folder: String = "opp_1"
@export var group_id: int = 0



const SPEED = 250.0
const ATTACK_RANGE = 55.0
const DETECT_RANGE = 400.0

@export_group("Offsets")
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var hitbox_offset_x: float = 30.0

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

func _ready():
	add_to_group("enemy")
	add_to_group("opp_group_" + str(group_id))
	# _setup_collision()
	_build_sprite()
	
	if not _hitbox.body_entered.is_connected(_on_hitbox_body_entered):
		_hitbox.body_entered.connect(_on_hitbox_body_entered)

# func _setup_collision(): ... removed

func _build_sprite():
	var base = "res://assets/opps/" + opp_folder + "/"
	var anims = ["idle", "walking", "attacking", "dying", "hurt", "taunt"]
	
	var sf = SpriteFrames.new()
	if sf.has_animation("default"): sf.remove_animation("default")
	
	for anim in anims:
		var dir = base + anim + "/"
		var frames = _load_frames(dir)
		if frames.size() > 0:
			sf.add_animation(anim)
			sf.set_animation_loop(anim, true)
			sf.set_animation_speed(anim, 15.0)
			for t in frames:
				sf.add_frame(anim, t)
			_loaded_anims.append(anim)
			print("Opp ", opp_folder, " loaded ", anim, ": ", frames.size(), " frames")
			
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

	# Safety check for target
	if target_body and not is_instance_valid(target_body):
		target_body = null
		current_state = State.IDLE
	
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
		
		State.CHASE:
			if target_body:
				var dist = global_position.distance_to(target_body.global_position)
				if dist <= ATTACK_RANGE:
					velocity = Vector2.ZERO # Stop immediately
					current_state = State.ATTACK
				else:
					var dir = (target_body.global_position - global_position).normalized()
					velocity = dir * SPEED
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
				velocity = dir * SPEED
				move_and_slide()
				
				if dir.x < 0: 
					_sprite.flip_h = true
					_hitbox.position.x = -hitbox_offset_x
				else:
					_sprite.flip_h = false
					_hitbox.position.x = hitbox_offset_x
					
				_play_anim("walking")

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

func _on_anim_finished():
	if current_state == State.ATTACK:
		_hitbox.monitoring = false
		_current_anim = "" # Reset so we can attack again immediately
		current_state = State.CHASE # check range
	elif current_state == State.HURT:
		current_state = State.IDLE # recover
		if target_body: current_state = State.CHASE

func _on_hitbox_body_entered(body):
	if body.is_in_group("player") or body.is_in_group("friendly_npc"):
		if body.has_method("take_damage"):
			body.take_damage(7)

func take_damage(amount):
	if current_state == State.DYING: return
	health -= amount
	current_state = State.HURT
	_play_anim_once("hurt")
	
	_play_anim_once("hurt")
	
	# Alert group - DELAYED
	get_tree().call_group("opp_group_" + str(group_id), "on_ally_attacked", get_tree().get_first_node_in_group("player")) 
	
	if health <= 0:
		die()

func on_ally_attacked(target):
	if target and !target_body:
		# Delayed reaction
		await get_tree().create_timer(randf_range(0.5, 1.5)).timeout
		if is_instance_valid(self) and is_instance_valid(target) and !target_body:
			target_body = target
			current_state = State.CHASE

func die():
	current_state = State.DYING
	_play_anim_once("dying")
	# Disable collision
	if _collision_shape:
		_collision_shape.call_deferred("set_disabled", true)
	await get_tree().create_timer(1.0).timeout
	queue_free()

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
