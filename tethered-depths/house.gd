extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
var player_nearby: Node = null

func _ready():
	prompt_label.visible = false
	prompt_label.bbcode_enabled = true
	$HouseZone.body_entered.connect(_on_body_entered)
	$HouseZone.body_exited.connect(_on_body_exited)

func _input(event):
	if not player_nearby: return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("sell"):
		if player_nearby.has_method("sleep"):
			player_nearby.sleep()
			prompt_label.text = "[center]Sweet dreams...[/center]"

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body
		prompt_label.text = "[center][b]HOUSE[/b][/center]\n[center]Press [b]F[/b] to sleep[/center]\n\n[center][color=gray]Step away to close[/color][/center]"
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_nearby = null
		prompt_label.visible = false
