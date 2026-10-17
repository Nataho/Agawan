class_name StaminaBar
extends Control

@export var max_stamina: float = 100.0
@export var current_stamina: float = 100.0
@export var dash_cost: float = 25.0
@export var is_burned_out: bool = false

# Dandelion yellow (#FED85D) and Burnout Red (#E74C3C)
@export var stable_color: Color = Color(0.996, 0.847, 0.365, 1.0)
@export var burnout_color: Color = Color(0.906, 0.298, 0.235, 1.0)
@export var bg_color: Color = Color(0.12, 0.12, 0.14, 0.85)
@export var border_color: Color = Color(0.05, 0.05, 0.05, 0.95)
@export var divider_color: Color = Color(0.1, 0.1, 0.1, 0.85)


func update_bar(cur: float, max_val: float, cost: float, burned_out: bool) -> void:
	current_stamina = cur
	max_stamina = max_val
	dash_cost = cost
	is_burned_out = burned_out
	queue_redraw()


func _draw() -> void:
	var total_w := size.x
	var total_h := size.y
	
	if max_stamina <= 0.0 or total_w <= 0.0 or total_h <= 0.0:
		return

	# Background
	var full_rect := Rect2(Vector2.ZERO, size)
	draw_rect(full_rect, bg_color, true)

	# Stamina fill
	var fill_ratio: float = clampf(current_stamina / max_stamina, 0.0, 1.0)
	var fill_w: float = total_w * fill_ratio
	var fill_rect := Rect2(Vector2.ZERO, Vector2(fill_w, total_h))
	var fill_color := burnout_color if is_burned_out else stable_color
	draw_rect(fill_rect, fill_color, true)

	# Dash segment dividers (vertical lines indicating dash costs)
	if dash_cost > 0.0:
		var segment_x: float = (dash_cost / max_stamina) * total_w
		var cur_x: float = segment_x
		while cur_x < total_w - 1.0:
			draw_line(Vector2(cur_x, 0.0), Vector2(cur_x, total_h), divider_color, 2.0)
			cur_x += segment_x

	# Border outline
	draw_rect(full_rect, border_color, false, 2.0)
