extends RigidBody3D
class_name ItemBase
## Shared status data for pickups. Collector code should duplicate() this
## before handing it to a Character so the shared file is never mutated.
@export var status: StatusEffect = preload("res://Classes/Entities/ItemBase/generic_status.tres")

func _ready():
	# report contacts so the item can see a character walking into it
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBase:
		collect(body)

## Gives the character a copy of the status data, then removes the pickup.
func collect(character: CharacterBase) -> void:
	character.apply_status(status.duplicate())
	queue_free()
