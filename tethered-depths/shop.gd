extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
var player_nearby: Node = null
var sell_hold_time: float = 1.0 # seconds to hold 'sell' action
var sell_timer: float = 0.0
var sell_progress: float = 0.0
var is_selling: bool = false

func _ready():
	prompt_label.visible = false
	$ShopZone.body_entered.connect(_on_body_entered)
	$ShopZone.body_exited.connect(_on_body_exited)

func _process(_delta):
	if not player_nearby:
		return

	var price_text = "\n[center]Prices:[/center]\n[center]"
	for ore in player_nearby.ORE_TABLE:
		var color_hex = ore[3].to_html(false)
		price_text += "[color=#%s]%s: $%d[/color]  " % [color_hex, ore[0], ore[2]]
	price_text += "[/center]"

	# If player has no cargo, inform them and don't start selling
	if player_nearby.current_cargo <= 0:
		prompt_label.text = "[center]No ore to sell[/center]" + price_text
		prompt_label.visible = true
		sell_timer = 0.0
		sell_progress = 0.0
		is_selling = false
		queue_redraw()
		return

	# Show base prompt when nearby
	if Input.is_action_pressed("sell"):
		# Hold-to-sell behaviour
		sell_timer += _delta
		sell_progress = clamp(sell_timer / sell_hold_time, 0.0, 1.0)
		prompt_label.text = "[center]Selling... " + str(int(sell_progress * 100)) + "%[/center]"
		prompt_label.visible = true
		is_selling = true
		queue_redraw()

		if sell_timer >= sell_hold_time:
			_sell_ores()
			sell_timer = 0.0
			sell_progress = 0.0
			is_selling = false
			queue_redraw()
	else:
		# Not holding — reset any in-progress sell
		if is_selling:
			sell_timer = 0.0
			sell_progress = 0.0
			is_selling = false
		prompt_label.text = "[center]Hold E to sell ores[/center]" + price_text
		prompt_label.visible = true
		queue_redraw()

func _draw():
	if is_selling and player_nearby:
		# Draw a small progress bar above the shop (centered)
		var bar_width = 100.0
		var bar_height = 10.0
		var bar_pos = Vector2(-bar_width / 2.0, -180.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar_pos, Vector2(bar_width * sell_progress, bar_height)), Color(0, 1, 0, 0.7))

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = null
		prompt_label.visible = false
		# reset selling progress when player leaves
		sell_timer = 0.0
		sell_progress = 0.0
		is_selling = false
		queue_redraw()

func _sell_ores():
	if player_nearby.current_cargo <= 0:
		return

	var total_earnings = 0
	var total_ores_sold = 0

	# Calculate earnings based on individual ore values from player's ORE_TABLE
	for ore in player_nearby.ORE_TABLE:
		var nm: String = ore[0]
		var val: int = ore[2]
		var count = player_nearby.ore_counts.get(nm, 0)

		total_earnings += count * val
		total_ores_sold += count

		# Reset the count for this ore
		player_nearby.ore_counts[nm] = 0

		# Update the HUD label for this ore
		if player_nearby.ore_labels.has(nm):
			player_nearby.ore_labels[nm].text = "%s: 0" % nm

	player_nearby.money += total_earnings
	player_nearby.money_label.text = "$" + str(player_nearby.money)
	player_nearby.current_cargo = 0
	print("Sold ", total_ores_sold, " ores for $", total_earnings)
