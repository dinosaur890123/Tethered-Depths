extends Node2D

@onready var prompt_label: RichTextLabel = $PromptLabel
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
var player_nearby: Node = null

enum TraderState { IDLE, PROMPT, TALKING, GAMBLING_RESULT }
var current_state = TraderState.IDLE

var feedback_timer: float = 0.0
var feedback_text: String = ""

func _ready():
	prompt_label.visible = false
	prompt_label.bbcode_enabled = true
	$InteractZone.body_entered.connect(_on_body_entered)
	$InteractZone.body_exited.connect(_on_body_exited)
	anim_sprite.play("idle")

func _input(event):
	if not player_nearby:
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if current_state == TraderState.PROMPT:
			if event.keycode == KEY_F:
				current_state = TraderState.TALKING
				if player_nearby: player_nearby.is_in_menu = true
				anim_sprite.play("dialogue")
		elif current_state == TraderState.TALKING:
			if event.keycode == KEY_1 or event.keycode == KEY_Y:
				_gamble_ores()
			elif event.keycode == KEY_2 or event.keycode == KEY_N or event.keycode == KEY_ESCAPE:
				current_state = TraderState.PROMPT
				if player_nearby: player_nearby.is_in_menu = false
				anim_sprite.play("idle")
		elif current_state == TraderState.GAMBLING_RESULT:
			current_state = TraderState.PROMPT
			if player_nearby: player_nearby.is_in_menu = false
			anim_sprite.play("idle")


func _process(delta):
	if not player_nearby:
		return

	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_text = ""

	match current_state:
		TraderState.PROMPT:
			prompt_label.text = "[center][b]TRADER[/b][/center]\n[center]Press [b]F[/b] to talk[/center]\n\n[center][color=gray]Step away to close[/color][/center]"
			prompt_label.visible = true
		
		TraderState.TALKING:
			var total_ores = 0
			for ore in player_nearby.ORE_TABLE:
				total_ores += player_nearby.ore_counts.get(ore[0], 0)
			
			if total_ores <= 0:
				prompt_label.text = '[center][b]TRADER[/b][/center]\n\n[center]"You have no ores to gamble!"[/center]\n\n[center][color=gray]Press any key to close[/color][/center]'
				if Input.is_anything_pressed():
					current_state = TraderState.PROMPT
					anim_sprite.play("idle")
			else:
				prompt_label.text = '[center][b]TRADER[/b][/center]\n\n[center]"Want to gamble your %d ores?"[/center]\n\n[center][color=yellow]1: Yes (50/50 double or lose)[/color][/center]\n[center][color=yellow]2 / ESC: No[/color][/center]' % total_ores
		
		TraderState.GAMBLING_RESULT:
			prompt_label.text = '[center][b]TRADER[/b][/center]\n\n[center]%s[/center]\n\n[center][color=gray]Press any key to close[/color][/center]' % feedback_text
			if Input.is_anything_pressed() and feedback_timer < 1.5: # Small delay to prevent instant skip
				current_state = TraderState.PROMPT
				if player_nearby: player_nearby.is_in_menu = false
				anim_sprite.play("idle")


func _gamble_ores():
	var total_ores = 0
	for ore in player_nearby.ORE_TABLE:
		total_ores += player_nearby.ore_counts.get(ore[0], 0)
	
	if total_ores <= 0:
		return

	if randf() < 0.5:
		# Double ores
		for ore in player_nearby.ORE_TABLE:
			var nm = ore[0]
			var count = player_nearby.ore_counts.get(nm, 0)
			player_nearby.ore_counts[nm] = count * 2
			if player_nearby.ore_labels.has(nm):
				player_nearby.ore_labels[nm].text = "%s: %d" % [nm, player_nearby.ore_counts[nm]]
		
		player_nearby.current_cargo *= 2
		feedback_text = 'Trader: "Lucky! Your ores have doubled!"'
	else:
		# Lose all ores
		for ore in player_nearby.ORE_TABLE:
			var nm = ore[0]
			player_nearby.ore_counts[nm] = 0
			if player_nearby.ore_labels.has(nm):
				player_nearby.ore_labels[nm].text = "%s: 0" % nm
		
		player_nearby.current_cargo = 0
		feedback_text = 'Trader: "Too bad! Better luck next time."'
	
	current_state = TraderState.GAMBLING_RESULT
	feedback_timer = 2.0

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_nearby = body
		current_state = TraderState.PROMPT
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		if player_nearby:
			player_nearby.is_in_menu = false
		player_nearby = null
		current_state = TraderState.IDLE
		prompt_label.visible = false
		anim_sprite.play("idle")

