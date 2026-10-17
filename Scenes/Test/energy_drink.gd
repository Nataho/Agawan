extends Node


@export var max_cans := 5       
@export var respawn_time := 8.0  
@export var boost_time := 3.0   
@export var speed_mult := 1.5   
@export var regen_mult := 4.0   

var player: Node3D      
var cans: Array[Node3D] = []
var count := 0           
var boost_left := 0.0   
var saved := []           
var icon: TextureRect
var label: Label


func _ready() -> void:
	player = get_parent().get_node("Character")
	make_hud()

	var timer := Timer.new()        
	timer.wait_time = respawn_time
	timer.timeout.connect(spawn_can)
	add_child(timer)
	timer.start()

	await get_tree().physics_frame   
	for i in 4:
		spawn_can()


func _process(delta: float) -> void:
	
	for can in cans:
		var gap := (can.global_position - player.global_position) * Vector3(1, 0, 1)
		if gap.length() < 1.5:
			cans.erase(can)
			can.queue_free()
			count += 1
			update_hud()
			break


	if boost_left > 0.0:
		boost_left -= delta
		if boost_left <= 0.0:
			end_boost()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		if count > 0:
			count -= 1
			update_hud()
			drink()




func spawn_can() -> void:
	if cans.size() >= max_cans:
		return

	
	var angle := randf() * TAU
	var pos := player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(2.5, 10.0)


	var ray := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 10, pos + Vector3.DOWN * 100)
	var body := player as CollisionObject3D
	if body:
		ray.exclude = [body.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		pos = hit.position


	var can := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.texture = load_png(DRINK_PNG)
	sprite.pixel_size = 0.02
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.position.y = sprite.texture.get_height() * sprite.pixel_size / 2  # bottom touches the floor
	can.add_child(sprite)

	get_parent().add_child(can)
	can.global_position = pos
	cans.append(can)




func drink() -> void:
	boost_left = boost_time
	if saved.is_empty():        
		boost("speed", speed_mult)
		boost("regen", regen_mult)



func boost(word: String, mult: float) -> void:
	var ignore := ["dash", "delay", "cooldown", "cost"]
	var nodes: Array = [player] + player.find_children("*", "", true, false)
	var controller := get_parent().get_node_or_null("PlayerController")
	if controller:
		nodes.append(controller)

	for node in nodes:
		for p in node.get_property_list():
			var is_number: bool = p.type == TYPE_FLOAT and (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
			var pname: String = p.name.to_lower()
			if is_number and word in pname and not ignore.any(func(w): return w in pname):
				saved.append([node, p.name, node.get(p.name)])
				node.set(p.name, node.get(p.name) * mult)
				print("Energy drink boosted: ", p.name)


func end_boost() -> void:
	for s in saved:                 
		if is_instance_valid(s[0]):
			s[0].set(s[1], s[2])
	saved.clear()




func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var bag := TextureRect.new()                  
	bag.texture = load_png(BAG_PNG)
	bag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bag.stretch_mode = TextureRect.STRETCH_SCALE
	bag.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bag.offset_left = 20
	bag.offset_right = 20 + 164
	bag.offset_top = -250
	bag.offset_bottom = -250 + 122
	layer.add_child(bag)

	var q := Label.new()                       
	q.text = "Q"
	q.position = Vector2(4, -26)
	bag.add_child(q)

	icon = TextureRect.new()                    
	icon.texture = load_png(DRINK_PNG)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(8, 6)
	icon.size = Vector2(148, 110)
	icon.visible = false
	bag.add_child(icon)

	label = Label.new()                           
	label.position = Vector2(124, 94)
	bag.add_child(label)


func update_hud() -> void:
	icon.visible = count > 0
	label.text = "x%d" % count if count > 0 else ""


func load_png(text: String) -> Texture2D:
	var img := Image.new()
	img.load_png_from_buffer(Marshalls.base64_to_raw(text))
	return ImageTexture.create_from_image(img)



# DATA PICTURE items ako ra ge copy address ge himo nako ase

const DRINK_PNG := "iVBORw0KGgoAAAANSUhEUgAAABAAAAAuCAYAAAAhg5m8AAABz0lEQVR4nLVVO07DQBB9RsFdUIoUEVW6lLElC+pwAqBA4gJI2IXP4iJBcAEkCriBXQdZCinTpQFRUCDoDNLSZJ3ZL5tgnhRt7Nl582Zmd+xBBdO8o/CMDwDY+dkpOt2e8PL97RUA0On2cDWZCH6UgF3GseIgkwDA7d29LnitgK3SsP2MKQAAu34+xnyxVAyToyfFZ0cnYxP8DwGVPx7NNicYDvr1/6QIrSRagov9B6foJrA4DxhjTFjjPFBaaFQA/C6do2Uz3rycaM+DkwJXNE7A4jwAILaSY2Uz3gXjHZBB7wRXoDjrFOiU1CnoIttIOIxtdElFUOAa0UgwHPSdoxoVbIPmCOaLpVMNssgXnoUu0BrwjWlZKU4U/CTWR9i0OS0rwb679wgAXp1CFvmCc1pWaLWn9Sqr4tihDnxNy0oZJqaUhC5Q4/fnIYD1XOTEWeTrFVASOXpShMbaCARZ5GM8miEpQrTaUyRFKMiXowOkC18fB0ql5dSoM58JShF1Urmz3ClBQZwHShspAVUCrM+BMg9c0qA2oQZyZF0qHIoCm6NtT7Pz4E8jrREF2xLUs4BiOOg7fVyEqUwxXyydxpwwE02fNhtJfZCsYczwfgBC8/KxOVfBPAAAAABJRU5ErkJggg=="
const BAG_PNG := "iVBORw0KGgoAAAANSUhEUgAAAFIAAAA9CAYAAAA+jj4UAAAAt0lEQVR4nO3csQ2DAAwAQYOybBgIxiVVJuAlBLqrXFov115m5hwuW+9e4C0+/+G7bXfu8VjHvs+Mi8wIGREyImREyIiQESEjQkaEjAgZETIiZETIiJARISNCRoSMCBkRMiJkRMiIkBEhI0JGhIwIGREyImREyIiQESEjQkaEjAgZETIiZETIiJARISNCRoSMCBkRMiJkRMiIkBEhI0JGhIwIGREyImREyIiQESEjQkaW8dIr4SIjP3f+BXlm0kWiAAAAAElFTkSuQmCC"
