extends CharacterBody2D

# Stats (Upgradable!)
var speed: float = 150.0
var jump_speed: float = 400.0
var gravity: float = 980.0
var mine_time: float = 1.0
var max_battery: float = 100.0
var current_battery: float = 100.0
var max_cargo: int = 10
var current_cargo: int = 0

@onready var mining_timer = $MiningTimer
@onready var tilemap: TileMapLayer = get_parent().get_node("Dirt")
var is_mining: bool = false
var target_tile_coords: Vector2i
var spawn_position: Vector2

# Track which direction the player is facing so we know which block to target
var facing_dir: int = 1  # 1 = right, -1 = left

# Highlight state — updated every frame based on player position
var highlighted_tile: Vector2i
var highlight_valid: bool = false
# Tile size in world space: tileset is 128px, TileMapLayer scale is 0.5
const TILE_WORLD_SIZE = 64.0

func _ready():
	spawn_position = global_position

func _physics_process(delta):
	# 1. Drain Battery
	current_battery -= delta * 2.0
	if current_battery <= 0:
		die_and_respawn()

	# 2. Gravity
	if not is_on_floor():
		velocity.y += gravity * delta

	# 3. Jump
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = -jump_speed

	# 4. Horizontal movement — also tracks facing direction
	var h = Input.get_axis("ui_left", "ui_right")
	if not is_mining:
		velocity.x = h * speed
		if h != 0:
			facing_dir = sign(h)
	else:
		velocity.x = 0.0

	move_and_slide()

	# 5. Find the nearest adjacent block to highlight
	_update_highlight()
	queue_redraw()

	# 6. Mine the highlighted block when spacebar is pressed
	if highlight_valid and Input.is_action_just_pressed("mine"):
		start_mining(highlighted_tile)

func _update_highlight():
	if is_mining:
		highlight_valid = false
		return

	# Find which tile the player is currently occupying
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	# Check adjacent tiles in priority order:
	#   1. The block directly in front (facing direction)
	#   2. The block below (digging down)
	#   3. The block behind
	#   4. The block above
	var candidates = [
		player_tile + Vector2i(facing_dir, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(-facing_dir, 0),
		player_tile + Vector2i(0, -1),
	]

	for tile in candidates:
		if tilemap.get_cell_source_id(tile) != -1:
			highlighted_tile = tile
			highlight_valid = true
			return

	highlight_valid = false

func _draw():
	# Yellow hover highlight (when not mining)
	if highlight_valid:
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(highlighted_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 0.25), true)
		draw_rect(rect, Color(1.0, 1.0, 0.0, 0.9), false, 2.0)

	# Orange highlight + progress bar on the block currently being mined
	if is_mining:
		var progress = 1.0 - (mining_timer.time_left / mine_time)
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0

		# Orange border to mark the block being broken
		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.3), true)
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.9), false, 2.0)

		# Progress bar drawn above the block
		var bar_w = TILE_WORLD_SIZE
		var bar_h = 6.0
		var bar_pos = tile_center_local - Vector2(bar_w / 2.0, half + bar_h + 4.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.15, 0.15, 0.85), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * progress, bar_h)), Color(0.2, 0.85, 0.2, 0.9), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.5), false, 1.0)

func start_mining(tile_coords: Vector2i):
	is_mining = true
	target_tile_coords = tile_coords
	mining_timer.start(mine_time)
	await mining_timer.timeout
	finish_mining()

func die_and_respawn():
	# Cancel any in-progress mining
	if is_mining:
		mining_timer.stop()
		is_mining = false

	# Reset stats — cargo is lost as a death penalty
	current_battery = max_battery
	current_cargo = 0

	# Teleport back to spawn
	global_position = spawn_position
	velocity = Vector2.ZERO
	print("Player died! Respawning at ", spawn_position)

func finish_mining():
	# Get tile data before destroying it to check for ores
	var tile_data = tilemap.get_cell_tile_data(target_tile_coords)
	if tile_data:
		var is_ore = tile_data.get_custom_data("is_ore")
		if is_ore and current_cargo < max_cargo:
			current_cargo += 1
			print("Ore collected! Cargo: ", current_cargo, "/", max_cargo)

	# Destroy the tile
	tilemap.set_cell(target_tile_coords, -1)
	is_mining = false
