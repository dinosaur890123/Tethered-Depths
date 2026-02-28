extends Node2D

@export var half_width_tiles: int = 1
@export var depth_tiles: int = 2

func _ready() -> void:
	_register_unbreakable_foundation_tiles()

func _register_unbreakable_foundation_tiles() -> void:
	var main := get_parent()
	if main == null:
		return
	var tilemap := main.get_node_or_null("Dirt") as TileMapLayer
	if tilemap == null:
		return

	# Compute a probe position slightly below this node so we land inside the ground tile.
	var origin_global := tilemap.to_global(tilemap.map_to_local(Vector2i(0, 0)))
	var down_global := tilemap.to_global(tilemap.map_to_local(Vector2i(0, 1)))
	var tile_step_y := down_global.y - origin_global.y
	var probe_global := global_position + Vector2(0.0, tile_step_y * 0.5)
	var anchor_tile: Vector2i = tilemap.local_to_map(tilemap.to_local(probe_global))

	var unbreakable: Dictionary = {}
	if tilemap.has_meta("unbreakable_tiles"):
		var existing = tilemap.get_meta("unbreakable_tiles")
		if existing is Dictionary:
			unbreakable = existing

	for x in range(anchor_tile.x - half_width_tiles, anchor_tile.x + half_width_tiles + 1):
		for y in range(anchor_tile.y, anchor_tile.y + max(1, depth_tiles)):
			unbreakable[Vector2i(x, y)] = true

	tilemap.set_meta("unbreakable_tiles", unbreakable)
