extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

# TileSet source IDs
const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4
const TILE_COPPER_NODE := 5
const TILE_SILVER_NODE := 6
const TILE_GOLD_NODE := 7

# World parameters
const WIDTH = 120
const DEPTH = 250
const SURFACE_Y = 0

# Noise parameters for variety
var patch_noise = FastNoiseLite.new()

func _ready():
	randomize()
	patch_noise.seed = randi()
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	patch_noise.frequency = 0.08
	
	generate_world()
	position_entities()

func generate_world():
	tilemap.clear()
	print("Generating world with rich deep core...")
	
	for x in range(-WIDTH/2, WIDTH/2):
		for y in range(SURFACE_Y, DEPTH):
			var cell_pos = Vector2i(x, y)
			var roll = randf()
			var source_id := TILE_DIRT
			
			# 1. Surface
			if y == SURFACE_Y:
				source_id = TILE_GRASS
			
			# 2. Dirt to Stone Transition (y = 1 to 40)
			elif y < 40:
				# Base probability of stone increases with depth
				var stone_chance = lerp(0.15, 0.85, float(y) / 40.0)
				var deep_chance = lerp(0.0, 0.4, float(max(0, y - 15)) / 25.0)
				
				if roll < stone_chance:
					source_id = TILE_DEEPSLATE if (randf() < deep_chance) else TILE_COBBLE
				else:
					source_id = TILE_DIRT
				
				# Occasional Copper/Silver in mid layers
				var ore_roll = randf()
				if y > 10 and ore_roll < 0.08:
					source_id = TILE_COPPER_NODE if ore_roll < 0.05 else TILE_SILVER_NODE

			# 3. Gold Deep Core (y = 40+) - Gold takes up the space
			else:
				var deep_roll = randf()
				if deep_roll < 0.55: # 55% chance for Gold
					source_id = TILE_GOLD_NODE
				elif deep_roll < 0.80: # 25% chance for Silver
					source_id = TILE_SILVER_NODE
				elif deep_roll < 0.95: # 15% chance for Deepslate
					source_id = TILE_DEEPSLATE
				else: # 5% chance for Cobble
					source_id = TILE_COBBLE

			# 4. Final Polish (Random Flips)
			var alt_tile = 0
			if source_id in [TILE_DIRT, TILE_COBBLE, TILE_DEEPSLATE]:
				if randf() < 0.5: alt_tile |= TileSetAtlasSource.TRANSFORM_FLIP_H
				if randf() < 0.5: alt_tile |= TileSetAtlasSource.TRANSFORM_FLIP_V

			tilemap.set_cell(cell_pos, source_id, Vector2i(0, 0), alt_tile)

func position_entities():
	# Get world surface Y (top of grass)
	# TileMapLayer is scale 0.5, Main is scale 1.4. Tile size 128.
	# Effective height = 128 * 0.5 * 1.4 = 89.6
	var surface_pos_local = tilemap.map_to_local(Vector2i(0, SURFACE_Y))
	var tile_h_world = (128.0 * tilemap.scale.y * self.scale.y)
	var surface_y = tilemap.to_global(surface_pos_local).y - (tile_h_world / 2.0)

	# 1. Player
	var player = get_node_or_null("Player")
	if player:
		# Player origin is center, height ~46. Place feet on surface.
		player.global_position = Vector2(0, surface_y - 40)
		if "spawn_position" in player:
			player.spawn_position = player.global_position
			
	# 2. Shop & Trader (Origins are at bases)
	var shop = get_node_or_null("Shop")
	if shop:
		shop.global_position = Vector2(450, surface_y)

	var trader = get_node_or_null("Trader")
	if trader:
		trader.global_position = Vector2(650, surface_y)

	# 3. Trees
	var trees_node = get_node_or_null("Trees")
	if trees_node:
		var tx = [-1100, -700, 1100, 1500]
		var i = 0
		for tree in trees_node.get_children():
			if tree is Sprite2D:
				var h = tree.texture.get_size().y * tree.scale.y * self.scale.y
				# Sprite2D origin center: subtract half height to sit on surface
				tree.global_position = Vector2(tx[i % tx.size()], surface_y - (h/2.0) + 10)
				i += 1

	# 4. Signs
	var signs = {"Signtutorial": -250, "Shopsign": 380, "Signprice": 850}
	for s_name in signs:
		var s_node = get_node_or_null(s_name)
		if s_node:
			var h = s_node.texture.get_size().y * s_node.scale.y * self.scale.y
			s_node.global_position = Vector2(signs[s_name], surface_y - (h/2.0))
