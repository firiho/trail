extends Node2D

static var _auto_start_after_reload: bool = false

const TILE_PX = 32
const CHUNK_SIZE = 32
const CHUNK_PX = CHUNK_SIZE * TILE_PX 
const ENV_ANIM_FPS = 5.0
const WORLD_SEED = 42

# Preload scenes
var Opp1Scene = preload("res://scenes/opps/opp_1.tscn")
var Opp2Scene = preload("res://scenes/opps/opp_2.tscn")
var Opp3Scene = preload("res://scenes/opps/opp_3.tscn")
var Player1Scene = preload("res://scenes/players/player_1.tscn")
var Player2Scene = preload("res://scenes/players/player_2.tscn")
var Player3Scene = preload("res://scenes/players/player_3.tscn")

# State
var generated_chunks = {}
var player_ref: Node2D = null
var next_group_id = 1

const PIXELS_PER_METER = 40.0
@export var trail_spawn_target_proximity_meters: float = 3.0
@export var trail_spawn_min_distance_from_player_meters: float = 1.0
@export var help_call_min_friendly_distance_meters: float = 3.0
@export var help_call_cluster_radius_meters: float = 3.0
var transform_cooldown: float = 0.0
const TRANSFORM_COOLDOWN_MAX = 3.0

enum { START, PLAYING, GAMEOVER }
var game_state = START
var ui = null

const DB_SILENT = -80.0

@export_group("Audio")
@export var menu_music_volume_db: float = -10.0
@export var soundtrack_volume_db: float = -12.0
@export var soundtrack_near_enemy_volume_db: float = -20.0
@export var wrong_place_volume_db: float = -12.0
@export var clock_volume_db: float = -18.0
@export var player_attack_volume_db: float = -4.0
@export var friendly_attack_volume_db: float = -14.0
@export var player_hit_volume_db: float = -8.0
@export var enemy_music_blend_range_meters: float = 8.0
@export var music_fade_speed: float = 3.0
@export var sfx_fade_speed: float = 8.0

var _menu_music_player: AudioStreamPlayer = null
var _main_music_player: AudioStreamPlayer = null
var _danger_music_player: AudioStreamPlayer = null
var _clock_player: AudioStreamPlayer = null
var _ui_start_sfx_player: AudioStreamPlayer = null
var _ui_game_over_sfx_player: AudioStreamPlayer = null

var _menu_music_stream = preload("res://assets/audio/start-and-gameover-soundtrack.mp3")
var _main_music_stream = preload("res://assets/audio/soundtrack.mp3")
var _danger_music_stream = preload("res://assets/audio/wrong-place-soundtrack.mp3")
var _clock_stream = preload("res://assets/audio/clock.mp3")
var _start_click_stream = preload("res://assets/audio/game-start.wav")
var _game_over_stream = preload("res://assets/audio/game-end.wav")
var _player_sword_stream = preload("res://assets/audio/player-sword.mp3")
var _enemy_hits_stream = preload("res://assets/audio/enemy-hits.mp3")

var _danger_music_mix: float = 0.0
var _clock_should_play: bool = false

# Asset References
var tile_source_ids: Array[int] = []
var tree_textures: Array = []
var bush_textures: Array = []
var stone_textures: Array = []
var decor_textures: Array = [] 
var anim_env_sheets: Array = [] 

func _ready():
	seed(WORLD_SEED)
	_setup_audio()
	
	# 1. UI Setup (Do this FIRST to avoid null refs in _process/_input)
	var ui_scene = load("res://scenes/ui_hud.tscn")
	if ui_scene:
		ui = ui_scene.instantiate()
		add_child(ui)
	
	_setup_assets()
	_setup_tilemap()
	
	var world = Node2D.new()
	world.name = "WorldContainer"
	world.y_sort_enabled = true # Enable sorting
	add_child(world)
	move_child($BackgroundTileMap, 0)
	
	_place_fixed_entities()
	
	_update_chunks()
	
	if ui:
		if player_ref and player_ref.has_signal("health_changed"):
			player_ref.health_changed.connect(ui.update_health)
			player_ref.died.connect(_on_player_died)
			# Init health
			ui.update_health(player_ref.health, 100)
		if player_ref and player_ref.has_signal("idle_timer_changed") and ui.has_method("update_idle_timer"):
			player_ref.idle_timer_changed.connect(ui.update_idle_timer)
			if "idle_death_time_left" in player_ref and "idle_death_timeout_seconds" in player_ref:
				ui.update_idle_timer(player_ref.idle_death_time_left, player_ref.idle_death_timeout_seconds)
		
		# Start State
		game_state = START
		if _auto_start_after_reload:
			_auto_start_after_reload = false
			ui.show_hud()
			if player_ref and player_ref.has_method("set_input_enabled"):
				player_ref.set_input_enabled(true)
			game_state = PLAYING
		else:
			ui.show_start_screen()
		
	if game_state != PLAYING and player_ref and player_ref.has_method("set_input_enabled"):
		player_ref.set_input_enabled(false)
	_clock_should_play = false
	_refresh_audio_state(true)

func _input(event):
	if event.is_action_pressed("attack"):
		if game_state == START:
			start_game()
		elif game_state == GAMEOVER:
			restart_game()
	if event.is_action_pressed("help") and game_state == PLAYING:
		_call_for_help()

func start_game():
	if !ui: return
	game_state = PLAYING
	_play_ui_start_sfx()
	ui.show_hud()
	if player_ref and player_ref.has_method("set_input_enabled"):
		player_ref.set_input_enabled(true)
	_refresh_audio_state()

func restart_game():
	_auto_start_after_reload = true
	get_tree().reload_current_scene()

func _on_player_died():
	game_state = GAMEOVER
	_clock_should_play = false
	_play_game_over_sfx()
	_refresh_audio_state()
	if ui: ui.show_game_over()

func _process(delta):
	if is_instance_valid(player_ref):
		_update_chunks()
		_process_trail_transformation()
		
		# Update UI with proximity to nearest group
		var nearest_enemy = _get_nearest_in_group(player_ref.global_position, "enemy")
		var nearest_friend = _get_nearest_in_group(player_ref.global_position, "friendly_npc")
		var enemy_dist_m = -1.0
		var friend_dist_m = -1.0
		var nearest_enemy_color_key := ""
		if nearest_enemy:
			enemy_dist_m = player_ref.global_position.distance_to(nearest_enemy.global_position) / PIXELS_PER_METER
			if "opp_folder" in nearest_enemy:
				nearest_enemy_color_key = str(nearest_enemy.opp_folder)
		if nearest_friend:
			friend_dist_m = player_ref.global_position.distance_to(nearest_friend.global_position) / PIXELS_PER_METER
		
			if ui and ui.has_method("update_transform_info"):
				ui.update_transform_info(enemy_dist_m, friend_dist_m, nearest_enemy_color_key, trail_spawn_target_proximity_meters)
		_update_dynamic_music_blend(delta, enemy_dist_m)
	else:
		_update_dynamic_music_blend(delta, -1.0)

	if transform_cooldown > 0:
		transform_cooldown -= delta

	_update_clock_audio(delta)
	_refresh_audio_state()

# =====================================================================
# AUDIO
# =====================================================================
func _setup_audio():
	_menu_music_player = _make_audio_player("MenuMusic", _menu_music_stream, true)
	_main_music_player = _make_audio_player("MainMusic", _main_music_stream, true)
	_danger_music_player = _make_audio_player("DangerMusic", _danger_music_stream, true)
	_clock_player = _make_audio_player("ClockLoop", _clock_stream, true)
	_ui_start_sfx_player = _make_audio_player("StartClickSfx", _start_click_stream, false)
	_ui_game_over_sfx_player = _make_audio_player("GameOverSfx", _game_over_stream, false)

	for p in [_menu_music_player, _main_music_player, _danger_music_player, _clock_player]:
		if p:
			p.volume_db = DB_SILENT
			if !p.playing:
				p.play()

func _make_audio_player(node_name: String, stream: AudioStream, looped: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	_set_stream_loop(p.stream, looped)
	add_child(p)
	return p

func _set_stream_loop(stream: AudioStream, enabled: bool):
	if !stream:
		return
	if stream is AudioStreamMP3:
		stream.loop = enabled
	elif stream is AudioStreamOggVorbis:
		stream.loop = enabled
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED

func _refresh_audio_state(force: bool = false):
	var in_menu_state = game_state == START or game_state == GAMEOVER
	var in_play_state = game_state == PLAYING

	var menu_target = menu_music_volume_db if in_menu_state else DB_SILENT
	var main_target = DB_SILENT
	var danger_target = DB_SILENT
	if in_play_state:
		main_target = lerpf(soundtrack_volume_db, soundtrack_near_enemy_volume_db, _danger_music_mix)
		danger_target = lerpf(DB_SILENT, wrong_place_volume_db, _danger_music_mix)

	_set_player_target_volume(_menu_music_player, menu_target, force, music_fade_speed)
	_set_player_target_volume(_main_music_player, main_target, force, music_fade_speed)
	_set_player_target_volume(_danger_music_player, danger_target, force, music_fade_speed)

func _update_dynamic_music_blend(delta: float, nearest_enemy_dist_m: float):
	var target_mix := 0.0
	if game_state == PLAYING and nearest_enemy_dist_m >= 0.0 and enemy_music_blend_range_meters > 0.0:
		target_mix = clamp(1.0 - (nearest_enemy_dist_m / enemy_music_blend_range_meters), 0.0, 1.0)
	var t = clamp(delta * music_fade_speed, 0.0, 1.0)
	_danger_music_mix = lerpf(_danger_music_mix, target_mix, t)

func _update_clock_audio(delta: float):
	var target = clock_volume_db if game_state == PLAYING and _clock_should_play else DB_SILENT
	_set_player_target_volume(_clock_player, target, false, sfx_fade_speed, delta)

func _set_player_target_volume(player: AudioStreamPlayer, target_db: float, force: bool = false, speed: float = 5.0, delta: float = -1.0):
	if !player:
		return
	if force:
		player.volume_db = target_db
		return
	var dt = delta if delta >= 0.0 else get_process_delta_time()
	var t = clamp(dt * speed, 0.0, 1.0)
	player.volume_db = lerpf(player.volume_db, target_db, t)

func _play_ui_start_sfx():
	if _ui_start_sfx_player:
		_ui_start_sfx_player.play()

func _play_game_over_sfx():
	if _ui_game_over_sfx_player:
		_ui_game_over_sfx_player.play()

func _play_one_shot_2d(stream: AudioStream, pos: Vector2, volume_db: float):
	if !stream:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.max_distance = 900.0
	p.attenuation = 1.8
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _register_audio_hooks_for_player(player: Node):
	if !player or !is_instance_valid(player):
		return
	if player.has_signal("attack_started"):
		var attack_cb = Callable(self, "_on_player_attack_started").bind(player)
		if !player.is_connected("attack_started", attack_cb):
			player.connect("attack_started", attack_cb)
	if player.has_signal("damage_taken"):
		var damage_cb = Callable(self, "_on_player_damage_taken").bind(player)
		if !player.is_connected("damage_taken", damage_cb):
			player.connect("damage_taken", damage_cb)
	if player.has_signal("idle_clock_active_changed"):
		var idle_cb = Callable(self, "_on_player_idle_clock_active_changed")
		if !player.is_connected("idle_clock_active_changed", idle_cb):
			player.connect("idle_clock_active_changed", idle_cb)

func _on_player_attack_started(is_controllable_attack: bool, source_player: Node2D):
	if !is_instance_valid(source_player):
		return
	var vol = player_attack_volume_db if is_controllable_attack else friendly_attack_volume_db
	_play_one_shot_2d(_player_sword_stream, source_player.global_position, vol)

func _on_player_damage_taken(amount, is_controllable_target: bool, source_player: Node2D):
	if !is_controllable_target:
		return
	if !is_instance_valid(source_player):
		return
	_play_one_shot_2d(_enemy_hits_stream, source_player.global_position, player_hit_volume_db)

func _on_player_idle_clock_active_changed(active: bool):
	_clock_should_play = active

# =====================================================================
# ASSET LOADING
# =====================================================================
func _setup_assets():
	var tiles_dir = "res://assets/art/tiles/"
	var tile_paths = _list_pngs(tiles_dir, "fields_tile_")
	tile_paths.sort()
	# TileSources created in _setup_tilemap
	
	var obj_base = "res://assets/art/objects/"
	tree_textures = _load_textures_from(obj_base + "decor", ["tree"])
	bush_textures = _load_textures_from(obj_base + "bush")
	stone_textures = _load_textures_from(obj_base + "stone")
	
	var obj_cats = _list_subdirs(obj_base)
	for cat in obj_cats:
		if cat in ["camp", "bush", "stone", "decor"]: continue
		var texs = _load_textures_from(obj_base + cat)
		decor_textures.append_array(texs)
	
	var all_decor = _load_textures_from(obj_base + "decor")
	for t in all_decor:
		if !t.resource_path.get_file().begins_with("tree"):
			decor_textures.append(t)

	var anim_base = "res://assets/art/animated_objects/"
	var anim_cats = _list_subdirs(anim_base)
	for cat in anim_cats:
		if cat == "campfire": continue
		var sheets = _list_pngs(anim_base + cat + "/")
		for s in sheets:
			var tex = load(s)
			if tex: anim_env_sheets.append(tex)

func _load_textures_from(path: String, filter_includes = []) -> Array:
	var arr = []
	var list = _list_pngs(path + "/")
	for p in list:
		if filter_includes.size() > 0:
			var is_match = false
			for f in filter_includes:
				if p.get_file().contains(f): is_match = true
			if !is_match: continue
		var t = load(p)
		if t: arr.append(t)
	return arr

# =====================================================================
# TILEMAP
# =====================================================================
func _setup_tilemap():
	var tile_map = TileMap.new()
	tile_map.name = "BackgroundTileMap"
	add_child(tile_map)
	move_child(tile_map, 0)
	
	var tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(TILE_PX, TILE_PX)
	tile_map.tile_set = tile_set
	
	var tiles_dir = "res://assets/art/tiles/"
	var paths = _list_pngs(tiles_dir, "fields_tile_")
	paths.sort()
	
	for i in range(paths.size()):
		var tex = load(paths[i])
		if tex:
			var source = TileSetAtlasSource.new()
			source.texture = tex
			source.texture_region_size = Vector2i(TILE_PX, TILE_PX)
			source.create_tile(Vector2i(0, 0))
			tile_set.add_source(source, i)
			tile_source_ids.append(i)

# =====================================================================
# CHUNK GENERATION (Infinite)
# =====================================================================
func _update_chunks():
	var center = Vector2.ZERO
	if is_instance_valid(player_ref):
		center = player_ref.position
	
	var cx = floor(center.x / CHUNK_PX)
	var cy = floor(center.y / CHUNK_PX)
	
	for x in range(cx - 1, cx + 2):
		for y in range(cy - 1, cy + 2):
			var key = Vector2i(x, y)
			if !generated_chunks.has(key):
				_generate_chunk(key)
				generated_chunks[key] = true

func _generate_chunk(chunk_coords: Vector2i):
	var tile_map = $BackgroundTileMap
	var container = $WorldContainer
	
	# 1. Fill Tiles
	var start_tx = chunk_coords.x * CHUNK_SIZE
	var start_ty = chunk_coords.y * CHUNK_SIZE
	
	for lx in range(CHUNK_SIZE):
		for ly in range(CHUNK_SIZE):
			var tx = start_tx + lx
			var ty = start_ty + ly
			var seed_val = (tx * 73856093) ^ (ty * 19349663)
			var idx = abs(seed_val % tile_source_ids.size())
			tile_map.set_cell(0, Vector2i(tx, ty), tile_source_ids[idx], Vector2i(0, 0))
	
	# 2. Objects
	var rng = RandomNumberGenerator.new()
	rng.seed = (chunk_coords.x * 10000) + chunk_coords.y
	
	# A. Trees
	var tree_count = rng.randi_range(3, 8)
	for i in range(tree_count):
		if tree_textures.size() > 0:
			var tex = tree_textures[rng.randi() % tree_textures.size()]
			_spawn_sprite(container, tex, _rand_pos_in_chunk(chunk_coords, rng))
			
	# B. Bushes
	var bush_clusters = rng.randi_range(2, 5)
	for i in range(bush_clusters):
		if bush_textures.size() > 0:
			var center = _rand_pos_in_chunk(chunk_coords, rng)
			var count = rng.randi_range(3, 5)
			for j in range(count):
				var tex = bush_textures[rng.randi() % bush_textures.size()]
				var pos = center + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
				_spawn_sprite(container, tex, pos)
	
	# C. Stones
	var stone_count = rng.randi_range(2, 6)
	for i in range(stone_count):
		if stone_textures.size() > 0:
			var tex = stone_textures[rng.randi() % stone_textures.size()]
			_spawn_sprite(container, tex, _rand_pos_in_chunk(chunk_coords, rng))

	# D. Decor
	var misc_count = rng.randi_range(1, 4)
	for i in range(misc_count):
		if decor_textures.size() > 0:
			var tex = decor_textures[rng.randi() % decor_textures.size()]
			_spawn_sprite(container, tex, _rand_pos_in_chunk(chunk_coords, rng))
			
	# E. Animated
	var anim_count = rng.randi_range(0, 2)
	for i in range(anim_count):
		if anim_env_sheets.size() > 0:
			var sheet = anim_env_sheets[rng.randi() % anim_env_sheets.size()]
			_spawn_anim(container, sheet, _rand_pos_in_chunk(chunk_coords, rng))

	# F. Opps (Clusters) - 30% chance
	if rng.randf() < 0.3:
		var opps = [Opp1Scene, Opp2Scene, Opp3Scene]
		var scn = opps[rng.randi() % opps.size()]
		var pos = _rand_pos_in_chunk(chunk_coords, rng)
		_spawn_opp_cluster(scn, pos, next_group_id)
		next_group_id += 1
		
	# G. Friendly Players (Clusters) - 20% chance
	if rng.randf() < 0.2:
		var friends = [Player2Scene, Player3Scene]
		var scn = friends[rng.randi() % friends.size()]
		var pos = _rand_pos_in_chunk(chunk_coords, rng)
		_spawn_friendly_cluster(scn, pos)

func _spawn_sprite(parent, texture, pos, add_collision: bool = false):
	if add_collision:
		var sb = StaticBody2D.new()
		sb.position = pos
		
		var s = Sprite2D.new()
		s.texture = texture
		s.offset = Vector2(0, -texture.get_height() / 2.0) # Offset for Y-sort pivot at feet
		sb.add_child(s)
		
		var col = CollisionShape2D.new()
		var cap = CapsuleShape2D.new()
		cap.radius = 10
		cap.height = 20
		col.shape = cap
		col.position = Vector2(0, -5) # Small collider at base
		col.rotation_degrees = 90
		sb.add_child(col)
		
		parent.add_child(sb)
	else:
		var s = Sprite2D.new()
		s.texture = texture
		s.position = pos
		s.offset = Vector2(0, -texture.get_height() / 2.0) # Pivot at bottom for Y-sort
		parent.add_child(s)

func _spawn_anim(parent, sheet, pos):
	var sw = sheet.get_width()
	var sh = sheet.get_height()
	var nf = sw / 32
	if nf <= 0: return
	var sf = SpriteFrames.new()
	sf.set_animation_loop("default", true)
	sf.set_animation_speed("default", ENV_ANIM_FPS)
	for fi in range(nf):
		var at = AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(fi * 32, 0, 32, sh)
		sf.add_frame("default", at)
	var asp = AnimatedSprite2D.new()
	asp.sprite_frames = sf
	asp.play("default")
	asp.play("default")
	asp.frame = randi() % nf
	asp.position = pos
	asp.offset = Vector2(0, -sh / 2.0) # Pivot at bottom
	parent.add_child(asp)

func _rand_pos_in_chunk(coords: Vector2i, rng: RandomNumberGenerator) -> Vector2:
	var min_x = coords.x * CHUNK_PX
	var min_y = coords.y * CHUNK_PX
	return Vector2(
		rng.randf_range(min_x, min_x + CHUNK_PX),
		rng.randf_range(min_y, min_y + CHUNK_PX)
	)

# =====================================================================
# ENTITIES & CLUSTERS
# =====================================================================
func _place_fixed_entities():
	# Player 1
	var p1 = Player1Scene.instantiate()
	p1.position = Vector2.ZERO
	p1.is_controllable = true
	$WorldContainer.add_child(p1)
	_register_audio_hooks_for_player(p1)
	player_ref = p1
	
	var cam = $Camera2D
	if cam:
		cam.reparent(p1)
		cam.position = Vector2.ZERO
		
	# Opps (Fixed)
	_spawn_opp_cluster(Opp1Scene, Vector2(500, 300), next_group_id)
	next_group_id += 1
	_spawn_opp_cluster(Opp2Scene, Vector2(0, -400), next_group_id)
	next_group_id += 1
	_spawn_opp_cluster(Opp3Scene, Vector2(-500, 300), next_group_id)
	next_group_id += 1

func _spawn_opp_cluster(scene, center_pos, gid: int):
	var offsets = [Vector2(0,0), Vector2(60, 40), Vector2(-60, 40)]
	for off in offsets:
		var opp = scene.instantiate()
		opp.position = center_pos + off
		opp.group_id = gid
		$WorldContainer.add_child(opp)

func _spawn_friendly_cluster(scene, center_pos):
	var offsets = [Vector2(0,0), Vector2(50, 0), Vector2(-50, 0)]
	for off in offsets:
		var p = scene.instantiate()
		p.position = center_pos + off
		p.is_controllable = false # Force passive
		$WorldContainer.add_child(p)
		_register_audio_hooks_for_player(p)

# =====================================================================
# TRAIL TRANSFORMATION
# =====================================================================

func _process_trail_transformation():
	if !is_instance_valid(player_ref): return
	if transform_cooldown > 0: return # Rate limit
	
	var target_proximity_px = trail_spawn_target_proximity_meters * PIXELS_PER_METER
	var max_player_distance_px = trail_spawn_min_distance_from_player_meters * PIXELS_PER_METER
	var points = player_ref.trail_points
	var point_spawn_times: Array[float] = player_ref.trail_point_spawn_times
	var trail_lifetime_sec: float = player_ref.trail_fade_lifetime_seconds
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	var transformed_indices = []
	var current_pos = player_ref.global_position

	# The current player position should also count as a valid trail/spawn point.
	if player_ref.global_position.distance_to(current_pos) <= max_player_distance_px:
		var current_enemy = _get_nearest_in_group(current_pos, "enemy")
		if current_enemy and current_pos.distance_to(current_enemy.global_position) < target_proximity_px:
			_spawn_transformed_entity(current_pos, "enemy", current_enemy)
			return
		var current_friend = _get_nearest_in_group(current_pos, "friendly_npc")
		if current_friend and current_pos.distance_to(current_friend.global_position) < target_proximity_px:
			_spawn_transformed_entity(current_pos, "friendly", current_friend)
			return

	if player_ref.trail_points.is_empty(): return
	
	for i in range(points.size()):
		var pos = points[i]
		if i >= point_spawn_times.size():
			continue
		if now_sec - point_spawn_times[i] > trail_lifetime_sec:
			continue
		
		# Only allow trail points that are within the player-distance gate (e.g. <= 1m).
		if player_ref.global_position.distance_to(pos) > max_player_distance_px:
			continue
		
		# Proximity to enemies
		var nearest_enemy = _get_nearest_in_group(pos, "enemy")
		if nearest_enemy and pos.distance_to(nearest_enemy.global_position) < target_proximity_px:
			_spawn_transformed_entity(pos, "enemy", nearest_enemy)
			transformed_indices.append(i)
			break # ONLY ALLOW ONE SPAWN PER COOLODWN
			
		# Proximity to friendly players
		var nearest_friend = _get_nearest_in_group(pos, "friendly_npc")
		if nearest_friend and pos.distance_to(nearest_friend.global_position) < target_proximity_px:
			_spawn_transformed_entity(pos, "friendly", nearest_friend)
			transformed_indices.append(i)
			break # ONLY ALLOW ONE SPAWN PER COOLODWN

	# Remove transformed points (backwards to keep indices valid)
	transformed_indices.sort()
	transformed_indices.reverse()
	for idx in transformed_indices:
		player_ref.trail_points.remove_at(idx)
		if idx < player_ref.trail_point_spawn_times.size():
			player_ref.trail_point_spawn_times.remove_at(idx)

func _call_for_help():
	if !is_instance_valid(player_ref):
		return

	var attackers = _get_attackers_chasing_player()
	if attackers.is_empty():
		return

	var min_friend_dist_px = help_call_min_friendly_distance_meters * PIXELS_PER_METER
	var cluster_radius_px = help_call_cluster_radius_meters * PIXELS_PER_METER
	var friendlies: Array = get_tree().get_nodes_in_group("friendly_npc")
	friendlies.sort_custom(func(a, b): return player_ref.global_position.distance_to(a.global_position) < player_ref.global_position.distance_to(b.global_position))

	var eligible_friendlies: Array = []
	for friendly in friendlies:
		if !is_instance_valid(friendly) or friendly.is_queued_for_deletion():
			continue
		if player_ref.global_position.distance_to(friendly.global_position) < min_friend_dist_px:
			continue
		if !friendly.has_method("set_assist_target"):
			continue
		eligible_friendlies.append(friendly)

	if eligible_friendlies.is_empty():
		return

	var anchor_friendly: Node2D = _get_nearest_node_from_list(player_ref.global_position, eligible_friendlies)
	if !anchor_friendly:
		return

	for friendly in eligible_friendlies:
		if friendly.global_position.distance_to(anchor_friendly.global_position) > cluster_radius_px:
			continue

		var nearest_attacker = _get_nearest_node_from_list(friendly.global_position, attackers)
		if nearest_attacker:
			friendly.set_assist_target(nearest_attacker)

func _get_attackers_chasing_player() -> Array:
	var attackers: Array = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if !is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.get("target_body") == player_ref:
			attackers.append(enemy)
	return attackers

func _get_nearest_node_from_list(pos: Vector2, nodes: Array) -> Node2D:
	var nearest: Node2D = null
	var min_dist = 999999.0
	for n in nodes:
		if !is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var d = pos.distance_to(n.global_position)
		if d < min_dist:
			min_dist = d
			nearest = n
	return nearest

func _get_nearest_in_group(pos: Vector2, group_name: String) -> Node2D:
	var nodes = get_tree().get_nodes_in_group(group_name)
	var nearest = null
	var min_dist = 999999.0
	for n in nodes:
		if n.is_queued_for_deletion(): continue
		var d = pos.distance_to(n.global_position)
		if d < min_dist:
			min_dist = d
			nearest = n
	return nearest

func _spawn_transformed_entity(pos: Vector2, type: String, template: Node2D):
	var container = $WorldContainer
	if type == "enemy":
		var opps = [Opp1Scene, Opp2Scene, Opp3Scene]
		# Find the scene that matches the template's folder if possible
		var scn = opps[randi() % opps.size()]
		if template.has_method("get") and template.get("opp_folder"):
			for s in opps:
				var inst = s.instantiate()
				if inst.opp_folder == template.opp_folder:
					scn = s
					inst.queue_free()
					break
				inst.queue_free()
		
		var new_opp = scn.instantiate()
		new_opp.position = pos
		if "group_id" in template:
			new_opp.group_id = template.group_id
		container.add_child(new_opp)
		if new_opp.has_method("spawn_effect"):
			new_opp.spawn_effect()
		if new_opp.has_method("join_group_behavior"):
			new_opp.join_group_behavior(template.global_position)
		
		transform_cooldown = TRANSFORM_COOLDOWN_MAX
			
	elif type == "friendly":
		var templates = [Player2Scene, Player3Scene]
		var scn = templates[randi() % templates.size()]
		# Match template if possible
		if template.has_method("get") and template.get("player_folder"):
			for s in templates:
				var inst = s.instantiate()
				if inst.player_folder == template.player_folder:
					scn = s
					inst.queue_free()
					break
				inst.queue_free()
				
		var new_friend = scn.instantiate()
		new_friend.position = pos
		new_friend.is_controllable = false
		container.add_child(new_friend)
		_register_audio_hooks_for_player(new_friend)
		if new_friend.has_method("join_group_behavior"):
			new_friend.join_group_behavior(template.global_position)
		if new_friend.has_method("spawn_effect"):
			new_friend.spawn_effect()
		
		transform_cooldown = TRANSFORM_COOLDOWN_MAX

# =====================================================================
# HELPERS
# =====================================================================
func _list_pngs(dir_path: String, prefix: String = "") -> Array[String]:
	var result: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if dir == null: return result
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if !dir.current_is_dir():
			var file_name = f
			if file_name.ends_with(".import"):
				file_name = file_name.replace(".import", "")
			if file_name.ends_with(".remap"):
				file_name = file_name.replace(".remap", "")
				
			if file_name.ends_with(".png"):
				if prefix == "" or file_name.begins_with(prefix):
					if not (dir_path + file_name) in result:
						result.append(dir_path + file_name)
		f = dir.get_next()
	return result

func _list_subdirs(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if dir == null: return result
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if dir.current_is_dir() and !f.begins_with("."):
			result.append(f)
		f = dir.get_next()
	return result
