extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

# TileSet source IDs (must match `main.tscn` TileSet sources/*)
const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_ORE_GENERIC := 2
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4
const TILE_COPPER_NODE := 5
const TILE_SILVER_NODE := 6
const TILE_GOLD_NODE := 7

# World parameters
const WIDTH = 100
const DEPTH = 200
const SURFACE_Y = 0

# Noise parameters for caves
var cave_noise = FastNoiseLite.new()
# Noise parameters for ore/stone patches
var patch_noise = FastNoiseLite.new()
# Noise for ore veins
var ore_noise = FastNoiseLite.new()

func _ready():
	randomize()
	setup_noise()
	generate_world()
	position_entities()

func setup_noise():
	# Configure cave noise (Perlin-like for organic caves)
	cave_noise.seed = randi()
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise.frequency = 0.10
	
	# Configure patch noise for stone/ore distribution
	patch_noise.seed = randi()
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	patch_noise.frequency = 0.05

	# Configure ore noise to form chunky veins/pockets
	ore_noise.seed = randi()
	ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ore_noise.frequency = 0.085

func generate_world():
	tilemap.clear()
	
	print("Starting world generation...")
	var generated_count = 0
	
	for x in range(-WIDTH/2, WIDTH/2):
		for y in range(SURFACE_Y, DEPTH):
			var cell_pos = Vector2i(x, y)
			
			# 1. Caves (skip top few layers so the surface stays stable)
			if y > SURFACE_Y + 4:
				var cave_val := cave_noise.get_noise_2d(float(x), float(y))
				# More caves deeper down
				var depth_t := float(y - SURFACE_Y) / float(DEPTH)
				var cave_threshold := 0.28 - (depth_t * 0.18)
				if cave_val > cave_threshold:
					continue

			# 2. Base material by depth + patch noise
			var source_id := TILE_DIRT
			if y == SURFACE_Y:
				source_id = TILE_GRASS
			else:
				var patch_val := patch_noise.get_noise_2d(float(x), float(y)) # -1..1
				var deep_line := int(DEPTH * 0.65)
				var mid_line := int(DEPTH * 0.35)

				if y <= SURFACE_Y + 10:
					# Mostly dirt with occasional stones
					source_id = TILE_COBBLE if patch_val > 0.60 else TILE_DIRT
				elif y < mid_line:
					# Stone band: mostly cobble, with dirt pockets
					source_id = TILE_DIRT if patch_val < -0.35 else TILE_COBBLE
				elif y < deep_line:
					# Transition: cobble → deepslate
					source_id = TILE_DEEPSLATE if patch_val > 0.10 else TILE_COBBLE
				else:
					# Deep: mostly deepslate, with some cobble pockets
					source_id = TILE_COBBLE if patch_val < -0.25 else TILE_DEEPSLATE

			# 3. Ores (only embedded in stone-like blocks)
			if y > SURFACE_Y + 12 and (source_id == TILE_COBBLE or source_id == TILE_DEEPSLATE):
				var ore_val := ore_noise.get_noise_2d(float(x) * 1.3, float(y) * 1.3)
				var roll := randf()
				# Copper: common in upper/mid depths
				if y < int(DEPTH * 0.55) and ore_val > 0.62 and roll < 0.08:
					source_id = TILE_COPPER_NODE
				# Silver: mid/deeper
				elif y >= int(DEPTH * 0.35) and ore_val > 0.68 and roll < 0.05:
					source_id = TILE_SILVER_NODE
				# Gold: deep and rarer
				elif y >= int(DEPTH * 0.65) and ore_val > 0.74 and roll < 0.03:
					source_id = TILE_GOLD_NODE

			# 4. Set the cell
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
