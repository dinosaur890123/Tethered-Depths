extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
var player_nearby: Node = null

# Protect the ground under the shop from being mined.
@export var foundation_half_width_tiles: int = 2 # total width = (half*2+1)
@export var foundation_depth_tiles: int = 2

# Developer menu unlock (press E 10x near shop)
const DEV_TAP_TARGET: int = 10
var _dev_tap_count: int = 0

enum ShopState { IDLE, PROMPT, MAIN_MENU, SELL_MENU, BUY_MENU, CONFIRM_BUY, DEV_MENU }
var current_state = ShopState.IDLE
var pending_upgrade_index: int = -1

var pickaxe_sprites: Array[Sprite2D] = []
var feedback_timer: float = 0.0
var feedback_text: String = ""

func _ready():
	prompt_label.visible = false
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

	# Secret dev menu: tap E 10 times while near the shop.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
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
		elif current_state == ShopState.BUY_MENU:
			if event.keycode == KEY_1:
				_start_confirm_buy(1)
			elif event.keycode == KEY_2:
				_start_confirm_buy(2)
			elif event.keycode == KEY_3:
				_start_confirm_buy(3)
			elif event.keycode == KEY_4:
				_start_confirm_buy(4)
		elif current_state == ShopState.CONFIRM_BUY:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_buy_pickaxe(pending_upgrade_index)
				current_state = ShopState.BUY_MENU
			elif event.keycode == KEY_BACKSPACE or event.keycode == KEY_ESCAPE:
				current_state = ShopState.BUY_MENU
				feedback_text = ""
		
		# Allow going back to main menu
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE:
			if current_state in [ShopState.SELL_MENU, ShopState.BUY_MENU]:
				current_state = ShopState.MAIN_MENU
				feedback_text = ""

func _process(delta):
	if not player_nearby:
		_set_pickaxes_visible(false)
		return

	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_text = ""

	match current_state:
		ShopState.PROMPT:
			prompt_label.text = "[center]Press E to open shop[/center]"
			prompt_label.visible = true
			_set_pickaxes_visible(false)
			if Input.is_action_just_pressed("sell"):
				current_state = ShopState.MAIN_MENU
		
		ShopState.MAIN_MENU:
			prompt_label.text = "[center]1: Sell Ores\n2: Buy Pickaxes[/center]"
			_set_pickaxes_visible(false)
		
		ShopState.SELL_MENU:
			var cargo_msg = ""
			if player_nearby.current_cargo <= 0:
				cargo_msg = "No ore to sell"
			else:
				cargo_msg = "Press E to sell ores"
			
			prompt_label.text = "[center]%s[/center]" % cargo_msg
			_set_pickaxes_visible(false)
			
			if Input.is_action_just_pressed("sell"):
				_sell_ores()
				
		ShopState.BUY_MENU:
			_set_pickaxes_visible(true)
			var upg_text = "[center]Buy Pickaxes:[/center]\n"
			for i in range(1, 5):
				var upg = player_nearby.PICKAXE_UPGRADES[i]
				var color_hex = upg["color"].to_html(false)
				pickaxe_sprites[i-1].modulate = upg["color"]
				var status = ""
				if player_nearby.pickaxe_level == i:
					status = " (Owned)"
				upg_text += "[center][color=#%s]%d: %s ($%d)%s[/color][/center]\n" % [color_hex, i, upg["name"], upg["price"], status]
			
			if feedback_text != "":
				prompt_label.text = "[center][color=yellow]%s[/color][/center]\n%s" % [feedback_text, upg_text]
			else:
				prompt_label.text = upg_text
		
		ShopState.CONFIRM_BUY:
			_set_pickaxes_visible(false)
			var upg = player_nearby.PICKAXE_UPGRADES[pending_upgrade_index]
			var old_upg = player_nearby.PICKAXE_UPGRADES[player_nearby.pickaxe_level]
			
			var old_speed = old_upg["mine_time"]
			var new_speed = upg["mine_time"]
			var old_luck = old_upg["luck"]
			var new_luck = upg["luck"]
			
			var confirm_text = "[center]Are you sure you want to buy [color=yellow]%s[/color]?[/center]\n" % upg["name"]
			confirm_text += "[center]Mine Time: %.2fs [color=green]→[/color] [color=green]%.2fs[/color][/center]\n" % [old_speed, new_speed]
			if new_luck > old_luck:
				confirm_text += "[center]Ore Luck: %.1fx [color=green]→[/color] [color=green]%.1fx[/color][/center]\n" % [old_luck, new_luck]
			confirm_text += "[center]Cost: $%d[/center]\n" % upg["price"]
			confirm_text += "\n[center][color=white]Return: Yes (Confirm) | Backspace: No (Cancel)[/color][/center]"
			
			prompt_label.text = confirm_text

		ShopState.DEV_MENU:
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
		player_nearby.mine_time = upg["mine_time"]
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
		feedback_text = "they dont have enough money"
		feedback_timer = 2.0

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
	player_nearby.mine_time = player_nearby.PICKAXE_UPGRADES[level]["mine_time"]
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
	player_nearby.current_battery = player_nearby.max_battery
	if player_nearby.oxygen_bar:
		player_nearby.oxygen_bar.value = player_nearby.current_battery
	player_nearby.pickaxe_level = 0
	player_nearby.mine_time = player_nearby.PICKAXE_UPGRADES[0]["mine_time"]
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
