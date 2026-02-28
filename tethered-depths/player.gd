extends CharacterBody2D

# Stats (Upgradable!)
var speed: float = 150.0
var mine_time: float = 1.0 
var max_battery: float = 100.0
var current_battery: float = 100.0
var max_cargo: int = 10
var current_cargo: int = 0

@onready var mining_timer = $MiningTimer
var is_mining: bool = false
var target_tile_coords: Vector2i

func _physics_process(delta):
	# 1. Drain Battery
	current_battery -= delta * 2.0 # Drains 2 units per second
	if current_battery <= 0:
		die_and_respawn()

	# 2. Movement
	var direction = Vector2.ZERO
	if not is_mining:
		direction.x = Input.get_axis("ui_left", "ui_right")
		direction.y = Input.get_axis("ui_up", "ui_down")
	
	velocity = direction * speed
	var collision = move_and_collide(velocity * delta)

	# 3. Detect Mining
	if collision and not is_mining:
		var collider = collision.get_collider()
		if collider is TileMapLayer:
			start_mining(collision, collider)

func start_mining(collision: KinematicCollision2D, tilemap: TileMapLayer):
	is_mining = true
	# Calculate which tile we hit by pushing slightly into the normal
	var hit_pos = collision.get_position() - collision.get_normal() * 5
	target_tile_coords = tilemap.local_to_map(hit_pos)
	
	# Check if there is actually a tile there
	if tilemap.get_cell_source_id(target_tile_coords) != -1:
		mining_timer.start(mine_time)
		await mining_timer.timeout
		finish_mining(tilemap)
	else:
		is_mining = false

func finish_mining(tilemap: TileMapLayer):
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
