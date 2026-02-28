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
var is_mining: bool = false
var target_tile_coords: Vector2i
var spawn_position: Vector2

func _ready():
	spawn_position = global_position

func _physics_process(delta):
	# 1. Drain Battery
	current_battery -= delta * 2.0 # Drains 2 units per second
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

	# 5. Detect mining from wall collisions (not floor/ceiling)
	if not is_mining:
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			if collision.get_collider() is TileMapLayer:
				if abs(collision.get_normal().x) > abs(collision.get_normal().y):
					start_mining(collision, collision.get_collider())
					break

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
