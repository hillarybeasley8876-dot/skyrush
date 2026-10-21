extends RefCounted
## Factory for the menu screens.
##
## The screens are built in code (see screens/*.gd); this is the one place that knows which
## script belongs to which screen name.

const LoadingScreen := preload("res://ui/menu/screens/loading_screen.gd")
const TitleScreen := preload("res://ui/menu/screens/title_screen.gd")
const MainMenu := preload("res://ui/menu/screens/main_menu.gd")
const RaceSetup := preload("res://ui/menu/screens/race_setup.gd")
const PursuitSetup := preload("res://ui/menu/screens/pursuit_setup.gd")
const SettingsScreen := preload("res://ui/menu/screens/settings_screen.gd")
const ControlsPage := preload("res://ui/menu/screens/controls_page.gd")
const PauseMenu := preload("res://ui/menu/screens/pause_menu.gd")
const ResultsScreen := preload("res://ui/menu/screens/results_screen.gd")
const MenuScreen := preload("res://ui/menu/screens/menu_screen.gd")


## Builds the screen for a name, or null when the name is unknown.
static func make(name: StringName) -> Control:
	var screen: Control = null
	match name:
		&"loading":
			screen = LoadingScreen.new()
		&"title":
			screen = TitleScreen.new()
		&"main":
			screen = MainMenu.new()
		&"race_setup":
			screen = RaceSetup.new()
		&"pursuit_setup":
			screen = PursuitSetup.new()
		&"settings":
			screen = SettingsScreen.new()
		&"controls":
			screen = ControlsPage.new()
		&"pause":
			screen = PauseMenu.new()
		&"results":
			screen = ResultsScreen.new()
	if screen == null:
		return null
	var base := screen as MenuScreen
	if base != null:
		base.kind = name
	screen.name = "Screen" + String(name).to_pascal_case()
	return screen
