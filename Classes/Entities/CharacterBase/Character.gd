class_name CharacterBase
extends CharacterBody3D

@export var base_movement_speed: float = 5.0
@export var sprint_speed_multiplier: float = 1.5
@export var dash_distance: float = 3.0
@export var dash_speed_multiplier: float = 3.0 # Dash is noticeably faster than sprint (1.5x)
@export var dash_duration: float = 0.2 # Duration of the burst dash in seconds
@export var team_index: int = -1

# Stats
var _player_effective_lvl: int = 1
var level: int = 1
var lvl_booster_bonus: int = 0
@export var stamina_points: float = 0.0 

var _max_stamina: float = 100.0
var _current_stamina: float = _max_stamina

@export var archetype_multiplier: float = 1.0 # 0.8 Athletic, 1.0 Balanced, 1.2 Tank
var stamina_rate: float = 1.0
var stamina_regen_rate: float = 15.0 # Stamina recovered per second when idle

# Action Costs
@export var dash_base_cost: float = 25.0
@export var sprint_base_cost_per_sec: float = 12.0

# Burnout System
@export var burnout_recovery_stamina: float = 50.0 # Stamina required to recover from burnout
@export var burnout_speed_multiplier: float = 0.5 # Slowdown factor while in burnout state

# State Signals
signal airborne_changed(is_airborne: bool)
signal poison_ticked(damage: float) ## fired every poison_interval during poison (health system hooks here later)

# State Tracking
var is_sprinting: bool = false
var is_dashing: bool = false
var is_burned_out: bool = false
var is_airborne: bool = false
var is_regen_blocked: bool = false
var _dash_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

@export var airborne_control_multiplier: float = 0.7 # Air control factor for horizontal movement

@onready var sprite: AnimatedSprite3D = get_node_or_null("AnimatedSprite3D")
@onready var stamina_bar: StaminaBar = get_node_or_null("BarViewport/StaminaBar")
@onready var bar_sprite_3d: Sprite3D = get_node_or_null("AnimatedSprite3D/BarSprite3D")

# Status Effects (fed by ItemBase.collect, see Status.gd for the data)
var active_status: StatusEffect = null
var _stun_left: float = 0.0
var _air_left: float = 0.0
var _speed_left: float = 0.0
var _poison_left: float = 0.0
var _poison_tick: float = 0.0

var _last_direction_anim: String = "down"

func _ready() -> void:
	_update_stamina_bar()

func _update_stamina_bar() -> void:
	if stamina_bar:
		var final_dash_cost: float = dash_base_cost * stamina_rate
		stamina_bar.update_bar(_current_stamina, _max_stamina, final_dash_cost, is_burned_out)


func _physics_process(delta: float) -> void:
	_calculate_stats()
	_tick_status(delta)
	_apply_gravity(delta)
	_handle_dash(delta)
	_handle_sprint_stamina(delta)
	_handle_stamina_regeneration(delta)
	_update_stamina_bar()
	move_and_slide()


# --- Public Controller API (Called by PlayerController or AI) ---

func trigger_burnout() -> void:
	if not is_burned_out:
		is_burned_out = true
		is_sprinting = false
		is_dashing = false
		_dash_timer = 0.0


func try_dash(dash_dir: Vector3 = Vector3.ZERO) -> bool:
	if is_stunned() or is_dashing or is_burned_out:
		return false

	var final_dash_cost: float = dash_base_cost * stamina_rate
	var causes_burnout: bool = false
	
	if _current_stamina >= final_dash_cost:
		_current_stamina -= final_dash_cost
	else:
		# Stamina was below the dash cost: execute dash, zero out stamina, and trigger burnout
		_current_stamina = 0.0
		causes_burnout = true

	is_dashing = true
	_dash_timer = dash_duration

	# If no direction provided, dash forward facing or in current horizontal velocity direction
	if dash_dir != Vector3.ZERO:
		_dash_direction = dash_dir.normalized()
	elif Vector2(velocity.x, velocity.z).length() > 0.1:
		_dash_direction = Vector3(velocity.x, 0, velocity.z).normalized()
	else:
		_dash_direction = -transform.basis.z.normalized()

	# Immediately apply fast burst velocity
	var dash_speed: float = base_movement_speed * dash_speed_multiplier
	velocity.x = _dash_direction.x * dash_speed
	velocity.z = _dash_direction.z * dash_speed
	update_directional_animation(_dash_direction.x, _dash_direction.z)

	if causes_burnout:
		is_burned_out = true
		is_sprinting = false

	return true


func set_sprinting(active: bool) -> void:
	if is_stunned():
		is_sprinting = false
		return

	if is_burned_out:
		is_sprinting = false
		return

	if active and _current_stamina > 0.0:
		is_sprinting = true
	else:
		is_sprinting = false


func get_current_speed() -> float:
	if is_burned_out:
		return base_movement_speed * burnout_speed_multiplier
	if is_dashing:
		return base_movement_speed * dash_speed_multiplier
	if is_sprinting and _current_stamina > 0.0:
		return base_movement_speed * sprint_speed_multiplier
	if _speed_left > 0.0 and active_status != null: # speed status
		return base_movement_speed * active_status.speed_multiplier
	return base_movement_speed

func set_move_direction(dir: Vector3) -> void:
	# During a fast dash, movement direction is driven by the dash
	if is_dashing:
		return

	# Stunned: inputs are ignored and the body grinds to a stop
	if is_stunned():
		velocity.x = move_toward(velocity.x, 0.0, base_movement_speed)
		velocity.z = move_toward(velocity.z, 0.0, base_movement_speed)
		return

	var move_speed := get_current_speed()
	if dir != Vector3.ZERO:
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	update_directional_animation(dir.x, dir.z)

#ANIMATION HANDLER
func update_directional_animation(input_x: float, input_z: float) -> void:
	if not sprite:
		return

	sprite.flip_h = false

	if absf(input_x) > 0.01 or absf(input_z) > 0.01:
		var anim_name: String = ""

		if input_z < -0.1: # UP
			if input_x < -0.1:
				anim_name = "move_up_left"
			elif input_x > 0.1:
				anim_name = "move_up_right"
			else:
				anim_name = "move_up"
		elif input_z > 0.1: # DOWN
			if input_x < -0.1:
				anim_name = "move_down_left"
			elif input_x > 0.1:
				anim_name = "move_down_right"
			else:
				anim_name = "move_down"
		else: # HORIZONTAL
			if input_x < -0.1:
				anim_name = "move_left"
			elif input_x > 0.1:
				anim_name = "move_right"

		if not anim_name.is_empty():
			_last_direction_anim = anim_name
			if sprite.animation != anim_name:
				sprite.play(anim_name)
			elif not sprite.is_playing():
				sprite.play()
	else:
		sprite.play("default")
		if sprite.is_playing():
			sprite.pause()
			sprite.frame = 0


# --- Internal Systems ---

func _calculate_stats() -> void:
	_player_effective_lvl = min(level + lvl_booster_bonus, 15)
	var efficiency := 100.0 / (100.0 + (_player_effective_lvl * 4.0) + stamina_points)
	stamina_rate = archetype_multiplier * efficiency


func _apply_gravity(delta: float) -> void:
	if _air_left > 0.0: # air status: keep hovering until it runs out
		velocity.y = 0.0
		return
	if not is_on_floor():
		velocity += get_gravity() * delta


func _handle_dash(delta: float) -> void:
	if is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			is_dashing = false
			# After dash finishes, transition smoothly into current sprint/run speed
			var regular_speed := get_current_speed()
			velocity.x = _dash_direction.x * regular_speed
			velocity.z = _dash_direction.z * regular_speed


func _handle_sprint_stamina(delta: float) -> void:
	if is_sprinting:
		if _current_stamina > 0.0:
			var final_sprint_cost: float = sprint_base_cost_per_sec * stamina_rate * delta
			_current_stamina = max(0.0, _current_stamina - final_sprint_cost)
			if _current_stamina <= 0.0:
				trigger_burnout()
		else:
			trigger_burnout()


func _handle_stamina_regeneration(delta: float) -> void:
	if not is_sprinting and not is_regen_blocked and _current_stamina < _max_stamina:
		_current_stamina = min(_max_stamina, _current_stamina + (stamina_regen_rate * delta))
		
		# Recover from burnout once stamina hits the recovery threshold (e.g. 50.0)
		if is_burned_out and _current_stamina >= burnout_recovery_stamina:
			is_burned_out = false

func get_current_stamina() -> float:
	return _current_stamina


# --- Status Effects (fed by pickups, data lives in Status.gd) ---

## Replaces whatever status is active. ItemBase passes status.duplicate()
## so edits stay local to this character.
func apply_status(effect: StatusEffect) -> void:
	active_status = effect
	_stun_left = effect.stun_time
	_air_left = effect.air_time
	_speed_left = effect.speed_duration
	_poison_left = effect.poison_time
	_poison_tick = float(effect.poison_interval)

func is_stunned() -> bool:
	return _stun_left > 0.0

func clear_status() -> void:
	active_status = null
	_stun_left = 0.0
	_air_left = 0.0
	_speed_left = 0.0
	_poison_left = 0.0

func _tick_status(delta: float) -> void:
	if active_status == null:
		return

	_stun_left = maxf(0.0, _stun_left - delta)
	_air_left = maxf(0.0, _air_left - delta)
	_speed_left = maxf(0.0, _speed_left - delta)

	if _poison_left > 0.0: # damage per interval, ticks toward zero
		_poison_left -= delta
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick += float(active_status.poison_interval)
			poison_ticked.emit(active_status.poison_damage)

	var all_expired: bool = _stun_left <= 0.0 and _air_left <= 0.0 \
		and _speed_left <= 0.0 and _poison_left <= 0.0
	if all_expired:
		active_status = null
