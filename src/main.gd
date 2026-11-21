extends Node3D
## Flow: intro -> menu -> game -> menu.

var audio: AudioBank
var intro: Intro
var menu: Menu
var game: Game


func _ready() -> void:
	audio = AudioBank.new()
	audio.name = "AudioBank"
	add_child(audio)
	audio.play_music("intro_theme", -7.0)
	_show_intro()


func _show_intro() -> void:
	intro = Intro.new()
	intro.name = "Intro"
	add_child(intro)
	intro.finished.connect(_show_menu)


func _show_menu() -> void:
	if intro != null:
		intro.queue_free()
		intro = null
	menu = Menu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.start_requested.connect(_start_game)
	audio.play_music("menu_theme", -11.0)


func _start_game() -> void:
	if menu != null:
		menu.queue_free()
		menu = null
	game = Game.new()
	game.name = "Game"
	game.audio = audio
	add_child(game)
	game.quit_to_menu.connect(_back_to_menu)


func _back_to_menu() -> void:
	if game != null:
		game.queue_free()
		game = null
	audio.stop_music()
	audio.play_music("menu_theme", -11.0)
	_show_menu()
