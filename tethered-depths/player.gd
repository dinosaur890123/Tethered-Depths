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
@onready var tilemap: TileMapLayer = get_parent().get_node("TileMapLayer")
var is_mining: bool = false
var target_tile_coords: Vector2i
var spawn_position: Vector2

# Max distance (in world pixels) the player can reach to mine a block
var mine_range: float = 200.0

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

	# 4. Horizontal movement
	if not is_mining:
		velocity.x = Input.get_axis("ui_left", "ui_right") * speed
	else:
		velocity.x = 0.0

	move_and_slide()

	# 5. Mine the block under the mouse cursor when spacebar is pressed
	if not is_mining and Input.is_action_just_pressed("mine"):
		var mouse_global = get_global_mouse_position()
		var hovered_tile = tilemap.local_to_map(tilemap.to_local(mouse_global))
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(hovered_tile))
		var dist = global_position.distance_to(tile_center_global)
		if dist <= mine_range and tilemap.get_cell_source_id(hovered_tile) != -1:
			start_mining(hovered_tile)

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
