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
const WATER_TICK         := 0.2    # seconds between simulation steps
const WATER_PER_TICK     := 15     # max new water cells added per tick

var _water_cells:       Dictionary = {}   # Vector2i -> true
var _water_sources:     Array[Vector2i] = []  # top of each staircase hole
var _water_source_dirs: Array[int] = []       # staircase direction per source
var _water_cell_dir:    Dictionary = {}   # Vector2i -> int (flow direction)
var _water_blocked:     Dictionary = {}   # cells permanently removed by bubble; never re-filled
var _water_timer:       float = 0.0
var _water_drawer:      Node2D = null

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
	_setup_water_drawer()

	# Connect player signals
	var player = get_node_or_null("Player")
	if player:
		# Apply persisted ore collection to the in-run player so the Ore tab shows lifetime totals.
		if ("lifetime_ore_counts" in player) and (lifetime_ore_counts is Dictionary) and lifetime_ore_counts.size() > 0:
			player.lifetime_ore_counts = lifetime_ore_counts.duplicate(true)
		# Share water cells so the player can react when submerged
		if "water_cells" in player:
			player.water_cells = _water_cells

		if not player.has_signal("died"):
			player.add_user_signal("died")
		player.connect("died", _on_player_died)
		
		if not player.has_signal("ore_collected"):
			player.add_user_signal("ore_collected")
		player.connect("ore_collected", _on_ore_collected)
	_setup_sky_bg_rect()

var _current_sky_texture: String = "res://8bit-pixel-graphic-blue-sky-background-with-clouds-vector.jpg"
var _sky_base_sprites: Array = []
var _sky_overlay_sprites: Array = []
var _sky_overlay_texture: String = ""
var _sky_scroll_offset: float = 0.0
var _sky_bg_rect: ColorRect = null
const SKY_SCROLL_SPEED: float = 12.0  # global units/sec — clouds drift left
const SKY_COLOR_DAY    := Color(0.48, 0.73, 0.89)
const SKY_COLOR_SUNSET := Color(0.78, 0.50, 0.36)
const SKY_COLOR_NIGHT  := Color(0.07, 0.09, 0.20)

const SUNSET_START_MINUTES = 16.0 * 60.0  # 4 PM — begin blue→sunset crossfade
const SUNSET_MINUTES       = 17.0 * 60.0  # 5 PM — fully sunset
const NIGHT_START_MINUTES  = 19.0 * 60.0  # 7 PM — begin sunset→night crossfade
const NIGHT_MINUTES        = 20.0 * 60.0  # 8 PM — fully night

func _process(_delta: float) -> void:
	# Sky always tracks camera, even during menu/day transitions
	_sky_scroll_offset -= SKY_SCROLL_SPEED * _delta
	var camera := get_node_or_null("Player/Camera2D") as Camera2D
	if camera:
		_anchor_sky_to_camera(camera.global_position.x)

	if not is_game_started: return

	_water_timer += _delta
	if _water_timer >= WATER_TICK:
		_water_timer = 0.0
		_tick_water()

	var player = get_node_or_null("Player")
	if player and "game_minutes" in player:
		_update_sky_blend(player.game_minutes)

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

	# Keep the solid-color backstop in sync so no viewport clear-colour shows through
	if is_instance_valid(_sky_bg_rect):
		var bg_color: Color
		if mins >= NIGHT_MINUTES:
			bg_color = SKY_COLOR_NIGHT
		elif mins >= NIGHT_START_MINUTES:
			bg_color = SKY_COLOR_SUNSET.lerp(SKY_COLOR_NIGHT,
				(mins - NIGHT_START_MINUTES) / (NIGHT_MINUTES - NIGHT_START_MINUTES))
		elif mins >= SUNSET_MINUTES:
			bg_color = SKY_COLOR_SUNSET
		elif mins >= SUNSET_START_MINUTES:
			bg_color = SKY_COLOR_DAY.lerp(SKY_COLOR_SUNSET,
				(mins - SUNSET_START_MINUTES) / (SUNSET_MINUTES - SUNSET_START_MINUTES))
		else:
			bg_color = SKY_COLOR_DAY
		_sky_bg_rect.color = bg_color

# Re-textures and repositions a set of sky sprites (2-sprite side-by-side layout).
# X is a temporary placeholder; _anchor_sprite_row overwrites it every frame.
# Y is the important part: bottom of sprite aligned to the surface.
func _retile_sky_sprites(sprites: Array, tex: Texture2D) -> void:
	if sprites.is_empty() or tex == null: return
	var ref: Sprite2D = sprites[0]
	if not is_instance_valid(ref): return
	# Set texture on ref first so get_rect() reflects the new size
	ref.texture = tex
	var ref_rect := ref.get_rect()
	var tile_w: float = abs(ref.to_global(Vector2(ref_rect.end.x, 0.0)).x
			- ref.to_global(Vector2(ref_rect.position.x, 0.0)).x)
	for i in range(sprites.size()):
		var sp: Sprite2D = sprites[i]
		if not is_instance_valid(sp): continue
		sp.texture = tex
		sp.global_position.x = (float(i) - 1.0) * tile_w  # placeholder, overridden each frame
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
	var ref: Sprite2D = null
	for s in sprites:
		if is_instance_valid(s) and (s as Sprite2D).texture != null:
			ref = s as Sprite2D
			break
	if ref == null: return
	# Compute actual global pixel width via the sprite's transform — handles all
	# parent scales (bg_above, Main, etc.) without manual multiplication.
	var ref_rect := ref.get_rect()
	var tile_w: float = abs(ref.to_global(Vector2(ref_rect.end.x, 0.0)).x
			- ref.to_global(Vector2(ref_rect.position.x, 0.0)).x)
	if tile_w <= 0.0: return
	var wrapped := fmod(scroll, tile_w)
	# centered=false: each sprite's left edge is at its global_position.x.
	# tile[1] left edge = cam_x+wrapped, which is always in (cam_x-tile_w, cam_x].
	# Since tile_w >> viewport_w, tile[1] alone covers the full viewport with no gaps.
	# tile[0] and tile[2] are seamlessly adjacent on either side.
	for i in range(sprites.size()):
		var sp := sprites[i] as Sprite2D
		if not is_instance_valid(sp): continue
		sp.global_position.x = cam_x + wrapped + (float(i) - 1.0) * tile_w

func _setup_sky_bg_rect() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -10
	add_child(cl)
	_sky_bg_rect = ColorRect.new()
	# Oversized rect in screen-space covers the full viewport regardless of window size
	_sky_bg_rect.position = Vector2(-4000, -4000)
	_sky_bg_rect.size = Vector2(12000, 12000)
	_sky_bg_rect.color = SKY_COLOR_DAY
	cl.add_child(_sky_bg_rect)

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
		"Emerald": return "res://Stones_ores_bars/emerald_ore.png"
		"Ruby": return "res://Stones_ores_bars/ruby_ore.png"
		"Diamond": return "res://Stones_ores_bars/diamond_ore.png"
		"Void Crystal": return "res://Stones_ores_bars/void_crystal_ore.png"
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

func _setup_water_drawer() -> void:
	if _water_drawer:
		_water_drawer.queue_free()
	var drawer := WaterDrawer.new()
	drawer.water_cells    = _water_cells
	drawer.parent_tilemap = tilemap
	drawer.z_index        = 2
	tilemap.add_child(drawer)
	_water_drawer = drawer

func _is_water_passable(pos: Vector2i) -> bool:
	return pos.y > SURFACE_Y and tilemap.get_cell_source_id(pos) == -1

# Called by player after breaking a tile; water seeps in after a short delay.
func notify_tile_removed(pos: Vector2i) -> void:
	if not _is_water_passable(pos):
		return
	# Check now whether a neighbour has water — if not, no need to schedule anything
	var neighbours := [
		pos + Vector2i( 0, -1),
		pos + Vector2i( 0,  1),
		pos + Vector2i(-1,  0),
		pos + Vector2i( 1,  0),
	]
	var has_water_neighbour := false
	for nb in neighbours:
		if _water_cells.has(nb):
			has_water_neighbour = true
			break
	if not has_water_neighbour:
		return

	# Wait 0.5 s before filling so the seep feels physical, not instant
	await get_tree().create_timer(0.5).timeout

	# Re-check passability after the delay (player may have re-placed a block)
	if not _is_water_passable(pos):
		return

	# Fill the tile and inherit direction from the first water neighbour found
	var filled := false
	for nb in neighbours:
		if _water_cells.has(nb):
			_water_cells[pos] = true
			if _water_cell_dir.has(nb) and not _water_cell_dir.has(pos):
				_water_cell_dir[pos] = _water_cell_dir[nb]
			filled = true
			break
	if not filled:
		return

	if _water_drawer:
		_water_drawer.queue_redraw()

	# Release a bubble from the topmost water cell near the break point
	var top_pos := pos
	var found_top := false
	for raw in _water_cells:
		var c := raw as Vector2i
		if abs(c.x - pos.x) <= 8:
			if not found_top or c.y < top_pos.y:
				top_pos = c
				found_top = true
	if found_top and top_pos != pos:
		_water_cells.erase(top_pos)
		_water_cell_dir.erase(top_pos)
		_water_blocked[top_pos] = true
		_spawn_water_bubble(top_pos)
		if _water_drawer:
			_water_drawer.queue_redraw()

func _spawn_water_bubble(tile_pos: Vector2i) -> void:
	var world_pos := tilemap.to_global(tilemap.map_to_local(tile_pos))
	var p := CPUParticles2D.new()
	p.global_position = world_pos
	p.amount          = 10
	p.lifetime        = 0.9
	p.one_shot        = true
	p.explosiveness   = 0.6
	p.direction       = Vector2(0.0, -1.0)
	p.spread          = 25.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.gravity         = Vector2(0.0, -60.0)   # bubbles float upward
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.0
	p.color           = Color(0.65, 0.88, 1.0, 0.85)
	add_child(p)
	p.emitting = true
	var tw := create_tween()
	tw.tween_interval(p.lifetime + 0.3)
	tw.tween_callback(p.queue_free)

func _tick_water() -> void:
	var down_cands:       Array[Vector2i] = []
	var side_cands_pref:  Array[Vector2i] = []  # staircase direction (preferred)
	var side_cands_other: Array[Vector2i] = []  # opposite direction

	# Sources drip in if not yet filled and not permanently blocked
	for i in range(_water_sources.size()):
		var src  := _water_sources[i]
		var sdir := _water_source_dirs[i] if i < _water_source_dirs.size() else -1
		if not _water_cells.has(src) and not _water_blocked.has(src) and _is_water_passable(src):
			down_cands.append(src)
			if not _water_cell_dir.has(src):
				_water_cell_dir[src] = sdir

	# Existing water spreads downward first, then in staircase direction, then opposite
	for raw_pos in _water_cells:
		var cell := raw_pos as Vector2i
		var fd: int = _water_cell_dir.get(cell, -1)

		var below := cell + Vector2i(0, 1)
		if not _water_cells.has(below) and not _water_blocked.has(below) and _is_water_passable(below):
			down_cands.append(below)
			if not _water_cell_dir.has(below):
				_water_cell_dir[below] = fd

		for dx in [fd, -fd]:
			var side := cell + Vector2i(dx, 0)
			if not _water_cells.has(side) and not _water_blocked.has(side) and _is_water_passable(side):
				if dx == fd:
					side_cands_pref.append(side)
				else:
					side_cands_other.append(side)
				if not _water_cell_dir.has(side):
					_water_cell_dir[side] = fd

	var added := 0
	for pos in down_cands + side_cands_pref + side_cands_other:
		if added >= WATER_PER_TICK:
			break
		if not _water_cells.has(pos):
			_water_cells[pos] = true
			added += 1

	if added > 0 and _water_drawer:
		_water_drawer.queue_redraw()

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
	_water_cells.clear()
	_water_sources.clear()
	_water_source_dirs.clear()
	_water_cell_dir.clear()
	_water_blocked.clear()
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
			# Top of step 0 is the water entry point for this staircase
			_water_sources.append(Vector2i(ox, oy))
			_water_source_dirs.append(dir)
			for s in range(n_steps):
				var sy := oy + s
				# 2 tiles wide per step: carve the current column and the next one in dir
				for w in range(2):
					var sx := ox + (s + w) * dir
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

	# 5. Sky backgrounds — 3 sprites: left / centre / right of camera, scrolling left on loop
	var bg_above = get_node_or_null("Background above")
	_sky_base_sprites.clear()
	_sky_overlay_sprites.clear()
	_sky_overlay_texture = ""
	if bg_above:
		# Inherit scale/z_index from existing scene sprite if present, then clear all
		var spr_scale := Vector2(1.4, 1.4)
		var spr_z := -1
		for child in bg_above.get_children():
			if child is Sprite2D and (child as Sprite2D).texture != null:
				spr_scale = (child as Sprite2D).scale
				spr_z     = (child as Sprite2D).z_index
				break
		for child in bg_above.get_children():
			child.queue_free()

		var sky_tex: Texture2D = load(_current_sky_texture)
		if sky_tex:
			# Create 3 tiles with centered=false so left-edge placement is exact.
			# tile[1] always straddles the camera — no gap can appear in the viewport.
			for i in range(3):
				var sp := Sprite2D.new()
				sp.texture        = sky_tex
				sp.scale          = spr_scale
				sp.z_index        = spr_z
				sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				sp.centered       = false
				bg_above.add_child(sp)  # Must be in tree before global_position is valid
				# Align bottom edge to the surface using the actual global transform
				var rect      := sp.get_rect()
				var bot_gly   := sp.to_global(Vector2(0.0, rect.end.y)).y
				sp.global_position.y += surface_y - bot_gly
				_sky_base_sprites.append(sp)

			for base in _sky_base_sprites:
				var ov := Sprite2D.new()
				ov.texture        = null
				ov.scale          = base.scale
				ov.z_index        = base.z_index + 1
				ov.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				ov.modulate       = Color(1.0, 1.0, 1.0, 0.0)
				ov.centered       = false
				bg_above.add_child(ov)  # Add first so global_position is valid
				ov.global_position = base.global_position
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
					bg.modulate = Color(0.45, 0.35, 0.28, 1.0)
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
