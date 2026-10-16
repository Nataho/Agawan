extends Control

func _ready() -> void:
	Segue.change_scene(Segue.MAIN_SCENE)
	# or
	Segue.change_scene("res://Scenes/main/main.tscn")
	
