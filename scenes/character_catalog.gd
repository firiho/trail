extends RefCounted
class_name CharacterCatalog

const ENTITY_PLAYER := "player"
const ENTITY_ENEMY := "enemy"

const PLAYER_BASE_PATH := "res://assets/players"
const ENEMY_BASE_PATH := "res://assets/opps"

const PLAYER_DEFAULT_FAMILY := "warriors"
const ENEMY_DEFAULT_FAMILY := "wraiths"

const PLAYER_FPS := 20.0
const ENEMY_FPS := 15.0
const PLAYER_SHEET_IDLE_FPS := 7.0
const PLAYER_SHEET_MOVE_FPS := 9.0
const PLAYER_SHEET_ATTACK_FPS := 10.0
const PLAYER_SHEET_HIT_FPS := 7.0
const ENEMY_SHEET_IDLE_FPS := 6.0
const ENEMY_SHEET_MOVE_FPS := 8.0
const ENEMY_SHEET_ATTACK_FPS := 9.0
const ENEMY_SHEET_HIT_FPS := 6.0

const PLAYER_ATTACK_PRIORITY := [
	"attack_1",
	"attack_2",
	"attack_3",
	"slashing",
	"kicking",
	"attacking",
	"throwing",
	"run_slashing",
	"run_throwing",
	"slashing_in_the_air",
	"throwing_in_the_air"
]

const ENEMY_ATTACK_PRIORITY := [
	"attack_1",
	"attack_2",
	"attack_3",
	"attacking",
	"run_attack",
	"casting_spells",
	"taunt"
]

const SHEET_ACTION_ALIASES := [
	"run_attack",
	"attack",
	"idle",
	"walk",
	"run",
	"jump",
	"hurt",
	"dead"
]

static var _catalog_ready := false
static var _family_catalog := {}
static var _build_cache := {}

static func resolve_player_family(requested_family: String) -> String:
	return _resolve_family(ENTITY_PLAYER, requested_family, PLAYER_DEFAULT_FAMILY)

static func resolve_enemy_family(requested_family: String) -> String:
	return _resolve_family(ENTITY_ENEMY, requested_family, ENEMY_DEFAULT_FAMILY)

static func get_player_family_choices() -> Array:
	return _get_family_choices(ENTITY_PLAYER, PLAYER_DEFAULT_FAMILY)

static func get_enemy_family_choices() -> Array:
	return _get_family_choices(ENTITY_ENEMY, ENEMY_DEFAULT_FAMILY)

static func get_player_sprite_data(player_family: String, player_folder: String) -> Dictionary:
	return _get_entity_sprite_data(ENTITY_PLAYER, player_family, player_folder)

static func get_enemy_sprite_data(enemy_family: String, opp_folder: String) -> Dictionary:
	return _get_entity_sprite_data(ENTITY_ENEMY, enemy_family, opp_folder)

static func _ensure_catalog() -> void:
	if _catalog_ready:
		return

	_family_catalog = {
		ENTITY_PLAYER: _discover_families(ENTITY_PLAYER, PLAYER_BASE_PATH),
		ENTITY_ENEMY: _discover_families(ENTITY_ENEMY, ENEMY_BASE_PATH)
	}
	_catalog_ready = true

static func _discover_families(entity_type: String, base_path: String) -> Dictionary:
	var result := {}
	var family_ids = _list_dirs(base_path)
	family_ids.sort()

	for family_id in family_ids:
		var family_path = base_path + "/" + family_id
		var member_ids = _list_dirs(family_path)
		var filtered_member_ids: Array = []
		for member_id in member_ids:
			var member_name = String(member_id)
			if entity_type == ENTITY_PLAYER:
				if member_name.begins_with("player_"):
					filtered_member_ids.append(member_name)
			elif member_name.begins_with("opp_"):
				filtered_member_ids.append(member_name)
		member_ids = filtered_member_ids
		member_ids.sort_custom(func(a, b): return _extract_trailing_number(a) < _extract_trailing_number(b))
		if member_ids.is_empty():
			continue

		var format = _detect_member_format(family_path + "/" + member_ids[0])
		result[family_id] = {
			"id": family_id,
			"display_name": _format_family_name(family_id),
			"base_path": family_path,
			"member_ids": member_ids,
			"format": format
		}

	return result

static func _resolve_family(entity_type: String, requested_family: String, fallback_family: String) -> String:
	_ensure_catalog()
	var families: Dictionary = _family_catalog.get(entity_type, {})
	if requested_family != "" and families.has(requested_family):
		return requested_family
	if families.has(fallback_family):
		return fallback_family

	var family_ids: Array = families.keys()
	family_ids.sort()
	return "" if family_ids.is_empty() else String(family_ids[0])

static func _resolve_member_id(entity_type: String, family_id: String, member_id: String) -> String:
	_ensure_catalog()
	var family_info: Dictionary = _family_catalog.get(entity_type, {}).get(family_id, {})
	var member_ids: Array = family_info.get("member_ids", [])
	if member_id != "" and member_ids.has(member_id):
		return member_id
	return "" if member_ids.is_empty() else String(member_ids[0])

static func _get_family_choices(entity_type: String, fallback_family: String) -> Array:
	_ensure_catalog()
	var families: Dictionary = _family_catalog.get(entity_type, {})
	var family_ids: Array = families.keys()
	family_ids.sort()
	if family_ids.has(fallback_family):
		family_ids.erase(fallback_family)
		family_ids.push_front(fallback_family)

	var choices: Array = []
	for family_id in family_ids:
		var family_info: Dictionary = families[family_id]
		var choice := {
			"id": family_id,
			"display_name": String(family_info.get("display_name", family_id)),
			"members": []
		}

		for member_id in family_info.get("member_ids", []):
			var sprite_data = _get_entity_sprite_data(entity_type, family_id, String(member_id))
			choice["members"].append({
				"id": member_id,
				"label": _format_member_label(String(member_id)),
				"preview_texture": sprite_data.get("preview_texture", null),
				"preview_animation": sprite_data.get("preview_animation", ""),
				"preview_sprite_frames": sprite_data.get("sprite_frames", null),
				"attack_animations": sprite_data.get("attack_animations", []),
				"default_animation": sprite_data.get("default_animation", "")
			})

		choices.append(choice)

	return choices

static func _get_entity_sprite_data(entity_type: String, family_id: String, member_id: String) -> Dictionary:
	_ensure_catalog()
	var fallback_family = PLAYER_DEFAULT_FAMILY if entity_type == ENTITY_PLAYER else ENEMY_DEFAULT_FAMILY
	var resolved_family = _resolve_family(entity_type, family_id, fallback_family)
	if resolved_family == "":
		return {}

	var resolved_member = _resolve_member_id(entity_type, resolved_family, member_id)
	if resolved_member == "":
		return {}

	var cache_key = "%s:%s:%s" % [entity_type, resolved_family, resolved_member]
	if _build_cache.has(cache_key):
		return _clone_build_data(_build_cache[cache_key])

	var family_info: Dictionary = _family_catalog.get(entity_type, {}).get(resolved_family, {})
	var member_path = String(family_info.get("base_path", "")) + "/" + resolved_member
	var sprite_data := {}
	if String(family_info.get("format", "folders")) == "folders":
		sprite_data = _build_folder_based_data(entity_type, member_path)
	else:
		sprite_data = _build_sheet_based_data(entity_type, member_path)
	if sprite_data.is_empty():
		return {}

	var loaded_anims: Array = sprite_data.get("loaded_anims", [])
	var attack_anims = _extract_attack_animations(entity_type, loaded_anims)
	var default_anim = _pick_default_animation(entity_type, loaded_anims)
	var preview_anim = _pick_preview_animation(attack_anims, default_anim)
	var preview_tex = _get_preview_texture(sprite_data.get("sprite_frames", null), preview_anim)

	sprite_data["family_id"] = resolved_family
	sprite_data["member_id"] = resolved_member
	sprite_data["attack_animations"] = attack_anims
	sprite_data["default_animation"] = default_anim
	sprite_data["preview_animation"] = preview_anim
	sprite_data["preview_texture"] = preview_tex

	_build_cache[cache_key] = sprite_data
	return _clone_build_data(sprite_data)

static func _build_folder_based_data(entity_type: String, member_path: String) -> Dictionary:
	var anim_dirs = _list_dirs(member_path)
	anim_dirs.sort()

	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	var built_anims: Array = []
	for anim_name in anim_dirs:
		var frames = _load_frames_from_dir(member_path + "/" + anim_name + "/")
		if frames.is_empty():
			continue

		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, PLAYER_FPS if entity_type == ENTITY_PLAYER else ENEMY_FPS)
		sprite_frames.set_animation_loop(anim_name, true)
		for frame_tex in frames:
			sprite_frames.add_frame(anim_name, frame_tex)
		built_anims.append(anim_name)

	return {
		"sprite_frames": sprite_frames,
		"loaded_anims": built_anims
	}

static func _build_sheet_based_data(entity_type: String, member_path: String) -> Dictionary:
	var files = _list_png_files(member_path)
	files.sort()

	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")

	var built_anims: Array = []
	for file_name in files:
		var parsed = _parse_sheet_file(file_name)
		if parsed.is_empty():
			continue

		var anim_names = _resolve_sheet_animation_names(entity_type, parsed)
		if anim_names.is_empty():
			continue
		if entity_type == ENTITY_ENEMY and String(parsed.get("action", "")) == "run" and sprite_frames.has_animation("walking"):
			continue

		var tex: Texture2D = load(member_path + "/" + file_name)
		if tex == null:
			continue

		var frames = _slice_sheet_texture(tex, int(parsed.get("frame_count", 0)))
		if frames.is_empty():
			continue
		var anim_speed = _get_sheet_animation_speed(entity_type, parsed)

		for anim_name in anim_names:
			if !sprite_frames.has_animation(anim_name):
				sprite_frames.add_animation(anim_name)
				sprite_frames.set_animation_speed(anim_name, anim_speed)
				sprite_frames.set_animation_loop(anim_name, true)
				built_anims.append(anim_name)

			for frame_tex in frames:
				sprite_frames.add_frame(anim_name, frame_tex)

	return {
		"sprite_frames": sprite_frames,
		"loaded_anims": built_anims
	}

static func _resolve_sheet_animation_names(entity_type: String, parsed: Dictionary) -> Array:
	var action = String(parsed.get("action", ""))
	var variant = int(parsed.get("variant", -1))
	var names: Array = []

	if entity_type == ENTITY_PLAYER:
		match action:
			"idle":
				names.append("idle")
			"walk":
				names.append("walking")
			"run":
				names.append("running")
			"jump":
				names.append("jump_start")
				names.append("jump_loop")
			"hurt":
				names.append("hurt")
			"dead":
				names.append("dying")
			"attack":
				names.append("attack_%d" % max(1, variant))
	else:
		match action:
			"idle":
				names.append("idle")
			"walk":
				names.append("walking")
			"run":
				names.append("walking")
			"hurt":
				names.append("hurt")
			"dead":
				names.append("dying")
			"attack":
				names.append("attack_%d" % max(1, variant))

	return names

static func _get_sheet_animation_speed(entity_type: String, parsed: Dictionary) -> float:
	var action = String(parsed.get("action", ""))
	if entity_type == ENTITY_PLAYER:
		match action:
			"walk", "run", "jump":
				return PLAYER_SHEET_MOVE_FPS
			"attack", "run_attack":
				return PLAYER_SHEET_ATTACK_FPS
			"hurt", "dead":
				return PLAYER_SHEET_HIT_FPS
			_:
				return PLAYER_SHEET_IDLE_FPS

	match action:
		"walk", "run", "jump":
			return ENEMY_SHEET_MOVE_FPS
		"attack", "run_attack":
			return ENEMY_SHEET_ATTACK_FPS
		"hurt", "dead":
			return ENEMY_SHEET_HIT_FPS
		_:
			return ENEMY_SHEET_IDLE_FPS

static func _parse_sheet_file(file_name: String) -> Dictionary:
	if !file_name.ends_with(".png"):
		return {}

	var stem = file_name.trim_suffix(".png")
	var tokens = stem.split("_")
	if tokens.size() < 3:
		return {}

	var frame_token = String(tokens[tokens.size() - 1])
	if !frame_token.is_valid_int():
		return {}

	var body_tokens: Array = []
	for i in range(tokens.size() - 1):
		body_tokens.append(String(tokens[i]))

	var matched_action := ""
	var variant := -1

	if body_tokens.size() >= 2 and String(body_tokens[body_tokens.size() - 1]).is_valid_int():
		var without_variant: Array = []
		for i in range(body_tokens.size() - 1):
			without_variant.append(String(body_tokens[i]))
		for alias in SHEET_ACTION_ALIASES:
			if _ends_with_tokens(without_variant, alias.split("_")):
				matched_action = alias
				variant = int(body_tokens[body_tokens.size() - 1])
				break
		if matched_action != "":
			return {
				"action": matched_action,
				"variant": variant,
				"frame_count": int(frame_token)
			}

	for alias in SHEET_ACTION_ALIASES:
		if _ends_with_tokens(body_tokens, alias.split("_")):
			matched_action = alias
			break

	if matched_action == "":
		return {}

	return {
		"action": matched_action,
		"variant": variant,
		"frame_count": int(frame_token)
	}

static func _slice_sheet_texture(texture: Texture2D, frame_count: int) -> Array:
	if texture == null or frame_count <= 0:
		return []

	var sheet_width = texture.get_width()
	var sheet_height = texture.get_height()
	if sheet_width <= 0 or sheet_height <= 0:
		return []

	var frame_width = max(1, int(round(float(sheet_width) / float(frame_count))))
	var frames: Array = []
	for frame_idx in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(frame_idx * frame_width, 0, min(frame_width, sheet_width - frame_idx * frame_width), sheet_height)
		frames.append(atlas)

	return frames

static func _extract_attack_animations(entity_type: String, loaded_anims: Array) -> Array:
	var attack_anims: Array = []
	for anim_name in loaded_anims:
		var anim = String(anim_name)
		if anim.begins_with("attack_"):
			attack_anims.append(anim)

	if !attack_anims.is_empty():
		attack_anims.sort_custom(func(a, b): return _extract_trailing_number(String(a)) < _extract_trailing_number(String(b)))
		return attack_anims

	var priorities = PLAYER_ATTACK_PRIORITY if entity_type == ENTITY_PLAYER else ENEMY_ATTACK_PRIORITY
	for anim_name in priorities:
		if loaded_anims.has(anim_name):
			attack_anims.append(anim_name)

	if !attack_anims.is_empty():
		return attack_anims

	for anim_name in loaded_anims:
		var lower = String(anim_name).to_lower()
		if lower.contains("attack") or lower.contains("slash") or lower.contains("kick") or lower.contains("throw"):
			attack_anims.append(anim_name)

	return attack_anims

static func _pick_default_animation(entity_type: String, loaded_anims: Array) -> String:
	var preferred = ["idle_blinking", "idle"] if entity_type == ENTITY_PLAYER else ["idle"]
	for anim_name in preferred:
		if loaded_anims.has(anim_name):
			return anim_name
	return "" if loaded_anims.is_empty() else String(loaded_anims[0])

static func _pick_preview_animation(attack_anims: Array, default_anim: String) -> String:
	if !attack_anims.is_empty():
		return String(attack_anims[0])
	return default_anim

static func _get_preview_texture(sprite_frames: SpriteFrames, anim_name: String) -> Texture2D:
	if sprite_frames == null or anim_name == "" or !sprite_frames.has_animation(anim_name):
		return null

	var frame_count = sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return null

	var preview_frame = int(clamp(frame_count / 2, 0, frame_count - 1))
	return sprite_frames.get_frame_texture(anim_name, preview_frame)

static func _clone_build_data(source: Dictionary) -> Dictionary:
	var sprite_frames: SpriteFrames = source.get("sprite_frames", null)
	return {
		"family_id": source.get("family_id", ""),
		"member_id": source.get("member_id", ""),
		"sprite_frames": sprite_frames.duplicate(true) if sprite_frames else null,
		"loaded_anims": (source.get("loaded_anims", []) as Array).duplicate(),
		"attack_animations": (source.get("attack_animations", []) as Array).duplicate(),
		"default_animation": source.get("default_animation", ""),
		"preview_animation": source.get("preview_animation", ""),
		"preview_texture": source.get("preview_texture", null)
	}

static func _detect_member_format(member_path: String) -> String:
	if !_list_dirs(member_path).is_empty():
		return "folders"
	return "sheets"

static func _list_dirs(path: String) -> Array:
	var result: Array = []
	var dir = DirAccess.open(path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and !String(entry).begins_with("."):
			result.append(String(entry))
		entry = dir.get_next()
	return result

static func _list_png_files(path: String) -> Array:
	var result: Array = []
	var dir = DirAccess.open(path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if !dir.current_is_dir():
			var file_name = String(entry)
			if file_name.ends_with(".import"):
				file_name = file_name.trim_suffix(".import")
			if file_name.ends_with(".remap"):
				file_name = file_name.trim_suffix(".remap")
			if file_name.ends_with(".png") and !result.has(file_name):
				result.append(file_name)
		entry = dir.get_next()
	return result

static func _load_frames_from_dir(dir_path: String) -> Array:
	var result: Array = []
	var files = _list_png_files(dir_path)
	files.sort()
	for file_name in files:
		var tex = load(dir_path + file_name)
		if tex:
			result.append(tex)
	return result

static func _ends_with_tokens(tokens: Array, suffix_tokens: Array) -> bool:
	if suffix_tokens.size() > tokens.size():
		return false
	for i in range(suffix_tokens.size()):
		var token_idx = tokens.size() - suffix_tokens.size() + i
		if String(tokens[token_idx]) != String(suffix_tokens[i]):
			return false
	return true

static func _extract_trailing_number(value: String) -> int:
	var parts = value.split("_")
	if parts.is_empty():
		return 0
	var last = String(parts[parts.size() - 1])
	return int(last) if last.is_valid_int() else 0

static func _format_family_name(family_id: String) -> String:
	if family_id == "creatives":
		return "Youngins"
	return family_id.replace("_", " ").capitalize()

static func _format_member_label(member_id: String) -> String:
	var member_number = _extract_trailing_number(member_id)
	return str(member_number) if member_number > 0 else member_id
