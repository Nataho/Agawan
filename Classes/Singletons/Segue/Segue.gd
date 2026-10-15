extends CanvasLayer
#Transition Global Scene
#Author: Nataho

const MAIN_SCENE = "res://Scenes/main/main.tscn"
const QUIT = "quit"

#transitions
const DISSOLVE_TRANSITION = "dissolve"

const _transitions = [
	DISSOLVE_TRANSITION
]

@onready var anim: AnimationPlayer = $anim

##changes the scene to the path[br]
##parameters `(String, String)`
func change_scene(path_to_scene, transition = DISSOLVE_TRANSITION):
	if path_to_scene == QUIT:
		get_tree().quit()
	
	assert(_transitions.has(transition), "transition '" + transition + "' does not exist!")
	if not _transitions.has(transition):
		return
	
	_transition(path_to_scene, transition)
	
	print("transitioning")
	#end

func _transition(path_to_scene, transition):
	match transition:
		DISSOLVE_TRANSITION:
			anim.play("dissolve_in")
	
	await anim.animation_finished
	get_tree().change_scene_to_file(path_to_scene)
	
	match transition:
		DISSOLVE_TRANSITION:
			anim.play("dissolve_out")
