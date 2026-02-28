extends CharacterBody2D

# Stats (Upgradable!)
var speed: float = 300.0
var jump_speed: float = 400.0
var climb_speed: float = 150.0
var gravity: float = 980.0
var mine_time: float = 4.0 # Default for Starter Pick
var max_battery: float = 100.0
var current_battery: float = 100.0
var max_cargo: int = 10
var current_cargo: int = 0

# --- Grappling Hook ---
var grapple_active: bool = false
var grapple_point: Vector2
var grapple_tile: Vector2i
var grapple_force: float = 600.0
var grapple_hover_tile: Vector2i
var grapple_hover_valid: bool = false
var grapple_hover_invalid: bool = false
var is_grapple_moving: bool = false
var is_wall_stuck: bool = false
const WALL_STICK_SLIDE_SPEED: float = 44.8  # half-tile/sec in global space
const GRAPPLE_MAX_TILES: int = 4

# --- Minimap ---
var minimap_texture_rect: TextureRect
var minimap_timer_node: Timer
var minimap_image: Image
var minimap_zoom: float = 9.0
const MINIMAP_W: int = 120
const MINIMAP_H: int = 150
const MINIMAP_TILE_COLORS = {
	0: Color(0.45, 0.30, 0.15),
	1: Color(0.25, 0.65, 0.15),
	3: Color(0.55, 0.55, 0.55),
	4: Color(0.25, 0.25, 0.30),
}
const MINIMAP_EMPTY_COLOR = Color(0.05, 0.05, 0.05)
const MINIMAP_PLAYER_COLOR = Color(1.0, 1.0, 1.0)

# --- Low Battery Overlay ---
var low_battery_overlay: ColorRect
var low_oxygen_label: Label
var low_oxygen_onset_time: float = -1.0  # tracks when warning first appeared
const LOW_BATTERY_PULSE_MIN: float = 0.10
const LOW_BATTERY_PULSE_MAX: float = 0.35
const LOW_BATTERY_PULSE_SPEED: float = 2.5

# --- Game Clock ---
var game_minutes: float = 7.0 * 60.0  # Start at 7:00 AM
var clock_label: Label

# TileSet source IDs (matching main.gd)
const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4

# Mining SFX (assign in Inspector, or place `anvil.mp3` at res://anvil.mp3)
const DEFAULT_MINING_SFX_PATH: String = "res://anvil.mp3"
@export var mining_sfx: AudioStream
var mining_sfx_player: AudioStreamPlayer

# Upgrade tracking
var pickaxe_level: int = 0
const PICKAXE_UPGRADES = [
	{"name": "Starter Pick", "price": 0,     "mine_time": 2.5,  "luck": 1.0,  "color": Color(0.6, 0.6, 0.6)},
	{"name": "Stone Pick",   "price": 500,   "mine_time": 1.6,  "luck": 1.1,  "color": Color(0.75, 0.7, 0.65)},
	{"name": "Copper Pick",  "price": 1000,  "mine_time": 1,  "luck": 1.2,  "color": Color(0.9, 0.5, 0.15)},
	{"name": "Silver Pick",  "price": 5000,  "mine_time": 0.6,  "luck": 1.35, "color": Color(0.8, 0.85, 0.95)},
	{"name": "Gold Pick",    "price": 50000, "mine_time": 0.3,  "luck": 1.55,  "color": Color(1.0, 0.85, 0.1)}
]

@onready var mining_timer: Timer = $MiningTimer
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
var tilemap: TileMapLayer
var money_label: Label
var oxygen_bar: ProgressBar
var money: int = 0
var is_mining: bool = false
var target_tile_coords: Vector2i
var spawn_position: Vector2

# Track which direction the player is facing so we know which block to target
var facing_dir: int = 1  # 1 = right, -1 = left
var is_walking: bool = false
var is_wall_climbing: bool = false

# Highlight state — updated every frame based on mouse position
var highlighted_tile: Vector2i
var highlight_valid: bool = false
# Tile size in world space: tileset is 128px, TileMapLayer scale is 0.5
const TILE_WORLD_SIZE = 64.0

# Ore table: [name, 1-in-N drop chance, value per ore, display color]
const ORE_TABLE = [
	["Stone",  1.8,  2,   Color(0.75, 0.70, 0.65)],
	["Copper", 9, 15,  Color(0.90, 0.50, 0.15)],
	["Silver", 22, 50,  Color(0.80, 0.85, 0.95)],
	["Gold",   45, 200, Color(1.00, 0.85, 0.10)],
]

# Per-ore inventory counts
var ore_counts: Dictionary = {}
# HUD label references keyed by ore name
var ore_labels: Dictionary = {}

func _ready():
	spawn_position = global_position
	# Find TileMapLayer more robustly
	var main = get_parent()
	tilemap = main.get_node_or_null("Dirt") as TileMapLayer
	
	# Find HUD nodes more robustly
	var hud = main.get_node_or_null("HUD")
	if hud:
		money_label = hud.get_node_or_null("MoneyLabel") as Label
		if money_label:
			money_label.text = "$0"

		clock_label = hud.get_node_or_null("ClockLabel") as Label
		if clock_label:
			clock_label.text = _format_game_time(game_minutes)

		oxygen_bar = hud.get_node_or_null("ProgressBar") as ProgressBar
		if oxygen_bar:
			oxygen_bar.visible = true
			# Anchor to top-center so it stays centered on any screen size
			oxygen_bar.anchor_left = 0.5
			oxygen_bar.anchor_right = 0.5
			oxygen_bar.anchor_top = 0.0
			oxygen_bar.anchor_bottom = 0.0
			oxygen_bar.offset_left = -125.0
			oxygen_bar.offset_right = 125.0
			oxygen_bar.offset_top = 20.0
			oxygen_bar.offset_bottom = 50.0
			oxygen_bar.max_value = max_battery
			oxygen_bar.value = current_battery
			
			var ox_label = oxygen_bar.get_node_or_null("Label") as Label
			if ox_label:
				ox_label.text = "Oxygen"
				ox_label.position = Vector2(85, -24)
	
	# Mining sound player
	mining_sfx_player = AudioStreamPlayer.new()
	add_child(mining_sfx_player)
	if mining_sfx == null and ResourceLoader.exists(DEFAULT_MINING_SFX_PATH):
		mining_sfx = load(DEFAULT_MINING_SFX_PATH) as AudioStream
	if mining_sfx != null:
		mining_sfx_player.stream = mining_sfx

	if hud:
		# --- Low Battery Overlay ---
		low_battery_overlay = hud.get_node_or_null("LowBatteryOverlay") as ColorRect

		# --- Low Oxygen Warning Label ---
		var lbl_ox = Label.new()
		lbl_ox.text = "LOW OXYGEN LEVELS"
		lbl_ox.add_theme_font_size_override("font_size", 72)
		lbl_ox.modulate = Color(1.0, 0.3, 0.3, 0.0)
		lbl_ox.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_ox.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_ox.anchor_left = 0.5
		lbl_ox.anchor_right = 0.5
		lbl_ox.anchor_top = 0.5
		lbl_ox.anchor_bottom = 0.5
		lbl_ox.offset_left = -420.0
		lbl_ox.offset_right = 420.0
		lbl_ox.offset_top = -50.0
		lbl_ox.offset_bottom = 50.0
		lbl_ox.z_index = 5
		hud.add_child(lbl_ox)
		low_oxygen_label = lbl_ox

	# --- Minimap ---
	var minimap_panel = hud.get_node_or_null("MinimapPanel") if hud else null
	if minimap_panel:
		minimap_texture_rect = minimap_panel.get_node_or_null("MinimapTexture") as TextureRect
		minimap_timer_node = minimap_panel.get_node_or_null("MinimapTimer") as Timer
		if minimap_timer_node:
			minimap_timer_node.timeout.connect(_update_minimap)
			minimap_timer_node.start()
	minimap_image = Image.create(MINIMAP_W, MINIMAP_H, false, Image.FORMAT_RGBA8)
	_update_minimap()

	mining_timer.timeout.connect(finish_mining)
	add_to_group("player")
	z_index = 1

	# Initialise ore counts and build HUD labels
	if hud:
		var y: float = 68.0
		for ore in ORE_TABLE:
			var nm: String = ore[0]
			ore_counts[nm] = 0

			var lbl := Label.new()
			lbl.text = "%s: 0" % nm
			lbl.modulate = ore[3] as Color
			lbl.add_theme_font_size_override("font_size", 20)
			lbl.position = Vector2(20.0, y)
			hud.add_child(lbl)
			ore_labels[nm] = lbl
			y += 26.0

func _process(delta: float) -> void:
	game_minutes += delta * 5.0  # 1 real second = 5 game minutes
	if game_minutes >= 1440.0:
		game_minutes -= 1440.0
	if clock_label:
		clock_label.text = _format_game_time(game_minutes)

func _physics_process(delta):
	if not tilemap: return
	if is_grapple_moving: return  # Physics paused during grapple travel

	# 1. Drain Battery (Oxygen)
	var pos_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var tile_below = pos_tile + Vector2i(0, 1)
	var on_grass = tilemap.get_cell_source_id(tile_below) == 1
	var tile_at_feet = tilemap.get_cell_source_id(pos_tile) == 1
	
	if (not on_grass and not tile_at_feet) and pos_tile.y > 0:
		current_battery -= delta * 2.0
	else:
		var refill_rate = 60.0 if (on_grass or tile_at_feet) else 15.0
		current_battery = min(max_battery, current_battery + delta * refill_rate)
		
	if oxygen_bar:
		oxygen_bar.value = current_battery
	_update_low_battery_overlay()

	if current_battery <= 0:
		die_and_respawn()

	# 2. Horizontal input
	var h = Input.get_axis("Left", "Right")
	is_walking = h != 0
	if h != 0:
		facing_dir = sign(h)

	# --- Wall Stick (post-grapple) ---
	if is_wall_stuck:
		if is_on_floor() or h != 0:
			is_wall_stuck = false
		else:
			velocity.y = WALL_STICK_SLIDE_SPEED
			velocity.x = 0.0
			if Input.is_action_just_pressed("ui_accept"):
				velocity.y = -jump_speed
				is_wall_stuck = false
			move_and_slide()
			_update_highlight()
			_update_grapple_hover()
			_update_animation()
			queue_redraw()
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				if highlight_valid and not is_mining:
					start_mining(highlighted_tile)
			else:
				if is_mining: cancel_mining()
			return

	# 3. Wall climbing
	var wall_normal = get_wall_normal()
	is_wall_climbing = (
		is_on_wall()
		and h != 0
		and wall_normal != Vector2.ZERO
		and sign(h) == -sign(wall_normal.x)
	)

	# 4. Gravity
	if not is_on_floor() and not is_wall_climbing:
		velocity.y += gravity * delta

	# 5. Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = -jump_speed

	# 6. Velocity
	velocity.x = h * speed
	if is_wall_climbing:
		velocity.y = -climb_speed

	move_and_slide()

	if is_mining and is_on_floor():
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		var adjacent_tiles = [
			player_tile + Vector2i(1, 0),
			player_tile + Vector2i(-1, 0),
			player_tile + Vector2i(0, 1),
			player_tile + Vector2i(0, -1),
		]
		if not (target_tile_coords in adjacent_tiles):
			cancel_mining()

	_update_highlight()
	_update_grapple_hover()
	_update_animation()
	queue_redraw()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if highlight_valid and not is_mining:
			start_mining(highlighted_tile)
	else:
		if is_mining:
			cancel_mining()

func _update_highlight():
	if is_mining or not tilemap:
		return

	var mouse_world_pos = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world_pos))
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	var adjacent_tiles = [
		player_tile + Vector2i(1, 0),
		player_tile + Vector2i(-1, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(0, -1),
	]

	if mouse_tile in adjacent_tiles and tilemap.get_cell_source_id(mouse_tile) != -1:
		highlighted_tile = mouse_tile
		highlight_valid = true
	else:
		highlight_valid = false

func _update_animation():
	var target_anim: StringName
	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		target_anim = &"mine_down" if target_tile_coords.y > player_tile.y else &"mine_right"
	elif is_wall_climbing:
		target_anim = &"climb"
	elif is_walking:
		# Animation 'walk' contains the walk frames
		target_anim = &"walk" 
	else:
		# Animation 'idle' contains the idle frames
		target_anim = &"idle"

	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		anim_sprite.flip_h = target_tile_coords.x < player_tile.x
	elif is_wall_climbing:
		var wall_normal = get_wall_normal()
		anim_sprite.flip_h = wall_normal.x > 0 
	else:
		anim_sprite.flip_h = facing_dir == -1

	if anim_sprite.animation != target_anim:
		anim_sprite.play(target_anim)

func _draw():
	if not tilemap: return

	# Grapple hover highlight (cyan = valid, red = out of range / blocked)
	if not grapple_active and (grapple_hover_valid or grapple_hover_invalid):
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(grapple_hover_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var r = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		if grapple_hover_valid:
			draw_rect(r, Color(0.0, 1.0, 1.0, 0.25), true)
			draw_rect(r, Color(0.0, 1.0, 1.0, 1.0), false, 2.5)
		else:
			draw_rect(r, Color(1.0, 0.0, 0.0, 0.25), true)
			draw_rect(r, Color(1.0, 0.0, 0.0, 1.0), false, 2.5)

	if highlight_valid and not is_mining:
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(highlighted_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 0.45), true)
		draw_rect(rect, Color(1.0, 0.85, 0.0, 1.0), false, 3.0)

	if is_mining:
		var progress = 1.0 - (mining_timer.time_left / mine_time)
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0

		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.3), true)
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.9), false, 2.0)

		var bar_w = TILE_WORLD_SIZE
		var bar_h = 6.0
		var bar_pos = tile_center_local - Vector2(bar_w / 2.0, half + bar_h + 4.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.15, 0.15, 0.85), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * progress, bar_h)), Color(0.2, 0.85, 0.2, 0.9), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.5), false, 1.0)

func start_mining(tile_coords: Vector2i):
	is_mining = true
	target_tile_coords = tile_coords
	_play_mining_sfx()
	mining_timer.start(mine_time)

func _play_mining_sfx() -> void:
	if mining_sfx_player == null:
		return
	if mining_sfx_player.stream == null and mining_sfx != null:
		mining_sfx_player.stream = mining_sfx
	if mining_sfx_player.stream == null:
		return
	# Connect finished signal so the sound loops for the full mining duration
	if not mining_sfx_player.finished.is_connected(_on_mining_sfx_finished):
		mining_sfx_player.finished.connect(_on_mining_sfx_finished)
	mining_sfx_player.stop()
	mining_sfx_player.play()

func _on_mining_sfx_finished() -> void:
	if is_mining:
		mining_sfx_player.play()

func cancel_mining():
	mining_timer.stop()
	is_mining = false
	if mining_sfx_player and mining_sfx_player.finished.is_connected(_on_mining_sfx_finished):
		mining_sfx_player.finished.disconnect(_on_mining_sfx_finished)
	if mining_sfx_player:
		mining_sfx_player.stop()

func die_and_respawn():
	anim_sprite.play("death")
	if is_mining:
		cancel_mining()
	_release_grapple()
	is_grapple_moving = false
	is_wall_stuck = false

	current_battery = max_battery
	current_cargo = 0
	for ore in ORE_TABLE:
		var nm: String = ore[0]
		ore_counts[nm] = 0
		if ore_labels.has(nm):
			ore_labels[nm].text = "%s: 0" % nm

	global_position = spawn_position
	velocity = Vector2.ZERO

func _roll_count() -> int:
	var count = 1
	var n = 2
	while n <= 10 and randi() % n == 0:
		count += 1
		n += 1
	return count

func finish_mining():
	if not tilemap: return

	var source_id = tilemap.get_cell_source_id(target_tile_coords)
	var is_grass = (source_id == 1)
	is_mining = false

	var tile_world_pos = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
	var cargo_remaining = max_cargo - current_cargo

	# Regular block (dirt, cobble, deepslate, grass)
	tilemap.set_cell(target_tile_coords, -1)

	if is_grass:
		return

	# Block-specific luck bonus
	var block_luck_mult = 1.0
	if source_id == 3: # Cobblestone
		block_luck_mult = 1.5
	elif source_id == 4: # Deepslate
		block_luck_mult = 2.0

	var found: Array[Dictionary] = []

	if cargo_remaining <= 0:
		_spawn_floating_text("Cargo Full!", tile_world_pos, Color(1.0, 0.3, 0.3))
		return

	var current_luck = PICKAXE_UPGRADES[pickaxe_level]["luck"] * block_luck_mult

	# 75% chance to drop at least one Stone from regular blocks
	if source_id in [TILE_DIRT, TILE_COBBLE, TILE_DEEPSLATE] and randf() < 0.75:
		var amount = min(_roll_count(), cargo_remaining)
		if amount > 0:
			cargo_remaining -= amount
			found.append({
				"name":   "Stone",
				"amount": amount,
				"value":  2,
				"color":  Color(0.75, 0.70, 0.65),
			})

	for ore in ORE_TABLE:
		if cargo_remaining <= 0:
			break
		if ore[0] == "Stone":
			continue
		var chance_denom = float(ore[1]) / current_luck
		if randf() * chance_denom < 1.0:
			var amount = min(_roll_count(), cargo_remaining)
			cargo_remaining -= amount
			found.append({
				"name":   ore[0] as String,
				"amount": amount,
				"value":  int(ore[2]),
				"color":  ore[3] as Color,
			})

	if found.is_empty():
		_spawn_floating_text("No ore...", tile_world_pos, Color(0.6, 0.6, 0.6, 0.85))
		return

	var delay := 0.0
	for ore_data in found:
		_spawn_ore_fly(ore_data, tile_world_pos, delay)
		delay += 0.22


func _spawn_floating_text(msg: String, world_pos: Vector2, color: Color) -> void:
	var hud = get_parent().get_node_or_null("HUD")
	if not hud: return
	var label := Label.new()
	label.text = msg
	label.modulate = color
	label.add_theme_font_size_override("font_size", 16)
	label.position = get_viewport().get_canvas_transform() * world_pos + Vector2(-30.0, -10.0)
	label.z_index = 10
	hud.add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -45.0), 1.1)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.1)
	tween.tween_callback(label.queue_free)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if grapple_active:
					_release_grapple()
				else:
					_try_fire_grapple()
			MOUSE_BUTTON_WHEEL_UP:
				minimap_zoom = clamp(minimap_zoom * 1.25, 0.5, 8.0)
				_update_minimap()
			MOUSE_BUTTON_WHEEL_DOWN:
				minimap_zoom = clamp(minimap_zoom / 1.25, 0.5, 8.0)
				_update_minimap()
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_release_grapple()
			KEY_BRACKETRIGHT:  # ] = zoom in
				minimap_zoom = clamp(minimap_zoom * 1.25, 0.5, 8.0)
				_update_minimap()
			KEY_BRACKETLEFT:   # [ = zoom out
				minimap_zoom = clamp(minimap_zoom / 1.25, 0.5, 8.0)
				_update_minimap()

func _update_grapple_hover() -> void:
	grapple_hover_valid = false
	grapple_hover_invalid = false
	if grapple_active or not tilemap: return
	var mouse_world = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world))
	var src = tilemap.get_cell_source_id(mouse_tile)
	if src == -1: return  # Air — nothing to show
	grapple_hover_tile = mouse_tile
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var dist = Vector2(mouse_tile).distance_to(Vector2(player_tile))
	if src == TILE_GRASS or dist > float(GRAPPLE_MAX_TILES) or not _has_los_to_tile(mouse_tile):
		grapple_hover_invalid = true
	else:
		grapple_hover_valid = true

func _try_fire_grapple() -> void:
	if not tilemap or is_grapple_moving: return
	var mouse_world = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world))
	var src = tilemap.get_cell_source_id(mouse_tile)
	if src == -1 or src == TILE_GRASS: return
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	if Vector2(mouse_tile).distance_to(Vector2(player_tile)) > float(GRAPPLE_MAX_TILES): return
	if not _has_los_to_tile(mouse_tile): return
	var tile_center = tilemap.to_global(tilemap.map_to_local(mouse_tile))
	var to_player = global_position - tile_center
	var sx = sign(to_player.x) if to_player.x != 0 else 1.0
	var sy = sign(to_player.y) if to_player.y != 0 else 1.0
	var candidates: Array[Vector2] = [
		tile_center + Vector2(sx * 56.0, 0.0),     # preferred horizontal face
		tile_center + Vector2(0.0, sy * 92.0),      # preferred vertical face
		tile_center + Vector2(-sx * 56.0, 0.0),    # opposite horizontal
		tile_center + Vector2(0.0, -sy * 92.0),    # opposite vertical
	]
	if abs(to_player.y) > abs(to_player.x):
		candidates = [candidates[1], candidates[0], candidates[3], candidates[2]]
	var target_pos := Vector2.ZERO
	var found := false
	for c in candidates:
		var lt = tilemap.local_to_map(tilemap.to_local(c))
		if tilemap.get_cell_source_id(lt) == -1:
			target_pos = c
			found = true
			break
	if not found: return
	# If the landing spot is beside the block (horizontal face), the player sticks to the wall
	var will_wall_stick = abs(target_pos.x - tile_center.x) > abs(target_pos.y - tile_center.y)
	is_grapple_moving = true
	velocity = Vector2.ZERO
	var dist = global_position.distance_to(target_pos)
	var duration = clamp(dist / 800.0, 0.08, 0.6)
	var tw = create_tween()
	tw.tween_property(self, "global_position", target_pos, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		is_grapple_moving = false
		if will_wall_stick:
			is_wall_stuck = true
	)

func _has_los_to_tile(target_tile: Vector2i) -> bool:
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var dx = target_tile.x - player_tile.x
	var dy = target_tile.y - player_tile.y
	var steps = max(abs(dx), abs(dy))
	if steps <= 1:
		return true
	for i in range(1, steps):  # skip endpoints — player is air, target is the block
		var cx = player_tile.x + roundi(float(dx * i) / float(steps))
		var cy = player_tile.y + roundi(float(dy * i) / float(steps))
		if tilemap.get_cell_source_id(Vector2i(cx, cy)) != -1:
			return false  # Solid tile in the way
	return true

func _release_grapple() -> void:
	grapple_active = false
	grapple_hover_valid = false
	grapple_hover_invalid = false

func sleep() -> void:
	game_minutes = 7.0 * 60.0  # Reset to 7:00 AM
	current_battery = max_battery
	if oxygen_bar: oxygen_bar.value = current_battery
	global_position = spawn_position
	velocity = Vector2.ZERO
	is_wall_stuck = false
	_release_grapple()
	is_grapple_moving = false
	if is_mining: cancel_mining()
	_update_low_battery_overlay()
	if clock_label: clock_label.text = _format_game_time(game_minutes)

func _format_game_time(total_mins: float) -> String:
	var m := int(total_mins) % 1440
	var h := m / 60
	var mn := m % 60
	var period := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0: h12 = 12
	return "%d:%02d %s" % [h12, mn, period]

func _update_minimap() -> void:
	if not tilemap or not minimap_image or not minimap_texture_rect: return
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	minimap_image.fill(MINIMAP_EMPTY_COLOR)
	# Each pixel represents (1 / minimap_zoom) tiles; view is centered on the player
	for tx in range(MINIMAP_W):
		for ty in range(MINIMAP_H):
			var world_x = player_tile.x + int((tx - MINIMAP_W / 2.0) / minimap_zoom)
			var world_y = player_tile.y + int((ty - MINIMAP_H / 2.0) / minimap_zoom)
			if world_y < 0:
				minimap_image.set_pixel(tx, ty, Color(0.45, 0.72, 1.0))
				continue
			var src = tilemap.get_cell_source_id(Vector2i(world_x, world_y))
			if src == -1:
				continue
			minimap_image.set_pixel(tx, ty, MINIMAP_TILE_COLORS.get(src, MINIMAP_EMPTY_COLOR))
	# Player dot always at image center
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var ix = clamp(MINIMAP_W / 2 + dx, 0, MINIMAP_W - 1)
			var iy = clamp(MINIMAP_H / 2 + dy, 0, MINIMAP_H - 1)
			minimap_image.set_pixel(ix, iy, MINIMAP_PLAYER_COLOR)
	minimap_texture_rect.texture = ImageTexture.create_from_image(minimap_image)

func _update_low_battery_overlay() -> void:
	if not low_battery_overlay: return
	if current_battery >= max_battery * 0.15:
		low_battery_overlay.visible = false
		low_oxygen_onset_time = -1.0
		if low_oxygen_label:
			low_oxygen_label.modulate.a = 0.0
		return
	# Record when the warning first fired
	if low_oxygen_onset_time < 0.0:
		low_oxygen_onset_time = Time.get_ticks_msec() / 1000.0
	low_battery_overlay.visible = true
	var t = Time.get_ticks_msec() / 1000.0
	var alpha = lerp(LOW_BATTERY_PULSE_MIN, LOW_BATTERY_PULSE_MAX,
		(sin(t * LOW_BATTERY_PULSE_SPEED) + 1.0) / 2.0)
	low_battery_overlay.color = Color(1.0, 0.0, 0.0, alpha)
	if low_oxygen_label:
		# Fade the label in over 2 seconds so it doesn't smash the player in the face
		var elapsed = (Time.get_ticks_msec() / 1000.0) - low_oxygen_onset_time
		var fade_in = clamp(elapsed / 2.0, 0.0, 1.0)
		low_oxygen_label.modulate = Color(1.0, 0.3, 0.3, alpha * fade_in)

func _spawn_ore_fly(ore_data: Dictionary, tile_world_pos: Vector2, delay: float) -> void:
	var hud = get_parent().get_node_or_null("HUD")
	if not hud: return
	
	var fly_node = Node2D.new()
	fly_node.z_index = 10
	
	var tex_path = ""
	match ore_data["name"]:
		"Stone": tex_path = "res://Stones_ores_bars/stone_1.png"
		"Copper": tex_path = "res://Stones_ores_bars/copper_ore.png"
		"Silver": tex_path = "res://Stones_ores_bars/silver_ore.png"
		"Gold": tex_path = "res://Stones_ores_bars/gold_ore.png"
		
	var sprite = Sprite2D.new()
	if tex_path != "" and FileAccess.file_exists(tex_path):
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(2.5, 2.5)
	fly_node.add_child(sprite)

	var label := Label.new()
	label.text = "+%d" % ore_data["amount"]
	label.modulate = ore_data["color"]
	label.add_theme_font_size_override("font_size", 18)
	label.position = Vector2(10.0, -10.0)
	fly_node.add_child(label)

	var ct := get_viewport().get_canvas_transform()
	var screen_start := ct * tile_world_pos
	var screen_end := get_viewport_rect().size * 0.5

	fly_node.position = screen_start
	hud.add_child(fly_node)

	var tween = create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(fly_node, "position", screen_start + Vector2(0.0, -30.0), 0.20)
	tween.tween_property(fly_node, "position", screen_end, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		var nm: String    = ore_data["name"]
		var amt: int      = ore_data["amount"]
		ore_counts[nm] += amt
		current_cargo   += amt
		if ore_labels.has(nm):
			ore_labels[nm].text = "%s: %d" % [nm, ore_counts[nm]]
			var flash = create_tween()
			flash.tween_property(ore_labels[nm], "modulate:a", 0.15, 0.07)
			flash.tween_property(ore_labels[nm], "modulate:a", 1.00, 0.18)
		fly_node.queue_free()
	)
