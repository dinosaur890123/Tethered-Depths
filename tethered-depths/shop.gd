extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
@onready var ui_layer: CanvasLayer = $ShopUI
@onready var ui_feedback: Label = $ShopUI/Root/Panel/Margin/VBox/Feedback
@onready var ui_header: RichTextLabel = $ShopUI/Root/Panel/Margin/VBox/Header
@onready var ui_body: RichTextLabel = $ShopUI/Root/Panel/Margin/VBox/Body
@onready var ui_buttons: VBoxContainer = $ShopUI/Root/Panel/Margin/VBox/Buttons
var player_nearby: Node = null

# Protect the ground under the shop from being mined.
@export var foundation_half_width_tiles: int = 2 # total width = (half*2+1)
@export var foundation_depth_tiles: int = 2

# Developer menu unlock (press F 10x near shop)
const DEV_TAP_TARGET: int = 10
var _dev_tap_count: int = 0

enum ShopState { IDLE, PROMPT, MAIN_MENU, SELL_MENU, BUY_MENU, UPGRADE_MENU, CONFIRM_BUY, DEV_MENU }
var current_state = ShopState.IDLE
var pending_upgrade_index: int = -1

const INTERACT_ACTION: StringName = &"sell" # Bound to F in project.godot

const CARGO_UPGRADE_STEP: int = 5
const OXYGEN_UPGRADE_STEP: float = 25.0
const SPEED_UPGRADE_STEP: float = 40.0
const MINE_SPEED_UPGRADE_STEP_PCT: int = 10

const CARGO_UPGRADE_BASE_PRICE: int = 400
const OXYGEN_UPGRADE_BASE_PRICE: int = 600
const SPEED_UPGRADE_BASE_PRICE: int = 800
const MINE_SPEED_UPGRADE_BASE_PRICE: int = 1200

const MAX_STAT_UPGRADE_LEVEL: int = 8

var pickaxe_sprites: Array[Sprite2D] = []
var feedback_timer: float = 0.0
var feedback_text: String = ""

var _last_render_state: int = -999
var _last_render_feedback: String = "__init__"
var _last_render_header: String = "__init__"

func _ready():
	prompt_label.visible = false
	# Ensure BBCode is enabled even if the scene gets edited.
	prompt_label.bbcode_enabled = true
	ui_layer.visible = false
	ui_header.bbcode_enabled = true
	ui_body.bbcode_enabled = true
	$ShopZone.body_entered.connect(_on_body_entered)
	$ShopZone.body_exited.connect(_on_body_exited)
	_register_unbreakable_foundation_tiles()
	
	# Create pickaxe sprites for visual selection using the tileset atlas
	var atlas_tex = load("res://Miner16Bit_AllFiles_v1/Miner16Bit_WorldTiles_01.png")
	for i in range(4):
		var s = Sprite2D.new()
		if atlas_tex:
			var at = AtlasTexture.new()
			at.atlas = atlas_tex
			at.region = Rect2(112, 112, 16, 16) 
			s.texture = at
		else:
			s.texture = load("res://icon.svg")
			
		s.scale = Vector2(4.0, 4.0)
		s.visible = false
		s.position = Vector2(-120 + i * 80, -320)
		add_child(s)
		pickaxe_sprites.append(s)

func _register_unbreakable_foundation_tiles() -> void:
	var main := get_parent()
	if main == null:
		return
	var tilemap := main.get_node_or_null("Dirt") as TileMapLayer
	if tilemap == null:
		return

	# Compute a probe position slightly below the shop origin so we land inside the ground tile.
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

	for x in range(anchor_tile.x - foundation_half_width_tiles, anchor_tile.x + foundation_half_width_tiles + 1):
		for y in range(anchor_tile.y, anchor_tile.y + max(1, foundation_depth_tiles)):
			unbreakable[Vector2i(x, y)] = true

	tilemap.set_meta("unbreakable_tiles", unbreakable)

func _input(event):
	if not player_nearby:
		return

	# Secret dev menu: tap F 10 times while near the shop.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		if current_state != ShopState.DEV_MENU:
			_dev_tap_count += 1
			if _dev_tap_count >= DEV_TAP_TARGET:
				_dev_tap_count = 0
				feedback_text = "Developer menu"
				feedback_timer = 1.5
				current_state = ShopState.DEV_MENU
				return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if current_state == ShopState.DEV_MENU:
			if event.keycode == KEY_1:
				_dev_add_money(1000)
			elif event.keycode == KEY_2:
				_dev_fill_oxygen()
			elif event.keycode == KEY_3:
				_dev_add_ores(10)
			elif event.keycode == KEY_4:
				_dev_set_pickaxe(4)
			elif event.keycode == KEY_5:
				_dev_add_cargo_capacity(10)
			elif event.keycode == KEY_6:
				_dev_reset_progress()
			elif event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE:
				current_state = ShopState.MAIN_MENU
				feedback_text = ""
			return

		if current_state == ShopState.MAIN_MENU:
			if event.keycode == KEY_1:
				current_state = ShopState.SELL_MENU
				feedback_text = ""
			elif event.keycode == KEY_2:
				current_state = ShopState.BUY_MENU
				feedback_text = ""
			elif event.keycode == KEY_3:
				current_state = ShopState.UPGRADE_MENU
				feedback_text = ""
		elif current_state == ShopState.BUY_MENU:
			if event.keycode == KEY_1:
				_start_confirm_buy(1)
			elif event.keycode == KEY_2:
				_start_confirm_buy(2)
			elif event.keycode == KEY_3:
				_start_confirm_buy(3)
			elif event.keycode == KEY_4:
				_start_confirm_buy(4)
		elif current_state == ShopState.UPGRADE_MENU:
			if event.keycode == KEY_1:
				_buy_stat_upgrade("cargo")
			elif event.keycode == KEY_2:
				_buy_stat_upgrade("oxygen")
			elif event.keycode == KEY_3:
				_buy_stat_upgrade("speed")
			elif event.keycode == KEY_4:
				_buy_stat_upgrade("mine")
		elif current_state == ShopState.CONFIRM_BUY:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_buy_pickaxe(pending_upgrade_index)
				current_state = ShopState.BUY_MENU
			elif event.keycode == KEY_BACKSPACE or event.keycode == KEY_ESCAPE:
				current_state = ShopState.BUY_MENU
				feedback_text = ""
		
		# Allow going back to main menu
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE:
			if current_state == ShopState.MAIN_MENU:
				current_state = ShopState.PROMPT
				feedback_text = ""
				return
			if current_state in [ShopState.SELL_MENU, ShopState.BUY_MENU, ShopState.UPGRADE_MENU]:
				current_state = ShopState.MAIN_MENU
				feedback_text = ""
				return
			if current_state == ShopState.CONFIRM_BUY:
				current_state = ShopState.BUY_MENU
				feedback_text = ""
				return


func _wrap_feedback(body_text: String) -> String:
	if feedback_text != "":
		return "[center][color=yellow]%s[/color][/center]\n%s" % [feedback_text, body_text]
	return body_text


func _controls_hint(hint: String) -> String:
	return "\n\n[center][color=gray]%s[/color][/center]" % hint


func _money_str(amount: int) -> String:
	return "$%d" % amount

func _process(delta):
	if not player_nearby:
		ui_layer.visible = false
		prompt_label.visible = false
		_set_pickaxes_visible(false)
		return

	if current_state == ShopState.IDLE:
		ui_layer.visible = false
		prompt_label.visible = false
		_set_pickaxes_visible(false)
		return

	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_text = ""

	if current_state == ShopState.PROMPT:
		ui_layer.visible = false
		prompt_label.visible = true
		_set_pickaxes_visible(false)
		var t := _ui_header()
		t += "[center][b]SHOP[/b][/center]\n"
		t += "[center]Press [b]F[/b] to open[/center]"
		prompt_label.text = t
		if Input.is_action_just_pressed(INTERACT_ACTION):
			current_state = ShopState.MAIN_MENU
		return

	# Screen-space UI for real buttons.
	var show_ui: bool = current_state in [ShopState.MAIN_MENU, ShopState.SELL_MENU, ShopState.BUY_MENU, ShopState.UPGRADE_MENU, ShopState.CONFIRM_BUY]
	ui_layer.visible = show_ui
	prompt_label.visible = not show_ui

	if show_ui:
		_set_pickaxes_visible(false)
		_render_ui_if_needed()
		return

	# Fallback: dev menu stays on the world-space prompt label.
	ui_layer.visible = false
	prompt_label.visible = true
	_set_pickaxes_visible(false)
	_render_dev_menu_label()


func _render_ui_if_needed() -> void:
	var header_now := _ui_header()
	if int(current_state) == _last_render_state and feedback_text == _last_render_feedback and header_now == _last_render_header:
		return
	_last_render_state = int(current_state)
	_last_render_feedback = feedback_text
	_last_render_header = header_now
	_render_ui()


func _clear_buttons() -> void:
	for c in ui_buttons.get_children():
		c.queue_free()


func _add_button(text: String, on_pressed: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(on_pressed)
	ui_buttons.add_child(b)
	return b


func _render_ui() -> void:
	ui_feedback.visible = feedback_text != ""
	ui_feedback.text = feedback_text
	ui_header.text = _ui_header()
	_clear_buttons()

	match current_state:
		ShopState.MAIN_MENU:
			ui_body.text = "[center][b]SHOP[/b][/center]"
			_add_button("Sell Ores", func(): current_state = ShopState.SELL_MENU)
			_add_button("Buy Pickaxes", func(): current_state = ShopState.BUY_MENU)
			_add_button("Upgrades", func(): current_state = ShopState.UPGRADE_MENU)
			_add_button("Close", func(): current_state = ShopState.PROMPT)

		ShopState.SELL_MENU:
			var total_value := 0
			var lines: Array[String] = []
			for ore in player_nearby.ORE_TABLE:
				var nm: String = ore[0]
				var val_each: int = int(ore[2])
				var count: int = int(player_nearby.ore_counts.get(nm, 0))
				if count <= 0:
					continue
				var value := count * val_each
				total_value += value
				lines.append("%s x%d (%s)" % [nm, count, _money_str(value)])
			var has_ores := not lines.is_empty()
			var body := "[center][b]SELL ORES[/b][/center]\n\n"
			if not has_ores:
				body += "[center]No ore to sell[/center]"
			else:
				body += "[center]" + "\n".join(lines) + "[/center]\n\n"
				body += "[center]Total: [color=yellow]%s[/color][/center]" % _money_str(total_value)
			ui_body.text = body
			_add_button("Sell All (%s)" % _money_str(total_value), func(): _sell_ores(); _last_render_state = -999, not has_ores)
			_add_button("Back", func(): current_state = ShopState.MAIN_MENU)

		ShopState.BUY_MENU:
			ui_body.text = "[center][b]BUY PICKAXES[/b][/center]\n[center][color=gray]Click a pickaxe to buy[/color][/center]"
			for i in range(1, 5):
				var idx := i
				var upg = player_nearby.PICKAXE_UPGRADES[i]
				var price: int = int(upg["price"])
				var owned: bool = int(player_nearby.pickaxe_level) == i
				var can_afford: bool = int(player_nearby.money) >= price
				var label := "%d: %s  (%s)" % [i, upg["name"], _money_str(price)]
				if owned:
					label += "  [Owned]"
				_add_button(label, func(): _start_confirm_buy(idx); _last_render_state = -999, owned or (not can_afford))
			_add_button("Back", func(): current_state = ShopState.MAIN_MENU)

		ShopState.UPGRADE_MENU:
			var cargo_lv := int(player_nearby.cargo_upgrade_level)
			var oxy_lv := int(player_nearby.oxygen_upgrade_level)
			var spd_lv := int(player_nearby.speed_upgrade_level)
			var mine_lv := int(player_nearby.mining_speed_upgrade_level)
			var cargo_price := _stat_upgrade_price(CARGO_UPGRADE_BASE_PRICE, cargo_lv)
			var oxy_price := _stat_upgrade_price(OXYGEN_UPGRADE_BASE_PRICE, oxy_lv)
			var spd_price := _stat_upgrade_price(SPEED_UPGRADE_BASE_PRICE, spd_lv)
			var mine_price := _stat_upgrade_price(MINE_SPEED_UPGRADE_BASE_PRICE, mine_lv)

			ui_body.text = "[center][b]UPGRADES[/b][/center]"
			_add_button("Cargo Pack (+%d cargo)  %s  (Lv %d/%d)" % [CARGO_UPGRADE_STEP, _money_str(cargo_price), cargo_lv, MAX_STAT_UPGRADE_LEVEL], func(): _buy_stat_upgrade("cargo"); _last_render_state = -999, cargo_lv >= MAX_STAT_UPGRADE_LEVEL)
			_add_button("Oxygen Tank (+%d)  %s  (Lv %d/%d)" % [int(OXYGEN_UPGRADE_STEP), _money_str(oxy_price), oxy_lv, MAX_STAT_UPGRADE_LEVEL], func(): _buy_stat_upgrade("oxygen"); _last_render_state = -999, oxy_lv >= MAX_STAT_UPGRADE_LEVEL)
			_add_button("Boots (+%d speed)  %s  (Lv %d/%d)" % [int(SPEED_UPGRADE_STEP), _money_str(spd_price), spd_lv, MAX_STAT_UPGRADE_LEVEL], func(): _buy_stat_upgrade("speed"); _last_render_state = -999, spd_lv >= MAX_STAT_UPGRADE_LEVEL)
			_add_button("Drill Motor (-%d%% mine time)  %s  (Lv %d/%d)" % [MINE_SPEED_UPGRADE_STEP_PCT, _money_str(mine_price), mine_lv, MAX_STAT_UPGRADE_LEVEL], func(): _buy_stat_upgrade("mine"); _last_render_state = -999, mine_lv >= MAX_STAT_UPGRADE_LEVEL)
			_add_button("Back", func(): current_state = ShopState.MAIN_MENU)

		ShopState.CONFIRM_BUY:
			var upg = player_nearby.PICKAXE_UPGRADES[pending_upgrade_index]
			var old_upg = player_nearby.PICKAXE_UPGRADES[player_nearby.pickaxe_level]
			var mult: float = float(player_nearby.get_mine_time_mult()) if player_nearby.has_method("get_mine_time_mult") else 1.0
			var old_speed = float(old_upg["mine_time"]) * mult
			var new_speed = float(upg["mine_time"]) * mult
			var old_luck = float(old_upg["luck"])
			var new_luck = float(upg["luck"])
			var body := "[center][b]CONFIRM PURCHASE[/b][/center]\n\n"
			body += "[center]Buy [color=yellow]%s[/color]?[/center]\n" % upg["name"]
			body += "[center]Mine Time: %.2fs → %.2fs[/center]\n" % [old_speed, new_speed]
			body += "[center]Luck: %.1fx → %.1fx[/center]\n" % [old_luck, new_luck]
			body += "[center]Cost: [color=yellow]%s[/color][/center]" % _money_str(int(upg["price"]))
			ui_body.text = body
			_add_button("Confirm", func(): _buy_pickaxe(pending_upgrade_index); current_state = ShopState.BUY_MENU; _last_render_state = -999)
			_add_button("Cancel", func(): current_state = ShopState.BUY_MENU)

		_:
			ui_body.text = ""
			_add_button("Close", func(): current_state = ShopState.PROMPT)


func _render_dev_menu_label() -> void:
	if current_state != ShopState.DEV_MENU:
		return
	_set_pickaxes_visible(false)
	var menu := "[center][b]DEV ADMIN[/b][/center]\n"
	menu += "[center]1: +$1000[/center]\n"
	menu += "[center]2: Fill Oxygen[/center]\n"
	menu += "[center]3: +10 of each Ore[/center]\n"
	menu += "[center]4: Set Pickaxe = Gold[/center]\n"
	menu += "[center]5: +10 Cargo Capacity[/center]\n"
	menu += "[center]6: Reset Progress[/center]\n"
	menu += "\n[center]ESC/Backspace: Close[/center]"
	if feedback_text != "":
		prompt_label.text = "[center][color=yellow]%s[/color][/center]\n%s" % [feedback_text, menu]
	else:
		prompt_label.text = menu

func _set_pickaxes_visible(v: bool):
	for i in range(pickaxe_sprites.size()):
		pickaxe_sprites[i].visible = v

func _start_confirm_buy(index: int):
	if player_nearby.pickaxe_level == index:
		feedback_text = "Already owned!"
		feedback_timer = 2.0
		return
	pending_upgrade_index = index
	current_state = ShopState.CONFIRM_BUY

func _buy_pickaxe(index: int):
	var upg = player_nearby.PICKAXE_UPGRADES[index]
	if player_nearby.money >= upg["price"]:
		player_nearby.money -= upg["price"]
		player_nearby.pickaxe_level = index
		player_nearby.base_mine_time = upg["mine_time"]
		if player_nearby.has_method("recompute_mine_time"):
			player_nearby.recompute_mine_time()
		if player_nearby.money_label:
			player_nearby.money_label.text = "$" + str(player_nearby.money)
		feedback_text = "Bought " + upg["name"] + "!"
		feedback_timer = 2.0
		
		if FileAccess.file_exists("res://buy_1.mp3"):
			var asp = AudioStreamPlayer.new()
			asp.stream = load("res://buy_1.mp3")
			add_child(asp)
			asp.play()
			asp.finished.connect(asp.queue_free)
	else:
		feedback_text = "Not enough money"
		feedback_timer = 2.0

func _stat_upgrade_price(base_price: int, level: int) -> int:
	# Doubles each level: 400, 800, 1600...
	return int(round(float(base_price) * pow(2.0, float(level))))

func _buy_stat_upgrade(kind: String) -> void:
	if player_nearby == null:
		return

	var level := 0
	var base_price := 0
	if kind == "cargo":
		level = int(player_nearby.cargo_upgrade_level)
		base_price = CARGO_UPGRADE_BASE_PRICE
	elif kind == "oxygen":
		level = int(player_nearby.oxygen_upgrade_level)
		base_price = OXYGEN_UPGRADE_BASE_PRICE
	elif kind == "speed":
		level = int(player_nearby.speed_upgrade_level)
		base_price = SPEED_UPGRADE_BASE_PRICE
	elif kind == "mine":
		level = int(player_nearby.mining_speed_upgrade_level)
		base_price = MINE_SPEED_UPGRADE_BASE_PRICE
	else:
		return

	if level >= MAX_STAT_UPGRADE_LEVEL:
		feedback_text = "Max level!"
		feedback_timer = 1.2
		return

	var price := _stat_upgrade_price(base_price, level)
	if player_nearby.money < price:
		feedback_text = "Not enough money"
		feedback_timer = 1.6
		return

	player_nearby.money -= price
	if player_nearby.money_label:
		player_nearby.money_label.text = "$" + str(player_nearby.money)

	if kind == "cargo":
		player_nearby.cargo_upgrade_level += 1
		player_nearby.max_cargo += CARGO_UPGRADE_STEP
		feedback_text = "+%d max cargo" % CARGO_UPGRADE_STEP
	elif kind == "oxygen":
		player_nearby.oxygen_upgrade_level += 1
		player_nearby.max_battery += OXYGEN_UPGRADE_STEP
		player_nearby.current_battery = player_nearby.max_battery
		if player_nearby.oxygen_bar:
			player_nearby.oxygen_bar.max_value = player_nearby.max_battery
			player_nearby.oxygen_bar.value = player_nearby.current_battery
		feedback_text = "+%d max oxygen" % int(OXYGEN_UPGRADE_STEP)
	elif kind == "speed":
		player_nearby.speed_upgrade_level += 1
		player_nearby.speed += SPEED_UPGRADE_STEP
		feedback_text = "+%d speed" % int(SPEED_UPGRADE_STEP)
	elif kind == "mine":
		player_nearby.mining_speed_upgrade_level += 1
		if player_nearby.has_method("recompute_mine_time"):
			player_nearby.recompute_mine_time()
		feedback_text = "-%d%% mine time" % MINE_SPEED_UPGRADE_STEP_PCT

	feedback_timer = 1.6
	if FileAccess.file_exists("res://buy_1.mp3"):
		var asp = AudioStreamPlayer.new()
		asp.stream = load("res://buy_1.mp3")
		add_child(asp)
		asp.play()
		asp.finished.connect(asp.queue_free)


func _ui_header() -> String:
	if player_nearby == null:
		return ""
	var money := int(player_nearby.money)
	var cargo := "%d/%d" % [int(player_nearby.current_cargo), int(player_nearby.max_cargo)]
	var oxy := "%d/%d" % [int(player_nearby.current_battery), int(player_nearby.max_battery)]
	return "[center][color=gray]$%d    Cargo %s    Oxygen %s[/color][/center]\n\n" % [money, cargo, oxy]

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body
		current_state = ShopState.PROMPT
		_dev_tap_count = 0
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = null
		current_state = ShopState.IDLE
		_dev_tap_count = 0
		prompt_label.visible = false
		_set_pickaxes_visible(false)

func _dev_add_money(amount: int) -> void:
	if player_nearby == null:
		return
	player_nearby.money += amount
	if player_nearby.money_label:
		player_nearby.money_label.text = "$" + str(player_nearby.money)
	feedback_text = "+$%d" % amount
	feedback_timer = 1.2

func _dev_fill_oxygen() -> void:
	if player_nearby == null:
		return
	player_nearby.current_battery = player_nearby.max_battery
	if player_nearby.oxygen_bar:
		player_nearby.oxygen_bar.value = player_nearby.current_battery
	feedback_text = "Oxygen filled"
	feedback_timer = 1.2

func _dev_add_ores(amount_each: int) -> void:
	if player_nearby == null:
		return
	for ore in player_nearby.ORE_TABLE:
		var nm: String = ore[0]
		player_nearby.ore_counts[nm] = int(player_nearby.ore_counts.get(nm, 0)) + amount_each
		if player_nearby.ore_labels.has(nm):
			player_nearby.ore_labels[nm].text = "%s: %d" % [nm, player_nearby.ore_counts[nm]]
	# Keep cargo in sync (cap at max)
	var total := 0
	for ore in player_nearby.ORE_TABLE:
		total += int(player_nearby.ore_counts.get(ore[0], 0))
	player_nearby.current_cargo = min(player_nearby.max_cargo, total)
	feedback_text = "+%d each ore" % amount_each
	feedback_timer = 1.2

func _dev_set_pickaxe(level: int) -> void:
	if player_nearby == null:
		return
	level = clamp(level, 0, player_nearby.PICKAXE_UPGRADES.size() - 1)
	player_nearby.pickaxe_level = level
	player_nearby.base_mine_time = player_nearby.PICKAXE_UPGRADES[level]["mine_time"]
	if player_nearby.has_method("recompute_mine_time"):
		player_nearby.recompute_mine_time()
	feedback_text = "Pickaxe set: %s" % player_nearby.PICKAXE_UPGRADES[level]["name"]
	feedback_timer = 1.2

func _dev_add_cargo_capacity(amount: int) -> void:
	if player_nearby == null:
		return
	player_nearby.max_cargo += amount
	feedback_text = "Max cargo: %d" % player_nearby.max_cargo
	feedback_timer = 1.2

func _dev_reset_progress() -> void:
	if player_nearby == null:
		return
	player_nearby.money = 0
	if player_nearby.money_label:
		player_nearby.money_label.text = "$0"
	player_nearby.speed = 300.0
	player_nearby.max_battery = 100.0
	player_nearby.max_cargo = 10
	player_nearby.cargo_upgrade_level = 0
	player_nearby.oxygen_upgrade_level = 0
	player_nearby.speed_upgrade_level = 0
	player_nearby.mining_speed_upgrade_level = 0
	player_nearby.current_battery = player_nearby.max_battery
	if player_nearby.oxygen_bar:
		player_nearby.oxygen_bar.max_value = player_nearby.max_battery
		player_nearby.oxygen_bar.value = player_nearby.current_battery
	player_nearby.pickaxe_level = 0
	player_nearby.base_mine_time = player_nearby.PICKAXE_UPGRADES[0]["mine_time"]
	if player_nearby.has_method("recompute_mine_time"):
		player_nearby.recompute_mine_time()
	player_nearby.current_cargo = 0
	for ore in player_nearby.ORE_TABLE:
		var nm: String = ore[0]
		player_nearby.ore_counts[nm] = 0
		if player_nearby.ore_labels.has(nm):
			player_nearby.ore_labels[nm].text = "%s: 0" % nm
	feedback_text = "Reset done"
	feedback_timer = 1.2

func _sell_ores():
	if player_nearby.current_cargo <= 0:
		return

	var total_earnings = 0
	var total_ores_sold = 0

	for ore in player_nearby.ORE_TABLE:
		var nm: String = ore[0]
		var val: int = ore[2]
		var count = player_nearby.ore_counts.get(nm, 0)

		total_earnings += count * val
		total_ores_sold += count
		player_nearby.ore_counts[nm] = 0

		if player_nearby.ore_labels.has(nm):
			player_nearby.ore_labels[nm].text = "%s: 0" % nm

	player_nearby.money += total_earnings
	player_nearby.daily_money_made += total_earnings
	if player_nearby.money_label:
		player_nearby.money_label.text = "$" + str(player_nearby.money)
	player_nearby.current_cargo = 0
	print("Sold ", total_ores_sold, " ores for $", total_earnings)
	
	feedback_text = "Sold for $" + str(total_earnings)
	feedback_timer = 2.0
