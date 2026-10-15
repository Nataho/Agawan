extends Node
#Author: Nataho

#Sounds = Sound effects
#Music = Music Tracks

var _sounds = {
	"alert": ["res://Assets/sounds/sounds/allclear.ogg",0], #ALERT Subject to change
	
}

var _music = {
	
}

#contains all the loaded sounds in `var sounds`\
#needs sound to be loaded using load_sounds
var _loaded_sounds = {}

func play_sound(sound:String, variation: bool = false, volume_db:float = 0):
	var sound_instance := AudioStreamPlayer.new()
	
	#safety net to check for the preloaded sounds
	assert(_loaded_sounds.has(sound), "Sound '" + sound + "' does not exist!")
	if not _loaded_sounds.has(sound):
		return
	
	var queued_sound = _loaded_sounds[sound]
	
	#playing the actual sound
	sound_instance.stream = queued_sound[0]
	sound_instance.volume_db = queued_sound[1]
	
	add_child(sound_instance)
	
	sound_instance.play()
	sound_instance.finished.connect(
		func():
			sound_instance.queue_free()
	)
	

#must be the first function to be used when using sound effects
func load_sounds(sounds_to_load:Array):
	_loaded_sounds.clear()
	for sound_to_load in sounds_to_load:
		var file_loc = _sounds[sound_to_load][0]
		var volume_db = _sounds[sound_to_load][1]
		
		var key = sound_to_load
		var value = [load(file_loc), volume_db]
		
		_loaded_sounds[key] = value
