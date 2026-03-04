extends Node2D

@onready var tilemap: TileMapLayer = $Dirt

const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4
const TILE_COPPER := 10
const TILE_SILVER := 11
const TILE_GOLD := 12
const TILE_EMERALD := 13
const TILE_RUBY := 14
const TILE_DIAMOND := 15
const TILE_VOID := 16

const WIDTH = 120
const DEPTH = 10000
const SURFACE_Y = 0

# --- Water simulation ---
const WATER_TICK     := 0.15  # seconds between simulation steps
const WATER_PER_TICK := 6     # max sideways cells added per tick (gravity is unlimited)

var _water_cells:       Dictionary = {}
var _water_sources:     Array[Vector2i] = []
var _water_source_dirs: Array[int] = []
var _water_cell_dir:    Dictionary = {}
var _water_pending:     Dictionary = {}   # tiles blocked for 0.5 s after being broken
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
var tutorial_root: Control
var current_tutorial_slide: int = 0
@onready var death_screen: CanvasLayer = $DeathScreen

@onready var volume_slider: HSlider = $MainMenu/Settings/VBox/VolumeSlider
@onready var start_btn: Button = $MainMenu/Root/PanelContainer/VBox/StartBtn
@onready var restart_btn: Button = $MainMenu/Root/PanelContainer/VBox/RestartBtn

func _ready():
	process_mode = PROCESS_MODE_ALWAYS
	_setup_autosave()
	_setup_ore_tiles()
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
	
	var tutorial_btn := Button.new()
	tutorial_btn.name = "TutorialBtn"
	tutorial_btn.text = "Tutorial"
	tutorial_btn.add_theme_font_size_override("font_size", 28)
	var vbox := $MainMenu/Root/PanelContainer/VBox as VBoxContainer
	vbox.add_child(tutorial_btn)
	vbox.move_child(tutorial_btn, 1) # Put it after Start but before Settings
	tutorial_btn.pressed.connect(_on_tutorial_pressed)

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

var _sky_sprite_day: Sprite2D = null
var _sky_sprite_sunset: Sprite2D = null
var _sky_sprite_night: Sprite2D = null
var _sky_scroll_offset: float = 0.0
var _sky_bg_rect: ColorRect = null
const SKY_SCROLL_SPEED: float = 12.0

func _process(_delta: float) -> void:
	_sky_scroll_offset += SKY_SCROLL_SPEED * _delta
	var player = get_node_or_null("Player")
	var camera = player.get_node_or_null("Camera2D") if player else null
	
	if player and camera:
		var mins = float(player.game_minutes)
		# Normalize mins to a 0-1440 range (one day)
		var m = fmod(mins, 1440.0)
		
		# Alpha and Darkness calculations
		var day_a = 0.0
		var sunset_a = 0.0
		var night_a = 0.0
		var night_darkness = 0.0
		
		# 360=6am, 900=3pm, 1020=5pm, 1080=6pm, 1200=8pm, 1320=10pm, 1440=12am
		if m >= 360 and m < 900: # 6am - 3pm: Pure Day
			day_a = 1.0
		elif m >= 900 and m < 1020: # 3pm - 5pm: Sunset rising
			day_a = 1.0
			sunset_a = (m - 900.0) / 120.0
		elif m >= 1020 and m < 1080: # 5pm - 6pm: Peak Sunset, Day fades
			sunset_a = 1.0
			day_a = 1.0 - (m - 1020.0) / 60.0
		elif m >= 1080 and m < 1200: # 6pm - 8pm: Night transition
			sunset_a = 1.0 - (m - 1080.0) / 120.0
			night_a = (m - 1080.0) / 120.0
		elif m >= 1200 or m < 240: # 8pm - 4am: Night
			night_a = 1.0
			if m >= 1320: # 10pm - 12am: Darkening
				night_darkness = (m - 1320.0) / 120.0
			elif m < 240: # Keep dark until sunrise
				night_darkness = 1.0
		elif m >= 240 and m < 360: # 4am - 6am: Sunrise
			night_a = 1.0 - (m - 240.0) / 120.0
			day_a = (m - 240.0) / 120.0
			night_darkness = 1.0 - (m - 240.0) / 120.0
		
		# Update sprite positions and scrolling
		for spr in [_sky_sprite_day, _sky_sprite_sunset, _sky_sprite_night]:
			if is_instance_valid(spr):
				spr.global_position.x = camera.global_position.x
				var tex_w: float = float(spr.texture.get_width())
				var gsx: float   = abs(float(spr.get_global_transform().get_scale().x))
				var rr: Rect2    = spr.region_rect
				rr.position.x     = fmod(_sky_scroll_offset / gsx, tex_w)
				spr.region_rect = rr
		
		if is_instance_valid(_sky_sprite_day): _sky_sprite_day.modulate.a = day_a
		if is_instance_valid(_sky_sprite_sunset): _sky_sprite_sunset.modulate.a = sunset_a
		
		# Night sprite also gets darker
		if is_instance_valid(_sky_sprite_night):
			_sky_sprite_night.modulate.a = night_a
			var darkness_col = Color.WHITE.lerp(Color(0.4, 0.4, 0.6), night_darkness)
			_sky_sprite_night.modulate.r = darkness_col.r
			_sky_sprite_night.modulate.g = darkness_col.g
			_sky_sprite_night.modulate.b = darkness_col.b
		
		# Background Rect Color (blends for better look)
		if _sky_bg_rect:
			var day_col = Color(0.48, 0.73, 0.89)
			var night_col_base = Color(0.04, 0.05, 0.12)
			var night_col_dark = Color(0.01, 0.01, 0.03)
			var sunset_col = Color(0.45, 0.25, 0.35)
			
			var night_col = night_col_base.lerp(night_col_dark, night_darkness)
			var final_col = day_col * day_a + sunset_col * sunset_a + night_col * night_a
			_sky_bg_rect.color = final_col

	if not is_game_started: return

	_water_timer += _delta
	if _water_timer >= WATER_TICK:
		_water_timer = 0.0
		_tick_water()

func _setup_sky_bg_rect() -> void:
	var cl := CanvasLayer.new()
	cl.layer = -10
	add_child(cl)
	_sky_bg_rect = ColorRect.new()
	_sky_bg_rect.position = Vector2(-4000, -4000)
	_sky_bg_rect.size     = Vector2(12000, 12000)
	_sky_bg_rect.color    = Color(0.48, 0.73, 0.89)
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

func _on_tutorial_pressed():
	if not tutorial_root:
		_setup_tutorial_ui()
	menu_root.visible = false
	tutorial_root.visible = true
	current_tutorial_slide = 0
	_update_tutorial_slide()

func _setup_tutorial_ui():
	tutorial_root = Control.new()
	tutorial_root.name = "TutorialTab"
	tutorial_root.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
	main_menu.add_child(tutorial_root)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
	tutorial_root.add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.LayoutPreset.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(1100, 680)
	vbox.position = Vector2(-550, -340)
	tutorial_root.add_child(vbox)

	# Side Navigation Arrows
	var left_arrow = Button.new()
	left_arrow.name = "LeftArrow"
	left_arrow.text = "<"
	left_arrow.custom_minimum_size = Vector2(60, 100)
	left_arrow.add_theme_font_size_override("font_size", 48)
	left_arrow.anchor_left = 0.5
	left_arrow.anchor_right = 0.5
	left_arrow.anchor_top = 0.5
	left_arrow.anchor_bottom = 0.5
	left_arrow.offset_left = -620
	left_arrow.offset_right = -560
	left_arrow.offset_top = -50
	left_arrow.offset_bottom = 50
	left_arrow.pressed.connect(_on_tutorial_prev)
	tutorial_root.add_child(left_arrow)

	var right_arrow = Button.new()
	right_arrow.name = "RightArrow"
	right_arrow.text = ">"
	right_arrow.custom_minimum_size = Vector2(60, 100)
	right_arrow.add_theme_font_size_override("font_size", 48)
	right_arrow.anchor_left = 0.5
	right_arrow.anchor_right = 0.5
	right_arrow.anchor_top = 0.5
	right_arrow.anchor_bottom = 0.5
	right_arrow.offset_left = 560
	right_arrow.offset_right = 620
	right_arrow.offset_top = -50
	right_arrow.offset_bottom = 50
	right_arrow.pressed.connect(_on_tutorial_next)
	tutorial_root.add_child(right_arrow)
	
	var title = Label.new()
	title.name = "Title"
	title.text = "TUTORIAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)
	
	vbox.add_spacer(false)
	
	var illust_container = Control.new()
	illust_container.name = "Illustration"
	illust_container.custom_minimum_size = Vector2(1050, 500)
	illust_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(illust_container)
	
	var texture_rect = TextureRect.new()
	texture_rect.name = "Image"
	texture_rect.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illust_container.add_child(texture_rect)
	
	var description = RichTextLabel.new()
	description.name = "Description"
	description.bbcode_enabled = true
	description.fit_content = true
	description.custom_minimum_size = Vector2(1000, 100)
	description.add_theme_font_size_override("normal_font_size", 28)
	vbox.add_child(description)
	
	vbox.add_spacer(false)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	
	var prev_btn = Button.new()
	prev_btn.name = "PrevBtn"
	prev_btn.text = "Previous"
	prev_btn.custom_minimum_size = Vector2(180, 60)
	prev_btn.add_theme_font_size_override("font_size", 28)
	prev_btn.pressed.connect(_on_tutorial_prev)
	hbox.add_child(prev_btn)
	
	var next_btn = Button.new()
	next_btn.name = "NextBtn"
	next_btn.text = "Next"
	next_btn.custom_minimum_size = Vector2(180, 60)
	next_btn.add_theme_font_size_override("font_size", 28)
	next_btn.pressed.connect(_on_tutorial_next)
	hbox.add_child(next_btn)
	
	var back_btn = Button.new()
	back_btn.name = "BackBtn"
	back_btn.text = "Back to Menu"
	back_btn.custom_minimum_size = Vector2(240, 60)
	back_btn.add_theme_font_size_override("font_size", 28)
	back_btn.pressed.connect(_on_tutorial_back)
	hbox.add_child(back_btn)

func _on_tutorial_next():
	current_tutorial_slide = min(current_tutorial_slide + 1, 6)
	_update_tutorial_slide()

func _on_tutorial_prev():
	current_tutorial_slide = max(current_tutorial_slide - 1, 0)
	_update_tutorial_slide()

func _on_tutorial_back():
	tutorial_root.visible = false
	menu_root.visible = true

func _update_tutorial_slide():
	var title = tutorial_root.find_child("Title", true, false) as Label
	var illust = tutorial_root.find_child("Illustration", true, false) as Control
	var img = illust.find_child("Image", true, false) as TextureRect
	var desc = tutorial_root.find_child("Description", true, false) as RichTextLabel
	var next_btn = tutorial_root.find_child("NextBtn", true, false) as Button
	var prev_btn = tutorial_root.find_child("PrevBtn", true, false) as Button
	var left_arrow = tutorial_root.find_child("LeftArrow", true, false) as Button
	var right_arrow = tutorial_root.find_child("RightArrow", true, false) as Button
	
	# Clear any dynamic animations from previous slides
	for child in illust.get_children():
		if child != img:
			child.queue_free()
	img.visible = true
	illust.visible = true

	prev_btn.disabled = (current_tutorial_slide == 0)
	if left_arrow: left_arrow.disabled = (current_tutorial_slide == 0)

	next_btn.text = "Finish" if current_tutorial_slide == 6 else "Next"
	if right_arrow: right_arrow.disabled = (current_tutorial_slide == 6)

	if current_tutorial_slide == 6 and next_btn.is_connected("pressed", _on_tutorial_next):
		next_btn.pressed.disconnect(_on_tutorial_next)
		if not next_btn.is_connected("pressed", _on_tutorial_back):
			next_btn.pressed.connect(_on_tutorial_back)
	elif current_tutorial_slide < 6 and next_btn.is_connected("pressed", _on_tutorial_back):
		next_btn.pressed.disconnect(_on_tutorial_back)
		if not next_btn.is_connected("pressed", _on_tutorial_next):
			next_btn.pressed.connect(_on_tutorial_next)

	match current_tutorial_slide:
		0:
			title.text = "1. Movement"
			img.texture = load("res://Walking.png")
			desc.text = "[center][color=yellow]WASD[/color] or [color=yellow]Arrow Keys[/color] to move with [color=yellow]Spacebar[/color] to jump.[/center]"
		1:
			title.text = "2. Climbing"
			img.texture = load("res://Climbing.png")
			desc.text = "[center]Hold [color=yellow]W + A/D[/color] to climb up walls.\nHold [color=yellow]S + A/D[/color] to climb down walls.[/center]"
		2:
			title.text = "3. Wall Jumping"
			img.visible = false
			var anim = load("res://scenes/tutorial_jump_anim.tscn").instantiate()
			illust.add_child(anim)
			desc.text = "[center]Press [color=yellow]Spacebar[/color] while on a wall to jump off it.[/center]"
		3:
			title.text = "4. Inventory"
			img.texture = load("res://Inventory.png")
			desc.text = "[center]Press [color=yellow]E[/color] to open your Inventory.\nCheck your [color=cyan]Drop Chances[/color] and [color=magenta]Rare Ores[/color] here.[/center]"
		4:
			title.text = "5. Oxygen"
			img.texture = load("res://Oxygen.png")
			desc.text = "[center]The [color=cyan]Oxygen Bar[/color] at the top shows your remaining air.\nIt drains while underground and refills at the surface.[/center]"
			title.text = "6. HUD Overview"
			img.texture = load("res://Hud overview.png")
			desc.text = "[center]Top: Oxygen & Money\nBottom: Hotbar\nRight: Minimap & Objectives\nLeft: Ore Collection & Value[/center]"
		6:
			title.text = "7. Good Luck!"
			img.texture = load("res://subterralogo.png")
			desc.text = "[center]Good luck on your journey into the depths!\nWatch your oxygen and mine carefully.[/center]"

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
	if tutorial_root: tutorial_root.visible = false
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
	return pos.y > SURFACE_Y and tilemap.get_cell_source_id(pos) == -1 \
		and not _water_pending.has(pos)

# Called by player after breaking a tile near water.
# Blocks the position for 0.5 s; the movement-based simulation then flows
# water into it naturally on the next tick (volume conserved automatically).
func notify_tile_removed(pos: Vector2i) -> void:
	var has_nb := false
	for nb in [pos + Vector2i(0,-1), pos + Vector2i(0,1),
			   pos + Vector2i(-1,0), pos + Vector2i(1,0)]:
		if _water_cells.has(nb):
			has_nb = true
			break
	if not has_nb:
		return
	_water_pending[pos] = true
	await get_tree().create_timer(0.5).timeout
	_water_pending.erase(pos)
	# Visual-only bubble at the topmost nearby water cell
	var top_pos := pos
	var found   := false
	for raw in _water_cells:
		var c := raw as Vector2i
		if abs(c.x - pos.x) <= 8:
			if not found or c.y < top_pos.y:
				top_pos = c
				found   = true
	if found and top_pos != pos:
		_spawn_water_bubble(top_pos)

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
	var changed := false

	# ── 1. GRAVITY (movement, not additive) ──────────────────────────────────
	# Sort cells highest-y first (deepest in world first) so that when the
	# bottom cell falls, the one above immediately falls into the vacated slot —
	# the whole column cascades in a single tick with no per-tick cell limit.
	var cells: Array[Vector2i] = []
	for raw in _water_cells:
		cells.append(raw as Vector2i)
	cells.sort_custom(func(a, b): return a.y > b.y)

	for cell in cells:
		if not _water_cells.has(cell):
			continue          # already moved earlier this frame
		var below := cell + Vector2i(0, 1)
		if not _water_cells.has(below) and _is_water_passable(below):
			var fd: int = _water_cell_dir.get(cell, -1)
			_water_cells.erase(cell)
			_water_cell_dir.erase(cell)
			_water_cells[below] = true
			_water_cell_dir[below] = fd
			changed = true

	# ── 2. SIDEWAYS SPREAD (additive, fills staircase steps) ─────────────────
	# Only for settled cells that cannot fall any further.
	var pref:  Array[Vector2i] = []
	var other: Array[Vector2i] = []
	for raw in _water_cells:
		var cell := raw as Vector2i
		var fd: int = _water_cell_dir.get(cell, -1)
		var below   := cell + Vector2i(0, 1)
		if _water_cells.has(below) or not _is_water_passable(below):
			for dx in [fd, -fd]:
				var side := cell + Vector2i(dx, 0)
				if not _water_cells.has(side) and _is_water_passable(side):
					if dx == fd: pref.append(side)
					else:        other.append(side)
					if not _water_cell_dir.has(side):
						_water_cell_dir[side] = fd

	var added := 0
	for pos in pref + other:
		if added >= WATER_PER_TICK: break
		if not _water_cells.has(pos) and _is_water_passable(pos):
			_water_cells[pos] = true
			added   += 1
			changed  = true

	# ── 3. SOURCE DRIP (refills top when gravity vacates it) ─────────────────
	for i in range(_water_sources.size()):
		var src  := _water_sources[i]
		var sdir := _water_source_dirs[i] if i < _water_source_dirs.size() else -1
		if not _water_cells.has(src) and _is_water_passable(src):
			_water_cells[src] = true
			if not _water_cell_dir.has(src):
				_water_cell_dir[src] = sdir
			changed = true

	if changed and _water_drawer:
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
	_water_pending.clear()
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
			else:
				var ore_roll = randf()
				if ore_roll < 0.025: # 2.5% chance for ANY ore
					if y >= 800 and randf() < 0.08: source_id = TILE_VOID
					elif y >= 500 and y < 1600 and randf() < 0.12: source_id = TILE_DIAMOND
					elif y >= 250 and y < 1400 and randf() < 0.18: source_id = TILE_RUBY
					elif y >= 100 and y < 1200 and randf() < 0.22: source_id = TILE_EMERALD
					elif y >= 45 and y < 1000 and randf() < 0.3: source_id = TILE_GOLD
					elif y >= 22 and y < 800 and randf() < 0.45: source_id = TILE_SILVER
					elif y >= 9 and y < 600: source_id = TILE_COPPER

				if source_id == TILE_DIRT:
					if y < 50:
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

	# 5. Sky — Three layers for day/sunset/night transitions
	_sky_sprite_day = null
	_sky_sprite_sunset = null
	_sky_sprite_night = null
	var bg_above = get_node_or_null("Background above")
	if bg_above:
		var spr_scale := Vector2(1.4, 1.4)
		var spr_z     := -1
		for child in bg_above.get_children():
			if child is Sprite2D and (child as Sprite2D).texture != null:
				spr_scale = (child as Sprite2D).scale
				spr_z     = (child as Sprite2D).z_index
				break
		for child in bg_above.get_children():
			child.queue_free()

		var day_tex = load("res://8bit-pixel-graphic-blue-sky-background-with-clouds-vector.jpg")
		var sunset_tex = load("res://sunset.png")
		var night_tex = load("res://night.png")
		
		var textures = [day_tex, sunset_tex, night_tex]
		var sprites = []
		
		for tex in textures:
			if tex:
				var sp := Sprite2D.new()
				sp.texture        = tex
				sp.scale          = spr_scale
				sp.z_index        = spr_z
				sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
				sp.centered       = true
				sp.region_enabled = true
				sp.region_rect    = Rect2(0.0, 0.0, float(tex.get_width()) * 4.0, float(tex.get_height()))
				bg_above.add_child(sp)
				
				var rect    := sp.get_rect()
				var bot_gly := sp.to_global(Vector2(0.0, rect.end.y)).y
				sp.global_position.y += surface_y - bot_gly
				sprites.append(sp)
			else:
				sprites.append(null)
		
		_sky_sprite_day = sprites[0]
		_sky_sprite_sunset = sprites[1]
		_sky_sprite_night = sprites[2]
		
		# Initial Alphas
		if _sky_sprite_day: _sky_sprite_day.modulate.a = 1.0
		if _sky_sprite_sunset: _sky_sprite_sunset.modulate.a = 0.0
		if _sky_sprite_night: _sky_sprite_night.modulate.a = 0.0

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
					bg.modulate = Color(0.38, 0.32, 0.28, 1.0)
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

func _setup_ore_tiles():
	var ts = tilemap.tile_set
	if not ts: return
	var ores = {
		TILE_COPPER: "res://Stones_ores_bars/copper_node.png",
		TILE_SILVER: "res://Stones_ores_bars/silver_node.png",
		TILE_GOLD: "res://Stones_ores_bars/gold_node.png",
		TILE_EMERALD: "res://Stones_ores_bars/emerald_ore.png",
		TILE_RUBY: "res://Stones_ores_bars/ruby_ore.png",
		TILE_DIAMOND: "res://Stones_ores_bars/diamond_ore.png",
		TILE_VOID: "res://Stones_ores_bars/void_crystal_ore.png"
	}
	for id in ores:
		if ts.has_source(id): continue
		var tex = load(ores[id]) as Texture2D
		if tex:
			var img = tex.get_image()
			# Ores appear as 16x16 specks in 128x128 tiles. Upscale 5x for visibility.
			img.resize(img.get_width() * 5, img.get_height() * 5, Image.INTERPOLATE_NEAREST)
			var scaled_tex = ImageTexture.create_from_image(img)
			
			var source = TileSetAtlasSource.new()
			source.texture = scaled_tex
			source.texture_region_size = scaled_tex.get_size()
			source.create_tile(Vector2i(0, 0))
			var td = source.get_tile_data(Vector2i(0, 0), 0)
			# Full block collision: 128/2 = 64
			td.set_collision_polygon_points(0, 0, PackedVector2Array([-64,-64, 64,-64, 64,64, -64,64]))
			ts.add_source(source, id)
