extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
var player_nearby: Node = null

enum ShopState { IDLE, PROMPT, MAIN_MENU, SELL_MENU, BUY_MENU }
var current_state = ShopState.IDLE

var pickaxe_sprites: Array[Sprite2D] = []
var feedback_timer: float = 0.0
var feedback_text: String = ""

func _ready():
	prompt_label.visible = false
	$ShopZone.body_entered.connect(_on_body_entered)
	$ShopZone.body_exited.connect(_on_body_exited)
	
	# Create pickaxe sprites for visual selection
	for i in range(4):
		var s = Sprite2D.new()
		s.texture = load("res://icon.svg")
		s.scale = Vector2(0.4, 0.4)
		s.visible = false
		s.position = Vector2(-120 + i * 80, -320)
		add_child(s)
		pickaxe_sprites.append(s)

func _input(event):
	if not player_nearby:
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if current_state == ShopState.MAIN_MENU:
			if event.keycode == KEY_1:
				current_state = ShopState.SELL_MENU
				feedback_text = ""
			elif event.keycode == KEY_2:
				current_state = ShopState.BUY_MENU
				feedback_text = ""
		elif current_state == ShopState.BUY_MENU:
			if event.keycode == KEY_1: _buy_pickaxe(1)
			elif event.keycode == KEY_2: _buy_pickaxe(2)
			elif event.keycode == KEY_3: _buy_pickaxe(3)
			elif event.keycode == KEY_4: _buy_pickaxe(4)
		
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
			var price_text = "\n[center]Prices:[/center]\n[center]"
			for ore in player_nearby.ORE_TABLE:
				var color_hex = ore[3].to_html(false)
				price_text += "[color=#%s]%s: $%d[/color]  " % [color_hex, ore[0], ore[2]]
			price_text += "[/center]"
			
			var cargo_msg = ""
			if player_nearby.current_cargo <= 0:
				cargo_msg = "No ore to sell"
			else:
				cargo_msg = "Press E to sell ores"
			
			prompt_label.text = "[center]%s[/center]%s" % [cargo_msg, price_text]
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

func _set_pickaxes_visible(v: bool):
	for s in pickaxe_sprites:
		s.visible = v

func _buy_pickaxe(index: int):
	var upg = player_nearby.PICKAXE_UPGRADES[index]
	if player_nearby.money >= upg["price"]:
		player_nearby.money -= upg["price"]
		player_nearby.pickaxe_level = index
		player_nearby.mine_time = upg["mine_time"]
		player_nearby.money_label.text = "$" + str(player_nearby.money)
		feedback_text = "Bought " + upg["name"] + "!"
		feedback_timer = 2.0
		
		# Play sound if available
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
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = null
		current_state = ShopState.IDLE
		prompt_label.visible = false
		_set_pickaxes_visible(false)

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
	player_nearby.money_label.text = "$" + str(player_nearby.money)
	player_nearby.current_cargo = 0
	print("Sold ", total_ores_sold, " ores for $", total_earnings)
	
	feedback_text = "Sold for $" + str(total_earnings)
	feedback_timer = 2.0
