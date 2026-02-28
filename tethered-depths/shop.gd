extends Node2D

@onready var prompt_label: Label = $PromptLabel
var player_nearby: Node = null

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
	if player_nearby and Input.is_action_just_pressed("sell"):
		_sell_ores()

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = null
		prompt_label.visible = false

func _sell_ores():
	if player_nearby.current_cargo <= 0:
		return
	var cargo = player_nearby.current_cargo
	var earnings = cargo * 10
	player_nearby.money += earnings
	player_nearby.money_label.text = "$" + str(player_nearby.money)
	player_nearby.current_cargo = 0
	print("Sold ", cargo, " ores for $", earnings)
