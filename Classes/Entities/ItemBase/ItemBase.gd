extends RigidBody3D

@export_flags("test1", "test2", "test3")
var selected_flags:int = 0

## Shared status data for pickups. Collector code should duplicate() this
## before handing it to a Character so the shared file is never mutated.
@export var status: StatusEffect = preload("res://Classes/Entities/ItemBase/generic_status.tres")

func _ready():
	if selected_flags & 1: print("test1 selected")
	if selected_flags & 2: print("test2 selected")
	if selected_flags & 3: print("test3 selected")
	print(selected_flags)

## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#pass # Replace with function body.
#
#
## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
