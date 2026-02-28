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
	
	var total_earnings = 0
	
	# Calculate earnings based on individual ore values from player's ORE_TABLE
	for ore in player_nearby.ORE_TABLE:
		var nm: String = ore[0]
		var val: int = ore[2]
		var count = player_nearby.ore_counts.get(nm, 0)
		
		total_earnings += count * val
		
		# Reset the count for this ore
		player_nearby.ore_counts[nm] = 0
		
		# Update the HUD label for this ore
		if player_nearby.ore_labels.has(nm):
			player_nearby.ore_labels[nm].text = "%s: 0" % nm
	
	player_nearby.money += total_earnings
	player_nearby.money_label.text = "$" + str(player_nearby.money)
	player_nearby.current_cargo = 0
	
	print("Sold cargo for $", total_earnings)
