extends CharacterBody2D

# Stats (Upgradable!)
var speed: float = 300.0
var jump_speed: float = 400.0
var climb_speed: float = 150.0
var gravity: float = 980.0
var mine_time: float = 1.0
var max_battery: float = 100.0
var current_battery: float = 100.0
var max_cargo: int = 10
var current_cargo: int = 0

@onready var mining_timer = $MiningTimer
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
var tilemap: TileMapLayer
var money_label: Label
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

# Ore table: [name, 1-in-N drop chance, value per ore]
# Adjust values to match your spreadsheet
const ORE_TABLE = [
	["Stone",  2,  2  ],
	["Copper", 10, 15 ],
	["Silver", 25, 50 ],
	["Gold",   50, 200],
]

func _ready():
	spawn_position = global_position
	tilemap = get_parent().get_node("Dirt") as TileMapLayer
	money_label = get_parent().get_node("HUD/MoneyLabel") as Label
	money_label.text = "$0"
	mining_timer.timeout.connect(finish_mining)
	add_to_group("player")
	# Draw above the tilemap so highlights aren't buried under adjacent tiles
	z_index = 1

func _physics_process(delta):
	# 1. Drain Battery
	current_battery -= delta * 2.0
	if current_battery <= 0:
		die_and_respawn()

	# 2. Horizontal input — read early so wall-climb detection can use it
	var h = Input.get_axis("Left", "Right")
	is_walking = h != 0
	if h != 0:
		facing_dir = sign(h)

	# 3. Wall climbing: player presses into a wall while not grounded
	var wall_normal = get_wall_normal()
	is_wall_climbing = (
		is_on_wall()
		and h != 0
		and wall_normal != Vector2.ZERO
		and sign(h) == -sign(wall_normal.x)
	)

	# 4. Gravity — suppressed while clinging to a wall
	if not is_on_floor() and not is_wall_climbing:
		velocity.y += gravity * delta

	# 5. Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = -jump_speed

	# 6. Velocity — climb upward when on wall, otherwise normal horizontal
	velocity.x = h * speed
	if is_wall_climbing:
		velocity.y = -climb_speed

	move_and_slide()

	# Cancel mining if the player has walked a tile away from the target block.
	# Skip the check while airborne — jumping shouldn't interrupt mining.
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

	# 7. Find the adjacent block under the mouse cursor
	_update_highlight()
	_update_animation()
	queue_redraw()

	# 8. Mouse-based mining: hold left mouse button over an adjacent block to mine it
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if highlight_valid and not is_mining:
			start_mining(highlighted_tile)
	else:
		# Mouse released — cancel and reset mining progress
		if is_mining:
			cancel_mining()

func _update_highlight():
	if is_mining:
		# Keep showing the block being mined; don't recalculate
		return

	# Convert mouse position to tile coordinates
	var mouse_world_pos = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world_pos))

	# Find which tile the player occupies
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	# Only allow mining tiles directly adjacent to the player
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
	# Determine target animation using StringName to match Godot's internal type
	var target_anim: StringName
	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		target_anim = &"mine_down" if target_tile_coords.y > player_tile.y else &"mine_right"
	elif is_wall_climbing:
		target_anim = &"climb"
	elif is_walking:
		target_anim = &"walk"
	else:
		target_anim = &"idle"

	# Flip: when mining use target tile position, otherwise use movement direction
	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		anim_sprite.flip_h = target_tile_coords.x < player_tile.x
	else:
		anim_sprite.flip_h = facing_dir == -1

	# Only switch animation when it actually changes — prevents frame resets
	if anim_sprite.animation != target_anim:
		anim_sprite.play(target_anim)

func _draw():
	# Yellow hover highlight (when not mining)
	if highlight_valid and not is_mining:
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(highlighted_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 0.45), true)
		draw_rect(rect, Color(1.0, 0.85, 0.0, 1.0), false, 3.0)

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

func cancel_mining():
	mining_timer.stop()
	is_mining = false

func die_and_respawn():
	anim_sprite.play("death")
	# Cancel any in-progress mining
	if is_mining:
		cancel_mining()

	# Reset stats — cargo is lost as a death penalty
	current_battery = max_battery
	current_cargo = 0

	# Teleport back to spawn
	global_position = spawn_position
	velocity = Vector2.ZERO
	print("Player died! Respawning at ", spawn_position)

# Cascading count roll: always get 1, then 1-in-2 for a 2nd, 1-in-3 for a 3rd, etc.
func _roll_count() -> int:
	var count = 1
	var n = 2
	while n <= 10 and randi() % n == 0:
		count += 1
		n += 1
	return count

func finish_mining():
	# Destroy the tile
	tilemap.set_cell(target_tile_coords, -1)
	is_mining = false

	# Roll each ore type independently
	var summary: Array[String] = []
	for ore in ORE_TABLE:
		var ore_name: String = ore[0]
		var chance: int     = ore[1]
		var value: int      = ore[2]

		if randi() % chance == 0:
			var rolled = _roll_count()
			# Clamp to remaining cargo space
			var space = max_cargo - current_cargo
			if space <= 0:
				break
			var amount = min(rolled, space)
			current_cargo += amount
			var earned = amount * value
			money += earned
			summary.append("%dx %s ($%d)" % [amount, ore_name, earned])

	if summary.size() > 0:
		money_label.text = "$" + str(money)
		print("Mined: ", ", ".join(summary), " | Cargo: ", current_cargo, "/", max_cargo)
	else:
		print("Nothing found. Cargo: ", current_cargo, "/", max_cargo)
