extends Node2D

func _ready():
	var tilemap := $TileMapLayer
	var used := tilemap.get_used_cells()
	if used.is_empty():
		return

	var min_x := used[0].x
	var max_x := used[0].x
	var min_y := used[0].y
	var max_y := used[0].y

	for cell in used:
		min_x = min(min_x, cell.x)
		max_x = max(max_x, cell.x)
		min_y = min(min_y, cell.y)
		max_y = max(max_y, cell.y)

	var width  := max_x - min_x + 1
	var height := max_y - min_y + 1

	# Sample the tile type from an existing cell
	var src_id    := tilemap.get_cell_source_id(used[0])
	var atlas_coords := tilemap.get_cell_atlas_coords(used[0])

	# Extend 5x to the left, right, and downward
	var new_min_x := min_x - width * 5
	var new_max_x := max_x + width * 5
	var new_max_y := max_y + height * 5

	for x in range(new_min_x, new_max_x + 1):
		for y in range(min_y, new_max_y + 1):
			if tilemap.get_cell_source_id(Vector2i(x, y)) == -1:
				tilemap.set_cell(Vector2i(x, y), src_id, atlas_coords)
