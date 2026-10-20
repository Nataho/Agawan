extends Resource
class_name StatusEffect
#Author: Nataho

@export var status_name = "generic status"
@export var stun_time:float = 0.0 ## stun duration
@export var air_time:float = 0.0 ## airborne duration

@export var poison_time:float = 0.0 
@export var poison_interval:int =  1 ##in seconds
@export var poison_damage:float = 0.0 ##damage per second

#both can work with fast and slow
@export var speed_multiplier:float = 0.0
@export var speed_duration:float = 0.0

func _init(status_name:String) -> void:
	self.status_name = status_name

func create_from_dict(status_name:String, effects:Dictionary) -> StatusEffect:
	var obj := StatusEffect.new(status_name)
	for effect in effects.keys():
		_conversion(effect, effects[effect], obj)
	
	return obj

#used on networking and status
func _conversion(effect_name:String, value:Variant, obj_inst:StatusEffect) -> void:
	match effect_name:
		"stun_time": obj_inst.stun_time = value
		"air_time": obj_inst.air_time = value
		"poison_time": obj_inst.poison_time = value
		"poison_interval": obj_inst.poison_interval = value
		"poison_damage": obj_inst.poison_damage = value
		"speed_multiplier": obj_inst.speed_multiplier = value
		"speed_duration": obj_inst.speed_duration = value
