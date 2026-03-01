extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4

const WIDTH = 120
const DEPTH = 1000
const SURFACE_Y = 0

# --- Water simulation ---
const WATER_TICK         := 0.5   # seconds between simulation steps
const WATER_PER_TICK     := 3     # max new water cells added per tick

var _water_cells:   Dictionary = {}        # Vector2i -> true
var _water_sources: Array[Vector2i] = []   # top of each staircase hole
var _water_timer:   float = 0.0
var _water_drawer:  Node2D = null

class WaterDrawer extends Node2D:
	var water_cells:     Dictionary   = {}
	var parent_tilemap:  TileMapLayer = null

	func _draw() -> void:
		if not parent_tilemap or not parent_tilemap.tile_set:
			return
		var ts  := parent_tilemap.tile_set.tile_size
		var hw  := ts.x * 0.5
		var hh  := ts.y * 0.5
		var col := Color(0.10, 0.40, 0.95, 0.60)
		for raw_pos in water_cells:
			var pos := raw_pos as Vector2i
			var lp  := parent_tilemap.map_to_local(pos)
			draw_rect(Rect2(lp.x - hw, lp.y - hh, float(ts.x), float(ts.y)), col)

var is_game_started: bool = false

# PB Tracking & Persistence
const SAVE_PATH = "user://savegame.cfg"
var high_money: int = 0
var high_days: int = 0
var high_depth: int = 0
var discovered_ores: Dictionary = {} # ore_name -> bool
var lifetime_ore_counts: Dictionary = {} # ore_name -> int

var _save_dirty: bool = false
var _autosave_timer: Timer

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
	process_mode = PROCESS_MODE_ALWAYS
	_setup_autosave()
	get_tree().paused = true
	main_menu.visible = true
	menu_root.visible = true
	settings_root.visible = false
	pb_root.visible = false
	ore_root.visible = false
	death_screen.visible = false
	start_btn.text = "Start Game"
	restart_btn.visible = false

	# Push the button panel down so it sits below the logo
	var panel := $MainMenu/Root/PanelContainer as PanelContainer
	if panel:
		panel.offset_top += 90.0
		panel.offset_bottom += 90.0

	# Add Furthest Depth label to Records tab (before the Back button)
	var pb_vbox := $MainMenu/PBTab/VBox as VBoxContainer
	var depth_lbl := Label.new()
	depth_lbl.name = "DepthLabel"
	depth_lbl.text = "Furthest Depth: 0 tiles"
	depth_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	depth_lbl.add_theme_font_size_override("font_size", 32)
	pb_vbox.add_child(depth_lbl)
	pb_vbox.move_child(depth_lbl, 3) # After DaysLabel, before BackBtn

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

	load_game()

	randomize()
	generate_world()
	await get_tree().physics_frame
	position_entities()
	
	# Connect player signals
	var player = get_node_or_null("Player")
	if player:
		# Apply persisted ore collection to the in-run player so the Ore tab shows lifetime totals.
		if ("lifetime_ore_counts" in player) and (lifetime_ore_counts is Dictionary) and lifetime_ore_counts.size() > 0:
			player.lifetime_ore_counts = lifetime_ore_counts.duplicate(true)

		if not player.has_signal("died"):
			player.add_user_signal("died")
		player.connect("died", _on_player_died)
		
		if not player.has_signal("ore_collected"):
			player.add_user_signal("ore_collected")
		player.connect("ore_collected", _on_ore_collected)

var _current_sky_texture: String = "res://8bit-pixel-graphic-blue-sky-background-with-clouds-vector.jpg"
var _sky_base_sprites: Array = []
var _sky_overlay_sprites: Array = []
var _sky_overlay_texture: String = ""
var _sky_scroll_offset: float = 0.0
const SKY_SCROLL_SPEED: float = 12.0  # global units/sec — clouds drift left

const SUNSET_START_MINUTES = 16.0 * 60.0  # 4 PM — begin blue→sunset crossfade
const SUNSET_MINUTES       = 17.0 * 60.0  # 5 PM — fully sunset
const NIGHT_START_MINUTES  = 19.0 * 60.0  # 7 PM — begin sunset→night crossfade
const NIGHT_MINUTES        = 20.0 * 60.0  # 8 PM — fully night

func _process(_delta: float) -> void:
	if not is_game_started: return

	var player = get_node_or_null("Player")
	if player and "game_minutes" in player:
		_update_sky_blend(player.game_minutes)

	# Advance cloud scroll and re-centre tiles around the camera
	_sky_scroll_offset -= SKY_SCROLL_SPEED * _delta
	var camera := get_node_or_null("Player/Camera2D") as Camera2D
	if camera:
		_anchor_sky_to_camera(camera.global_position.x)

func _update_sky_blend(mins: float) -> void:
	var base_path: String
	var overlay_path: String
	var alpha: float

	if mins >= NIGHT_MINUTES:
		base_path    = "res://night.png"
		overlay_path = ""
		alpha        = 0.0
	elif mins >= NIGHT_START_MINUTES:
		base_path    = "res://sunset.png"
		overlay_path = "res://night.png"
		alpha        = (mins - NIGHT_START_MINUTES) / (NIGHT_MINUTES - NIGHT_START_MINUTES)
	elif mins >= SUNSET_MINUTES:
		base_path    = "res://sunset.png"
		overlay_path = ""
		alpha        = 0.0
	elif mins >= SUNSET_START_MINUTES:
		base_path    = "res://8bit-pixel-graphic-blue-sky-background-with-clouds-vector.jpg"
		overlay_path = "res://sunset.png"
		alpha        = (mins - SUNSET_START_MINUTES) / (SUNSET_MINUTES - SUNSET_START_MINUTES)
	else:
		base_path    = "res://8bit-pixel-graphic-blue-sky-background-with-clouds-vector.jpg"
		overlay_path = ""
		alpha        = 0.0

	if base_path != _current_sky_texture:
		_update_sky_texture(base_path)
		_current_sky_texture = base_path

	if overlay_path != _sky_overlay_texture:
		if overlay_path != "":
			_retile_sky_sprites(_sky_overlay_sprites, load(overlay_path))
		else:
			for sp in _sky_overlay_sprites:
				if is_instance_valid(sp):
					sp.texture = null
		_sky_overlay_texture = overlay_path

	for sp in _sky_overlay_sprites:
		if is_instance_valid(sp):
			sp.modulate.a = alpha

# Re-textures and repositions a set of sky sprites so they tile gap-free
# across the world, centred on the player's spawn (global x = 0).
func _retile_sky_sprites(sprites: Array, tex: Texture2D) -> void:
	if sprites.is_empty() or tex == null: return
	var ref: Sprite2D = sprites[0]
	if not is_instance_valid(ref): return
	# Global rendered width of one tile: texture_px * sprite_scale * Main_scale
	var tile_w: float = float(tex.get_width()) * ref.scale.x * self.scale.x
	var n := sprites.size()
	var half := n / 2  # integer division — centre index
	for i in range(n):
		var sp: Sprite2D = sprites[i]
		if not is_instance_valid(sp): continue
		sp.texture = tex
		sp.global_position.x = float(i - half) * tile_w
		var rect := sp.get_rect()
		var bottom_gly := sp.to_global(Vector2(0.0, rect.end.y)).y
		sp.global_position.y += _surface_y_cached - bottom_gly

func _update_sky_texture(path: String) -> void:
	var tex: Texture2D = load(path)
	if not tex: return
	_retile_sky_sprites(_sky_base_sprites, tex)

# Called every frame — keeps sky tiles centred on the camera so horizontal
# gaps are impossible regardless of texture size or player position.
func _anchor_sky_to_camera(cam_x: float) -> void:
	_anchor_sprite_row(_sky_base_sprites, cam_x, _sky_scroll_offset)
	_anchor_sprite_row(_sky_overlay_sprites, cam_x, _sky_scroll_offset)

func _anchor_sprite_row(sprites: Array, cam_x: float, scroll: float) -> void:
	if sprites.is_empty(): return
	# Find the first valid sprite with a texture to measure tile width
	var ref: Sprite2D = null
	for s in sprites:
		if is_instance_valid(s) and (s as Sprite2D).texture != null:
			ref = s as Sprite2D
			break
	if ref == null: return
	var tile_w := float(ref.texture.get_width()) * ref.scale.x * self.scale.x
	# Wrap the scroll within one tile so the float stays small forever
	var wrapped := fmod(scroll, tile_w)   # stays in (-tile_w, 0]
	var n := sprites.size()
	var half := n / 2
	for i in range(n):
		var sp := sprites[i] as Sprite2D
		if not is_instance_valid(sp): continue
		sp.global_position.x = cam_x + wrapped + float(i - half) * tile_w

func _setup_autosave() -> void:
	if _autosave_timer != null:
		return
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = 3.0
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	_autosave_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_on_autosave_timeout)

func _mark_save_dirty() -> void:
	_save_dirty = true

func _pull_player_progress() -> void:
	var player = get_node_or_null("Player")
	if player and ("lifetime_ore_counts" in player) and (player.lifetime_ore_counts is Dictionary):
		lifetime_ore_counts = player.lifetime_ore_counts.duplicate(true)

func _on_autosave_timeout() -> void:
	if not _save_dirty:
		return
	_pull_player_progress()
	save_game()
	_save_dirty = false

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
	$MainMenu/LogoTexture.visible = false

func _on_records_pressed():
	menu_root.visible = false
	pb_root.visible = true
	$MainMenu/LogoTexture.visible = false
	_update_pb_labels()

func _on_ore_tab_pressed():
	menu_root.visible = false
	ore_root.visible = true
	$MainMenu/LogoTexture.visible = false
	_update_ore_grid()

func _on_settings_back_pressed():
	menu_root.visible = true
	settings_root.visible = false
	pb_root.visible = false
	ore_root.visible = false
	$MainMenu/LogoTexture.visible = true

func _on_exit_pressed():
	_update_pb_labels()
	_pull_player_progress()
	save_game()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_update_pb_labels()
		get_tree().quit()

func _on_volume_changed(value: float):
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value / 100.0))

func _on_player_died():
	_update_pb_labels() # Save records on death
	_pull_player_progress()
	save_game()
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
	_mark_save_dirty()

func _update_pb_labels():
	var player = get_node_or_null("Player")
	if player:
		high_money = max(high_money, player.money)
		high_days = max(high_days, player.day_count)
		high_depth = max(high_depth, player.lifetime_max_depth)
	_mark_save_dirty()
	
	$MainMenu/PBTab/VBox/MoneyLabel.text = "Highest Money: $%d" % high_money
	$MainMenu/PBTab/VBox/DaysLabel.text = "Most Days Survived: %d" % high_days
	var depth_lbl := $MainMenu/PBTab/VBox/DepthLabel as Label
	if depth_lbl:
		depth_lbl.text = "Furthest Depth: %d tiles" % high_depth
	save_game()

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
		
		# Image & Glow
		var icon_container = Control.new()
		icon_container.custom_minimum_size = Vector2(100, 100)
		icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		container.add_child(icon_container)
		
		if discovered and nm.begins_with("Mutated "):
			# Add Glow Panel
			var glow = Panel.new()
			glow.set_anchors_preset(Control.LayoutPreset.PRESET_CENTER)
			glow.offset_left = -15
			glow.offset_right = 15
			glow.offset_top = -15
			glow.offset_bottom = 15
			
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0) # Transparent center
			sb.set_corner_radius_all(50)
			sb.shadow_color = ore[3] # The purple color
			sb.shadow_size = 18
			glow.add_theme_stylebox_override("panel", sb)
			icon_container.add_child(glow)

		var rect = TextureRect.new()
		var tex_path = _get_ore_tex_path(nm)
		if discovered and tex_path != "":
			rect.texture = load(tex_path)
			if nm.begins_with("Mutated "):
				rect.modulate = Color(0.8, 0.2, 0.95)
			elif nm == "Rainbow":
				rect.modulate = Color(1, 0.5, 1)
		else:
			rect.texture = load("res://icon.svg")
			rect.modulate = Color(0, 0, 0, 0.8)
		
		rect.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(rect)
		
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
	config.set_value("records", "high_depth", high_depth)
	config.set_value("collection", "discovered_ores", discovered_ores)
	config.set_value("collection", "lifetime_ore_counts", lifetime_ore_counts)
	config.save(SAVE_PATH)

func load_game():
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		high_money = config.get_value("records", "high_money", 0)
		high_days = config.get_value("records", "high_days", 0)
		high_depth = config.get_value("records", "high_depth", 0)
		discovered_ores = config.get_value("collection", "discovered_ores", {})
		lifetime_ore_counts = config.get_value("collection", "lifetime_ore_counts", {})

func generate_world():
	tilemap.clear()
	if OS.is_debug_build():
		print("Generating world...")
	var half_w: int = WIDTH >> 1
	var skip_tiles := {}

	# --- Staircase holes pre-pass ---
	# Check every 8x8 grid cell; 5% chance to carve a staircase in each cell.
	# Each staircase: 3-5 steps, 2 tiles tall per step = 6-10 blocks removed.
	# Steps go diagonally down-left or down-right (randomly chosen).
	const STAIR_GRID := 8
	const STAIR_CHANCE := 0.05
	for gx in range(-half_w + 1, half_w - 7, STAIR_GRID):
		for gy in range(SURFACE_Y + 2, DEPTH - 10, STAIR_GRID):
			if randf() >= STAIR_CHANCE:
				continue
			# Jitter origin within the grid cell for a more organic look
			var ox := gx + randi_range(0, STAIR_GRID - 1)
			var oy := gy + randi_range(0, STAIR_GRID - 1)
			var n_steps := randi_range(3, 5)       # 3-5 steps = 6-10 blocks
			var dir := 1 if randf() < 0.5 else -1  # down-right or down-left
			for s in range(n_steps):
				var sx := ox + s * dir
				var sy := oy + s
				if sx >= -half_w and sx < half_w:
					if sy < DEPTH:
						skip_tiles[Vector2i(sx, sy)] = true
					if sy + 1 < DEPTH:
						skip_tiles[Vector2i(sx, sy + 1)] = true

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

var _surface_y_cached: float = 0.0

func position_entities():
	var surface_pos_local = tilemap.map_to_local(Vector2i(0, SURFACE_Y))
	var global_center = tilemap.to_global(surface_pos_local)
	var tile_h_world = (128.0 * tilemap.scale.y * self.scale.y)
	var surface_y = global_center.y - (tile_h_world / 2.0)
	_surface_y_cached = surface_y



	var player = get_node_or_null("Player")
	if player:
		player.global_position = Vector2(0, surface_y - (32.0 * self.scale.y))
		if "spawn_position" in player:
			player.spawn_position = player.global_position

	var shop := get_node_or_null("Shop")
	if shop is Node2D:
		_align_node_bottom_to_surface(shop as Node2D, surface_y)
		_register_surface_footprint(shop as Node2D, surface_y, 1)

	var house := get_node_or_null("House")
	if house is Node2D:
		house.z_index = 1
		_align_node_bottom_to_surface(house as Node2D, surface_y)
		_register_surface_footprint(house as Node2D, surface_y, 1)

	var sign_paths := ["Signtutorial", "Shopsign", "Signprice"]

	for p in sign_paths:
		var s_node := get_node_or_null(p)
		if s_node is Node2D:
			s_node.z_index = 1
			_align_node_bottom_to_surface(s_node as Node2D, surface_y)
			_register_surface_footprint(s_node as Node2D, surface_y, 1)

	var tree_paths := ["Trees/Tree1", "Trees/Tree2", "Trees/Tree3", "Trees/Tree4", "Trees/Tree5", "Trees/Tree6", "Trees/Tree7", "Trees/Tree8", "Trees/Tree9", "Trees/Tree10", "Trees/Tree11"]
	for p in tree_paths:
		var tree := get_node_or_null(p)
		if tree is Node2D:
			_align_node_bottom_to_surface(tree as Node2D, surface_y)
			_register_surface_footprint(tree as Node2D, surface_y, 0)

	# 5. Sky backgrounds — align to surface, add extra copies, create crossfade overlay layer
	var bg_above = get_node_or_null("Background above")
	_sky_base_sprites.clear()
	_sky_overlay_sprites.clear()
	_sky_overlay_texture = ""
	if bg_above:
		# Align existing scene sprites and collect them
		var ref_sprite: Sprite2D = null
		for bg in bg_above.get_children():
			if not (bg is Sprite2D) or not bg.texture: continue
			var rect = bg.get_rect()
			var bottom_global_y = bg.to_global(Vector2(0.0, rect.end.y)).y
			bg.global_position.y += surface_y - bottom_global_y
			_sky_base_sprites.append(bg)
			if ref_sprite == null:
				ref_sprite = bg

		# Add 2 extra copies (one far-left, one far-right) to prevent evening-sky gaps
		if ref_sprite != null and _sky_base_sprites.size() >= 2:
			var xs: Array = []
			for s in _sky_base_sprites:
				xs.append(s.global_position.x)
			xs.sort()
			var spacing: float = (xs[-1] - xs[0]) / float(_sky_base_sprites.size() - 1)
			for extra_x in [xs[0] - spacing, xs[-1] + spacing]:
				var new_bg = Sprite2D.new()
				new_bg.texture = ref_sprite.texture
				new_bg.scale = ref_sprite.scale
				new_bg.z_index = ref_sprite.z_index
				new_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				new_bg.global_position = Vector2(extra_x, ref_sprite.global_position.y)
				bg_above.add_child(new_bg)
				_sky_base_sprites.append(new_bg)

		# Create an invisible overlay sprite per base sprite for crossfade transitions
		for base in _sky_base_sprites:
			var ov = Sprite2D.new()
			ov.texture = null
			ov.scale = base.scale
			ov.z_index = base.z_index + 1
			ov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ov.global_position = base.global_position
			ov.modulate = Color(1.0, 1.0, 1.0, 0.0)
			bg_above.add_child(ov)
			_sky_overlay_sprites.append(ov)

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


# Registers the surface grass tiles directly under a structure as unminable.
# half_w: how many tiles to each side of the node's center column to protect.
func _register_surface_footprint(node: Node2D, surface_y: float, half_w: int) -> void:
	var probe_global := Vector2(node.global_position.x, surface_y + 4.0)
	var anchor_tile := tilemap.local_to_map(tilemap.to_local(probe_global))
	var unbreakable: Dictionary = {}
	if tilemap.has_meta("unbreakable_tiles"):
		var ex = tilemap.get_meta("unbreakable_tiles")
		if ex is Dictionary:
			unbreakable = ex
	for tx in range(anchor_tile.x - half_w, anchor_tile.x + half_w + 1):
		unbreakable[Vector2i(tx, anchor_tile.y)] = true
	tilemap.set_meta("unbreakable_tiles", unbreakable)


func find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name: return root
	for child in root.get_children():
		var found = find_node_by_name(child, node_name)
		if found: return found
	return null
