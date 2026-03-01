extends CharacterBody2D

signal died
signal ore_collected(ore_name)


# Stats (Upgradable!)
var speed: float = 300.0
var jump_speed: float = 400.0
var climb_speed: float = 150.0
var gravity: float = 980.0
var mine_time: float = 1.8 # Default for Starter Pick
var base_mine_time: float = 1.8
var max_battery: float = 100.0
var current_battery: float = 100.0
var max_cargo: int = 10
var current_cargo: int = 0

# Shop upgrades (repeatable)
var cargo_upgrade_level: int = 0
var oxygen_upgrade_level: int = 0
var speed_upgrade_level: int = 0
var mining_speed_upgrade_level: int = 0

const MINE_TIME_UPGRADE_FACTOR: float = 0.90  # 10% faster per level
const MIN_MINE_TIME_MULT: float = 0.35

# --- Grappling Hook ---
var grapple_active: bool = false
var grapple_point: Vector2
var grapple_tile: Vector2i
var grapple_force: float = 600.0
var grapple_hover_tile: Vector2i
var grapple_hover_valid: bool = false
var grapple_hover_invalid: bool = false
var is_grapple_moving: bool = false
var is_wall_stuck: bool = false
const WALL_STICK_SLIDE_SPEED: float = 44.8  # half-tile/sec in global space
const GRAPPLE_MAX_TILES: int = 8

# --- Minimap ---
var minimap_texture_rect: TextureRect
var minimap_timer_node: Timer
var minimap_image: Image
var minimap_zoom: float = 9.0
const MINIMAP_W: int = 120
const MINIMAP_H: int = 150
const MINIMAP_TILE_COLORS = {
	0: Color(0.45, 0.30, 0.15),
	1: Color(0.25, 0.65, 0.15),
	3: Color(0.55, 0.55, 0.55),
	4: Color(0.25, 0.25, 0.30),
}
const MINIMAP_EMPTY_COLOR = Color(0.05, 0.05, 0.05)
const MINIMAP_PLAYER_COLOR = Color(1.0, 1.0, 1.0)

# --- Low Battery Overlay ---
var low_battery_overlay: ColorRect
var low_oxygen_label: Label
var low_oxygen_onset_time: float = -1.0  # tracks when warning first appeared
const LOW_BATTERY_PULSE_MIN: float = 0.10
const LOW_BATTERY_PULSE_MAX: float = 0.35
const LOW_BATTERY_PULSE_SPEED: float = 2.5

# --- Game Clock ---
var game_minutes: float = 7.0 * 60.0  # Start at 7:00 AM
var clock_label: Label

# --- End of Day Stats & UI ---
var day_count: int = 0
var day_label: Label
var daily_ores_collected: int = 0
var daily_money_made: int = 0
var times_died: int = 0

# --- Daily Objectives ---
var daily_objectives: Array[Dictionary] = []
var daily_max_depth: int = 0
var daily_mutated_collected: int = 0
var daily_ore_collected: Dictionary = {} # base ore name -> count (non-mutated)
var daily_objectives_rewarded: bool = false
var objectives_label: RichTextLabel
var objectives_toggle_btn: Button
var _last_objectives_hud_text: String = "__init__"

# --- Inventory & Storage ---
var selected_slot: int = 0
var hotbar_slots: Array[Panel] = []
var hotbar_item_ids: Array[String] = []
var hotbar_item_counts: Array[int] = []
var hotbar_item_labels: Array[Label] = []
var hotbar_item_count_labels: Array[Label] = []
const HOTBAR_SLOT_COUNT: int = 9

# Hotbar consumables
const ITEM_POTION_SURFACE: String = "potion_surface"
const ITEM_POTION_OXYGEN: String = "potion_oxygen"
const ITEM_POTION_SPEED: String = "potion_speed"
const OXYGEN_POTION_RESTORE: float = 60.0
const SPEED_POTION_MULT: float = 1.5
const SPEED_POTION_DURATION: float = 10.0
var speed_potion_timer: float = 0.0
var speed_potion_mult: float = 1.0
var cargo_label: Label

var grapple_line: Line2D

# --- Luck Strategy ---
var oxygen_luck_bonus: float = 1.0

var end_day_layer: CanvasLayer
var fade_rect: ColorRect
var dashboard: TextureRect
var stats_label: RichTextLabel
var close_btn: TextureButton

var is_end_of_day: bool = false

# TileSet source IDs (matching main.gd)
const TILE_DIRT := 0
const TILE_GRASS := 1
const TILE_COBBLE := 3
const TILE_DEEPSLATE := 4

# Mining SFX (assign in Inspector, or place `anvil.mp3` at res://anvil.mp3)
const DEFAULT_MINING_SFX_PATH: String = "res://anvil.mp3"
@export var mining_sfx: AudioStream
var mining_sfx_player: AudioStreamPlayer

# Walking SFX (assign in Inspector, or place `walking.mp3` at res://walking.mp3)
const DEFAULT_WALKING_SFX_PATH: String = "res://walking.mp3"
@export var walking_sfx: AudioStream
var walking_sfx_player: AudioStreamPlayer

# Upgrade tracking
var pickaxe_level: int = 0
const PICKAXE_UPGRADES = [
	{"name": "Starter Pick", "price": 0,     "mine_time": 1.8,  "luck": 1.0,  "color": Color(0.6, 0.6, 0.6)},
	{"name": "Stone Pick",   "price": 500,   "mine_time": 1.25, "luck": 1.1,  "color": Color(0.75, 0.7, 0.65)},
	{"name": "Copper Pick",  "price": 1000,  "mine_time": 0.9,  "luck": 1.2,  "color": Color(0.9, 0.5, 0.15)},
	{"name": "Silver Pick",  "price": 5000,  "mine_time": 0.54, "luck": 1.35, "color": Color(0.8, 0.85, 0.95)},
	{"name": "Gold Pick",    "price": 50000, "mine_time": 0.27, "luck": 1.55,  "color": Color(1.0, 0.85, 0.1)},
	{"name": "Admin Pick",   "price": 0,     "mine_time": 0.01, "luck": 10.0,  "color": Color(0.80, 0.20, 0.95), "admin": true, "insta_mine": true}
]

@onready var mining_timer: Timer = $MiningTimer
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
var tilemap: TileMapLayer
var hud: CanvasLayer
var money_label: Label
var oxygen_bar: ProgressBar
var money: int = 0
var is_mining: bool = false
var target_tile_coords: Vector2i
var spawn_position: Vector2

# --- Depth Lighting ---
var depth_canvas_modulate: CanvasModulate
const DEPTH_DARKEN_START_TILE_Y: int = 6
const DEPTH_DARKEN_FULL_TILE_Y: int = 220
const DEPTH_DARKEN_MIN_MULT: float = 0.22

# --- Flashlight ---
var flashlight: PointLight2D
var flashlight_texture: Texture2D
const FLASHLIGHT_TEX_SIZE: int = 256
const FLASHLIGHT_MAX_RADIUS_FRAC: float = 0.48
const FLASHLIGHT_ENERGY_SURFACE: float = 0.35
const FLASHLIGHT_ENERGY_DEEP: float = 0.9
var flashlight_on: bool = true

# Track which direction the player is facing so we know which block to target
var facing_dir: int = 1  # 1 = right, -1 = left
var is_walking: bool = false
var is_wall_climbing: bool = false

# Highlight state — updated every frame based on mouse position
var highlighted_tile: Vector2i
var highlight_valid: bool = false
# Tile size in world space: tileset is 128px, TileMapLayer scale is 0.5
const TILE_WORLD_SIZE = 64.0

# --- Block Break VFX ---
const _BREAK_TEX_PATH_BY_SOURCE := {
	TILE_DIRT: "res://dirt.png",
	TILE_GRASS: "res://grass.png",
	TILE_COBBLE: "res://blocks/cobblestone.png",
	TILE_DEEPSLATE: "res://blocks/deepslate.png",
}

func _spawn_block_break_effect(tile_center_global: Vector2, source_id: int) -> void:
	var tex_path: String = ""
	if _BREAK_TEX_PATH_BY_SOURCE.has(source_id):
		tex_path = _BREAK_TEX_PATH_BY_SOURCE[source_id]
	if tex_path == "":
		return
	var tex := load(tex_path) as Texture2D
	if tex == null:
		return

	var root := Node2D.new()
	root.z_index = 10
	var parent_node := get_parent()
	if parent_node != null:
		parent_node.add_child(root)
		if parent_node is Node2D:
			root.position = (parent_node as Node2D).to_local(tile_center_global)
		else:
			root.global_position = tile_center_global
	else:
		# Fallback: still place it, though it won't be visible without being in-tree.
		root.global_position = tile_center_global

	var tex_size := tex.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		root.queue_free()
		return

	# Texture (128px) -> world tile (64px) scale.
	var base_scale := TILE_WORLD_SIZE / float(tex_size.x)
	base_scale = clampf(base_scale, 0.05, 8.0)

	var chunk_px := int(max(8.0, min(tex_size.x, tex_size.y) / 4.0))
	var chunk_count := 7
	var duration := 0.42

	for i in range(chunk_count):
		var s := Sprite2D.new()
		s.texture = tex
		s.region_enabled = true
		var rx := randi_range(0, max(0, int(tex_size.x) - chunk_px))
		var ry := randi_range(0, max(0, int(tex_size.y) - chunk_px))
		s.region_rect = Rect2(rx, ry, chunk_px, chunk_px)
		s.centered = true
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2.ONE * base_scale * randf_range(0.8, 1.05)
		s.position = Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		s.rotation = randf_range(-0.8, 0.8)
		root.add_child(s)

		var vel := Vector2(randf_range(-120.0, 120.0), randf_range(-220.0, -80.0))
		var t := root.create_tween()
		t.tween_property(s, "position", s.position + vel * duration, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(s, "rotation", s.rotation + randf_range(-2.5, 2.5), duration)
		t.parallel().tween_property(s, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Clean up after the last tween finishes.
	var cleanup := root.create_tween()
	cleanup.tween_interval(duration + 0.05)
	cleanup.tween_callback(root.queue_free)

# --- Mutated Ores ---
const MUTATED_CHANCE: float = 0.05
const MUTATED_DROP_DENOM: float = 999999.0  # kept for pricing/inventory; never rolled directly

# Ore table: [name, 1-in-N drop chance, value per ore, display color]
const ORE_TABLE = [
	["Stone",  1.8,  2,   Color(0.75, 0.70, 0.65)],
	["Copper", 9, 15,  Color(0.90, 0.50, 0.15)],
	["Silver", 22, 50,  Color(0.80, 0.85, 0.95)],
	["Gold",   45, 200, Color(1.00, 0.85, 0.10)],
	["Mutated Stone",  MUTATED_DROP_DENOM,  8,   Color(0.80, 0.20, 0.95)],
	["Mutated Copper", MUTATED_DROP_DENOM,  60,  Color(0.80, 0.20, 0.95)],
	["Mutated Silver", MUTATED_DROP_DENOM,  200, Color(0.80, 0.20, 0.95)],
	["Mutated Gold",   MUTATED_DROP_DENOM,  800, Color(0.80, 0.20, 0.95)],
	["Rainbow", 180, 2500, Color(1.00, 1.00, 1.00)],
]

# Per-ore inventory counts
var ore_counts: Dictionary = {}
# Lifetime collection counts
var lifetime_ore_counts: Dictionary = {}
# HUD label references keyed by ore name

var ore_labels: Dictionary = {}

# --- Inventory (opened with the `inventory` action, default E) ---
var inventory_panel: ColorRect
var inventory_label: RichTextLabel
var inventory_open: bool = false
var is_in_menu: bool = false # Used to block player input when shop/trader is open

func _is_gameplay_enabled() -> bool:
	# Block gameplay while the main menu is up (tree paused) and until Start is clicked.
	# Note: `Main` sets `process_mode = ALWAYS`, so we must explicitly opt out.
	if get_tree() == null:
		return true
	if get_tree().paused:
		return false
	var main := get_parent()
	if main != null and ("is_game_started" in main):
		return bool(main.is_game_started)
	return true

func _ready():
	# Ensure we pause correctly even though the scene root (`Main`) runs while paused.
	process_mode = PROCESS_MODE_PAUSABLE
	# ... rest of _ready (no change to the beginning)
	base_mine_time = float(PICKAXE_UPGRADES[pickaxe_level]["mine_time"])
	recompute_mine_time()
	spawn_position = global_position
	# Find TileMapLayer more robustly
	var main = get_parent()
	tilemap = main.get_node_or_null("Dirt") as TileMapLayer
	_setup_depth_lighting()
	_setup_flashlight()
	
	# Find HUD nodes more robustly
	hud = main.get_node_or_null("HUD") as CanvasLayer
	if hud:
		money_label = hud.get_node_or_null("MoneyLabel") as Label
		if money_label:
			money_label.text = "$0"

		clock_label = hud.get_node_or_null("ClockLabel") as Label
		if clock_label:
			clock_label.text = _format_game_time(game_minutes)
			
			day_label = Label.new()
			day_label.text = "Day " + str(day_count)
			day_label.add_theme_font_size_override("font_size", 18)
			day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# Position day_label at top, clock_label below it
			day_label.position = Vector2(1060.0, 10.0)
			day_label.size = Vector2(210, 30) # Match ClockLabel width
			hud.add_child(day_label)

			clock_label.position = Vector2(1060.0, 35.0)
			clock_label.add_theme_font_size_override("font_size", 18)

		# Move Minimap down
		var minimap_panel = hud.get_node_or_null("MinimapPanel") as Panel
		if minimap_panel:
			minimap_panel.position.y = 70.0
			
			# Cargo label under minimap
			cargo_label = Label.new()
			cargo_label.text = "Cargo: 0/%d" % max_cargo
			cargo_label.add_theme_font_size_override("font_size", 18)
			cargo_label.position = Vector2(minimap_panel.position.x, minimap_panel.position.y + minimap_panel.size.y + 5.0)
			hud.add_child(cargo_label)

			# Daily objectives toggle button (under minimap)
			var obj_x: float = minimap_panel.position.x
			var obj_y: float = minimap_panel.position.y + minimap_panel.size.y + 32.0
			var obj_w: float = minimap_panel.size.x if minimap_panel.size.x > 0.0 else float(MINIMAP_W) + 10.0
			objectives_toggle_btn = Button.new()
			objectives_toggle_btn.text = "Daily Tasks ▼"
			objectives_toggle_btn.position = Vector2(obj_x, obj_y)
			objectives_toggle_btn.size = Vector2(obj_w, 28)
			objectives_toggle_btn.add_theme_font_size_override("font_size", 14)
			var obj_btn_sb := StyleBoxFlat.new()
			obj_btn_sb.bg_color = Color(0.08, 0.08, 0.14, 0.85)
			obj_btn_sb.border_width_left = 1
			obj_btn_sb.border_width_top = 1
			obj_btn_sb.border_width_right = 1
			obj_btn_sb.border_width_bottom = 1
			obj_btn_sb.border_color = Color(0.35, 0.35, 0.5, 1.0)
			obj_btn_sb.corner_radius_top_left = 6
			obj_btn_sb.corner_radius_top_right = 6
			obj_btn_sb.corner_radius_bottom_left = 6
			obj_btn_sb.corner_radius_bottom_right = 6
			objectives_toggle_btn.add_theme_stylebox_override("normal", obj_btn_sb)
			var obj_btn_hover := obj_btn_sb.duplicate() as StyleBoxFlat
			obj_btn_hover.bg_color = Color(0.14, 0.14, 0.22, 0.9)
			objectives_toggle_btn.add_theme_stylebox_override("hover", obj_btn_hover)
			objectives_toggle_btn.add_theme_stylebox_override("pressed", obj_btn_sb)
			objectives_toggle_btn.pressed.connect(_toggle_objectives_panel)
			hud.add_child(objectives_toggle_btn)

			# Daily objectives panel (hidden by default, revealed by button)
			objectives_label = RichTextLabel.new()
			objectives_label.bbcode_enabled = true
			objectives_label.fit_content = true
			objectives_label.scroll_active = false
			objectives_label.mouse_filter = Control.MouseFilter.MOUSE_FILTER_IGNORE
			objectives_label.position = Vector2(obj_x, obj_y + 30.0)
			objectives_label.size = Vector2(obj_w, 110)
			objectives_label.add_theme_font_size_override("normal_font_size", 14)
			objectives_label.visible = false
			hud.add_child(objectives_label)

		# --- Hotbar (Minecraft-style) ---
		var hotbar_bg = Panel.new()
		hotbar_bg.custom_minimum_size = Vector2(520, 70)
		var bg_sb = StyleBoxFlat.new()
		bg_sb.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		bg_sb.corner_radius_top_left = 10; bg_sb.corner_radius_top_right = 10
		bg_sb.border_width_top = 2; bg_sb.border_color = Color(0.3, 0.3, 0.3)
		hotbar_bg.add_theme_stylebox_override("panel", bg_sb)
		# Godot 4 doesn't have a built-in "bottom center" preset; anchor explicitly.
		hotbar_bg.anchor_left = 0.5
		hotbar_bg.anchor_right = 0.5
		hotbar_bg.anchor_top = 1.0
		hotbar_bg.anchor_bottom = 1.0
		hotbar_bg.offset_left = -hotbar_bg.custom_minimum_size.x * 0.5
		hotbar_bg.offset_right = hotbar_bg.custom_minimum_size.x * 0.5
		hotbar_bg.offset_top = -70
		hotbar_bg.offset_bottom = 0
		hud.add_child(hotbar_bg)

		var hotbar_container = HBoxContainer.new()
		hotbar_container.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
		hotbar_container.alignment = BoxContainer.ALIGNMENT_CENTER
		hotbar_container.add_theme_constant_override("separation", 8)
		hotbar_bg.add_child(hotbar_container)
		
		hotbar_item_ids.clear()
		hotbar_item_counts.clear()
		hotbar_item_labels.clear()
		hotbar_item_count_labels.clear()
		for i in range(HOTBAR_SLOT_COUNT):
			var slot = Panel.new()
			slot.custom_minimum_size = Vector2(50, 50)
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			sb.border_width_left = 2; sb.border_width_top = 2; sb.border_width_right = 2; sb.border_width_bottom = 2
			sb.border_color = Color(0.4, 0.4, 0.4)
			slot.add_theme_stylebox_override("panel", sb)
			
			# Slot number
			var num_label = Label.new()
			num_label.text = str(i + 1)
			num_label.add_theme_font_size_override("font_size", 12)
			num_label.position = Vector2(5, 2)
			num_label.modulate = Color(0.8, 0.8, 0.8, 0.8)
			slot.add_child(num_label)
			
			if i == 0:
				sb.border_color = Color(1, 0.9, 0) # Keep selection highlight for slot 1
				sb.bg_color = Color(0.3, 0.3, 0.3, 0.9)
				hotbar_item_labels.append(null)
				hotbar_item_count_labels.append(null)

			else:
				var item_lbl := Label.new()
				item_lbl.name = "ItemLabel"
				item_lbl.text = ""
				item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				item_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				item_lbl.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
				item_lbl.add_theme_font_size_override("font_size", 14)
				item_lbl.modulate = Color(1.0, 1.0, 1.0, 0.95)
				slot.add_child(item_lbl)
				hotbar_item_labels.append(item_lbl)

				var count_lbl := Label.new()
				count_lbl.name = "CountLabel"
				count_lbl.text = ""
				count_lbl.add_theme_font_size_override("font_size", 12)
				count_lbl.modulate = Color(1.0, 1.0, 1.0, 0.95)
				count_lbl.anchor_left = 1.0
				count_lbl.anchor_right = 1.0
				count_lbl.anchor_top = 1.0
				count_lbl.anchor_bottom = 1.0
				count_lbl.offset_right = -4.0
				count_lbl.offset_left = -22.0
				count_lbl.offset_bottom = -2.0
				count_lbl.offset_top = -16.0
				count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				slot.add_child(count_lbl)
				hotbar_item_count_labels.append(count_lbl)

			hotbar_item_ids.append("")
			hotbar_item_counts.append(0)
			
			hotbar_container.add_child(slot)
			hotbar_slots.append(slot)

		var item_label = Label.new()
		item_label.name = "SelectedItemLabel"
		item_label.text = ""

		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.custom_minimum_size = Vector2(520, 30)
		item_label.anchor_left = 0.5
		item_label.anchor_right = 0.5
		item_label.anchor_top = 1.0
		item_label.anchor_bottom = 1.0
		item_label.offset_left = -item_label.custom_minimum_size.x * 0.5
		item_label.offset_right = item_label.custom_minimum_size.x * 0.5
		item_label.offset_bottom = -75
		item_label.offset_top = item_label.offset_bottom - item_label.custom_minimum_size.y
		item_label.add_theme_font_size_override("font_size", 20)
		item_label.add_theme_color_override("font_outline_color", Color.BLACK)
		item_label.add_theme_constant_override("outline_size", 4)
		hud.add_child(item_label)

		oxygen_bar = hud.get_node_or_null("ProgressBar") as ProgressBar
		if oxygen_bar:
			oxygen_bar.visible = true
			oxygen_bar.anchor_left = 0.5
			oxygen_bar.anchor_right = 0.5
			oxygen_bar.anchor_top = 0.0
			oxygen_bar.anchor_bottom = 0.0
			oxygen_bar.offset_left = -125.0
			oxygen_bar.offset_right = 125.0
			oxygen_bar.offset_top = 20.0
			oxygen_bar.offset_bottom = 50.0
			oxygen_bar.max_value = max_battery
			oxygen_bar.value = current_battery
			
			var ox_label = oxygen_bar.get_node_or_null("Label") as Label
			if ox_label:
				ox_label.text = "Oxygen"
				ox_label.position = Vector2(85, -24)

		# --- Low Battery Overlay ---
		low_battery_overlay = hud.get_node_or_null("LowBatteryOverlay") as ColorRect

		# --- Low Oxygen Warning Label ---
		var lbl_ox = Label.new()
		lbl_ox.text = "LOW OXYGEN LEVELS"
		lbl_ox.add_theme_font_size_override("font_size", 72)
		lbl_ox.modulate = Color(1.0, 0.3, 0.3, 0.0)
		lbl_ox.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_ox.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_ox.anchor_left = 0.5
		lbl_ox.anchor_right = 0.5
		lbl_ox.anchor_top = 0.5
		lbl_ox.anchor_bottom = 0.5
		lbl_ox.offset_left = -420.0
		lbl_ox.offset_right = 420.0
		lbl_ox.offset_top = -50.0
		lbl_ox.offset_bottom = 50.0
		lbl_ox.z_index = 5
		hud.add_child(lbl_ox)
		low_oxygen_label = lbl_ox

		# --- Inventory Panel ---
		inventory_panel = ColorRect.new()
		inventory_panel.visible = false
		inventory_panel.color = Color(0.0, 0.0, 0.0, 0.78)
		# Attach inventory to the hotbar area (bottom-center), like a drop-up panel.
		inventory_panel.anchor_left = 0.5
		inventory_panel.anchor_right = 0.5
		inventory_panel.anchor_top = 1.0
		inventory_panel.anchor_bottom = 1.0
		# Match hotbar width (520) and open above it.
		inventory_panel.offset_left = -260.0
		inventory_panel.offset_right = 260.0
		inventory_panel.offset_bottom = -80.0
		inventory_panel.offset_top = inventory_panel.offset_bottom - 240.0
		inventory_panel.z_index = 20
		hud.add_child(inventory_panel)

		inventory_label = RichTextLabel.new()
		inventory_label.bbcode_enabled = true
		inventory_label.fit_content = true
		inventory_label.anchor_left = 0.0
		inventory_label.anchor_right = 1.0
		inventory_label.anchor_top = 0.0
		inventory_label.anchor_bottom = 1.0
		inventory_label.offset_left = 18.0
		inventory_label.offset_right = -18.0
		inventory_label.offset_top = 14.0
		inventory_label.offset_bottom = -14.0
		inventory_panel.add_child(inventory_label)

		# Initialise ore counts and build HUD labels
		var y: float = 68.0
		for ore in ORE_TABLE:
			var nm: String = ore[0]
			ore_counts[nm] = 0
			if nm in ["Stone", "Copper", "Silver", "Gold"]:
				var lbl := Label.new()
				lbl.text = "%s: 0" % nm
				lbl.modulate = ore[3] as Color
				lbl.add_theme_font_size_override("font_size", 20)
				lbl.position = Vector2(20.0, y)
				hud.add_child(lbl)
				ore_labels[nm] = lbl
				y += 26.0

		# --- Minimap ---
		if minimap_panel:
			minimap_texture_rect = minimap_panel.get_node_or_null("MinimapTexture") as TextureRect
			minimap_timer_node = minimap_panel.get_node_or_null("MinimapTimer") as Timer
			if minimap_timer_node:
				if minimap_timer_node.timeout.is_connected(_update_minimap):
					minimap_timer_node.timeout.disconnect(_update_minimap)
				minimap_timer_node.timeout.connect(_update_minimap)
				minimap_timer_node.start()
		minimap_image = Image.create(MINIMAP_W, MINIMAP_H, false, Image.FORMAT_RGBA8)
		_update_minimap()

	# Grapple Line
	grapple_line = Line2D.new()
	grapple_line.width = 2.0
	grapple_line.default_color = Color(0.7, 0.5, 0.3)
	grapple_line.visible = false
	get_parent().add_child.call_deferred(grapple_line)

	# Mining sound player
	mining_sfx_player = AudioStreamPlayer.new()
	add_child(mining_sfx_player)
	
	# Init hotbar
	# (Pickaxe lives in slot 1; consumables use slots 2-9)

	if mining_sfx == null and ResourceLoader.exists(DEFAULT_MINING_SFX_PATH):

		mining_sfx = load(DEFAULT_MINING_SFX_PATH) as AudioStream
	if mining_sfx != null:
		mining_sfx_player.stream = mining_sfx

	# Walking sound player
	walking_sfx_player = AudioStreamPlayer.new()
	add_child(walking_sfx_player)
	if walking_sfx == null and ResourceLoader.exists(DEFAULT_WALKING_SFX_PATH):
		walking_sfx = load(DEFAULT_WALKING_SFX_PATH) as AudioStream
	if walking_sfx != null:
		walking_sfx_player.stream = walking_sfx

	mining_timer.timeout.connect(finish_mining)
	add_to_group("player")
	z_index = 1

	_generate_daily_objectives()
	_update_daily_objectives_hud()

	_setup_end_of_day_ui()

func _setup_depth_lighting() -> void:
	var main := get_parent()
	if main == null:
		return
	# NOTE: Adding children to the parent from inside a child's `_ready()` can error
	# with "Parent node is busy setting up children". Use deferred parenting.
	var existing := main.get_node_or_null("DepthCanvasModulate") as CanvasModulate
	if existing != null:
		depth_canvas_modulate = existing
	elif depth_canvas_modulate == null:
		depth_canvas_modulate = CanvasModulate.new()
		depth_canvas_modulate.name = "DepthCanvasModulate"
	# Ensure the node is actually parented to `main` (it may exist but not be in-tree
	# yet if a previous add failed).
	if depth_canvas_modulate.get_parent() != main:
		main.add_child.call_deferred(depth_canvas_modulate)
		# Keep it near the top for clarity (render order isn't critical for CanvasModulate).
		main.move_child.call_deferred(depth_canvas_modulate, 0)
	_update_depth_lighting()

func _setup_flashlight() -> void:
	if flashlight != null:
		return
	flashlight = PointLight2D.new()
	flashlight.name = "Flashlight"
	flashlight.enabled = flashlight_on
	flashlight.energy = FLASHLIGHT_ENERGY_SURFACE
	flashlight.color = Color(1.0, 0.98, 0.9)
	flashlight.texture_scale = 1.5
	flashlight.shadow_enabled = false
	if flashlight_texture == null:
		flashlight_texture = _create_flashlight_texture(FLASHLIGHT_TEX_SIZE)
	flashlight.texture = flashlight_texture
	add_child(flashlight)
	_update_flashlight()

func _create_flashlight_texture(size: int) -> Texture2D:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center: Vector2 = Vector2(float(size) * 0.5, float(size) * 0.5)
	var max_r: float = float(size) * FLASHLIGHT_MAX_RADIUS_FRAC

	for y in range(size):
		for x in range(size):
			var v: Vector2 = Vector2(float(x), float(y)) - center
			var dist: float = v.length()
			if dist <= 0.001 or dist > max_r:
				continue
			var radial: float = 1.0 - (dist / max_r)
			var a: float = clampf(radial * radial, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))

	return ImageTexture.create_from_image(img)

func _update_depth_lighting() -> void:
	if depth_canvas_modulate == null:
		return
	if tilemap == null:
		depth_canvas_modulate.color = Color(1, 1, 1)
		return
	var pos_tile: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
	var y: int = int(pos_tile.y)
	var t: float = 0.0
	if y > DEPTH_DARKEN_START_TILE_Y:
		t = clampf(float(y - DEPTH_DARKEN_START_TILE_Y) / float(DEPTH_DARKEN_FULL_TILE_Y - DEPTH_DARKEN_START_TILE_Y), 0.0, 1.0)
	var mult: float = lerpf(1.0, DEPTH_DARKEN_MIN_MULT, t)
	depth_canvas_modulate.color = Color(mult, mult, mult, 1.0)

func _update_flashlight() -> void:
	if flashlight == null:
		return
	flashlight.enabled = flashlight_on
	if not flashlight_on:
		return

	# Make light stronger as the player goes deeper.
	var energy := FLASHLIGHT_ENERGY_SURFACE
	if tilemap != null:
		var pos_tile: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
		var y: int = int(pos_tile.y)
		var t: float = 0.0
		if y > DEPTH_DARKEN_START_TILE_Y:
			t = clampf(float(y - DEPTH_DARKEN_START_TILE_Y) / float(DEPTH_DARKEN_FULL_TILE_Y - DEPTH_DARKEN_START_TILE_Y), 0.0, 1.0)
		energy = lerpf(FLASHLIGHT_ENERGY_SURFACE, FLASHLIGHT_ENERGY_DEEP, t)
	flashlight.energy = energy
	# Omnidirectional light centered on the player.
	flashlight.position = Vector2(0.0, -8.0)
	flashlight.rotation = 0.0

func get_mine_time_mult() -> float:
	return clamp(pow(MINE_TIME_UPGRADE_FACTOR, float(mining_speed_upgrade_level)), MIN_MINE_TIME_MULT, 1.0)

func recompute_mine_time() -> void:
	mine_time = max(0.05, base_mine_time * get_mine_time_mult())


func _process(delta: float) -> void:
	if is_end_of_day or not _is_gameplay_enabled():
		return
	_update_depth_lighting()
	game_minutes += delta * 5.0  # 1 real second = 5 game minutes

	if game_minutes >= 1440.0:
		game_minutes -= 1440.0
		trigger_end_of_day()
	if clock_label:
		clock_label.text = _format_game_time(game_minutes)

func _physics_process(delta):
	if is_end_of_day or not _is_gameplay_enabled():
		is_walking = false
		if is_mining:
			cancel_mining()
		velocity = Vector2.ZERO
		_update_animation()
		_update_walking_sfx()
		return
	if not tilemap: return
	if is_in_menu or inventory_open:
		is_walking = false
		if is_mining: cancel_mining()
		_update_animation()
		_update_flashlight()
		return

	if is_grapple_moving:
		_update_walking_sfx()
		_update_grapple_line()
		_update_flashlight()
		return  # Physics paused during grapple travel

	# Oxygen-based Luck Strategy: Lower oxygen = higher luck bonus
	# Bonus ranges from 1.0 (full tank) to 2.5 (empty tank)
	oxygen_luck_bonus = 1.0 + (1.0 - (current_battery / max_battery)) * 1.5

	# 1. Drain Battery (Oxygen)
	var pos_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var depth_y: int = max(0, int(pos_tile.y))
	if depth_y > daily_max_depth:
		daily_max_depth = depth_y
		_update_daily_objectives_hud()
	var tile_below = pos_tile + Vector2i(0, 1)
	var on_grass = tilemap.get_cell_source_id(tile_below) == 1
	var tile_at_feet = tilemap.get_cell_source_id(pos_tile) == 1

	if (not on_grass and not tile_at_feet) and pos_tile.y > 0:
		current_battery -= delta * 2.0
	else:
		var refill_rate = 60.0 if (on_grass or tile_at_feet) else 15.0
		current_battery = min(max_battery, current_battery + delta * refill_rate)

	if oxygen_bar:
		oxygen_bar.value = current_battery
	_update_low_battery_overlay()

	if current_battery <= 0:
		die_and_respawn()

	# Timed speed potion
	if speed_potion_timer > 0.0:
		speed_potion_timer = max(0.0, speed_potion_timer - delta)
		if speed_potion_timer == 0.0:
			speed_potion_mult = 1.0

	# 2. Horizontal input
	var h = Input.get_axis("Left", "Right")
	is_walking = h != 0
	if h != 0:
		facing_dir = sign(h)

	# --- Wall Stick (post-grapple) ---
	if is_wall_stuck:
		_update_grapple_line()
		if is_on_floor() or h != 0:
			is_wall_stuck = false
			_release_grapple()
		else:
			velocity.y = WALL_STICK_SLIDE_SPEED
			velocity.x = 0.0
			if Input.is_action_just_pressed("ui_accept"):
				velocity.y = -jump_speed
				is_wall_stuck = false
				_release_grapple()
			move_and_slide()
			_update_highlight()
			_update_grapple_hover()
			_update_animation()
			_update_walking_sfx()
			queue_redraw()
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and selected_slot == 0:
				if highlight_valid and not is_mining:
					start_mining(highlighted_tile)
			else:
				if is_mining: cancel_mining()
			return

	# 3. Gravity (moved before move_and_slide)
	if not is_on_floor() and not is_wall_climbing:
		velocity.y += gravity * delta

	# 4. Jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = -jump_speed

	# 5. Velocity
	velocity.x = h * speed * speed_potion_mult
	if is_wall_climbing:
		velocity.y = -climb_speed

	move_and_slide()

	# 6. Wall climbing (now after move_and_slide for better sync)
	var wall_normal = get_wall_normal()
	is_wall_climbing = (
		is_on_wall()
		and h != 0
		and wall_normal != Vector2.ZERO
		and sign(h) == -sign(wall_normal.x)
	)

	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		var adjacent_tiles = [
			player_tile + Vector2i(1, 0),
			player_tile + Vector2i(-1, 0),
			player_tile + Vector2i(0, 1),
			player_tile + Vector2i(0, -1),
		]
		if not (target_tile_coords in adjacent_tiles):
			cancel_mining()

	_update_highlight()
	_update_grapple_hover()
	_update_animation()
	_update_walking_sfx()
	_update_grapple_line()
	_update_flashlight()
	queue_redraw()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and selected_slot == 0:
		if highlight_valid and not is_mining:
			start_mining(highlighted_tile)
	else:
		if is_mining:
			cancel_mining()


func _update_grapple_line():
	if not grapple_line: return
	if is_grapple_moving or is_wall_stuck:
		grapple_line.visible = true
		grapple_line.clear_points()
		grapple_line.add_point(global_position)
		grapple_line.add_point(grapple_point)
	else:
		grapple_line.visible = false

func _update_highlight():
	if is_mining or not tilemap:
		return

	var mouse_world_pos = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world_pos))
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	var adjacent_tiles = [
		player_tile + Vector2i(1, 0),
		player_tile + Vector2i(-1, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(0, -1),
	]

	if mouse_tile in adjacent_tiles and tilemap.get_cell_source_id(mouse_tile) != -1:
		var unbreakable: Dictionary = {}
		if tilemap.has_meta("unbreakable_tiles"):
			var meta = tilemap.get_meta("unbreakable_tiles")
			if meta is Dictionary:
				unbreakable = meta
		
		if not unbreakable.has(mouse_tile):
			highlighted_tile = mouse_tile
			highlight_valid = true
		else:
			highlight_valid = false
	else:
		highlight_valid = false


func _update_animation():
	var target_anim: StringName
	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		target_anim = &"mine_down" if target_tile_coords.y > player_tile.y else &"mine_right"
	elif is_wall_climbing:
		target_anim = &"climb"
	elif is_walking:
		target_anim = &"walk" 
	else:
		target_anim = &"idle"


	if is_mining:
		var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
		anim_sprite.flip_h = target_tile_coords.x < player_tile.x
	elif is_wall_climbing:
		var wall_normal = get_wall_normal()
		anim_sprite.flip_h = wall_normal.x > 0 
	else:
		anim_sprite.flip_h = facing_dir == -1

	if anim_sprite.animation != target_anim:
		anim_sprite.play(target_anim)

func _draw():
	if not tilemap: return

	# Grapple hover highlight (cyan = valid, red = out of range / blocked)
	if not grapple_active and (grapple_hover_valid or grapple_hover_invalid):
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(grapple_hover_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var r = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		if grapple_hover_valid:
			draw_rect(r, Color(0.0, 1.0, 1.0, 0.25), true)
			draw_rect(r, Color(0.0, 1.0, 1.0, 1.0), false, 2.5)
		else:
			draw_rect(r, Color(1.0, 0.0, 0.0, 0.25), true)
			draw_rect(r, Color(1.0, 0.0, 0.0, 1.0), false, 2.5)

	if highlight_valid and not is_mining:
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(highlighted_tile))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0
		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 0.45), true)
		draw_rect(rect, Color(1.0, 0.85, 0.0, 1.0), false, 3.0)

	if is_mining:
		var progress = 1.0 - (mining_timer.time_left / mine_time)
		var tile_center_global = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
		var tile_center_local = to_local(tile_center_global)
		var half = TILE_WORLD_SIZE / 2.0

		var rect = Rect2(tile_center_local - Vector2(half, half), Vector2(TILE_WORLD_SIZE, TILE_WORLD_SIZE))
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.3), true)
		draw_rect(rect, Color(1.0, 0.5, 0.0, 0.9), false, 2.0)

		var bar_w = TILE_WORLD_SIZE
		var bar_h = 6.0
		var bar_pos = tile_center_local - Vector2(bar_w / 2.0, half + bar_h + 4.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.15, 0.15, 0.15, 0.85), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * progress, bar_h)), Color(0.2, 0.85, 0.2, 0.9), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 1.0, 1.0, 0.5), false, 1.0)

func start_mining(tile_coords: Vector2i):
	is_mining = true
	target_tile_coords = tile_coords
	if _is_insta_mine_pickaxe():
		finish_mining()
		return
	_play_mining_sfx()
	mining_timer.start(mine_time)

func _is_insta_mine_pickaxe() -> bool:
	if pickaxe_level < 0 or pickaxe_level >= PICKAXE_UPGRADES.size():
		return false
	var upg_any: Variant = PICKAXE_UPGRADES[pickaxe_level]
	if upg_any is Dictionary:
		var upg: Dictionary = upg_any as Dictionary
		return bool(upg.get("insta_mine", false))
	return false

func _play_mining_sfx() -> void:
	if mining_sfx_player == null:
		return
	if mining_sfx_player.stream == null and mining_sfx != null:
		mining_sfx_player.stream = mining_sfx
	if mining_sfx_player.stream == null:
		return
	# Connect finished signal so the sound loops for the full mining duration
	if not mining_sfx_player.finished.is_connected(_on_mining_sfx_finished):
		mining_sfx_player.finished.connect(_on_mining_sfx_finished)
	mining_sfx_player.stop()
	mining_sfx_player.play()

func _on_mining_sfx_finished() -> void:
	if is_mining:
		mining_sfx_player.play()

func _update_walking_sfx() -> void:
	if walking_sfx_player == null:
		return
	if walking_sfx_player.stream == null and walking_sfx != null:
		walking_sfx_player.stream = walking_sfx
	if walking_sfx_player.stream == null:
		return

	var should_play := is_walking and is_on_floor() and (not is_mining) and (not is_wall_climbing) and (not is_wall_stuck) and (not is_grapple_moving)

	if should_play:
		if not walking_sfx_player.finished.is_connected(_on_walking_sfx_finished):
			walking_sfx_player.finished.connect(_on_walking_sfx_finished)
		if not walking_sfx_player.playing:
			walking_sfx_player.play()
	else:
		if walking_sfx_player.finished.is_connected(_on_walking_sfx_finished):
			walking_sfx_player.finished.disconnect(_on_walking_sfx_finished)
		if walking_sfx_player.playing:
			walking_sfx_player.stop()

func _on_walking_sfx_finished() -> void:
	if is_walking and is_on_floor() and (not is_mining) and (not is_wall_climbing) and (not is_wall_stuck) and (not is_grapple_moving):
		walking_sfx_player.play()

func cancel_mining():
	mining_timer.stop()
	is_mining = false
	if mining_sfx_player and mining_sfx_player.finished.is_connected(_on_mining_sfx_finished):
		mining_sfx_player.finished.disconnect(_on_mining_sfx_finished)
	if mining_sfx_player:
		mining_sfx_player.stop()
	_update_walking_sfx()

func die_and_respawn():
	died.emit()
	anim_sprite.play("death")

	if is_mining:
		cancel_mining()
	_release_grapple()
	is_grapple_moving = false
	is_wall_stuck = false

	times_died += 1
	
	# Penalties: half money and +1 hour
	money = int(float(money) / 2.0)
	if money_label:
		money_label.text = "$" + str(money)
	
	game_minutes += 60.0
	
	# Reset state and respawn
	current_battery = max_battery
	if oxygen_bar:
		oxygen_bar.value = current_battery
	
	global_position = spawn_position
	velocity = Vector2.ZERO
	
	_update_low_battery_overlay()
	_update_walking_sfx()

func _roll_count() -> int:
	var count = 1
	var n = 2
	while n <= 10 and randi() % n == 0:
		count += 1
		n += 1
	return count

func _generate_daily_objectives() -> void:
	# 2 objectives per day:
	# - Always: reach a depth target
	# - Plus: either collect mutated ore or collect a specific normal ore
	daily_objectives.clear()
	daily_max_depth = 0
	daily_mutated_collected = 0
	daily_ore_collected.clear()
	daily_objectives_rewarded = false

	# Difficulty should scale with player upgrades so objectives stay possible.
	# Day count still nudges difficulty upward, but upgrades are the main driver.
	var upgrade_score := 0
	upgrade_score += int(oxygen_upgrade_level)
	upgrade_score += int(speed_upgrade_level)
	upgrade_score += int(mining_speed_upgrade_level)
	upgrade_score += int(cargo_upgrade_level)
	upgrade_score += int(floor(float(pickaxe_level) / 2.0))
	# If the player hasn't upgraded much, don't let day_count run away.
	var difficulty := clampi(min(day_count, 1 + upgrade_score), 1, 20)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Depth objective: grows primarily with upgrades.
	# Targets are in tile Y coordinates (0 = surface).
	var depth_target := 30 + difficulty * 18 + rng.randi_range(-12, 12)
	# Oxygen upgrades make deeper runs more realistic.
	depth_target += int(oxygen_upgrade_level) * 10
	# Speed upgrades help reach targets faster.
	depth_target += int(speed_upgrade_level) * 6
	depth_target = clampi(depth_target, 25, 330)
	daily_objectives.append({
		"type": "reach_depth",
		"target": depth_target,
	})

	# ~35% days ask for mutated, otherwise a normal ore quota.
	# Mutated are rare (~5% of non-stone ore drops), so keep targets small.
	if rng.randf() < 0.35:
		var mutated_target := 1 + int(floor(float(difficulty - 1) / 6.0)) + rng.randi_range(0, 1)
		# Mining speed + better pickaxes generally increase attempts, so allow slightly higher caps.
		mutated_target += int(floor(float(mining_speed_upgrade_level) / 4.0))
		mutated_target += int(floor(float(pickaxe_level) / 4.0))
		# Cargo capacity limits how many total drops can be carried.
		mutated_target = min(mutated_target, max(1, int(floor(float(max_cargo) / 5.0))))
		mutated_target = clampi(mutated_target, 1, 4)
		daily_objectives.append({
			"type": "collect_mutated",
			"target": mutated_target,
		})
	else:
		var ore_options: Array[String] = ["Stone", "Copper"]
		# Gate rarer ores until the player has some upgrade traction.
		if difficulty >= 4:
			ore_options.append("Silver")
		if difficulty >= 7:
			ore_options.append("Gold")
		var ore_name: String = ore_options[rng.randi_range(0, ore_options.size() - 1)]
		var base_amt := 0
		match ore_name:
			"Stone":
				base_amt = 7 + difficulty * 2
			"Copper":
				base_amt = 4 + difficulty
			"Silver":
				base_amt = 2 + int(floor(float(difficulty) / 2.0))
			"Gold":
				base_amt = 1 + int(floor(float(difficulty) / 4.0))
			_:
				base_amt = 5
		var target_amt: int = base_amt + int(rng.randi_range(0, 2))
		# Keep within what a player can realistically hold in a day.
		var cap_limit: int = maxi(3, int(floor(float(max_cargo) * 0.75)))
		target_amt = clampi(target_amt, 2, cap_limit)
		daily_objectives.append({
			"type": "collect_ore",
			"ore": ore_name,
			"target": target_amt,
		})

func _objective_is_complete(obj: Dictionary) -> bool:
	var t := String(obj.get("type", ""))
	match t:
		"reach_depth":
			return daily_max_depth >= int(obj.get("target", 0))
		"collect_mutated":
			return daily_mutated_collected >= int(obj.get("target", 0))
		"collect_ore":
			var ore_name := String(obj.get("ore", ""))
			return int(daily_ore_collected.get(ore_name, 0)) >= int(obj.get("target", 0))
		_:
			return false

func _objective_line_text(obj: Dictionary) -> String:
	var t := String(obj.get("type", ""))
	match t:
		"reach_depth":
			var target := int(obj.get("target", 0))
			return "Reach depth %d (%d/%d)" % [target, min(daily_max_depth, target), target]
		"collect_mutated":
			var target := int(obj.get("target", 0))
			return "Collect mutated ore (%d/%d)" % [min(daily_mutated_collected, target), target]
		"collect_ore":
			var ore_name := String(obj.get("ore", ""))
			var target := int(obj.get("target", 0))
			var have := int(daily_ore_collected.get(ore_name, 0))
			return "Collect %s (%d/%d)" % [ore_name, min(have, target), target]
		_:
			return ""

func _update_daily_objectives_hud() -> void:
	if objectives_label == null:
		return
	if daily_objectives.is_empty():
		objectives_label.text = ""
		_last_objectives_hud_text = ""
		return

	var lines: Array[String] = []
	lines.append("[center][b][color=gray]Objectives[/color][/b][/center]")
	for obj in daily_objectives:
		var ok := _objective_is_complete(obj)
		var color := "green" if ok else "white"
		var line := _objective_line_text(obj)
		if line == "":
			continue
		lines.append("[center][b][color=%s]%s[/color][/b][/center]" % [color, line])

	# Check if all objectives just became complete and give reward once
	if not daily_objectives_rewarded and not daily_objectives.is_empty():
		var all_done := true
		for obj in daily_objectives:
			if not _objective_is_complete(obj):
				all_done = false
				break
		if all_done:
			daily_objectives_rewarded = true
			var reward := _compute_daily_reward()
			money += reward
			if money_label:
				money_label.text = "$" + str(money)
			_spawn_floating_text("TASKS COMPLETE! +$%d" % reward, global_position + Vector2(0, -80), Color(1.0, 0.9, 0.1))
			if objectives_toggle_btn:
				objectives_toggle_btn.text = "✓ Daily Tasks"

	var text := "\n".join(lines)
	if text == _last_objectives_hud_text:
		return
	_last_objectives_hud_text = text
	objectives_label.text = text

func _compute_daily_reward() -> int:
	var total := 0
	for obj in daily_objectives:
		var t := String(obj.get("type", ""))
		match t:
			"reach_depth":
				total += int(obj.get("target", 0)) * 3
			"collect_mutated":
				total += int(obj.get("target", 0)) * 300
			"collect_ore":
				var ore_name := String(obj.get("ore", ""))
				var target := int(obj.get("target", 0))
				var unit := 0
				match ore_name:
					"Stone":  unit = 20
					"Copper": unit = 60
					"Silver": unit = 200
					"Gold":   unit = 600
					_:        unit = 30
				total += target * unit
	return total

func _toggle_objectives_panel() -> void:
	if objectives_label == null or objectives_toggle_btn == null:
		return
	objectives_label.visible = not objectives_label.visible
	objectives_toggle_btn.text = "Daily Tasks ▲" if objectives_label.visible else "Daily Tasks ▼"

func finish_mining():
	if not tilemap: return
	if mining_timer:
		mining_timer.stop()

	var source_id = tilemap.get_cell_source_id(target_tile_coords)
	var is_grass = (source_id == 1)
	is_mining = false

	var tile_world_pos = tilemap.to_global(tilemap.map_to_local(target_tile_coords))
	var cargo_remaining = max_cargo - current_cargo

	if source_id != -1:
		_spawn_block_break_effect(tile_world_pos, int(source_id))

	# Regular block (dirt, cobble, deepslate, grass)
	tilemap.set_cell(target_tile_coords, -1)

	if is_grass:
		return

	# Block-specific luck bonus
	var block_luck_mult = 1.0
	if source_id == 3: # Cobblestone
		block_luck_mult = 1.5
	elif source_id == 4: # Deepslate
		block_luck_mult = 2.3

	var found: Array[Dictionary] = []

	if cargo_remaining <= 0:
		_spawn_floating_text("Cargo Full!", tile_world_pos, Color(1.0, 0.3, 0.3))
		return

	# Apply oxygen-based luck bonus to current luck
	var current_luck = PICKAXE_UPGRADES[pickaxe_level]["luck"] * block_luck_mult * oxygen_luck_bonus

	# 75% chance to drop at least one Stone from regular blocks
	if source_id in [TILE_DIRT, TILE_COBBLE, TILE_DEEPSLATE] and randf() < 0.75:
		var amount = min(_roll_count(), cargo_remaining)
		if amount > 0:
			cargo_remaining -= amount
			found.append({
				"name":   "Stone",
				"amount": amount,
				"value":  2,
				"color":  Color(0.75, 0.70, 0.65),
			})

	for ore in ORE_TABLE:
		if cargo_remaining <= 0:
			break
		var ore_name: String = ore[0] as String
		if ore_name == "Stone":
			continue
		if ore_name.begins_with("Mutated "):
			continue
		var chance_denom = float(ore[1]) / current_luck
		if randf() * chance_denom < 1.0:
			var amount = min(_roll_count(), cargo_remaining)
			cargo_remaining -= amount
			var drop_name: String = ore_name
			var drop_color: Color = ore[3] as Color
			var drop_value: int = int(ore[2])
			if drop_name == "Rainbow":
				drop_color = Color.from_hsv(randf(), 0.95, 1.0, 1.0)
			elif randf() < MUTATED_CHANCE:
				drop_name = "Mutated %s" % drop_name
				drop_color = Color(0.80, 0.20, 0.95)
				drop_value = _get_ore_value(drop_name)
			found.append({
				"name":   drop_name,
				"amount": amount,
				"value":  drop_value,
				"color":  drop_color,
			})

	if found.is_empty():
		_spawn_floating_text("No ore...", tile_world_pos, Color(0.6, 0.6, 0.6, 0.85))
		return

	var delay := 0.0
	for ore_data in found:
		_spawn_ore_fly(ore_data, tile_world_pos, delay)
		delay += 0.22


func _spawn_floating_text(msg: String, world_pos: Vector2, color: Color) -> void:
	var hud_node := hud
	if not hud_node:
		hud_node = get_parent().get_node_or_null("HUD") as CanvasLayer
	if not hud_node:
		return
	var label := Label.new()
	label.text = msg
	label.modulate = color
	label.add_theme_font_size_override("font_size", 16)
	label.position = get_viewport().get_canvas_transform() * world_pos + Vector2(-30.0, -10.0)
	label.z_index = 10
	hud_node.add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0.0, -45.0), 1.1)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.1)
	tween.tween_callback(label.queue_free)

func _input(event: InputEvent) -> void:
	if is_end_of_day:
		if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
			_close_end_of_day()
		return

	if not _is_gameplay_enabled():
		return

	# Flashlight toggle (Q)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		flashlight_on = not flashlight_on
		if flashlight != null:
			flashlight.enabled = flashlight_on
			if flashlight_on:
				_update_flashlight()
		return
	
	if Input.is_action_just_pressed("inventory"):
		if not is_in_menu:
			_toggle_inventory()
		return

		
	if inventory_open:
		if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_E):
			_toggle_inventory()
		return

	if is_in_menu:
		return

	# Hotbar selection 1-9

	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_select_hotbar_slot(event.keycode - KEY_1)


func _unhandled_input(event: InputEvent) -> void:
	if is_end_of_day or is_in_menu or inventory_open or not _is_gameplay_enabled():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_use_selected_hotbar_item()


	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if grapple_active:
					_release_grapple()
				else:
					_try_fire_grapple()
			MOUSE_BUTTON_WHEEL_UP:
				minimap_zoom = clamp(minimap_zoom * 1.25, 0.5, 8.0)
				_update_minimap()
			MOUSE_BUTTON_WHEEL_DOWN:
				minimap_zoom = clamp(minimap_zoom / 1.25, 0.5, 8.0)
				_update_minimap()
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_release_grapple()
			KEY_BRACKETRIGHT:  # ] = zoom in
				minimap_zoom = clamp(minimap_zoom * 1.25, 0.5, 8.0)
				_update_minimap()
			KEY_BRACKETLEFT:   # [ = zoom out
				minimap_zoom = clamp(minimap_zoom / 1.25, 0.5, 8.0)
				_update_minimap()

func _update_grapple_hover() -> void:
	grapple_hover_valid = false
	grapple_hover_invalid = false
	if grapple_active or not tilemap: return
	var mouse_world = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world))
	var src = tilemap.get_cell_source_id(mouse_tile)
	if src == -1: return  # Air — nothing to show
	grapple_hover_tile = mouse_tile
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var dist = Vector2(mouse_tile).distance_to(Vector2(player_tile))
	if src == TILE_GRASS or dist > float(GRAPPLE_MAX_TILES) or not _has_los_to_tile(mouse_tile):
		grapple_hover_invalid = true
	else:
		grapple_hover_valid = true

func _try_fire_grapple() -> void:
	if not tilemap or is_grapple_moving: return
	var mouse_world = get_global_mouse_position()
	var mouse_tile = tilemap.local_to_map(tilemap.to_local(mouse_world))
	var src = tilemap.get_cell_source_id(mouse_tile)
	if src == -1 or src == TILE_GRASS: return
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	if Vector2(mouse_tile).distance_to(Vector2(player_tile)) > float(GRAPPLE_MAX_TILES): return
	if not _has_los_to_tile(mouse_tile): return
	var tile_center = tilemap.to_global(tilemap.map_to_local(mouse_tile))
	var to_player = global_position - tile_center
	var sx = sign(to_player.x) if to_player.x != 0 else 1.0
	var sy = sign(to_player.y) if to_player.y != 0 else 1.0
	var candidates: Array[Vector2] = [
		tile_center + Vector2(sx * 56.0, 0.0),     # preferred horizontal face
		tile_center + Vector2(0.0, sy * 92.0),      # preferred vertical face
		tile_center + Vector2(-sx * 56.0, 0.0),    # opposite horizontal
		tile_center + Vector2(0.0, -sy * 92.0),    # opposite vertical
	]
	if abs(to_player.y) > abs(to_player.x):
		candidates = [candidates[1], candidates[0], candidates[3], candidates[2]]
	var target_pos := Vector2.ZERO
	var found := false
	for c in candidates:
		var lt = tilemap.local_to_map(tilemap.to_local(c))
		if tilemap.get_cell_source_id(lt) == -1:
			target_pos = c
			found = true
			break
	if not found: return
	grapple_point = target_pos
	# If the landing spot is beside the block (horizontal face), the player sticks to the wall
	var will_wall_stick = abs(target_pos.x - tile_center.x) > abs(target_pos.y - tile_center.y)
	is_grapple_moving = true
	velocity = Vector2.ZERO
	var dist = global_position.distance_to(target_pos)
	var duration = clamp(dist / 800.0, 0.08, 0.6)
	var tw = create_tween()
	tw.tween_property(self, "global_position", target_pos, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		is_grapple_moving = false
		if will_wall_stick:
			is_wall_stuck = true
	)

func _has_los_to_tile(target_tile: Vector2i) -> bool:
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	var dx = target_tile.x - player_tile.x
	var dy = target_tile.y - player_tile.y
	var steps = max(abs(dx), abs(dy))
	if steps <= 1:
		return true
	for i in range(1, steps):  # skip endpoints — player is air, target is the block
		var cx = player_tile.x + roundi(float(dx * i) / float(steps))
		var cy = player_tile.y + roundi(float(dy * i) / float(steps))
		if tilemap.get_cell_source_id(Vector2i(cx, cy)) != -1:
			return false  # Solid tile in the way
	return true

func _release_grapple() -> void:
	grapple_active = false
	grapple_hover_valid = false
	grapple_hover_invalid = false

func sleep() -> void:
	trigger_end_of_day(false)
	_update_walking_sfx()

func _format_game_time(total_mins: float) -> String:
	var m := int(total_mins) % 1440
	var h: int = int(m / 60.0)
	var mn := m % 60
	var period := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0: h12 = 12
	return "%d:%02d %s" % [h12, mn, period]

func _update_minimap() -> void:
	if not tilemap or not minimap_image or not minimap_texture_rect: return
	var player_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	minimap_image.fill(MINIMAP_EMPTY_COLOR)
	# Each pixel represents (1 / minimap_zoom) tiles; view is centered on the player
	for tx in range(MINIMAP_W):
		for ty in range(MINIMAP_H):
			var world_x = player_tile.x + int((tx - MINIMAP_W / 2.0) / minimap_zoom)
			var world_y = player_tile.y + int((ty - MINIMAP_H / 2.0) / minimap_zoom)
			if world_y < 0:
				minimap_image.set_pixel(tx, ty, Color(0.45, 0.72, 1.0))
				continue
			var src = tilemap.get_cell_source_id(Vector2i(world_x, world_y))
			if src == -1:
				continue
			minimap_image.set_pixel(tx, ty, MINIMAP_TILE_COLORS.get(src, MINIMAP_EMPTY_COLOR))
	# Player dot always at image center
	var half_w: int = MINIMAP_W >> 1
	var half_h: int = MINIMAP_H >> 1
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var ix = clamp(half_w + dx, 0, MINIMAP_W - 1)
			var iy = clamp(half_h + dy, 0, MINIMAP_H - 1)
			minimap_image.set_pixel(ix, iy, MINIMAP_PLAYER_COLOR)
	minimap_texture_rect.texture = ImageTexture.create_from_image(minimap_image)

func _update_low_battery_overlay() -> void:
	if not low_battery_overlay: return
	if current_battery >= max_battery * 0.15:
		low_battery_overlay.visible = false
		low_oxygen_onset_time = -1.0
		if low_oxygen_label:
			low_oxygen_label.modulate.a = 0.0
		return
	# Record when the warning first fired
	if low_oxygen_onset_time < 0.0:
		low_oxygen_onset_time = Time.get_ticks_msec() / 1000.0
	low_battery_overlay.visible = true
	var t = Time.get_ticks_msec() / 1000.0
	var alpha = lerp(LOW_BATTERY_PULSE_MIN, LOW_BATTERY_PULSE_MAX,
		(sin(t * LOW_BATTERY_PULSE_SPEED) + 1.0) / 2.0)
	low_battery_overlay.color = Color(1.0, 0.0, 0.0, alpha)
	if low_oxygen_label:
		# Fade the label in over 2 seconds so it doesn't smash the player in the face
		var elapsed = (Time.get_ticks_msec() / 1000.0) - low_oxygen_onset_time
		var fade_in = clamp(elapsed / 2.0, 0.0, 1.0)
		low_oxygen_label.modulate = Color(1.0, 0.3, 0.3, alpha * fade_in)

func _spawn_ore_fly(ore_data: Dictionary, tile_world_pos: Vector2, delay: float) -> void:
	var hud_node := hud
	if not hud_node:
		hud_node = get_parent().get_node_or_null("HUD") as CanvasLayer
	if not hud_node:
		return
	
	var fly_node = Node2D.new()
	fly_node.z_index = 10
	
	var ore_name: String = ore_data.get("name", "") as String
	var base_name := ore_name
	if ore_name.begins_with("Mutated "):
		base_name = ore_name.substr("Mutated ".length(), ore_name.length())

	var tex_path = ""
	match base_name:
		"Stone": tex_path = "res://Stones_ores_bars/stone_1.png"
		"Copper": tex_path = "res://Stones_ores_bars/copper_ore.png"
		"Silver": tex_path = "res://Stones_ores_bars/silver_ore.png"
		"Gold": tex_path = "res://Stones_ores_bars/gold_ore.png"
		"Rainbow": tex_path = "res://Stones_ores_bars/gold_ore.png"
		
	var sprite = Sprite2D.new()
	if tex_path != "" and FileAccess.file_exists(tex_path):
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(2.5, 2.5)
	if (ore_name == "Rainbow" or ore_name.begins_with("Mutated ")) and ore_data.has("color") and ore_data["color"] is Color:
		sprite.modulate = ore_data["color"] as Color
	fly_node.add_child(sprite)

	var label := Label.new()
	label.text = "+%d" % ore_data["amount"]
	label.modulate = ore_data["color"]
	label.add_theme_font_size_override("font_size", 18)
	label.position = Vector2(10.0, -10.0)
	fly_node.add_child(label)

	var ct := get_viewport().get_canvas_transform()
	var screen_start := ct * tile_world_pos
	var screen_end := get_viewport_rect().size * 0.5

	fly_node.position = screen_start
	hud_node.add_child(fly_node)

	var tween = create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(fly_node, "position", screen_start + Vector2(0.0, -30.0), 0.20)
	tween.tween_property(fly_node, "position", screen_end, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		var nm: String    = ore_data["name"]
		var amt: int      = ore_data["amount"]
		if not ore_counts.has(nm):
			ore_counts[nm] = 0
		if not lifetime_ore_counts.has(nm):
			lifetime_ore_counts[nm] = 0
		
		ore_counts[nm] += amt
		lifetime_ore_counts[nm] += amt
		current_cargo   += amt
		daily_ores_collected += amt
		# Daily objective tracking
		var base_nm := nm
		if base_nm.begins_with("Mutated "):
			daily_mutated_collected += amt
			# do not count mutated toward normal ore quotas
		else:
			if not daily_ore_collected.has(base_nm):
				daily_ore_collected[base_nm] = 0
			daily_ore_collected[base_nm] = int(daily_ore_collected[base_nm]) + amt
		_update_daily_objectives_hud()
		ore_collected.emit(base_name)

		if cargo_label:
			cargo_label.text = "Cargo: %d/%d" % [current_cargo, max_cargo]
		if ore_labels.has(nm):
			ore_labels[nm].text = "%s: %d" % [nm, ore_counts[nm]]
			var flash = create_tween()
			flash.tween_property(ore_labels[nm], "modulate:a", 0.15, 0.07)
			flash.tween_property(ore_labels[nm], "modulate:a", 1.00, 0.18)
		if inventory_open:
			_refresh_inventory()
		fly_node.queue_free()
	)

func _setup_end_of_day_ui():
	end_day_layer = CanvasLayer.new()
	end_day_layer.layer = 100
	end_day_layer.visible = false
	add_child(end_day_layer)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MouseFilter.MOUSE_FILTER_IGNORE
	end_day_layer.add_child(fade_rect)
	
	dashboard = TextureRect.new()
	var tex = load("res://brown.jpg") as Texture2D
	if tex:
		dashboard.texture = tex
	else:
		var fallback_bg = ColorRect.new()
		fallback_bg.color = Color(0.35, 0.2, 0.1)
		fallback_bg.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
		dashboard.add_child(fallback_bg)

	dashboard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dashboard.anchor_left = 0.125
	dashboard.anchor_right = 0.875
	dashboard.anchor_top = 0.125
	dashboard.anchor_bottom = 0.875
	dashboard.modulate.a = 0.0
	dashboard.mouse_filter = Control.MouseFilter.MOUSE_FILTER_STOP
	end_day_layer.add_child(dashboard)
	
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.set_anchors_preset(Control.LayoutPreset.PRESET_FULL_RECT)
	stats_label.offset_left = 40.0
	stats_label.offset_top = 40.0
	stats_label.offset_right = -40.0
	stats_label.offset_bottom = -40.0
	stats_label.mouse_filter = Control.MouseFilter.MOUSE_FILTER_IGNORE
	dashboard.add_child(stats_label)
	
	close_btn = TextureButton.new()
	var img = Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	for i in range(40):
		img.set_pixel(i, i, Color(1, 1, 1))
		img.set_pixel(i, 39 - i, Color(1, 1, 1))
		if i > 0:
			img.set_pixel(i, i - 1, Color(1, 1, 1))
			img.set_pixel(i - 1, i, Color(1, 1, 1))
			img.set_pixel(i, 39 - i + 1, Color(1, 1, 1))
			img.set_pixel(i - 1, 39 - i, Color(1, 1, 1))
	close_btn.texture_normal = ImageTexture.create_from_image(img)
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = -50.0
	close_btn.offset_top = 10.0
	close_btn.offset_right = -10.0
	close_btn.offset_bottom = 50.0
	close_btn.pressed.connect(_close_end_of_day)
	dashboard.add_child(close_btn)

func trigger_end_of_day(_from_death: bool = false):
	if is_end_of_day: return
	is_end_of_day = true
	
	velocity = Vector2.ZERO
	is_walking = false
	is_mining = false
	is_wall_climbing = false
	if is_mining: cancel_mining()
	_release_grapple()
	
	end_day_layer.visible = true
	fade_rect.color.a = 0.0
	dashboard.modulate.a = 0.0
	fade_rect.mouse_filter = Control.MouseFilter.MOUSE_FILTER_STOP
	
	var tw = create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 1.5)
	tw.tween_interval(1.0)
	tw.tween_callback(func():
		var font_size = 48
		var text = "[center][font_size=%d]" % font_size
		text += "[color=white]End of Day %d[/color]\n\n" % day_count
		text += "[font_size=32]"
		text += "[color=orange]Ores Collected: %d[/color]\n\n" % daily_ores_collected
		text += "[color=gold]Money Made: $%d[/color]\n\n" % daily_money_made
		text += "[color=red]Times Died: %d[/color]\n" % times_died

		# Objectives summary
		if not daily_objectives.is_empty():
			text += "\n[color=cyan]Objectives[/color]\n"
			for obj in daily_objectives:
				var ok := _objective_is_complete(obj)
				var mark := "[color=green]✓[/color]" if ok else "[color=red]✗[/color]"
				var line := _objective_line_text(obj)
				if line != "":
					text += "%s %s\n" % [mark, line]
		text += "\n[color=gray][font_size=24]Press SPACE or Click X to continue...[/font_size][/color]"
		text += "[/font_size][/font_size][/center]"
		stats_label.text = text
	)
	tw.tween_property(dashboard, "modulate:a", 1.0, 0.5)

func _close_end_of_day():
	if not is_end_of_day: return
	var tw = create_tween()
	tw.tween_property(dashboard, "modulate:a", 0.0, 0.5)
	tw.tween_property(fade_rect, "color:a", 0.0, 0.5)
	tw.tween_callback(func():
		end_day_layer.visible = false
		fade_rect.mouse_filter = Control.MouseFilter.MOUSE_FILTER_IGNORE
		is_end_of_day = false
		
		daily_ores_collected = 0
		daily_money_made = 0
		
		day_count += 1
		if day_label:
			day_label.text = "Day " + str(day_count)
			
		_respawn_and_reset_day()
	)

func _respawn_and_reset_day():
	game_minutes = 7.0 * 60.0
	current_battery = max_battery
	current_cargo = 0
	daily_max_depth = 0
	daily_mutated_collected = 0
	daily_ore_collected.clear()
	
	for ore in ORE_TABLE:
		var nm: String = ore[0]
		ore_counts[nm] = 0
		if ore_labels.has(nm):
			ore_labels[nm].text = "%s: 0" % nm
			
	if oxygen_bar: oxygen_bar.value = current_battery
	
	global_position = spawn_position


	velocity = Vector2.ZERO

	_generate_daily_objectives()
	_update_daily_objectives_hud()
	is_wall_stuck = false
	_release_grapple()
	is_grapple_moving = false
	if is_mining: cancel_mining()
	_update_low_battery_overlay()
	if clock_label: clock_label.text = _format_game_time(game_minutes)
	if cargo_label: cargo_label.text = "Cargo: 0/%d" % max_cargo

func _select_hotbar_slot(index: int):
	if index < 0 or index >= hotbar_slots.size(): return
	
	# Reset old slot border
	var old_slot = hotbar_slots[selected_slot]
	var old_sb = old_slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	old_sb.border_color = Color(0.4, 0.4, 0.4)
	old_sb.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	old_slot.add_theme_stylebox_override("panel", old_sb)
	
	selected_slot = index
	
	# Set new slot border
	var new_slot = hotbar_slots[selected_slot]
	var new_sb = new_slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	new_sb.border_color = Color(1, 0.9, 0) # Gold highlight
	new_sb.bg_color = Color(0.3, 0.3, 0.3, 0.9)
	new_slot.add_theme_stylebox_override("panel", new_sb)
	
	# Update Selected Item Name
	var label = hud.get_node_or_null("SelectedItemLabel") as Label
	if label:
		if index == 0:
			label.text = ""
		else:
			var item_id := ""
			var count := 0
			if selected_slot >= 0 and selected_slot < hotbar_item_ids.size():
				item_id = hotbar_item_ids[selected_slot]
				count = int(hotbar_item_counts[selected_slot])
			if item_id != "" and count > 0:
				label.text = "%s x%d" % [_hotbar_item_display_name(item_id), count]
			else:
				label.text = "Empty Slot"


func _hotbar_item_display_name(item_id: String) -> String:
	match item_id:
		ITEM_POTION_SURFACE:
			return "Surface Potion"
		ITEM_POTION_OXYGEN:
			return "Oxygen Potion"
		ITEM_POTION_SPEED:
			return "Speed Potion"
		_:
			return "Item"


func _hotbar_item_short_label(item_id: String) -> String:
	match item_id:
		ITEM_POTION_SURFACE:
			return "UP"
		ITEM_POTION_OXYGEN:
			return "O2"
		ITEM_POTION_SPEED:
			return "SPD"
		_:
			return "?"


func _update_hotbar_slot_ui(slot_index: int) -> void:
	if slot_index <= 0:
		return
	if slot_index >= hotbar_item_ids.size() or slot_index >= hotbar_item_labels.size() or slot_index >= hotbar_item_count_labels.size():
		return
	var item_lbl := hotbar_item_labels[slot_index]
	var count_lbl := hotbar_item_count_labels[slot_index]
	if item_lbl == null or count_lbl == null:
		return
	var item_id := hotbar_item_ids[slot_index]
	var count := int(hotbar_item_counts[slot_index])
	if item_id == "" or count <= 0:
		item_lbl.text = ""
		count_lbl.text = ""
		return
	item_lbl.text = _hotbar_item_short_label(item_id)
	count_lbl.text = str(count) if count > 1 else ""


func _refresh_selected_item_label() -> void:
	if hud == null:
		return
	var label := hud.get_node_or_null("SelectedItemLabel") as Label
	if label == null:
		return
	if selected_slot == 0:
		label.text = PICKAXE_UPGRADES[pickaxe_level]["name"]
		return
	if selected_slot < 0 or selected_slot >= hotbar_item_ids.size():
		label.text = "Empty Slot"
		return
	var item_id := hotbar_item_ids[selected_slot]
	var count := int(hotbar_item_counts[selected_slot])
	if item_id != "" and count > 0:
		label.text = "%s x%d" % [_hotbar_item_display_name(item_id), count]
	else:
		label.text = "Empty Slot"


func add_hotbar_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	for i in range(1, min(HOTBAR_SLOT_COUNT, hotbar_item_ids.size())):
		if hotbar_item_ids[i] == item_id and int(hotbar_item_counts[i]) > 0:
			hotbar_item_counts[i] = int(hotbar_item_counts[i]) + amount
			_update_hotbar_slot_ui(i)
			_refresh_selected_item_label()
			return true
	for i in range(1, min(HOTBAR_SLOT_COUNT, hotbar_item_ids.size())):
		if hotbar_item_ids[i] == "" or int(hotbar_item_counts[i]) <= 0:
			hotbar_item_ids[i] = item_id
			hotbar_item_counts[i] = amount
			_update_hotbar_slot_ui(i)
			_refresh_selected_item_label()
			return true
	return false


func _use_selected_hotbar_item() -> void:
	if selected_slot <= 0:
		return
	if selected_slot >= hotbar_item_ids.size():
		return
	var item_id := hotbar_item_ids[selected_slot]
	var count := int(hotbar_item_counts[selected_slot])
	if item_id == "" or count <= 0:
		return

	var used := false
	match item_id:
		ITEM_POTION_SURFACE:
			global_position.y = spawn_position.y
			current_battery = max_battery
			if oxygen_bar:
				oxygen_bar.value = current_battery
			_update_low_battery_overlay()
			_spawn_floating_text("Surface!", global_position, Color(0.75, 0.55, 0.95, 0.9))
			used = true
		ITEM_POTION_OXYGEN:
			current_battery = min(max_battery, current_battery + OXYGEN_POTION_RESTORE)
			if oxygen_bar:
				oxygen_bar.value = current_battery
			_update_low_battery_overlay()
			_spawn_floating_text("+Oxygen", global_position, Color(0.35, 0.85, 1.0, 0.9))
			used = true
		ITEM_POTION_SPEED:
			speed_potion_mult = SPEED_POTION_MULT
			speed_potion_timer = SPEED_POTION_DURATION
			_spawn_floating_text("+Speed", global_position, Color(1.0, 0.85, 0.35, 0.9))
			used = true
		_:
			used = false

	if not used:
		return

	hotbar_item_counts[selected_slot] = max(0, int(hotbar_item_counts[selected_slot]) - 1)
	if int(hotbar_item_counts[selected_slot]) <= 0:
		hotbar_item_ids[selected_slot] = ""
	_update_hotbar_slot_ui(selected_slot)
	_refresh_selected_item_label()

func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	if inventory_panel:
		inventory_panel.visible = inventory_open
	if inventory_open:
		_refresh_inventory()

func _refresh_inventory() -> void:
	if not inventory_label:
		return

	var special_names := ["Rainbow", "Mutated Stone", "Mutated Copper", "Mutated Silver", "Mutated Gold"]
	var total_value := 0
	var text := "[center][b]INVENTORY[/b][/center]\n[center]Press E to close[/center]\n\n"
	text += "[b]Rainbow / Mutated Ores[/b]\n"
	for nm in special_names:
		var count := int(ore_counts.get(nm, 0))
		var value_each := _get_ore_value(nm)
		total_value += count * value_each
		text += "%s: %d  ($%d ea)\n" % [nm, count, value_each]
	text += "\n[b]Special value:[/b] $%d" % total_value
	inventory_label.text = text

func add_item_to_hotbar(item_name: String, color: Color) -> bool:
	# Legacy compatibility: route old calls to the new hotbar system.
	# `color` is ignored (hotbar uses text labels).
	match item_name:
		"Surface Potion":
			return add_hotbar_item(ITEM_POTION_SURFACE, 1)
		"Oxygen Potion":
			return add_hotbar_item(ITEM_POTION_OXYGEN, 1)
		"Speed Potion":
			return add_hotbar_item(ITEM_POTION_SPEED, 1)
		_:
			return false

func use_selected_item():
	# Legacy compatibility.
	_use_selected_hotbar_item()

func _get_ore_value(ore_name: String) -> int:

	for ore in ORE_TABLE:
		if (ore[0] as String) == ore_name:
			return int(ore[2])
	return 0
