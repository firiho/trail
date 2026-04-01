extends Node2D

static var _auto_start_after_reload: bool = false
static var _persisted_level: int = 1
static var _persisted_score: int = 0
static var _persisted_enemies_killed: int = 0
static var _persisted_coins: int = 0
static var _persisted_apples: int = 0
static var _persisted_damage: int = 0
static var _persisted_max_combo: int = 0
static var _persisted_play_start_time: float = -1.0
static var _max_unlocked_level: int = 1
static var _go_to_level_select_after_reload: bool = false
static var _has_persisted_run_stats: bool = false

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
@export var transformed_spawn_distance_from_player_meters: float = 1.0
@export var transformed_spawn_jitter_meters: float = 0.35

@export_group("Level Layout")
@export var use_structured_level_layout: bool = true
@export var current_level_id: int = 1
@export var level_disable_random_chunk_entity_spawns: bool = false
@export var level1_disable_chunk_ambient_objects: bool = false

@export_group("Level 1 Path")
@export var level1_path_origin: Vector2 = Vector2.ZERO
@export var level1_path_direction: Vector2 = Vector2(1.0, -1.0)
@export var level1_path_length_meters: float = 200.0
@export var level1_path_vertical_progress_ratio: float = 0.36
@export var level1_path_rows: int = 2
@export var level1_path_row_spacing_meters: float = 0.75
@export var level1_path_brick_spacing_meters: float = 0.8
@export var level1_path_brick_scale: float = 0.028
@export var level1_path_clear_half_width_meters: float = 0.95
@export var level1_goal_forward_offset_meters: float = 3.0
@export var level1_goal_scale: float = 2.0
@export var level1_path_layer_z_index: int = -20
@export var level1_path_uniform_mode: bool = true
@export var level1_path_lane_stagger_meters: float = 0.0
@export var level1_path_turn_count: int = 4
@export var level1_path_turn_depth_meters: float = 2.5
@export var level1_path_turn_depth_jitter_meters: float = 0.0
@export var level1_path_tile_snap_enabled: bool = true
@export var level1_path_curve_segment_count: int = 26
@export var level1_path_curve_wave_count: float = 1.85
@export var level1_path_curve_amplitude_meters: float = 6.5
@export var level1_path_curve_jitter_meters: float = 1.0
@export var level1_goal_trigger_radius_meters: float = 1.9
@export var level1_goal_bush_cluster_count: int = 40
@export var level1_goal_bush_cluster_radius_meters: float = 2.0
@export var level1_goal_bush_scale_min: float = 1.35
@export var level1_goal_bush_scale_max: float = 2.05
@export var level1_goal_drop_offset: Vector2 = Vector2(0.0, -6.0)
@export var level1_goal_drop_duration_seconds: float = 0.65
@export var level1_goal_drop_scale: float = 1.0

@export_group("Level 1 Path Decor")
@export var level1_path_grass_enabled: bool = false
@export var level1_path_grass_spacing_meters: float = 1.6
@export var level1_path_grass_edge_offset_meters: float = 1.8
@export var level1_path_grass_edge_jitter_meters: float = 0.5
@export var level1_path_grass_scale_min: float = 0.55
@export var level1_path_grass_scale_max: float = 0.9
@export var level1_path_grass_skip_chance: float = 0.18

@export_group("Level 1 Path Border")
@export var level1_path_border_enabled: bool = false
@export var level1_path_border_spacing_meters: float = 0.85
@export var level1_path_border_edge_offset_meters: float = 0.7
@export var level1_path_border_scale: float = 0.28
@export var level1_path_border_z_offset: int = 2

@export_group("Level 1 Objective")
@export var level1_objective_attach_enabled: bool = true
@export var level1_objective_attach_offset: Vector2 = Vector2(-44.0, -92.0)
@export var level1_objective_scale: float = 2.0
@export var level1_objective_anim_fps: float = 8.0
@export var level1_objective_z_index: int = 40
@export var level1_objective_initial_face_left: bool = true
@export var level1_objective_follow_player_turn: bool = true
@export var level1_objective_invert_turn_with_player: bool = true
@export var level1_objective_float_amplitude_px: float = 6.0
@export var level1_objective_float_speed: float = 2.4

@export_group("Level 1 Enemy Layout")
@export var level1_enemy_cluster_count: int = 25
@export var level1_enemy_spawn_start_meter: float = 8.0
@export var level1_enemy_spawn_end_meter: float = 200.0
@export var level1_enemy_density_curve_power: float = 0.55
@export var level1_enemy_random_side_range_meters: float = 12.0
@export var level1_enemy_off_path_min_side_meters: float = 1.5
@export var level1_enemy_on_path_chance: float = 0.25
@export var level1_enemy_on_path_side_jitter_meters: float = 1.5
@export var level1_enemy_along_jitter_meters: float = 5.0
@export var level1_friendly_cluster_count: int = 8
@export var level1_friendly_spawn_start_meter: float = 5.0
@export var level1_friendly_spawn_end_meter: float = 200.0
@export var level1_friendly_side_offset_meters: float = 1.2
@export var level1_friendly_random_side_range_meters: float = 12.0
@export var level1_friendly_off_path_min_side_meters: float = 2.0

@export_group("Level 1 Goal Border")
@export var level1_goal_border_enabled: bool = true
@export var level1_goal_border_radius_meters: float = 2.9
@export var level1_goal_border_collision_radius_meters: float = 2.8

@export_group("Level 1 Floating Text")
@export var level1_float_text_enabled: bool = true
@export var level1_float_text_top_px: float = 76.0
@export var level1_float_text_rise_px: float = 24.0
@export var level1_float_text_font_size: int = 14
@export var level1_float_text_duration_seconds: float = 2.8
@export var level1_float_text_panel_width_px: float = 560.0
@export var level1_goal_warning_distance_meters: float = 3.8
@export var level1_help_hint_cooldown_seconds: float = 4.0
@export var level1_help_recent_window_seconds: float = 8.0
@export var level1_arrrgg_cooldown_seconds: float = 1.1

@export_group("Pickups")
@export var level1_coin_count: int = 15
@export var level1_apple_count: int = 5
@export var level1_coin_spawn_start_meter: float = 5.0
@export var level1_coin_spawn_end_meter: float = 195.0
@export var level1_apple_spawn_start_meter: float = 20.0
@export var level1_apple_spawn_end_meter: float = 180.0
@export var level1_pickup_side_range_meters: float = 1.5
@export var pickup_collect_radius_meters: float = 1.2
@export var coin_score_value: int = 50
@export var apple_heal_amount: int = 25

@export_group("Stealth Hiding")
@export var level1_hide_bush_count: int = 5
@export var level1_hide_bush_spawn_start_meter: float = 16.0
@export var level1_hide_bush_spawn_end_meter: float = 170.0
@export var level1_hide_bush_min_spacing_meters: float = 28.0
@export var level1_hide_bush_min_side_offset_meters: float = 1.6
@export var level1_hide_bush_max_side_offset_meters: float = 3.9
@export var level1_hide_bush_along_jitter_meters: float = 5.0
@export var level1_hide_bush_scale_min: float = 3.0
@export var level1_hide_bush_scale_max: float = 4.2
@export var level1_hide_bush_hide_radius_meters: float = 1.45
@export var level1_hide_tree_diamond_half_width_meters: float = 1.15
@export var level1_hide_tree_diamond_half_height_meters: float = 0.78
@export var hide_bush_enemy_forget_delay_seconds: float = 3.0
@export var hide_bush_enemy_disengage_distance_meters: float = 6.0

@export_group("Score")
@export var kill_base_score: int = 100
@export var combo_time_window: float = 3.0
@export var combo_multiplier_max: int = 8

@export_group("Screen Shake")
@export var shake_damage_intensity: float = 4.0
@export var shake_damage_duration: float = 0.2
@export var shake_kill_intensity: float = 6.0
@export var shake_kill_duration: float = 0.3
@export var kill_slowmo_scale: float = 0.15
@export var kill_slowmo_duration: float = 0.2

var transform_cooldown: float = 0.0
const TRANSFORM_COOLDOWN_MAX = 3.0

enum { START, PLAYING, DELIVERING, GAMEOVER, WIN, LEVEL_SELECT }
var game_state = START
var ui = null

const DB_SILENT = -80.0

@export_group("Audio")
@export var menu_music_volume_db: float = -10.0
@export var soundtrack_volume_db: float = -12.0
@export var soundtrack_near_enemy_volume_db: float = -20.0
@export var wrong_place_volume_db: float = -12.0
@export var clock_volume_db: float = -12.0
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
var _path_fill_texture = preload("res://assets/art/objects/green grass.png")
var _path_outline_texture = preload("res://assets/art/objects/dirt.png")
var _path_goal_texture = preload("res://assets/art/objects/camp/2.png")
var _ui_font = preload("res://assets/fonts/PressStart2P-Regular.ttf")

var _danger_music_mix: float = 0.0
var _clock_should_play: bool = false
var _level_path_end_world: Vector2 = Vector2.ZERO
var _level_path_points: Array[Vector2] = []
var _level_path_lengths: Array[float] = []
var _level_path_total_length_px: float = 0.0
var _level_goal_node: Node2D = null
var _level_goal_border_collision: CollisionShape2D = null
var _level_goal_warning_phase: float = 0.0
var _level_goal_blink_targets: Array[CanvasItem] = []
var _level_goal_completed: bool = false
var _level_goal_drop_in_progress: bool = false
var _objective_payload: AnimatedSprite2D = null
var _objective_payload_owner: Node2D = null
var _objective_last_owner_flip_set: bool = false
var _objective_last_owner_flip_h: bool = false
var _objective_float_time: float = 0.0
var _floating_text_layer: CanvasLayer = null
var _floating_warning_panel: Panel = null
var _floating_warning_label: Label = null
var _last_help_call_time: float = -9999.0
var _last_help_hint_time: float = -9999.0
var _last_arrrgg_time: float = -9999.0
var _player_hide_overlap_count: int = 0
var _player_hidden_time_sec: float = 0.0
var _hide_escape_triggered: bool = false

# Score & Combo
var _score: int = 0
var _combo_count: int = 0
var _combo_timer: float = 0.0

# Screen Shake
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _cam_ref: Camera2D = null

# Slowmo
var _slowmo_timer: float = 0.0

# Pickup textures
var _apple_texture: Texture2D = null
var _coin_frames: Array = []

# Stats tracking
var _enemies_killed: int = 0
var _max_combo: int = 0
var _damage_taken_total: int = 0
var _coins_collected: int = 0
var _apples_collected: int = 0
var _play_start_time: float = 0.0

# Compass
var _compass_layer: CanvasLayer = null
var _compass_arrow: Control = null
var _compass_label: Label = null

# Asset References
var tile_source_ids: Array[int] = []
var tree_textures: Array = []
var bush_textures: Array = []
var stone_textures: Array = []
var decor_textures: Array = [] 
var anim_env_sheets: Array = [] 
var path_grass_textures: Array = []

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
	
	# Apply level progression from persisted state
	if _persisted_level > 1:
		current_level_id = _persisted_level
		# Each level adds 100m distance
		level1_path_length_meters = 200.0 + (_persisted_level - 1) * 100.0
		# Random direction for the bush each level
		var rng = RandomNumberGenerator.new()
		rng.seed = int(WORLD_SEED + _persisted_level * 997)
		var angle = rng.randf_range(0.0, TAU)
		level1_path_direction = Vector2(cos(angle), sin(angle))
		# More enemies at higher levels
		level1_enemy_cluster_count = 25 + (_persisted_level - 1) * 5
	
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
			if player_ref.has_signal("enemy_killed"):
				player_ref.enemy_killed.connect(_on_player_enemy_killed)
			# Init health
			ui.update_health(player_ref.health, 100)
		if player_ref and player_ref.has_signal("idle_timer_changed"):
			pass # Idle timer disabled — no connection needed
		
		# Connect level select / button signals
		if ui.has_signal("level_selected"):
			ui.level_selected.connect(_on_ui_level_selected)
		if ui.has_signal("retry_pressed"):
			ui.retry_pressed.connect(_on_ui_retry)
		if ui.has_signal("next_level_pressed"):
			ui.next_level_pressed.connect(_on_ui_next_level)
		if ui.has_signal("back_to_levels_pressed"):
			ui.back_to_levels_pressed.connect(_on_ui_back_to_levels)
		
		# Start State
		game_state = START
		if _auto_start_after_reload:
			_auto_start_after_reload = false
			ui.show_hud()
			if player_ref and player_ref.has_method("set_input_enabled"):
				player_ref.set_input_enabled(true)
			game_state = PLAYING
			# Show level banner
			if ui.has_method("show_level_banner"):
				ui.show_level_banner(current_level_id)
			if _is_level_one_layout_active():
				if current_level_id == 1:
					_show_floating_text("Zzzzzzz, take me to my bush", Color(0.9, 1.0, 0.9, 1.0))
				else:
					_show_floating_text("Level %d — Bush is %dm away!" % [current_level_id, int(level1_path_length_meters)], Color(0.7, 1.0, 0.85, 1.0))
		elif _go_to_level_select_after_reload:
			_go_to_level_select_after_reload = false
			_show_level_select()
		else:
			ui.show_start_screen()
		
	if game_state != PLAYING and player_ref and player_ref.has_method("set_input_enabled"):
		player_ref.set_input_enabled(false)
	_clock_should_play = false
	_refresh_audio_state(true)

func _input(event):
	if event.is_action_pressed("attack"):
		if game_state == START:
			_show_level_select()
	if event.is_action_pressed("help") and game_state == PLAYING:
		_last_help_call_time = _now_seconds()
		_call_for_help()

func start_game():
	if !ui: return
	game_state = PLAYING
	_play_start_time = _now_seconds() if _persisted_play_start_time < 0 else _persisted_play_start_time
	if _persisted_play_start_time >= 0:
		_persisted_play_start_time = -1.0
	_play_ui_start_sfx()
	ui.show_hud()
	# Restore carried run stats when advancing to the next level.
	if _has_persisted_run_stats:
		_score = _persisted_score
		_enemies_killed = _persisted_enemies_killed
		_coins_collected = _persisted_coins
		_apples_collected = _persisted_apples
		_damage_taken_total = _persisted_damage
		_max_combo = _persisted_max_combo
		if ui and ui.has_method("update_score"):
			ui.update_score(_score)
	if player_ref and player_ref.has_method("set_input_enabled"):
		player_ref.set_input_enabled(true)
	# Show level banner
	if ui.has_method("show_level_banner"):
		ui.show_level_banner(current_level_id)
	if _is_level_one_layout_active():
		if current_level_id == 1:
			_show_floating_text("Zzzzzzz, take me to my bush", Color(0.9, 1.0, 0.9, 1.0))
		else:
			_show_floating_text("Level %d — Find the bush! (%dm away)" % [current_level_id, int(level1_path_length_meters)], Color(0.7, 1.0, 0.85, 1.0))
	_refresh_audio_state()

func restart_game():
	# Called when going back to level select from game over — reset stats
	Engine.time_scale = 1.0
	_persisted_level = 1
	_persisted_score = 0
	_persisted_enemies_killed = 0
	_persisted_coins = 0
	_persisted_apples = 0
	_persisted_damage = 0
	_persisted_max_combo = 0
	_persisted_play_start_time = -1.0
	_has_persisted_run_stats = false
	_go_to_level_select_after_reload = true
	_auto_start_after_reload = false
	get_tree().reload_current_scene()

func _on_player_died():
	if game_state == DELIVERING or game_state == WIN:
		return
	game_state = GAMEOVER
	Engine.time_scale = 1.0
	_clock_should_play = false
	_play_game_over_sfx()
	_refresh_audio_state()
	if ui:
		var stats = _build_stats_dict()
		ui.show_game_over_with_stats(stats)

func _process(delta):
	if is_instance_valid(player_ref):
		_update_chunks()
		_process_trail_transformation()
		_collect_nearby_pickups()
		_update_player_hiding(delta)
		_update_objective_payload(delta)
		_update_context_help_hint()
		_update_level_goal_shield_state(delta)
		_check_level_one_goal_reached()
		_update_compass()
		
		# Update UI with proximity to nearest group
		var nearest_enemy = _get_nearest_in_group(player_ref.global_position, "enemy")
		var nearest_friend = _get_nearest_in_group(player_ref.global_position, "friendly_npc")
		var attackers = _get_attackers_chasing_player()
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
		if ui and ui.has_method("update_wanted_level"):
			ui.update_wanted_level(_get_wanted_star_level(attackers.size()), attackers.size())
		_update_dynamic_music_blend(delta, enemy_dist_m)
	else:
		if ui and ui.has_method("update_wanted_level"):
			ui.update_wanted_level(0, 0)
		_update_dynamic_music_blend(delta, -1.0)

	if transform_cooldown > 0:
		transform_cooldown -= delta

	_update_clock_audio(delta)
	_refresh_audio_state()
	_update_combo_timer(delta)
	_update_screen_shake(delta)
	_update_slowmo(delta)
	_update_progress_bar()

func _advance_to_next_level():
	# Persist stats across levels
	_persisted_score = _score
	_persisted_enemies_killed = _enemies_killed
	_persisted_coins = _coins_collected
	_persisted_apples = _apples_collected
	_persisted_damage = _damage_taken_total
	_persisted_max_combo = _max_combo
	_persisted_play_start_time = _play_start_time
	_persisted_level = current_level_id + 1
	_has_persisted_run_stats = true
	
	# Reload the scene to start next level
	_do_next_level_reload()

func _do_next_level_reload():
	Engine.time_scale = 1.0
	_auto_start_after_reload = true
	get_tree().reload_current_scene()

# =====================================================================
# LEVEL SELECT / NAVIGATION HANDLERS
# =====================================================================

func _show_level_select():
	game_state = LEVEL_SELECT
	_clock_should_play = false
	_refresh_audio_state()
	if ui and ui.has_method("show_level_select"):
		ui.show_level_select(_max_unlocked_level, 10)

func _on_ui_level_selected(level_id: int):
	# Start the selected level via scene reload
	Engine.time_scale = 1.0
	_persisted_level = level_id
	_persisted_score = 0
	_persisted_enemies_killed = 0
	_persisted_coins = 0
	_persisted_apples = 0
	_persisted_damage = 0
	_persisted_max_combo = 0
	_persisted_play_start_time = -1.0
	_has_persisted_run_stats = false
	_auto_start_after_reload = true
	get_tree().reload_current_scene()

func _on_ui_retry():
	# Retry current level — same level, reset stats
	Engine.time_scale = 1.0
	_persisted_level = current_level_id
	_persisted_score = 0
	_persisted_enemies_killed = 0
	_persisted_coins = 0
	_persisted_apples = 0
	_persisted_damage = 0
	_persisted_max_combo = 0
	_persisted_play_start_time = -1.0
	_has_persisted_run_stats = false
	_auto_start_after_reload = true
	get_tree().reload_current_scene()

func _on_ui_next_level():
	# Go to next level — persist stats and advance
	_advance_to_next_level()

func _on_ui_back_to_levels():
	# Go back to level select
	Engine.time_scale = 1.0
	_persisted_level = 1
	_persisted_score = 0
	_persisted_enemies_killed = 0
	_persisted_coins = 0
	_persisted_apples = 0
	_persisted_damage = 0
	_persisted_max_combo = 0
	_persisted_play_start_time = -1.0
	_has_persisted_run_stats = false
	_go_to_level_select_after_reload = true
	_auto_start_after_reload = false
	get_tree().reload_current_scene()

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
	var in_menu_state = game_state == START or game_state == GAMEOVER or game_state == WIN or game_state == LEVEL_SELECT
	var in_play_state = game_state == PLAYING or game_state == DELIVERING

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

func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0

func _ensure_floating_text_ui():
	if _floating_text_layer and is_instance_valid(_floating_text_layer):
		return

	_floating_text_layer = CanvasLayer.new()
	_floating_text_layer.name = "FloatingTextLayer"
	_floating_text_layer.layer = 20
	add_child(_floating_text_layer)

	_floating_warning_panel = _create_floating_text_panel(level1_float_text_top_px + 44.0)
	_floating_warning_panel.name = "GoalWarningPanel"
	_floating_warning_panel.visible = false
	_floating_text_layer.add_child(_floating_warning_panel)

	_floating_warning_label = Label.new()
	_floating_warning_label.name = "GoalWarningText"
	_floating_warning_label.anchor_left = 0.0
	_floating_warning_label.anchor_right = 1.0
	_floating_warning_label.anchor_top = 0.0
	_floating_warning_label.anchor_bottom = 1.0
	_floating_warning_label.offset_left = 14.0
	_floating_warning_label.offset_right = -14.0
	_floating_warning_label.offset_top = 8.0
	_floating_warning_label.offset_bottom = -8.0
	_floating_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floating_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_floating_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_warning_label.text = "DON'T BRING ENEMIES TO THE BUSH"
	_apply_floating_text_style(_floating_warning_label, Color(1.0, 0.42, 0.42, 0.0))
	_floating_warning_label.visible = false
	_floating_warning_panel.add_child(_floating_warning_label)

func _create_floating_text_panel(top_px: float) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	var half_width = max(120.0, level1_float_text_panel_width_px * 0.5)
	panel.offset_left = -half_width
	panel.offset_right = half_width
	panel.offset_top = top_px
	panel.offset_bottom = top_px + 44.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.65)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.35, 0.45, 0.65, 0.45)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	style.shadow_size = 4
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _apply_floating_text_style(label: Label, color: Color):
	if !label:
		return
	label.add_theme_font_override("font", _ui_font)
	label.add_theme_font_size_override("font_size", level1_float_text_font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_outline_size", 8)

func _show_floating_text(message: String, color: Color = Color(0.95, 0.95, 0.9, 1.0)):
	if !level1_float_text_enabled:
		return
	_ensure_floating_text_ui()
	if !_floating_text_layer or !is_instance_valid(_floating_text_layer):
		return

	var panel = _create_floating_text_panel(level1_float_text_top_px)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_floating_text_layer.add_child(panel)

	var label = Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 1.0
	label.offset_left = 14.0
	label.offset_right = -14.0
	label.offset_top = 8.0
	label.offset_bottom = -8.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = message
	_apply_floating_text_style(label, color)
	panel.add_child(label)

	var total = max(0.65, level1_float_text_duration_seconds)
	var fade_in = min(0.28, total * 0.22)
	var fade_out = min(0.36, total * 0.26)
	var visible_window = max(0.12, total - fade_out)
	var end_top = level1_float_text_top_px - max(2.0, level1_float_text_rise_px)
	var end_bottom = end_top + 44.0
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, fade_in)
	tween.parallel().tween_property(panel, "offset_top", end_top, visible_window)
	tween.parallel().tween_property(panel, "offset_bottom", end_bottom, visible_window)
	tween.tween_property(panel, "modulate:a", 0.0, fade_out)
	tween.finished.connect(panel.queue_free)

func _set_goal_warning_text(visible_state: bool, pulse: float):
	if !level1_float_text_enabled:
		return
	_ensure_floating_text_ui()
	if !_floating_warning_panel or !is_instance_valid(_floating_warning_panel):
		return
	if !_floating_warning_label or !is_instance_valid(_floating_warning_label):
		return

	if !visible_state:
		_floating_warning_panel.visible = false
		_floating_warning_label.visible = false
		return

	_floating_warning_panel.visible = true
	_floating_warning_label.visible = true
	var bob = sin(_level_goal_warning_phase * 0.9) * 6.0
	_floating_warning_panel.offset_top = level1_float_text_top_px + 44.0 + bob
	_floating_warning_panel.offset_bottom = _floating_warning_panel.offset_top + 44.0
	var panel_alpha = 0.72 + 0.18 * pulse
	_floating_warning_panel.modulate = Color(1.0, 1.0, 1.0, panel_alpha)
	_floating_warning_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.32 + 0.2 * pulse, 0.32 + 0.2 * pulse, 0.78 + 0.22 * pulse)
	)

func _update_context_help_hint():
	if game_state != PLAYING:
		return
	if !_is_level_one_layout_active():
		return
	if !is_instance_valid(player_ref):
		return

	var now = _now_seconds()
	var recently_called_help = now - _last_help_call_time <= level1_help_recent_window_seconds
	if _is_player_chased() and !recently_called_help and now - _last_help_hint_time >= level1_help_hint_cooldown_seconds:
		_last_help_hint_time = now
		_show_floating_text("ASK FOR HELP (H)", Color(1.0, 0.88, 0.48, 1.0))

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

	if is_controllable_attack and game_state == PLAYING and _is_level_one_layout_active():
		var now = _now_seconds()
		var recently_called_help = now - _last_help_call_time <= level1_help_recent_window_seconds
		if _is_player_chased() and !recently_called_help and now - _last_help_hint_time >= level1_help_hint_cooldown_seconds:
			_last_help_hint_time = now
			_show_floating_text("ASK FOR HELP (H)", Color(1.0, 0.88, 0.48, 1.0))

func _on_player_damage_taken(amount, is_controllable_target: bool, source_player: Node2D):
	if !is_controllable_target:
		return
	if !is_instance_valid(source_player):
		return
	_play_one_shot_2d(_enemy_hits_stream, source_player.global_position, player_hit_volume_db)
	_trigger_screen_shake(shake_damage_intensity, shake_damage_duration)
	_damage_taken_total += amount

	if game_state == PLAYING and _is_level_one_layout_active():
		var now = _now_seconds()
		if now - _last_arrrgg_time >= level1_arrrgg_cooldown_seconds:
			_last_arrrgg_time = now
			_show_floating_text("ARRRGGG!", Color(1.0, 0.42, 0.42, 1.0))

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
		if cat in ["camp", "bush", "stone", "decor", "coins", "apple"]: continue
		var texs = _load_textures_from(obj_base + cat)
		decor_textures.append_array(texs)
	
	var all_decor = _load_textures_from(obj_base + "decor")
	for t in all_decor:
		var fname = t.resource_path.get_file().to_lower()
		if fname.begins_with("tree"):
			continue
		if fname.begins_with("dirt"):
			continue
		decor_textures.append(t)

	path_grass_textures = _load_textures_from(obj_base + "grass")

	# Pickup assets
	_apple_texture = load("res://assets/art/objects/apple/Apple.png")
	_coin_frames.clear()
	for i in range(1, 7):
		var tex = load("res://assets/art/objects/coins/coin_%02d.png" % i)
		if tex:
			_coin_frames.append(tex)

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
	tile_map.z_index = -100
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

	if _is_level_one_layout_active() and level1_disable_chunk_ambient_objects:
		return
		
	# 2. Objects
	var rng = RandomNumberGenerator.new()
	rng.seed = (chunk_coords.x * 10000) + chunk_coords.y
	
	# A. Trees
	# Disabled: regular world trees removed so only intentional hiding spots use trees.
			
	# B. Bushes (fewer in level 1 so goal bush stays special)
	var bush_clusters = rng.randi_range(0, 2) if _is_level_one_layout_active() else rng.randi_range(2, 5)
	for i in range(bush_clusters):
		if bush_textures.size() > 0:
			var center = _rand_pos_in_chunk(chunk_coords, rng)
			if _is_pos_inside_level_one_path_corridor(center):
				continue
			var count = rng.randi_range(3, 5)
			for j in range(count):
				var tex = bush_textures[rng.randi() % bush_textures.size()]
				var pos = center + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
				if _is_pos_inside_level_one_path_corridor(pos):
					continue
				_spawn_sprite(container, tex, pos)
	
	# C. Stones
	var stone_count = rng.randi_range(2, 6)
	for i in range(stone_count):
		if stone_textures.size() > 0:
			var tex = stone_textures[rng.randi() % stone_textures.size()]
			var stone_pos = _rand_pos_in_chunk(chunk_coords, rng)
			if _is_pos_inside_level_one_path_corridor(stone_pos):
				continue
			_spawn_sprite(container, tex, stone_pos)

	# D. Decor
	var misc_count = rng.randi_range(1, 4)
	for i in range(misc_count):
		if decor_textures.size() > 0:
			var tex = decor_textures[rng.randi() % decor_textures.size()]
			var decor_pos = _rand_pos_in_chunk(chunk_coords, rng)
			if _is_pos_inside_level_one_path_corridor(decor_pos):
				continue
			_spawn_sprite(container, tex, decor_pos)
			
	# E. Animated
	var anim_count = rng.randi_range(0, 2)
	for i in range(anim_count):
		if anim_env_sheets.size() > 0:
			var sheet = anim_env_sheets[rng.randi() % anim_env_sheets.size()]
			var anim_pos = _rand_pos_in_chunk(chunk_coords, rng)
			if _is_pos_inside_level_one_path_corridor(anim_pos):
				continue
			_spawn_anim(container, sheet, anim_pos)

	if !_should_disable_chunk_entity_spawns() and !_is_player_currently_hidden_for_stealth():
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
	p1.position = level1_path_origin if _is_level_one_layout_active() else Vector2.ZERO
	p1.is_controllable = true
	$WorldContainer.add_child(p1)
	_register_audio_hooks_for_player(p1)
	_attach_level_one_objective_to_player(p1)
	player_ref = p1
	
	var cam = $Camera2D
	if cam:
		cam.reparent(p1)
		cam.position = Vector2.ZERO
		_cam_ref = cam

	if _is_level_one_layout_active():
		_build_level_one_path_layout()
		_spawn_level_one_enemy_layout()
		_spawn_level_one_friendly_layout()
		_spawn_level_one_hide_bush_layout()
		_spawn_level_one_pickup_layout()
	else:
		# Opps (Fixed)
		_spawn_opp_cluster(Opp1Scene, Vector2(500, 300), next_group_id)
		next_group_id += 1
		_spawn_opp_cluster(Opp2Scene, Vector2(0, -400), next_group_id)
		next_group_id += 1
		_spawn_opp_cluster(Opp3Scene, Vector2(-500, 300), next_group_id)
		next_group_id += 1

func _is_level_one_layout_active() -> bool:
	return use_structured_level_layout

func _should_disable_chunk_entity_spawns() -> bool:
	return _is_level_one_layout_active() and level_disable_random_chunk_entity_spawns

func _get_level_one_path_direction() -> Vector2:
	if level1_path_direction.length_squared() <= 0.0001:
		return Vector2.RIGHT
	return level1_path_direction.normalized()

func _get_level_one_path_perpendicular() -> Vector2:
	var dir = _get_level_one_path_direction()
	return Vector2(-dir.y, dir.x)

func _is_pos_inside_level_one_path_corridor(pos: Vector2) -> bool:
	if !_is_level_one_layout_active():
		return false

	if _level_path_points.size() < 2:
		_build_level_one_path_points()
	if _level_path_points.size() < 2:
		return false

	var max_dist = _get_level_one_path_reserved_half_width_meters() * PIXELS_PER_METER
	return _distance_to_level_path(pos) <= max_dist

func _get_level_one_path_reserved_half_width_meters() -> float:
	var reserved = level1_path_clear_half_width_meters
	if level1_path_grass_enabled:
		reserved = max(reserved, level1_path_grass_edge_offset_meters + 0.9)
	if level1_path_border_enabled:
		reserved = max(reserved, level1_path_border_edge_offset_meters + 0.8)
	return reserved

func _build_level_one_path_points():
	_level_path_points.clear()
	_level_path_lengths.clear()
	_level_path_total_length_px = 0.0

	var dir = _get_level_one_path_direction()
	var horizontal = Vector2.RIGHT if dir.x >= 0.0 else Vector2.LEFT
	var vertical = Vector2.UP if dir.y <= 0.0 else Vector2.DOWN
	if absf(dir.x) <= 0.0001:
		horizontal = Vector2.RIGHT

	var base_len_px = max(1.0, level1_path_length_meters * PIXELS_PER_METER)
	var turn_count = max(1, level1_path_turn_count)
	var vertical_ratio = clamp(level1_path_vertical_progress_ratio, 0.05, 0.8)
	var horizontal_total_px = base_len_px * (1.0 - vertical_ratio)
	var vertical_total_px = base_len_px - horizontal_total_px
	var horizontal_step_px = _snap_level_path_distance(horizontal_total_px / float(turn_count + 1))
	var vertical_step_px = _snap_level_path_distance(vertical_total_px / float(turn_count))

	var cursor = _snap_level_path_point(level1_path_origin)
	_append_level_one_path_point(cursor)

	for i in range(turn_count):
		cursor = _snap_level_path_point(cursor + horizontal * horizontal_step_px)
		_append_level_one_path_point(cursor)

		cursor = _snap_level_path_point(cursor + vertical * vertical_step_px)
		_append_level_one_path_point(cursor)

	cursor = _snap_level_path_point(cursor + horizontal * horizontal_step_px)
	_append_level_one_path_point(cursor)

	_level_path_lengths.append(0.0)
	var running = 0.0
	for i in range(1, _level_path_points.size()):
		running += _level_path_points[i - 1].distance_to(_level_path_points[i])
		_level_path_lengths.append(running)
	_level_path_total_length_px = running
	_level_path_end_world = _level_path_points[_level_path_points.size() - 1]

func _snap_level_path_point(point: Vector2) -> Vector2:
	if !level1_path_tile_snap_enabled:
		return point
	var tile_step = float(TILE_PX)
	return Vector2(round(point.x / tile_step) * tile_step, round(point.y / tile_step) * tile_step)

func _snap_level_path_distance(distance_px: float) -> float:
	if distance_px <= 0.0:
		return 0.0
	if !level1_path_tile_snap_enabled:
		return distance_px
	var tile_step = float(TILE_PX)
	return max(tile_step, round(distance_px / tile_step) * tile_step)

func _append_level_one_path_point(point: Vector2):
	if _level_path_points.is_empty():
		_level_path_points.append(point)
		return
	if _level_path_points[_level_path_points.size() - 1].distance_to(point) <= 0.01:
		return
	_level_path_points.append(point)

func _sample_level_path(distance_px: float) -> Dictionary:
	if _level_path_points.size() < 2 or _level_path_lengths.size() < 2:
		return {
			"position": level1_path_origin,
			"tangent": _get_level_one_path_direction(),
			"perp": _get_level_one_path_perpendicular()
		}

	var d = clamp(distance_px, 0.0, _level_path_total_length_px)
	for i in range(1, _level_path_lengths.size()):
		var seg_end = _level_path_lengths[i]
		if d > seg_end:
			continue
		var seg_start = _level_path_lengths[i - 1]
		var seg_len = max(0.001, seg_end - seg_start)
		var t = (d - seg_start) / seg_len
		var p0 = _level_path_points[i - 1]
		var p1 = _level_path_points[i]
		var tangent = (p1 - p0).normalized()
		if tangent.length_squared() <= 0.0001:
			tangent = _get_level_one_path_direction()
		var perp = Vector2(-tangent.y, tangent.x)
		return {
			"position": p0.lerp(p1, t),
			"tangent": tangent,
			"perp": perp
		}

	var last_idx = _level_path_points.size() - 1
	var fallback_tangent = (_level_path_points[last_idx] - _level_path_points[last_idx - 1]).normalized()
	if fallback_tangent.length_squared() <= 0.0001:
		fallback_tangent = _get_level_one_path_direction()
	return {
		"position": _level_path_points[last_idx],
		"tangent": fallback_tangent,
		"perp": Vector2(-fallback_tangent.y, fallback_tangent.x)
	}

func _distance_to_level_path(pos: Vector2) -> float:
	if _level_path_points.size() < 2:
		return INF
	var best = INF
	for i in range(1, _level_path_points.size()):
		var a = _level_path_points[i - 1]
		var b = _level_path_points[i]
		var ab = b - a
		var ab_len_sq = ab.length_squared()
		var closest = a
		if ab_len_sq > 0.0001:
			var t = clamp((pos - a).dot(ab) / ab_len_sq, 0.0, 1.0)
			closest = a + ab * t
		var d = pos.distance_to(closest)
		if d < best:
			best = d
	return best

func _get_level_path_bounds() -> Rect2:
	if _level_path_points.is_empty():
		return Rect2(level1_path_origin, Vector2.ZERO)
	var min_x = _level_path_points[0].x
	var max_x = _level_path_points[0].x
	var min_y = _level_path_points[0].y
	var max_y = _level_path_points[0].y
	for p in _level_path_points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _build_level_one_path_layout():
	# No visible path — compass guides the player instead
	_build_level_one_path_points()
	var path_len_px = _level_path_total_length_px
	if path_len_px <= 0.0:
		return

	var end_idx = _level_path_points.size() - 1
	_level_path_end_world = _level_path_points[end_idx]
	var end_tangent = _get_level_one_path_direction()
	if end_idx > 0:
		end_tangent = (_level_path_points[end_idx] - _level_path_points[end_idx - 1]).normalized()
		if end_tangent.length_squared() <= 0.0001:
			end_tangent = _get_level_one_path_direction()
	var forward_px = max(
		level1_goal_forward_offset_meters * PIXELS_PER_METER,
		level1_goal_bush_cluster_radius_meters * PIXELS_PER_METER + 24.0
	)
	var goal_pos = _snap_level_path_point(_level_path_end_world + end_tangent * forward_px)
	_spawn_level_goal_bush_cluster($WorldContainer, goal_pos)
	_setup_compass()

func _spawn_level_path_segment_tiles(
	parent: Node2D,
	from_pos: Vector2,
	to_pos: Vector2,
	row_count: int,
	half_rows: float,
	row_spacing_px: float,
	step_px: float,
	snap_tiles_to_grid: bool,
	occupied_tiles: Dictionary
):
	var seg = to_pos - from_pos
	var seg_len = seg.length()
	if seg_len <= 0.01:
		return
	var tangent = seg / seg_len
	var perp = Vector2(-tangent.y, tangent.x)
	var steps = int(floor(seg_len / max(1.0, step_px)))

	for step in range(steps + 1):
		var dist = min(seg_len, float(step) * step_px)
		var center = from_pos + tangent * dist
		for row in range(row_count):
			var lane_offset = (float(row) - half_rows) * row_spacing_px
			var tile_pos = center + perp * lane_offset
			_spawn_level_path_tile_once(parent, tile_pos, row, snap_tiles_to_grid, occupied_tiles)

	for row in range(row_count):
		var lane_offset = (float(row) - half_rows) * row_spacing_px
		var tile_pos = to_pos + perp * lane_offset
		_spawn_level_path_tile_once(parent, tile_pos, row, snap_tiles_to_grid, occupied_tiles)

func _spawn_level_path_tile_once(
	parent: Node2D,
	pos: Vector2,
	row_index: int,
	snap_to_grid: bool,
	occupied_tiles: Dictionary
):
	var tile_pos = _snap_level_path_point(pos) if snap_to_grid else pos
	var key_step = float(TILE_PX) if snap_to_grid else 8.0
	var key = "%d:%d:%d" % [
		int(round(tile_pos.x / key_step)),
		int(round(tile_pos.y / key_step)),
		row_index
	]
	if occupied_tiles.has(key):
		return
	occupied_tiles[key] = true
	_spawn_level_path_brick(parent, tile_pos, 0.0)

func _spawn_level_path_brick(parent: Node2D, pos: Vector2, _rotation_angle: float):
	var sprite = Sprite2D.new()
	sprite.texture = _path_fill_texture
	sprite.position = pos
	sprite.scale = Vector2.ONE * max(0.01, level1_path_brick_scale)
	sprite.offset = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.z_index = level1_path_layer_z_index
	parent.add_child(sprite)

func _spawn_level_one_path_border(parent: Node2D, path_len_px: float):
	if !level1_path_border_enabled:
		return
	if !_path_outline_texture:
		return

	var spacing_px = max(12.0, level1_path_border_spacing_meters * PIXELS_PER_METER)
	var edge_offset_px = max(0.0, level1_path_border_edge_offset_meters * PIXELS_PER_METER)
	var border_scale = max(0.01, level1_path_border_scale)
	var step_count = int(ceil(path_len_px / spacing_px))

	for step in range(step_count + 1):
		var along_px = min(path_len_px, float(step) * spacing_px)
		var sample = _sample_level_path(along_px)
		var center: Vector2 = sample["position"]
		var tangent: Vector2 = sample["tangent"]
		var row_perp: Vector2 = sample["perp"]
		for lane_sign in [-1.0, 1.0]:
			var pos = center + row_perp * lane_sign * edge_offset_px
			var sprite = Sprite2D.new()
			sprite.texture = _path_outline_texture
			sprite.position = pos
			sprite.scale = Vector2.ONE * border_scale
			sprite.offset = Vector2(0, -_path_outline_texture.get_height() * 0.5)
			sprite.rotation = tangent.angle()
			sprite.flip_v = lane_sign < 0.0
			sprite.z_index = level1_path_layer_z_index + level1_path_border_z_offset
			parent.add_child(sprite)

func _spawn_level_one_path_grass(parent: Node2D, path_len_px: float):
	if !level1_path_grass_enabled:
		return
	if path_grass_textures.is_empty():
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = int(WORLD_SEED * 177 + current_level_id * 911)

	var spacing_px = max(10.0, level1_path_grass_spacing_meters * PIXELS_PER_METER)
	var edge_offset_px = max(0.0, level1_path_grass_edge_offset_meters * PIXELS_PER_METER)
	var jitter_px = max(0.0, level1_path_grass_edge_jitter_meters * PIXELS_PER_METER)
	var skip_chance = clamp(level1_path_grass_skip_chance, 0.0, 0.95)
	if level1_path_uniform_mode:
		jitter_px = 0.0
		skip_chance = 0.0
	var min_scale = min(level1_path_grass_scale_min, level1_path_grass_scale_max)
	var max_scale = max(level1_path_grass_scale_min, level1_path_grass_scale_max)
	var step_count = int(ceil(path_len_px / spacing_px))

	for step in range(step_count + 1):
		var along_px = min(path_len_px, float(step) * spacing_px)
		for lane_sign in [-1.0, 1.0]:
			if rng.randf() < skip_chance:
				continue
			var along_jitter = rng.randf_range(-spacing_px * 0.35, spacing_px * 0.35)
			if level1_path_uniform_mode:
				along_jitter = 0.0
			var along = clamp(along_px + along_jitter, 0.0, path_len_px)
			var edge = lane_sign * edge_offset_px + rng.randf_range(-jitter_px, jitter_px)
			var sample = _sample_level_path(along)
			var center: Vector2 = sample["position"]
			var row_perp: Vector2 = sample["perp"]
			var pos = center + row_perp * edge
			var tex_idx = rng.randi() % path_grass_textures.size()
			if level1_path_uniform_mode:
				var lane_index = 0 if lane_sign < 0.0 else 1
				tex_idx = (step + lane_index) % path_grass_textures.size()
			var tex = path_grass_textures[tex_idx]
			var sprite = Sprite2D.new()
			sprite.texture = tex
			sprite.position = pos
			var scale_value = rng.randf_range(min_scale, max_scale)
			if level1_path_uniform_mode:
				scale_value = (min_scale + max_scale) * 0.5
			sprite.scale = Vector2.ONE * scale_value
			sprite.offset = Vector2(0, -tex.get_height() * 0.5)
			sprite.z_index = level1_path_layer_z_index + 1
			parent.add_child(sprite)

func _spawn_level_goal_bush_cluster(parent: Node2D, pos: Vector2):
	var goal = Node2D.new()
	goal.name = "Level1GoalBushNest"
	goal.position = pos
	goal.z_index = 2
	goal.set_meta("level_goal", true)
	goal.set_meta("level_id", 1)
	parent.add_child(goal)
	_level_goal_node = goal
	_level_goal_blink_targets.clear()

	var rng = RandomNumberGenerator.new()
	rng.seed = int(WORLD_SEED * 613 + current_level_id * 277)
	var bush_count = max(6, level1_goal_bush_cluster_count)
	var radius_px = max(20.0, level1_goal_bush_cluster_radius_meters * PIXELS_PER_METER)
	var min_scale = min(level1_goal_bush_scale_min, level1_goal_bush_scale_max)
	var max_scale = max(level1_goal_bush_scale_min, level1_goal_bush_scale_max)

	if bush_textures.is_empty():
		if _path_goal_texture:
			var fallback = Sprite2D.new()
			fallback.texture = _path_goal_texture
			fallback.scale = Vector2.ONE * max(0.01, level1_goal_scale)
			fallback.offset = Vector2(0, -_path_goal_texture.get_height() * 0.5)
			fallback.modulate = Color(1.0, 0.95, 0.76, 1.0)
			goal.add_child(fallback)
			_level_goal_blink_targets.append(fallback)
		return

	var center_tex = bush_textures[rng.randi() % bush_textures.size()]
	var center_bush = Sprite2D.new()
	center_bush.texture = center_tex
	center_bush.position = Vector2.ZERO
	center_bush.scale = Vector2.ONE * clamp((min_scale + max_scale) * 0.8, 1.4, 2.8)
	center_bush.offset = Vector2(0, -center_tex.get_height() * 0.5)
	center_bush.modulate = Color(0.86, 0.96, 0.76, 1.0)
	center_bush.set_meta("goal_drop_target", true)
	goal.add_child(center_bush)
	_level_goal_blink_targets.append(center_bush)

	for i in range(max(0, bush_count - 1)):
		var angle = rng.randf_range(0.0, TAU)
		var radial = sqrt(rng.randf()) * radius_px
		var offset = Vector2(cos(angle), sin(angle)) * radial
		var tex = bush_textures[rng.randi() % bush_textures.size()]
		var sprite = Sprite2D.new()
		sprite.texture = tex
		sprite.position = offset
		sprite.scale = Vector2.ONE * rng.randf_range(min_scale, max_scale)
		sprite.offset = Vector2(0, -tex.get_height() * 0.5)
		sprite.modulate = Color(0.80, 0.93, 0.72, 1.0)
		goal.add_child(sprite)
		_level_goal_blink_targets.append(sprite)

	if _path_goal_texture:
		var nest_marker = Sprite2D.new()
		nest_marker.texture = _path_goal_texture
		nest_marker.position = Vector2(0.0, -18.0)
		nest_marker.scale = Vector2.ONE * max(0.7, level1_goal_scale * 0.85)
		nest_marker.offset = Vector2(0, -_path_goal_texture.get_height() * 0.5)
		nest_marker.z_index = 8
		nest_marker.modulate = Color(1.0, 0.93, 0.72, 0.94)
		goal.add_child(nest_marker)
		_level_goal_blink_targets.append(nest_marker)

	_spawn_level_goal_border(goal)

func _spawn_level_goal_border(goal: Node2D):
	if !level1_goal_border_enabled:
		return
	if !goal or !is_instance_valid(goal):
		return

	_level_goal_border_collision = null
	_level_goal_warning_phase = 0.0

	var bush_radius_px = level1_goal_bush_cluster_radius_meters * PIXELS_PER_METER
	var ring_radius_px = max(level1_goal_border_radius_meters * PIXELS_PER_METER, bush_radius_px + 20.0)

	var body = StaticBody2D.new()
	body.name = "GoalShieldCollisionBody"
	goal.add_child(body)
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = max(
		level1_goal_border_collision_radius_meters * PIXELS_PER_METER,
		ring_radius_px - 8.0
	)
	shape.shape = circle
	shape.disabled = true
	body.add_child(shape)
	_level_goal_border_collision = shape

func _get_hide_tree_diamond_offsets() -> Array[Vector2]:
	var half_width_px = max(28.0, level1_hide_tree_diamond_half_width_meters * PIXELS_PER_METER)
	var half_height_px = max(20.0, level1_hide_tree_diamond_half_height_meters * PIXELS_PER_METER)
	return [
		Vector2(0.0, -half_height_px),
		Vector2(-half_width_px, 0.0),
		Vector2(half_width_px, 0.0),
		Vector2(0.0, half_height_px)
	]

func _spawn_hide_tree_diamond(parent: Node2D, hide_textures: Array, base_scale: float, hide_radius_px: float, rng: RandomNumberGenerator):
	var cluster_offsets = _get_hide_tree_diamond_offsets()

	for local_pos in cluster_offsets:
		var tex = hide_textures[rng.randi() % hide_textures.size()]
		var tree = Sprite2D.new()
		tree.texture = tex
		tree.position = local_pos
		tree.scale = Vector2.ONE * base_scale * rng.randf_range(0.96, 1.04)
		tree.offset = Vector2(0, -tex.get_height() * 0.5)
		tree.z_as_relative = false

		if local_pos.y > 0.0:
			tree.z_index = 102
		elif is_zero_approx(local_pos.y):
			tree.z_index = 16
		else:
			tree.z_index = 10
		parent.add_child(tree)

	var hide_area = Area2D.new()
	hide_area.name = "HideArea"
	hide_area.monitoring = true
	hide_area.monitorable = true
	hide_area.position = Vector2(0.0, 12.0)
	parent.add_child(hide_area)

	var area_shape = CollisionShape2D.new()
	var area_circle = CircleShape2D.new()
	var diamond_half_width_px = max(28.0, level1_hide_tree_diamond_half_width_meters * PIXELS_PER_METER)
	area_circle.radius = max(hide_radius_px, diamond_half_width_px * 0.72)
	area_shape.shape = area_circle
	hide_area.add_child(area_shape)

	hide_area.body_entered.connect(_on_hide_bush_body_entered.bind(hide_area))
	hide_area.body_exited.connect(_on_hide_bush_body_exited.bind(hide_area))

func _update_level_goal_shield_state(delta: float):
	var should_block = false
	var show_warning = false
	if _is_level_one_layout_active() and !_level_goal_completed and !_level_goal_drop_in_progress:
		if _level_goal_node and is_instance_valid(_level_goal_node):
			should_block = _is_player_chased()
			if should_block and is_instance_valid(player_ref):
				var warning_distance_px = max(
					level1_goal_warning_distance_meters * PIXELS_PER_METER,
					level1_goal_trigger_radius_meters * PIXELS_PER_METER + 24.0
				)
				show_warning = player_ref.global_position.distance_to(_level_goal_node.global_position) <= warning_distance_px

	if _level_goal_border_collision and is_instance_valid(_level_goal_border_collision):
		_level_goal_border_collision.set_deferred("disabled", !should_block)

	if should_block and show_warning:
		_level_goal_warning_phase += max(0.0, delta) * 5.0
		var pulse = 0.5 + 0.5 * sin(_level_goal_warning_phase)
		for target in _level_goal_blink_targets:
			if target and is_instance_valid(target):
				target.modulate = Color(1.0, 0.35 + 0.65 * pulse, 0.35 + 0.65 * pulse, 1.0)
		_set_goal_warning_text(true, pulse)
	else:
		_level_goal_warning_phase = 0.0
		for target in _level_goal_blink_targets:
			if target and is_instance_valid(target):
				target.modulate = Color.WHITE
		_set_goal_warning_text(false, 0.0)

func _is_player_chased() -> bool:
	return !_get_attackers_chasing_player().is_empty()

func _check_level_one_goal_reached():
	if game_state != PLAYING:
		return
	if !_is_level_one_layout_active():
		return
	if _level_goal_completed or _level_goal_drop_in_progress:
		return
	if !is_instance_valid(player_ref):
		return
	if !_level_goal_node or !is_instance_valid(_level_goal_node):
		return
	if _is_player_chased():
		return

	var trigger_px = max(22.0, level1_goal_trigger_radius_meters * PIXELS_PER_METER)
	if player_ref.global_position.distance_to(_level_goal_node.global_position) > trigger_px:
		return

	_begin_level_one_delivery()

func _begin_level_one_delivery():
	if _level_goal_drop_in_progress or _level_goal_completed:
		return
	_level_goal_drop_in_progress = true
	game_state = DELIVERING
	_clock_should_play = false

	if player_ref and player_ref.has_method("set_input_enabled"):
		player_ref.set_input_enabled(false)
	var player_collision: CollisionShape2D = player_ref.get_node_or_null("CollisionShape2D")
	if player_collision:
		player_collision.call_deferred("set_disabled", true)

	_refresh_audio_state()
	_deliver_objective_payload_to_goal()

func _deliver_objective_payload_to_goal():
	if !_objective_payload or !is_instance_valid(_objective_payload):
		_on_level_one_delivery_complete()
		return
	if !_level_goal_node or !is_instance_valid(_level_goal_node):
		_on_level_one_delivery_complete()
		return

	var drop_target = _get_level_goal_drop_target_global()
	var current_global = _objective_payload.global_position
	var current_scale = _objective_payload.scale

	var old_parent = _objective_payload.get_parent()
	if old_parent:
		old_parent.remove_child(_objective_payload)
	$WorldContainer.add_child(_objective_payload)
	_objective_payload.global_position = current_global
	_objective_payload.scale = current_scale
	_objective_payload_owner = null

	var duration = max(0.1, level1_goal_drop_duration_seconds)
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_objective_payload, "global_position", drop_target, duration)
	tween.parallel().tween_property(_objective_payload, "scale", Vector2.ONE * max(0.05, level1_goal_drop_scale), duration)
	tween.finished.connect(_on_level_one_delivery_complete)

func _get_level_goal_drop_target_global() -> Vector2:
	if _level_goal_node and is_instance_valid(_level_goal_node):
		for child in _level_goal_node.get_children():
			var child_node := child as Node2D
			if child_node and child_node.get_meta("goal_drop_target", false):
				return child_node.global_position + level1_goal_drop_offset
		return _level_goal_node.global_position + level1_goal_drop_offset
	return _level_path_end_world + level1_goal_drop_offset

func _on_level_one_delivery_complete():
	_level_goal_drop_in_progress = false
	_level_goal_completed = true
	game_state = WIN
	_refresh_audio_state()
	# Unlock next level
	_max_unlocked_level = max(_max_unlocked_level, current_level_id + 1)
	# Show win screen with stats (buttons handle navigation)
	_show_floating_text("Level %d Complete!" % current_level_id, Color(0.4, 1.0, 0.55, 1.0))
	# Short delay then show stats
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(func():
		if ui:
			var stats = _build_stats_dict()
			ui.show_win_with_stats(stats)
	)

func _spawn_level_one_enemy_layout():
	var count = max(0, level1_enemy_cluster_count)
	if count <= 0:
		return

	if _level_path_points.size() < 2:
		_build_level_one_path_points()
	if _level_path_points.size() < 2:
		return

	var start_m = clamp(level1_enemy_spawn_start_meter, 0.0, level1_path_length_meters)
	var end_m = clamp(level1_enemy_spawn_end_meter, start_m, level1_path_length_meters)
	var off_path_min_px = max(0.0, level1_enemy_off_path_min_side_meters * PIXELS_PER_METER)
	var off_path_max_px = max(
		off_path_min_px + float(TILE_PX),
		level1_enemy_random_side_range_meters * PIXELS_PER_METER
	)
	var on_path_chance = clamp(level1_enemy_on_path_chance, 0.0, 1.0)
	var on_path_jitter_px = max(0.0, level1_enemy_on_path_side_jitter_meters * PIXELS_PER_METER)
	var along_jitter_m = max(0.0, level1_enemy_along_jitter_meters)
	var density_power = max(0.01, level1_enemy_density_curve_power)
	var enemy_scenes = [Opp1Scene, Opp2Scene, Opp3Scene]
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for i in range(count):
		var progress = rng.randf()
		var shaped_progress = pow(progress, density_power)
		var meter_at = lerpf(start_m, end_m, shaped_progress)
		meter_at += rng.randf_range(-along_jitter_m, along_jitter_m)
		meter_at = clamp(meter_at, start_m, end_m)
		var sample = _sample_level_path(meter_at * PIXELS_PER_METER)
		var center_pos = sample["position"]

		if rng.randf() <= on_path_chance:
			var side_jitter = rng.randf_range(-on_path_jitter_px, on_path_jitter_px)
			center_pos += (sample["perp"] as Vector2) * side_jitter
		else:
			var side_sign = -1.0 if rng.randf() < 0.5 else 1.0
			var side_offset = rng.randf_range(off_path_min_px, off_path_max_px)
			center_pos += (sample["perp"] as Vector2) * side_sign * side_offset

		var enemy_scene = enemy_scenes[rng.randi() % enemy_scenes.size()]
		_spawn_opp_cluster(enemy_scene, center_pos, next_group_id)
		next_group_id += 1

func _spawn_level_one_friendly_layout():
	var count = max(0, level1_friendly_cluster_count)
	if count <= 0:
		return

	var start_m = clamp(level1_friendly_spawn_start_meter, 0.0, level1_path_length_meters)
	var end_m = clamp(level1_friendly_spawn_end_meter, start_m, level1_path_length_meters)
	if _level_path_points.size() < 2:
		_build_level_one_path_points()
	if _level_path_points.size() < 2:
		return

	var side_max_px = max(
		level1_friendly_random_side_range_meters * PIXELS_PER_METER,
		level1_friendly_off_path_min_side_meters * PIXELS_PER_METER + float(TILE_PX)
	)
	var off_path_min_px = max(
		level1_friendly_off_path_min_side_meters * PIXELS_PER_METER,
		level1_enemy_off_path_min_side_meters * PIXELS_PER_METER
	)
	var friendly_scenes = [Player2Scene, Player3Scene]
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for i in range(count):
		var t = 0.0 if count == 1 else float(i) / float(count - 1)
		var meter_at = lerpf(start_m, end_m, t)
		var sample = _sample_level_path(meter_at * PIXELS_PER_METER)
		var side_sign = -1.0 if i % 2 == 0 else 1.0
		var side_offset = rng.randf_range(off_path_min_px, side_max_px)
		var center_pos = sample["position"] + (sample["perp"] as Vector2) * side_sign * side_offset

		var friendly_scene = friendly_scenes[i % friendly_scenes.size()]
		_spawn_friendly_cluster(friendly_scene, center_pos)

func _spawn_level_one_hide_bush_layout():
	var count = max(0, level1_hide_bush_count)
	if count <= 0:
		return
	var hide_textures: Array = tree_textures if !tree_textures.is_empty() else bush_textures
	if hide_textures.is_empty():
		return
	if _level_path_points.size() < 2:
		_build_level_one_path_points()
	if _level_path_points.size() < 2:
		return

	var start_m = clamp(level1_hide_bush_spawn_start_meter, 0.0, level1_path_length_meters)
	var end_m = clamp(level1_hide_bush_spawn_end_meter, start_m, level1_path_length_meters)
	var side_min_px = max(
		level1_hide_bush_min_side_offset_meters * PIXELS_PER_METER,
		_get_level_one_path_reserved_half_width_meters() * PIXELS_PER_METER + 24.0
	)
	var side_max_px = max(side_min_px + 12.0, level1_hide_bush_max_side_offset_meters * PIXELS_PER_METER)
	var along_jitter_m = max(0.0, level1_hide_bush_along_jitter_meters)
	var scale_min = min(level1_hide_bush_scale_min, level1_hide_bush_scale_max)
	var scale_max = max(level1_hide_bush_scale_min, level1_hide_bush_scale_max)
	var hide_radius_px = max(24.0, level1_hide_bush_hide_radius_meters * PIXELS_PER_METER)
	var min_spacing_px = max(0.0, level1_hide_bush_min_spacing_meters * PIXELS_PER_METER)
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var placed_positions: Array[Vector2] = []
	var spawned = 0
	var attempts = max(count * 4, count)

	for _attempt in range(attempts):
		if spawned >= count:
			break
		var t = rng.randf()
		var meter_at = lerpf(start_m, end_m, t)
		meter_at += rng.randf_range(-along_jitter_m, along_jitter_m)
		meter_at = clamp(meter_at, start_m, end_m)
		var sample = _sample_level_path(meter_at * PIXELS_PER_METER)
		var side_sign = -1.0 if rng.randf() < 0.5 else 1.0
		var side_offset = rng.randf_range(side_min_px, side_max_px)
		var pos = sample["position"] + (sample["perp"] as Vector2) * side_sign * side_offset
		var too_close = false
		for placed_pos in placed_positions:
			if pos.distance_to(placed_pos) < min_spacing_px:
				too_close = true
				break
		if too_close:
			continue

		var bush_node = Node2D.new()
		bush_node.name = "HideBush"
		bush_node.position = pos
		bush_node.z_index = 12
		$WorldContainer.add_child(bush_node)
		var tree_cluster_scale = rng.randf_range(scale_min, scale_max) * 0.34
		_spawn_hide_tree_diamond(bush_node, hide_textures, tree_cluster_scale, hide_radius_px, rng)
		placed_positions.append(pos)
		spawned += 1

func _attach_level_one_objective_to_player(player: Node2D):
	if !level1_objective_attach_enabled:
		return
	if !_is_level_one_layout_active():
		return
	if !player or !is_instance_valid(player):
		return
	if player.get_node_or_null("ObjectiveMosquito") != null:
		return

	var frame_paths = [
		"res://assets/art/animated_objects/baby/mosquito 1.png",
		"res://assets/art/animated_objects/baby/mosquito 2.png",
		"res://assets/art/animated_objects/baby/mosquito 3.png",
		"res://assets/art/animated_objects/baby/mosquito 4.png"
	]

	var sf := SpriteFrames.new()
	sf.add_animation("carry")
	sf.set_animation_loop("carry", true)
	sf.set_animation_speed("carry", max(1.0, level1_objective_anim_fps))
	for p in frame_paths:
		var tex = load(p)
		if tex:
			sf.add_frame("carry", tex)
	if sf.get_frame_count("carry") == 0:
		return

	var baby := AnimatedSprite2D.new()
	baby.name = "ObjectiveMosquito"
	baby.sprite_frames = sf
	baby.flip_h = level1_objective_initial_face_left
	baby.position = level1_objective_attach_offset
	baby.scale = Vector2.ONE * max(0.05, level1_objective_scale)
	baby.z_index = level1_objective_z_index
	baby.set_meta("is_level_objective_payload", true)
	player.add_child(baby)
	baby.play("carry")
	_objective_payload = baby
	_objective_payload_owner = player
	_objective_last_owner_flip_set = false
	_objective_float_time = 0.0
	_update_objective_payload(0.0)

func _update_objective_payload(delta: float):
	if !_objective_payload or !is_instance_valid(_objective_payload):
		return
	if !_objective_payload_owner or !is_instance_valid(_objective_payload_owner):
		return

	if level1_objective_follow_player_turn:
		var owner_sprite: AnimatedSprite2D = _objective_payload_owner.get_node_or_null("AnimatedSprite2D")
		if owner_sprite:
			var owner_flip = owner_sprite.flip_h
			var payload_flip = !owner_flip if level1_objective_invert_turn_with_player else owner_flip
			if !_objective_last_owner_flip_set:
				_objective_last_owner_flip_set = true
				_objective_last_owner_flip_h = owner_flip
				_objective_payload.flip_h = payload_flip
			elif owner_flip != _objective_last_owner_flip_h:
				_objective_last_owner_flip_h = owner_flip
				_objective_payload.flip_h = payload_flip

	_objective_float_time += max(0.0, delta) * max(0.01, level1_objective_float_speed)
	var bob_px = sin(_objective_float_time) * level1_objective_float_amplitude_px
	_objective_payload.position = Vector2(level1_objective_attach_offset.x, level1_objective_attach_offset.y + bob_px)

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
	if _is_player_currently_hidden_for_stealth(): return
	
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

func _on_hide_bush_body_entered(body: Node2D, _hide_area: Area2D):
	if !is_instance_valid(player_ref):
		return
	if body != player_ref:
		return
	_player_hide_overlap_count += 1

func _on_hide_bush_body_exited(body: Node2D, _hide_area: Area2D):
	if !is_instance_valid(player_ref):
		return
	if body != player_ref:
		return
	_player_hide_overlap_count = max(0, _player_hide_overlap_count - 1)

func _update_player_hiding(delta: float):
	if !is_instance_valid(player_ref):
		return
	if game_state != PLAYING:
		_player_hidden_time_sec = 0.0
		_hide_escape_triggered = false
		_set_player_hidden_state(false)
		return

	var inside_hide_bush = _player_hide_overlap_count > 0
	if inside_hide_bush:
		_player_hidden_time_sec += max(0.0, delta)
		_set_player_hidden_state(true)
		if !_hide_escape_triggered and _player_hidden_time_sec >= hide_bush_enemy_forget_delay_seconds:
			_hide_escape_triggered = true
			_make_enemies_forget_player()
	else:
		_player_hidden_time_sec = 0.0
		_hide_escape_triggered = false
		_set_player_hidden_state(false)

func _set_player_hidden_state(hidden: bool):
	if !is_instance_valid(player_ref):
		return
	if player_ref.has_method("set_stealth_hidden"):
		player_ref.set_stealth_hidden(hidden)
	else:
		player_ref.modulate.a = 0.55 if hidden else 1.0

func _is_player_currently_hidden_for_stealth() -> bool:
	if _player_hide_overlap_count > 0:
		return true
	if !is_instance_valid(player_ref):
		return false
	if player_ref.has_method("is_stealth_hidden"):
		return player_ref.is_stealth_hidden()
	return false

func _make_enemies_forget_player():
	if !is_instance_valid(player_ref):
		return
	var disengage_distance_px = max(80.0, hide_bush_enemy_disengage_distance_meters * PIXELS_PER_METER)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if !is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.get("target_body") != player_ref:
			continue
		if enemy.has_method("force_forget_player"):
			enemy.force_forget_player(player_ref, disengage_distance_px)

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

func _get_wanted_star_level(attacker_count: int) -> int:
	if attacker_count > 10:
		return 5
	if attacker_count >= 8:
		return 4
	if attacker_count >= 6:
		return 3
	if attacker_count >= 4:
		return 2
	if attacker_count >= 2:
		return 1
	return 0

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
	if _is_player_currently_hidden_for_stealth():
		return
	var container = $WorldContainer
	var spawn_pos = _get_transformed_spawn_position(pos, template)
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
		new_opp.position = spawn_pos
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
		new_friend.position = spawn_pos
		new_friend.is_controllable = false
		container.add_child(new_friend)
		_register_audio_hooks_for_player(new_friend)
		if new_friend.has_method("join_group_behavior"):
			new_friend.join_group_behavior(template.global_position)
		if new_friend.has_method("spawn_effect"):
			new_friend.spawn_effect()
		
		transform_cooldown = TRANSFORM_COOLDOWN_MAX

func _get_transformed_spawn_position(base_pos: Vector2, template: Node2D) -> Vector2:
	if !is_instance_valid(player_ref):
		return base_pos

	var desired_distance_px = max(8.0, transformed_spawn_distance_from_player_meters * PIXELS_PER_METER)
	var jitter_px = max(0.0, transformed_spawn_jitter_meters * PIXELS_PER_METER)

	var away_dir = base_pos - player_ref.global_position
	if away_dir.length_squared() <= 0.0001 and template and is_instance_valid(template):
		away_dir = template.global_position - player_ref.global_position
	if away_dir.length_squared() <= 0.0001:
		var angle = randf() * TAU
		away_dir = Vector2(cos(angle), sin(angle))
	away_dir = away_dir.normalized()

	var lateral_dir = Vector2(-away_dir.y, away_dir.x)
	var radial_jitter = randf_range(-jitter_px * 0.25, jitter_px)
	var lateral_jitter = randf_range(-jitter_px, jitter_px)
	var spawn_pos = player_ref.global_position + away_dir * (desired_distance_px + radial_jitter)
	spawn_pos += lateral_dir * lateral_jitter

	var min_dist_px = desired_distance_px * 0.8
	if spawn_pos.distance_to(player_ref.global_position) < min_dist_px:
		spawn_pos = player_ref.global_position + away_dir * min_dist_px
	return spawn_pos

# =====================================================================
# PICKUPS
# =====================================================================

func _spawn_level_one_pickup_layout():
	if !_is_level_one_layout_active():
		return
	if _level_path_points.size() < 2:
		_build_level_one_path_points()
	if _level_path_points.size() < 2:
		return

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# Spawn coins along the path
	var coin_start_px = level1_coin_spawn_start_meter * PIXELS_PER_METER
	var coin_end_px = level1_coin_spawn_end_meter * PIXELS_PER_METER
	for i in range(level1_coin_count):
		var t = float(i) / max(1.0, float(level1_coin_count - 1))
		var along_px = lerpf(coin_start_px, coin_end_px, t)
		var sample = _sample_level_path(along_px)
		var side = rng.randf_range(-level1_pickup_side_range_meters, level1_pickup_side_range_meters) * PIXELS_PER_METER
		var pos = sample["position"] + (sample["perp"] as Vector2) * side
		_spawn_coin_pickup(pos)

	# Spawn apples along the path
	var apple_start_px = level1_apple_spawn_start_meter * PIXELS_PER_METER
	var apple_end_px = level1_apple_spawn_end_meter * PIXELS_PER_METER
	for i in range(level1_apple_count):
		var t = float(i) / max(1.0, float(level1_apple_count - 1))
		var along_px = lerpf(apple_start_px, apple_end_px, t)
		var sample = _sample_level_path(along_px)
		var side = rng.randf_range(-level1_pickup_side_range_meters * 0.5, level1_pickup_side_range_meters * 0.5) * PIXELS_PER_METER
		var pos = sample["position"] + (sample["perp"] as Vector2) * side
		_spawn_apple_pickup(pos)

func _spawn_coin_pickup(pos: Vector2):
	if _coin_frames.is_empty():
		return

	var pickup = Area2D.new()
	pickup.name = "CoinPickup"
	pickup.position = pos
	pickup.monitoring = true
	pickup.monitorable = false
	pickup.set_meta("pickup_type", "coin")

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = max(20.0, pickup_collect_radius_meters * PIXELS_PER_METER)
	shape.shape = circle
	pickup.add_child(shape)

	# Animated coin sprite
	var sf = SpriteFrames.new()
	sf.add_animation("spin")
	sf.set_animation_loop("spin", true)
	sf.set_animation_speed("spin", 10.0)
	for tex in _coin_frames:
		sf.add_frame("spin", tex)

	var sprite = AnimatedSprite2D.new()
	sprite.name = "PickupVisual"
	sprite.sprite_frames = sf
	sprite.scale = Vector2(0.35, 0.35)
	sprite.offset = Vector2(0, -_coin_frames[0].get_height() * 0.5)
	sprite.play("spin")
	pickup.add_child(sprite)

	pickup.add_to_group("pickup_collectible")
	pickup.body_entered.connect(_on_pickup_body_entered.bind(pickup))
	$WorldContainer.add_child(pickup)

func _spawn_apple_pickup(pos: Vector2):
	if !_apple_texture:
		return

	var pickup = Area2D.new()
	pickup.name = "ApplePickup"
	pickup.position = pos
	pickup.monitoring = true
	pickup.monitorable = false
	pickup.set_meta("pickup_type", "apple")

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = max(22.0, pickup_collect_radius_meters * PIXELS_PER_METER)
	shape.shape = circle
	pickup.add_child(shape)

	var sprite = Sprite2D.new()
	sprite.name = "PickupVisual"
	sprite.texture = _apple_texture
	sprite.scale = Vector2(0.4, 0.4)
	sprite.offset = Vector2(0, -_apple_texture.get_height() * 0.5)
	pickup.add_child(sprite)

	pickup.add_to_group("pickup_collectible")
	pickup.body_entered.connect(_on_pickup_body_entered.bind(pickup))
	$WorldContainer.add_child(pickup)

func _on_pickup_body_entered(body: Node2D, pickup: Area2D):
	if !body.is_in_group("player"):
		return
	_collect_pickup(pickup)

func _collect_nearby_pickups():
	if game_state != PLAYING:
		return
	if !is_instance_valid(player_ref):
		return
	var collect_radius_px = max(8.0, pickup_collect_radius_meters * PIXELS_PER_METER)
	for node in get_tree().get_nodes_in_group("pickup_collectible"):
		var pickup = node as Area2D
		if !pickup or !is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			continue
		if pickup.get_meta("collected", false):
			continue
		if player_ref.global_position.distance_to(pickup.global_position) <= collect_radius_px:
			_collect_pickup(pickup)

func _collect_pickup(pickup: Area2D):
	if !is_instance_valid(pickup) or pickup.is_queued_for_deletion():
		return
	if pickup.get_meta("collected", false):
		return
	pickup.set_meta("collected", true)
	pickup.set_deferred("monitoring", false)
	var pickup_shape := pickup.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if pickup_shape:
		pickup_shape.set_deferred("disabled", true)
	var pickup_type = pickup.get_meta("pickup_type", "")

	if pickup_type == "coin":
		_coins_collected += 1
		_add_score(coin_score_value)
		_spawn_pickup_particles(pickup.global_position, Color(1.0, 0.85, 0.2, 1.0))
		_show_floating_text("+" + str(coin_score_value), Color(1.0, 0.9, 0.3, 1.0))
	elif pickup_type == "apple":
		_apples_collected += 1
		if is_instance_valid(player_ref):
			player_ref.health = min(100, player_ref.health + apple_heal_amount)
			player_ref.emit_signal("health_changed", player_ref.health, 100)
		_spawn_pickup_particles(pickup.global_position, Color(0.4, 1.0, 0.5, 1.0))
		_show_floating_text("+" + str(apple_heal_amount) + " HP", Color(0.5, 1.0, 0.6, 1.0))

	_animate_pickup_collection(pickup, pickup_type)

func _animate_pickup_collection(pickup: Area2D, pickup_type: String):
	if !is_instance_valid(pickup):
		return

	var jump_height_px = 22.0 if pickup_type == "coin" else 18.0
	var base_y = pickup.position.y
	var tween = create_tween()
	tween.tween_property(pickup, "position:y", base_y - jump_height_px, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pickup, "position:y", base_y - jump_height_px * 0.55, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(pickup, "scale", Vector2(1.16, 1.16), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pickup, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var visual := pickup.get_node_or_null("PickupVisual") as Node2D
	if visual:
		var rot = 0.55 if pickup_type == "coin" else -0.35
		tween.parallel().tween_property(visual, "rotation", rot, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func():
		if is_instance_valid(pickup):
			pickup.queue_free()
	)

func _spawn_pickup_particles(pos: Vector2, color: Color):
	var particles = CPUParticles2D.new()
	particles.global_position = pos
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 12
	particles.lifetime = 0.5
	particles.emitting = true
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, 200)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 120.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0

	var grad = Gradient.new()
	grad.colors = [color, Color(color.r, color.g, color.b, 0.0)]
	particles.color_ramp = grad

	$WorldContainer.add_child(particles)
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)

# =====================================================================
# SCORE & COMBO
# =====================================================================

func _add_score(amount: int):
	var multiplier = max(1, min(_combo_count, combo_multiplier_max))
	_score += amount * multiplier
	if ui and ui.has_method("update_score"):
		ui.update_score(_score)

func _add_kill_score():
	_combo_count += 1
	_combo_timer = combo_time_window
	_add_score(kill_base_score)
	if ui and ui.has_method("update_combo"):
		ui.update_combo(_combo_count, min(_combo_count, combo_multiplier_max))

func _update_combo_timer(delta: float):
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_count = 0
			if ui and ui.has_method("update_combo"):
				ui.update_combo(0, 1)

func _on_player_enemy_killed():
	_enemies_killed += 1
	_add_kill_score()
	if _combo_count > _max_combo:
		_max_combo = _combo_count
	_trigger_screen_shake(shake_kill_intensity, shake_kill_duration)
	_trigger_kill_slowmo()

# =====================================================================
# SCREEN SHAKE & JUICE
# =====================================================================

func _trigger_screen_shake(intensity: float, duration: float):
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = duration

func _update_screen_shake(delta: float):
	if _shake_timer <= 0.0:
		if _cam_ref and is_instance_valid(_cam_ref):
			_cam_ref.offset = Vector2.ZERO
		return

	_shake_timer -= delta
	var ratio = clamp(_shake_timer / max(0.001, _shake_duration), 0.0, 1.0)
	var current_intensity = _shake_intensity * ratio

	if _cam_ref and is_instance_valid(_cam_ref):
		_cam_ref.offset = Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)

	if _shake_timer <= 0.0 and _cam_ref and is_instance_valid(_cam_ref):
		_cam_ref.offset = Vector2.ZERO

func _trigger_kill_slowmo():
	Engine.time_scale = kill_slowmo_scale
	_slowmo_timer = kill_slowmo_duration

func _update_slowmo(_delta: float):
	if _slowmo_timer > 0.0:
		var real_delta = _delta / max(0.01, Engine.time_scale)
		_slowmo_timer -= real_delta
		if _slowmo_timer <= 0.0:
			Engine.time_scale = 1.0

# =====================================================================
# PROGRESS
# =====================================================================

func _get_player_progress_ratio() -> float:
	if !is_instance_valid(player_ref):
		return 0.0
	if !_level_goal_node or !is_instance_valid(_level_goal_node):
		return 0.0
	if _level_path_total_length_px <= 0.0:
		return 0.0

	var player_pos = player_ref.global_position
	var best_dist = INF
	var best_along = 0.0

	for i in range(1, _level_path_points.size()):
		var a = _level_path_points[i - 1]
		var b = _level_path_points[i]
		var ab = b - a
		var ab_len_sq = ab.length_squared()
		var t = 0.0
		if ab_len_sq > 0.0001:
			t = clamp((player_pos - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var closest = a + ab * t
		var d = player_pos.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best_along = _level_path_lengths[i - 1] + t * (a.distance_to(b))

	return clamp(best_along / _level_path_total_length_px, 0.0, 1.0)

func _update_progress_bar():
	# Progress bar removed — compass handles direction
	pass

# =====================================================================
# COMPASS
# =====================================================================

func _setup_compass():
	if _compass_layer:
		return

	_compass_layer = CanvasLayer.new()
	_compass_layer.name = "CompassLayer"
	_compass_layer.layer = 15
	add_child(_compass_layer)

	# Container for the whole compass widget — center bottom of screen
	var wrapper = Control.new()
	wrapper.name = "CompassWrapper"
	wrapper.anchor_left = 0.5
	wrapper.anchor_right = 0.5
	wrapper.anchor_top = 1.0
	wrapper.anchor_bottom = 1.0
	wrapper.offset_left = -44
	wrapper.offset_right = 44
	wrapper.offset_top = -108
	wrapper.offset_bottom = -8
	_compass_layer.add_child(wrapper)

	# Arrow draw area (square, centered in wrapper)
	_compass_arrow = Control.new()
	_compass_arrow.name = "CompassArrow"
	_compass_arrow.position = Vector2(0, 0)
	_compass_arrow.size = Vector2(88, 88)
	_compass_arrow.pivot_offset = Vector2(44, 44)
	wrapper.add_child(_compass_arrow)

	# Distance label below the arrow
	_compass_label = Label.new()
	_compass_label.name = "CompassLabel"
	_compass_label.position = Vector2(-8, 70)
	_compass_label.size = Vector2(104, 20)
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _ui_font:
		_compass_label.add_theme_font_override("font", _ui_font)
	_compass_label.add_theme_font_size_override("font_size", 10)
	_compass_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.85, 0.9))
	_compass_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_compass_label.add_theme_constant_override("shadow_outline_size", 4)
	_compass_label.text = "-- BUSH --"
	wrapper.add_child(_compass_label)

	# Connect draw once
	_compass_arrow.draw.connect(_draw_compass_arrow)

var _compass_angle_current: float = 0.0

func _update_compass():
	if !_compass_arrow or !is_instance_valid(_compass_arrow):
		return
	if !is_instance_valid(player_ref):
		if _compass_arrow.get_parent(): _compass_arrow.get_parent().visible = false
		return
	if !_level_goal_node or !is_instance_valid(_level_goal_node):
		if _compass_arrow.get_parent(): _compass_arrow.get_parent().visible = false
		return
	if game_state != PLAYING:
		if _compass_arrow.get_parent(): _compass_arrow.get_parent().visible = false
		return

	if _compass_arrow.get_parent(): _compass_arrow.get_parent().visible = true

	var dir_to_goal = _level_goal_node.global_position - player_ref.global_position
	var dist = dir_to_goal.length() / PIXELS_PER_METER
	var target_angle = dir_to_goal.angle()

	# Smooth rotation — lerp angular difference
	var angle_diff = fmod(target_angle - _compass_angle_current + PI, TAU) - PI
	_compass_angle_current += angle_diff * clamp(get_process_delta_time() * 12.0, 0.0, 1.0)

	if _compass_label:
		if dist > 999.0:
			_compass_label.text = "BUSH  FAR"
		else:
			_compass_label.text = "BUSH  %dm" % int(dist)

	_compass_arrow.queue_redraw()

func _draw_compass_arrow():
	if !_compass_arrow or !is_instance_valid(_compass_arrow):
		return
	if !is_instance_valid(player_ref) or !_level_goal_node or !is_instance_valid(_level_goal_node):
		return

	var center = Vector2(44, 44)
	var radius = 38.0
	var angle = _compass_angle_current

	var dist_m = player_ref.global_position.distance_to(_level_goal_node.global_position) / PIXELS_PER_METER

	# Arrow color based on distance
	var color: Color
	if dist_m > 40.0:
		color = Color(0.55, 0.9, 0.7, 0.95)
	elif dist_m > 15.0:
		color = Color(0.4, 1.0, 0.55, 1.0)
	else:
		color = Color(0.3, 1.0, 0.4, 1.0)
		var pulse = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 80.0)
		color.a = pulse

	# Outer circle background
	_compass_arrow.draw_circle(center, radius + 4.0, Color(0.03, 0.04, 0.08, 0.6))
	_compass_arrow.draw_arc(center, radius + 4.0, 0, TAU, 48, Color(0.4, 0.6, 0.5, 0.35), 2.0)

	# Inner subtle ring
	_compass_arrow.draw_arc(center, radius - 6.0, 0, TAU, 32, Color(0.3, 0.4, 0.35, 0.15), 1.0)

	# Arrow — big and clear
	var tip = center + Vector2(cos(angle), sin(angle)) * radius
	var back_l = center + Vector2(cos(angle + 2.7), sin(angle + 2.7)) * (radius * 0.45)
	var back_r = center + Vector2(cos(angle - 2.7), sin(angle - 2.7)) * (radius * 0.45)
	var notch = center + Vector2(cos(angle + PI), sin(angle + PI)) * (radius * 0.15)

	var arrow_pts = PackedVector2Array([tip, back_l, notch, back_r])
	var arrow_cols = PackedColorArray([color, color, color, color])
	_compass_arrow.draw_polygon(arrow_pts, arrow_cols)

	# Bright outline on the arrow for clarity
	var outline_color = Color(color.r, color.g, color.b, color.a * 0.5)
	_compass_arrow.draw_polyline(PackedVector2Array([tip, back_l, notch, back_r, tip]), outline_color, 1.5)

	# Center dot
	_compass_arrow.draw_circle(center, 4.0, Color(1.0, 1.0, 1.0, 0.6))
	_compass_arrow.draw_circle(center, 2.0, Color(color.r, color.g, color.b, 0.9))

	# Cardinal hint — small "N" label at top for visual grounding
	var n_pos = center + Vector2(0, -radius - 1)
	_compass_arrow.draw_circle(n_pos, 2.0, Color(0.8, 0.8, 0.8, 0.2))

# =====================================================================
# STATS
# =====================================================================

func _build_stats_dict() -> Dictionary:
	var elapsed = _now_seconds() - _play_start_time
	var minutes = int(elapsed / 60.0)
	var seconds = int(elapsed) % 60
	return {
		"level": current_level_id,
		"score": _score,
		"enemies_killed": _enemies_killed,
		"max_combo": _max_combo,
		"coins_collected": _coins_collected,
		"apples_collected": _apples_collected,
		"damage_taken": _damage_taken_total,
		"time": "%d:%02d" % [minutes, seconds],
		"progress": _get_player_progress_ratio()
	}

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
