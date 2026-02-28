extends Node2D

@onready var prompt_label: Label = $PromptLabel
var player_nearby: Node = null
var sell_hold_time: float = 1.0 # seconds to hold 'sell' action
var sell_timer: float = 0.0
var sell_progress: float = 0.0
var is_selling: bool = false

func _ready():
	prompt_label.visible = false
	$ShopZone.body_entered.connect(_on_body_entered)
	$ShopZone.body_exited.connect(_on_body_exited)
	await get_tree().physics_frame
	var space = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0, -300),
		global_position + Vector2(0, 600)
	)
	var result = space.intersect_ray(query)
	if result:
		global_position.y = result.position.y

func _process(_delta):
	if not player_nearby:
		return

	# If player has no cargo, inform them and don't start selling
	if player_nearby.current_cargo <= 0:
		prompt_label.text = "No ore to sell"
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
		prompt_label.text = "Hold E to sell... " + str(int(sell_progress * 100)) + "%"
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
		prompt_label.text = "Press E to start selling"
		prompt_label.visible = true
		queue_redraw()

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
	var cargo = player_nearby.current_cargo
	var earnings = cargo * 10
	player_nearby.money += earnings
	player_nearby.money_label.text = "$" + str(player_nearby.money)
	player_nearby.current_cargo = 0
	print("Sold ", cargo, " ores for $", earnings)

	# Feedback: show sold text briefly
	prompt_label.text = "Sold " + str(cargo) + " ores for $" + str(earnings)
	prompt_label.visible = true
	# ensure progress reset
	sell_timer = 0.0
	sell_progress = 0.0
	is_selling = false
	queue_redraw()

func _draw():
	# Draw a simple progress bar above the shop when the player is nearby
	if not player_nearby:
		return

	var bar_w = 120.0
	var bar_h = 10.0
	var offset = Vector2(-bar_w / 2.0, -60.0)
	var bg_rect = Rect2(offset, Vector2(bar_w, bar_h))
	draw_rect(bg_rect, Color(0.1, 0.1, 0.1, 0.9), true)
	# filled portion according to sell_progress
	var filled_rect = Rect2(offset, Vector2(bar_w * sell_progress, bar_h))
	draw_rect(filled_rect, Color(0.2, 0.8, 0.2, 0.95), true)
	# border
	draw_rect(bg_rect, Color(1,1,1,0.6), false, 2.0)
