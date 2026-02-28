extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

# World parameters
const WIDTH = 100
const DEPTH = 200
const SURFACE_Y = 0

# Noise parameters for caves
var cave_noise = FastNoiseLite.new()
# Noise parameters for ore/stone patches
var patch_noise = FastNoiseLite.new()

func _ready():
	randomize()
	setup_noise()
	generate_world()
	position_entities()

func setup_noise():
	# Configure cave noise (Perlin-like for organic caves)
	cave_noise.seed = randi()
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise.frequency = 0.1
	
	# Configure patch noise for stone/ore distribution
	patch_noise.seed = randi()
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	patch_noise.frequency = 0.05

func generate_world():
	tilemap.clear()
	
	print("Starting world generation...")
	var generated_count = 0
	
	for x in range(-WIDTH/2, WIDTH/2):
		for y in range(SURFACE_Y, DEPTH):
			var cell_pos = Vector2i(x, y)
			
			# 1. Check for caves (exclude top layer for stability)
			if y > SURFACE_Y + 2:
				var cave_val = cave_noise.get_noise_2d(x, y)
				if cave_val > 0.2: # Threshold for caves
					continue # It's a cave, leave it empty
			
			# 2. Determine tile type
			var source_id = 0 # Default: Dirt
			
			if y == SURFACE_Y:
				source_id = 1 # Grass
			else:
				# Use patch noise to decide between Dirt and Cobblestone
				var patch_val = patch_noise.get_noise_2d(x, y)
				
				# Increase stone probability with depth
				var depth_factor = float(y - SURFACE_Y) / DEPTH
				var stone_threshold = 0.3 - (depth_factor * 0.5) # Decreasing threshold = more stone
				
				if patch_val > stone_threshold:
					source_id = 3 # Cobblestone
				else:
					source_id = 0 # Dirt
			
			# 3. Set the cell
			tilemap.set_cell(cell_pos, source_id, Vector2i(0, 0))
			generated_count += 1
			
	print("World generation complete. Total tiles: ", generated_count)

func position_entities():
	# Position player at surface
	var player = get_node_or_null("Player")
	if player:
		# map_to_local returns center of tile in tilemap's local space.
		var surface_pos = tilemap.map_to_local(Vector2i(0, SURFACE_Y))
		# Subtract half tile size to get to the top edge
		surface_pos.y -= tilemap.tile_set.tile_size.y / 2.0
		player.global_position = tilemap.to_global(surface_pos)
		
		if "spawn_position" in player:
			player.spawn_position = player.global_position
			
	# Position Shop at surface, a bit to the right
	var shop = get_node_or_null("Shop")
	if shop:
		var shop_pos = tilemap.map_to_local(Vector2i(5, SURFACE_Y))
		shop_pos.y -= tilemap.tile_set.tile_size.y / 2.0
		shop.global_position = tilemap.to_global(shop_pos)
