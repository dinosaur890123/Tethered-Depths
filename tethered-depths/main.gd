extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

# TileSet source IDs
const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4

# World parameters
const WIDTH = 120
const DEPTH = 350
const SURFACE_Y = 0

func _ready():
	randomize()
	generate_world()
	# Wait one physics frame so the TileMapLayer's collision shapes are registered
	# before placing the player — prevents the Camera2D from jumping on startup
	await get_tree().physics_frame
	position_entities()

func generate_world():
	tilemap.clear()
	print("Generating world...")

	for x in range(-WIDTH/2, WIDTH/2):
		for y in range(SURFACE_Y, DEPTH):
			var cell_pos = Vector2i(x, y)
			var roll = randf()
			var source_id := TILE_DIRT

			# Layering
			if y == SURFACE_Y:
				source_id = TILE_GRASS
			elif y < 5:
				source_id = TILE_DIRT
			elif y < 25:
				source_id = TILE_COBBLE if roll < 0.35 else TILE_DIRT
			elif y < 40:
				source_id = TILE_DEEPSLATE if roll < 0.4375 else TILE_COBBLE
			else: # 40+ Deep Core
				source_id = TILE_DEEPSLATE

			# Tile variety (flips) — only for regular tiles
			var alt_tile = 0
			if source_id in [TILE_DIRT, TILE_COBBLE, TILE_DEEPSLATE]:
				if randf() < 0.5: alt_tile |= TileSetAtlasSource.TRANSFORM_FLIP_H
				if randf() < 0.5: alt_tile |= TileSetAtlasSource.TRANSFORM_FLIP_V

			tilemap.set_cell(cell_pos, source_id, Vector2i(0, 0), alt_tile)

func position_entities():
	var surface_pos_local = tilemap.map_to_local(Vector2i(0, SURFACE_Y))
	var global_center = tilemap.to_global(surface_pos_local)
	var tile_h_world = (128.0 * tilemap.scale.y * self.scale.y)
	var surface_y = global_center.y - (tile_h_world / 2.0)

	# 1. Player — spawn on the surface
	var player = get_node_or_null("Player")
	if player:
		player.global_position = Vector2(0, surface_y - (32.0 * self.scale.y))
		if "spawn_position" in player:
			player.spawn_position = player.global_position

	# 2. Cobblestone backgrounds — align top edge to the grass surface
	var bg_under = get_node_or_null("Background Under")
	if bg_under:
		for bg in bg_under.get_children():
			if bg is Sprite2D and bg.texture:
				var h = bg.texture.get_size().y * bg.scale.y * self.scale.y
				bg.global_position = Vector2(bg.global_position.x, surface_y + h / 2.0)

# Helper to find nodes that might be nested
func find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name: return root
	for child in root.get_children():
		var found = find_node_by_name(child, node_name)
		if found: return found
	return null
