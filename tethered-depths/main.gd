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
			elif y < 50:
				# Near-surface: dirt 75%, cobble 25%
				source_id = TILE_COBBLE if roll < 0.25 else TILE_DIRT
			else:
				# y=50→200: linear transition to dirt 50%, cobble 35%, deepslate 15%
				# y>200: constant at those final ratios
				var t = clamp(float(y - 50) / 150.0, 0.0, 1.0)
				var deep_c = lerp(0.0, 0.15, t)
				var cobble_c = lerp(0.25, 0.35, t)
				if roll < deep_c:
					source_id = TILE_DEEPSLATE
				elif roll < deep_c + cobble_c:
					source_id = TILE_COBBLE
				else:
					source_id = TILE_DIRT

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

	# 2. House / Shop / Trader — snap bottoms to the grass surface (keep editor-set X)
	var shop := get_node_or_null("Shop")
	if shop is Node2D:
		_align_node_bottom_to_surface(shop as Node2D, surface_y)

	var house := get_node_or_null("House")
	if house is Node2D:
		_align_node_bottom_to_surface(house as Node2D, surface_y)

	var trader := get_node_or_null("Trader")
	if trader is Node2D:
		_align_node_bottom_to_surface(trader as Node2D, surface_y)

	# 3. Signs — snap bottoms to the grass surface (keep editor-set X)
	var sign_paths := ["Signtutorial", "Shopsign", "Signprice"]
	for p in sign_paths:
		var s_node := get_node_or_null(p)
		if s_node is Node2D:
			_align_node_bottom_to_surface(s_node as Node2D, surface_y)

	# 4. Trees — snap bottoms to the grass surface (keep editor-set X)
	var tree_paths := ["Trees/Tree1", "Trees/Tree2", "Tree3", "Tree4"]
	for p in tree_paths:
		var tree := get_node_or_null(p)
		if tree is Node2D:
			_align_node_bottom_to_surface(tree as Node2D, surface_y)

	# 5. Cobblestone backgrounds — align top edge exactly to the grass surface
	var bg_under = get_node_or_null("Background Under")
	if bg_under:
		for bg in bg_under.get_children():
			if not (bg is Sprite2D) or not bg.texture: continue
			var rect = bg.get_rect()
			var top_global_y = bg.to_global(Vector2(0.0, rect.position.y)).y
			bg.global_position.y += surface_y - top_global_y

# Keep editor-authored X/Y layout and only adjust Y to match the surface.
# We avoid magic offsets by computing bounds from Sprite2D descendants.
func _subtree_bottom_global_y(root: Node) -> float:
	var bottom := -INF
	if root is Sprite2D:
		var s := root as Sprite2D
		if s.texture:
			var rect := s.get_rect()
			bottom = max(bottom, s.to_global(Vector2(0.0, rect.end.y)).y)
	for child in root.get_children():
		bottom = max(bottom, _subtree_bottom_global_y(child))
	return bottom

func _align_node_bottom_to_surface(n: Node2D, surface_y: float) -> void:
	var bottom := _subtree_bottom_global_y(n)
	if bottom == -INF:
		return
	n.global_position.y += surface_y - bottom

# Helper to find nodes that might be nested
func find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name: return root
	for child in root.get_children():
		var found = find_node_by_name(child, node_name)
		if found: return found
	return null
