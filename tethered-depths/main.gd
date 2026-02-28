extends Node2D

func _ready():
	var tilemap := $TileMapLayer
	# For Godot 4.x, use get_used_cells(0) or get_used_cells_by_id if needed
	var used: Array = tilemap.get_used_cells()
	if used.size() == 0:
		return

	var min_x = used[0].x
	var max_x = used[0].x
	var min_y = used[0].y
	var max_y = used[0].y

	for cell in used:
		min_x = min(min_x, cell.x)
		max_x = max(max_x, cell.x)
		min_y = min(min_y, cell.y)
		max_y = max(max_y, cell.y)

	var width = max_x - min_x + 1
	var height = max_y - min_y + 1

	# Sample the tile type from an existing cell
	var src_id = tilemap.get_cell_source_id(used[0])
	var atlas_coords = tilemap.get_cell_atlas_coords(used[0])

	# Extend 5x to the left, right, and downward
	var new_min_x = min_x - width * 5
	var new_max_x = max_x + width * 5
	var new_max_y = max_y + height * 5
	
	print("World Generation Stats:")
	print("min_y: ", min_y, " max_y: ", max_y)
	var generated = 0
	var overwrote = 0

	for x in range(new_min_x, new_max_x + 1):
		for y in range(min_y, new_max_y + 1):
			var cell_pos = Vector2i(x, y)
			
			# We want to randomize both empty cells AND existing cells below the top layer
			if tilemap.get_cell_source_id(cell_pos) == -1 or y > min_y:
				if tilemap.get_cell_source_id(cell_pos) == -1:
					generated += 1
				else:
					overwrote += 1
					
				var chosen_src_id = 0 # Default to dirt (0)
				
				# Gradually increase the chance of cobblestone (3) the deeper we go
				if y > min_y:
					var depth = float(y - min_y)
					# At depth 1, 5% chance. At depth 20+, 80% chance
					var cobble_chance = min(depth * 0.04, 0.8) 
					if randf() < cobble_chance:
						chosen_src_id = 3
				else:
					# If it's the very top layer, we want it to remain grass/dirt
					# Check if it was empty, if so make it grass (1) or dirt (0) based on your preference
					# We will just use the original src_id for the top layer
					chosen_src_id = src_id
				
				tilemap.set_cell(cell_pos, chosen_src_id, Vector2i(0, 0))
				
	print("Generated: ", generated, " Overwrote: ", overwrote)
