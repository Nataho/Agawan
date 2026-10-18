extends Node
class_name PlayerController

@export var character: CharacterBase

func _physics_process(_delta: float) -> void:
	if not character:
		return

	# Handle Sprint Hold
	character.set_sprinting(Input.is_action_pressed("dash"))

	# Handle Movement Vector
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (character.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	character.set_move_direction(direction)

func _unhandled_input(event: InputEvent) -> void:
	# Handle Tap Dash
	if event.is_action_pressed("dash") and character:
		var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var dash_dir := (character.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		character.try_dash(dash_dir)
