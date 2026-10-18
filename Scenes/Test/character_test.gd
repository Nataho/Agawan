extends Node3D

@export var move_speed: float = 6.0
@export var jump_velocity: float = 8.0

@onready var player: CharacterBody3D = $Player
@onready var sprite: AnimatedSprite3D = $Player/AnimatedSprite3D
@onready var stamina_label: Label = %stamina_label

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _last_direction_anim: String = "down"

@onready var character: CharacterBase = $Character

func _ready() -> void:
	if sprite:
		sprite.play("down")

func _process(delta: float) -> void:
	stamina_label.text = "stamina: " + str(character.get_current_stamina())

#func _physics_process(delta: float) -> void:
	#if not player:
		#return
#
	## Apply gravity natively
	#if not player.is_on_floor():
		#player.velocity.y -= gravity * delta
#
	## Handle Jump
	#if Input.is_physical_key_pressed(KEY_SPACE) and player.is_on_floor():
		#player.velocity.y = jump_velocity
#
	## Handle Up, Down, Left, Right (WASD or Arrow keys)
	#var input_x: float = 0.0
	#var input_z: float = 0.0
#
	#if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		#input_x += 1.0
	#if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		#input_x -= 1.0
	#if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		#input_z += 1.0
	#if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		#input_z -= 1.0
#
	#var direction: Vector3 = Vector3(input_x, 0.0, input_z).normalized()
	#if direction != Vector3.ZERO:
		#player.velocity.x = direction.x * move_speed
		#player.velocity.z = direction.z * move_speed
	#else:
		#player.velocity.x = move_toward(player.velocity.x, 0.0, move_speed)
		#player.velocity.z = move_toward(player.velocity.z, 0.0, move_speed)
#
	## Update 8-directional animation based on input direction
	#_update_animation(input_x, input_z)
#
	## Native Godot 3D physics collision handling
	#player.move_and_slide()
#
#
#func _update_animation(input_x: float, input_z: float) -> void:
	#if not sprite:
		#return
#
	## Ensure flip_h is disabled since distinct directional animations are provided
	#sprite.flip_h = false
#
	#if input_x != 0.0 or input_z != 0.0:
		#var anim_name: String = ""
#
		#if input_z < 0.0: # UP
			#if input_x < 0.0:
				#anim_name = "up-left"
			#elif input_x > 0.0:
				#anim_name = "up-right"
			#else:
				#anim_name = "up"
		#elif input_z > 0.0: # DOWN
			#if input_x < 0.0:
				#anim_name = "down-left"
			#elif input_x > 0.0:
				#anim_name = "down-right"
			#else:
				#anim_name = "down"
		#else: # HORIZONTAL ONLY
			#if input_x < 0.0:
				#anim_name = "left"
			#elif input_x > 0.0:
				#anim_name = "right"
#
		#if not anim_name.is_empty():
			#_last_direction_anim = anim_name
			#if sprite.animation != anim_name:
				#sprite.play(anim_name)
	#else:
		## When idle, pause on current direction or play first frame
		#if sprite.is_playing():
			#sprite.pause()
			#sprite.frame = 0
