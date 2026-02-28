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

func _ready():
	randomize()
	generate_world()
	position_entities()

func generate_world():
	tilemap.clear()
	print("Generating world with requested RNG layers...")
	
	for x in range(-WIDTH/2, WIDTH/2):
		for y in range(SURFACE_Y, DEPTH):
			var cell_pos = Vector2i(x, y)
			var roll = randf()
			var source_id := TILE_DIRT
			
			# 1. Layering
			if y == SURFACE_Y:
				source_id = TILE_GRASS
			elif y < 5:
				source_id = TILE_DIRT
			elif y < 25: # Next 20 layers (5 to 24)
				# Lowered Cobblestone RNG (0.7 -> 0.35)
				source_id = TILE_COBBLE if roll < 0.35 else TILE_DIRT
			elif y < 40: # Next 15 layers (25 to 39)
				# Deepslate starts taking over, lowered Cobblestone RNG (0.25 -> 0.125)
				source_id = TILE_DEEPSLATE if roll < 0.875 else TILE_COBBLE
			else: # 40+ Gold Deep Core
				var deep_roll = randf()
				if deep_roll < 0.60: # 60% chance for Gold (Takes up most space)
					source_id = TILE_GOLD_NODE
				elif deep_roll < 0.85: # 25% chance for Silver
					source_id = TILE_SILVER_NODE
				else: # 15% Deepslate/Stone
					source_id = TILE_DEEPSLATE

			# 2. Occasional Copper in mid layers
			if y > 5 and y < 40 and source_id in [TILE_DIRT, TILE_COBBLE] and randf() < 0.05:
				source_id = TILE_COPPER_NODE

			# 3. Tile variety (flips)
			var alt_tile = 0
			if source_id in [TILE_DIRT, TILE_COBBLE, TILE_DEEPSLATE]:
				if randf() < 0.5: alt_tile |= TileSetAtlasSource.TRANSFORM_FLIP_H
				if randf() < 0.5: alt_tile |= TileSetAtlasSource.TRANSFORM_FLIP_V

			tilemap.set_cell(cell_pos, source_id, Vector2i(0, 0), alt_tile)

func position_entities():
	# Calculate exact world Y for the surface (top edge of grass)
	# TileMapLayer scale is 0.5, Main scale is 1.4. Tile size 128.
	var surface_pos_local = tilemap.map_to_local(Vector2i(0, SURFACE_Y))
	var global_center = tilemap.to_global(surface_pos_local)
	var tile_h_world = (128.0 * tilemap.scale.y * self.scale.y)
	var surface_y = global_center.y - (tile_h_world / 2.0)

	# 1. Player (Bottom at surface)
	var player = get_node_or_null("Player")
	if player:
		player.global_position = Vector2(0, surface_y - (32.0 * self.scale.y))
		if "spawn_position" in player:
			player.spawn_position = player.global_position
			
	# 2. Shop & Trader (Adjusted offsets to be above ground)
	var shop = get_node_or_null("Shop")
	if shop:
		# Shop visual bottom is ~55 pixels below origin in its local space
		shop.global_position = Vector2(450, surface_y - (55.0 * self.scale.y))

	var trader = get_node_or_null("Trader")
	if trader:
		# Trader visual bottom is ~34 pixels below origin in its local space
		trader.global_position = Vector2(650, surface_y - (34.0 * self.scale.y))

	# 3. Trees (Position them on top of the surface)
	var tree_nodes = ["Tree1", "Tree2", "Tree3", "Tree4"]
	var tx = [-1200, -800, 1100, 1500]
	for i in range(tree_nodes.size()):
		var tree = find_node_by_name(self, tree_nodes[i])
		if tree and tree is Sprite2D:
			var h = tree.texture.get_size().y * tree.scale.y * self.scale.y
			tree.global_position = Vector2(tx[i], surface_y - (h/2.0))

	# 4. Signs (Bottom at surface)
	var signs = {"Signtutorial": -250, "Shopsign": 380, "Signprice": 850}
	for s_name in signs:
		var s_node = get_node_or_null(s_name)
		if s_node:
			var h = s_node.texture.get_size().y * s_node.scale.y * self.scale.y
			s_node.global_position = Vector2(signs[s_name], surface_y - (h/2.0))

# Helper to find nodes that might be nested
func find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name: return root
	for child in root.get_children():
		var found = find_node_by_name(child, node_name)
		if found: return found
	return null
