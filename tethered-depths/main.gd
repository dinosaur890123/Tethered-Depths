extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4

const WIDTH = 120
const DEPTH = 350
const SURFACE_Y = 0

var is_game_started: bool = false

# PB Tracking & Persistence
const SAVE_PATH = "user://savegame.cfg"
var high_money: int = 0
var high_days: int = 0
var discovered_ores: Dictionary = {} # ore_name -> bool
var lifetime_ore_counts: Dictionary = {} # ore_name -> int

@onready var main_menu: CanvasLayer = $MainMenu
@onready var menu_root: Control = $MainMenu/Root
@onready var settings_root: Control = $MainMenu/Settings
@onready var pb_root: Control = $MainMenu/PBTab
@onready var ore_root: Control = $MainMenu/OreTab
@onready var death_screen: CanvasLayer = $DeathScreen

@onready var volume_slider: HSlider = $MainMenu/Settings/VBox/VolumeSlider
@onready var start_btn: Button = $MainMenu/Root/PanelContainer/VBox/StartBtn
@onready var restart_btn: Button = $MainMenu/Root/PanelContainer/VBox/RestartBtn

func _ready():
	load_game()
	process_mode = PROCESS_MODE_ALWAYS
	get_tree().paused = true
	main_menu.visible = true
	menu_root.visible = true
	settings_root.visible = false
	pb_root.visible = false
	ore_root.visible = false
	death_screen.visible = false
	start_btn.text = "Start Game"
	restart_btn.visible = false
	
	# Connect menu buttons
	start_btn.pressed.connect(_on_start_pressed)
	restart_btn.pressed.connect(_on_restart_pressed)
	$MainMenu/Root/PanelContainer/VBox/SettingsBtn.pressed.connect(_on_settings_pressed)
	$MainMenu/Root/PanelContainer/VBox/RecordsBtn.pressed.connect(_on_records_pressed)
	$MainMenu/Root/PanelContainer/VBox/OreBtn.pressed.connect(_on_ore_tab_pressed)
	$MainMenu/Root/PanelContainer/VBox/ExitBtn.pressed.connect(_on_exit_pressed)
	
	$MainMenu/Settings/VBox/BackBtn.pressed.connect(_on_settings_back_pressed)
	$MainMenu/PBTab/VBox/BackBtn.pressed.connect(_on_settings_back_pressed)
	$MainMenu/OreTab/VBox/BackBtn.pressed.connect(_on_settings_back_pressed)

	volume_slider.value_changed.connect(_on_volume_changed)
	
	# Initial volume
	_on_volume_changed(volume_slider.value)

	randomize()
	generate_world()
	await get_tree().physics_frame
	position_entities()
	
	# Connect player signals
	var player = get_node_or_null("Player")
	if player:
		if not player.has_signal("died"):
			player.add_user_signal("died")
		player.connect("died", _on_player_died)
		
		if not player.has_signal("ore_collected"):
			player.add_user_signal("ore_collected")
		player.connect("ore_collected", _on_ore_collected)

func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC
		if settings_root.visible or pb_root.visible or ore_root.visible:
			_on_settings_back_pressed()
		else:
			_toggle_menu()

func _toggle_menu():
	if not is_game_started: return
	main_menu.visible = !main_menu.visible
	get_tree().paused = main_menu.visible
	if main_menu.visible:
		start_btn.text = "Continue"
		restart_btn.visible = true
		menu_root.visible = true
		settings_root.visible = false
		pb_root.visible = false
		ore_root.visible = false

func _on_start_pressed():
	is_game_started = true
	main_menu.visible = false
	get_tree().paused = false
	start_btn.text = "Continue"
	restart_btn.visible = true

func _on_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_settings_pressed():
	menu_root.visible = false
	settings_root.visible = true

func _on_records_pressed():
	menu_root.visible = false
	pb_root.visible = true
	_update_pb_labels()

func _on_ore_tab_pressed():
	menu_root.visible = false
	ore_root.visible = true
	_update_ore_grid()

func _on_settings_back_pressed():
	menu_root.visible = true
	settings_root.visible = false
	pb_root.visible = false
	ore_root.visible = false

func _on_exit_pressed():
	get_tree().quit()

func _on_volume_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value / 100.0))

func _on_player_died():
	_update_pb_labels() # Save records on death
	death_screen.visible = true
	var label = death_screen.get_node("VBox/Label")
	var overlay = death_screen.get_node("Overlay")

	overlay.modulate.a = 0.0
	label.modulate.a = 0.0

	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(overlay, "modulate:a", 0.6, 0.5)
	tw.parallel().tween_property(label, "modulate:a", 1.0, 0.5)
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		death_screen.visible = false
		is_game_started = false
		main_menu.visible = true
		menu_root.visible = true
		start_btn.text = "Start Game"
		restart_btn.visible = false
		get_tree().paused = true
		# Optionally reset the player position here or let reload_scene handle it?
		# reload_current_scene is better for a full reset.
		get_tree().reload_current_scene()
	)

func _on_ore_collected(ore_name: String):
	discovered_ores[ore_name] = true

func _update_pb_labels():
	var player = get_node_or_null("Player")
	if player:
		high_money = max(high_money, player.money)
		high_days = max(high_days, player.day_count)
	
	$MainMenu/PBTab/VBox/MoneyLabel.text = "Highest Money: $%d" % high_money
	$MainMenu/PBTab/VBox/DaysLabel.text = "Most Days Survived: %d" % high_days

func _update_ore_grid():
	var grid = $MainMenu/OreTab/VBox/Scroll/Grid
	for child in grid.get_children():
		child.queue_free()
	
	var player = get_node_or_null("Player")
	if not player: return
	
	for ore in player.ORE_TABLE:
		var nm: String = ore[0]
		
		var container = VBoxContainer.new()
		container.custom_minimum_size = Vector2(180, 200)
		
		var discovered = discovered_ores.has(nm)
		
		# Image
		var rect = TextureRect.new()
		var tex_path = _get_ore_tex_path(nm)
		if discovered and tex_path != "":
			rect.texture = load(tex_path)
			# Apply purple tint to mutated versions
			if nm.begins_with("Mutated "):
				rect.modulate = Color(0.8, 0.2, 0.95)
			elif nm == "Rainbow":
				rect.modulate = Color(1, 0.5, 1) # Specific rainbow tint
		else:
			# Show a placeholder or darkened version
			rect.texture = load("res://icon.svg")
			rect.modulate = Color(0, 0, 0, 0.8)
		
		rect.custom_minimum_size = Vector2(100, 100)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.add_child(rect)
		
		# Name
		var name_lbl = Label.new()
		name_lbl.text = nm if discovered else "???"
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if discovered:
			name_lbl.modulate = ore[3]
		else:
			name_lbl.modulate = Color.GRAY
		container.add_child(name_lbl)
		
		# Count
		var count_lbl = Label.new()
		var total = player.lifetime_ore_counts.get(nm, 0)
		count_lbl.text = "Collected: %d" % total
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_lbl.add_theme_font_size_override("font_size", 14)
		container.add_child(count_lbl)
		
		grid.add_child(container)

func _get_ore_tex_path(nm: String) -> String:
	var base_name = nm
	if nm.begins_with("Mutated "):
		base_name = nm.replace("Mutated ", "")
	
	match base_name:
		"Stone": return "res://Stones_ores_bars/stone_1.png"
		"Copper": return "res://Stones_ores_bars/copper_ore.png"
		"Silver": return "res://Stones_ores_bars/silver_ore.png"
		"Gold": return "res://Stones_ores_bars/gold_ore.png"
		"Rainbow": return "res://Stones_ores_bars/gold_ore.png"
	return ""

# Persistence logic
func save_game():
	var config = ConfigFile.new()
	config.set_value("records", "high_money", high_money)
	config.set_value("records", "high_days", high_days)
	config.set_value("collection", "discovered_ores", discovered_ores)
	config.set_value("collection", "lifetime_ore_counts", lifetime_ore_counts)
	config.save(SAVE_PATH)

func load_game():
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		high_money = config.get_value("records", "high_money", 0)
		high_days = config.get_value("records", "high_days", 0)
		discovered_ores = config.get_value("collection", "discovered_ores", {})
		lifetime_ore_counts = config.get_value("collection", "lifetime_ore_counts", {})

func generate_world():
	tilemap.clear()
	if OS.is_debug_build():
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
		house.z_index = 1
		_align_node_bottom_to_surface(house as Node2D, surface_y)

	var trader := get_node_or_null("Trader")

	if trader is Node2D:
		if shop:
			trader.global_position.x = shop.global_position.x + 80.0
		_align_node_bottom_to_surface(trader as Node2D, surface_y)


	var sign_paths := ["Signtutorial", "Shopsign", "Signprice"]

	for p in sign_paths:
		var s_node := get_node_or_null(p)
		if s_node is Node2D:
			s_node.z_index = 1
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
		var bg_tex = load("res://rockwallbackground2.png")
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
	var anchor := n.get_node_or_null("GroundAnchor") as Node2D
	if anchor != null:
		n.global_position.y += surface_y - anchor.global_position.y
		return

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
