extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4

const WIDTH = 120
const DEPTH = 350
const SURFACE_Y = 0

func _ready():
	randomize()
	generate_world()
	await get_tree().physics_frame
	position_entities()

func generate_world():
	tilemap.clear()
	print("Generating world...")
	var half_w: int = WIDTH >> 1
	var skip_tiles := {}
	for x in range(-half_w, half_w):
		for y in range(SURFACE_Y, DEPTH):
			var cell_pos = Vector2i(x, y)
			
			# 5% chance for an air pocket (at least 2 adjacent blocks missing)
			# Only below the surface grass
			if y > SURFACE_Y and not cell_pos in skip_tiles:
				if randf() < 0.05:
					skip_tiles[cell_pos] = true
					# Also skip one neighbor (down or right)
					if randf() < 0.5:
						skip_tiles[Vector2i(x + 1, y)] = true
					else:
						skip_tiles[Vector2i(x, y + 1)] = true
					continue
			
			if cell_pos in skip_tiles:
				continue
				
			var roll = randf()
			var source_id := TILE_DIRT

			if y == SURFACE_Y:
				source_id = TILE_GRASS
			elif y < 50:
				source_id = TILE_COBBLE if roll < 0.25 else TILE_DIRT
			else:
				var t = clamp(float(y - 50) / 150.0, 0.0, 1.0)
				var deep_c = lerp(0.0, 0.15, t)
				var cobble_c = lerp(0.25, 0.35, t)
				if roll < deep_c:
					source_id = TILE_DEEPSLATE
				elif roll < deep_c + cobble_c:
					source_id = TILE_COBBLE
				else:
					source_id = TILE_DIRT

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


	var player = get_node_or_null("Player")
	if player:
		player.global_position = Vector2(0, surface_y - (32.0 * self.scale.y))
		if "spawn_position" in player:
			player.spawn_position = player.global_position

	var shop := get_node_or_null("Shop")
	if shop is Node2D:
		_align_node_bottom_to_surface(shop as Node2D, surface_y)

	var house := get_node_or_null("House")
	if house is Node2D:
		_align_node_bottom_to_surface(house as Node2D, surface_y)

	var trader := get_node_or_null("Trader")
	if trader is Node2D:
		_align_node_bottom_to_surface(trader as Node2D, surface_y)

	var sign_paths := ["Signtutorial", "Shopsign", "Signprice"]
	for p in sign_paths:
		var s_node := get_node_or_null(p)
		if s_node is Node2D:
			_align_node_bottom_to_surface(s_node as Node2D, surface_y)

	var tree_paths := ["Trees/Tree1", "Trees/Tree2", "Trees/Tree3", "Trees/Tree4", "Trees/Tree5", "Trees/Tree6", "Trees/Tree7", "Trees/Tree8", "Trees/Tree9", "Trees/Tree10", "Trees/Tree11"]
	for p in tree_paths:
		var tree := get_node_or_null(p)
		if tree is Node2D:
			_align_node_bottom_to_surface(tree as Node2D, surface_y)

	# 5. Sky backgrounds — align bottom edge exactly to the grass surface
	var bg_above = get_node_or_null("Background above")
	if bg_above:
		for bg in bg_above.get_children():
			if not (bg is Sprite2D) or not bg.texture: continue
			var rect = bg.get_rect()
			var bottom_global_y = bg.to_global(Vector2(0.0, rect.end.y)).y
			bg.global_position.y += surface_y - bottom_global_y

	# 6. Cobblestone backgrounds — Tile to cover the entire depth and width
	var bg_under = get_node_or_null("Background Under")
	if bg_under:
		var bg_tex = load("res://stonewallbackground.png")
		if bg_tex:
			# Clear old ones
			for child in bg_under.get_children():
				child.queue_free()
			
			var bg_scale = 0.35
			var scaled_size = bg_tex.get_size() * bg_scale
			
			# Width covers -WIDTH/2 to WIDTH/2 tiles (tile size 64px)
			var world_width = WIDTH * 64.0
			var world_height = DEPTH * 64.0
			
			var start_x = -world_width / 2.0 - scaled_size.x
			var end_x = world_width / 2.0 + scaled_size.x
			var start_y = surface_y
			var end_y = surface_y + world_height + scaled_size.y
			
			var x = start_x
			while x < end_x:
				var y = start_y
				while y < end_y:
					var bg = Sprite2D.new()
					bg.texture = bg_tex
					bg.scale = Vector2(bg_scale, bg_scale)
					bg.z_index = -34
					bg.centered = false
					bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					# Use floor and a 1px overlap to prevent sub-pixel seams
					bg.global_position = Vector2(floor(x), floor(y))
					bg_under.add_child(bg)
					y += scaled_size.y - 1.0
				x += scaled_size.x - 1.0

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


func find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name: return root
	for child in root.get_children():
		var found = find_node_by_name(child, node_name)
		if found: return found
	return null
