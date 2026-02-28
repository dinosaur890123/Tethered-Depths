extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
var player_nearby: Node = null
var upgrade_hold_time: float = 1.5 # seconds to hold 'interact' action
var interact_timer: float = 0.0
var interact_progress: float = 0.0
var is_interacting: bool = false

func _ready():
	prompt_label.visible = false
	$ShopZone.body_entered.connect(_on_body_entered)
	$ShopZone.body_exited.connect(_on_body_exited)

func _process(_delta):
	if not player_nearby:
		return

	var current_level = player_nearby.pickaxe_level
	var max_level = player_nearby.PICKAXE_UPGRADES.size() - 1
	
	var info_text = "
[center]Pickaxe Upgrades:[/center]
[center]"
	
	# Show prices for all upgrades
	for i in range(1, player_nearby.PICKAXE_UPGRADES.size()):
		var upg = player_nearby.PICKAXE_UPGRADES[i]
		var color_hex = upg["color"].to_html(false)
		var status = ""
		if i <= current_level:
			status = " (Owned)"
		info_text += "[color=#%s]%s: $%d%s[/color]
" % [color_hex, upg["name"], upg["price"], status]
	info_text += "[/center]"

	if current_level >= max_level:
		prompt_label.text = "[center][color=#00ff00]MAX LEVEL REACHED[/color][/center]" + info_text
		prompt_label.visible = true
		return

	var next_upg = player_nearby.PICKAXE_UPGRADES[current_level + 1]
	var can_afford = player_nearby.money >= next_upg["price"]

	if Input.is_action_pressed("sell"): # Using "sell" action (F key)
		if not can_afford:
			prompt_label.text = "[center][color=#ff0000]NEED $%d[/color][/center]" % next_upg["price"] + info_text
			return
			
		interact_timer += _delta
		interact_progress = clamp(interact_timer / upgrade_hold_time, 0.0, 1.0)
		prompt_label.text = "[center]Upgrading... " + str(int(interact_progress * 100)) + "%[/center]"
		prompt_label.visible = true
		is_interacting = true
		queue_redraw()

		if interact_timer >= upgrade_hold_time:
			_apply_upgrade()
			interact_timer = 0.0
			interact_progress = 0.0
			is_interacting = false
			queue_redraw()
	else:
		if is_interacting:
			interact_timer = 0.0
			interact_progress = 0.0
			is_interacting = false
			
		var prompt = "Hold F to Upgrade to %s" % next_upg["name"]
		if not can_afford:
			prompt = "[color=#aaaaaa]Cannot Afford %s[/color]" % next_upg["name"]
			
		prompt_label.text = "[center]%s[/center]" % prompt + info_text
		prompt_label.visible = true
		queue_redraw()

func _draw():
	if is_interacting and player_nearby:
		var bar_width = 100.0
		var bar_height = 10.0
		var bar_pos = Vector2(-bar_width / 2.0, -180.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar_pos, Vector2(bar_width * interact_progress, bar_height)), Color(0, 0.8, 1, 0.7))

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = null
		prompt_label.visible = false
		interact_timer = 0.0
		interact_progress = 0.0
		is_interacting = false
		queue_redraw()

func _apply_upgrade():
	var next_level = player_nearby.pickaxe_level + 1
	var upg = player_nearby.PICKAXE_UPGRADES[next_level]
	
	player_nearby.money -= upg["price"]
	player_nearby.pickaxe_level = next_level
	player_nearby.mine_time = upg["mine_time"]
	
	# Update HUD
	player_nearby.money_label.text = "$" + str(player_nearby.money)
	print("Upgraded to ", upg["name"], "! New mine time: ", upg["mine_time"])
