extends Resource
class_name Attack

var attack_name: String
var contact: = false
var dmg: = 0
var effect_to_self: StatusEffect
var effect_to_target: StatusEffect

func _init(attack_name) -> void:
	self.attack_name = attack_name
	
