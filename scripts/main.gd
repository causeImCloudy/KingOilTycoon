extends Node
## Boot scene. Normally goes straight to the main menu.
##
## Dev flags (after `--` on the command line):
##   --shots=<dir>   tour every screen and auto-play part of a match, saving screenshots, then quit
##   --autoplay      jump into a hot-seat match where a bot plays the human seat
##   --editortest=<dir>  open the map editor, screenshot some maps, test placing and drawing
##   --shoptest=<dir>    buy items in the General Store with button presses (profile restored)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shots="):
			var d := TestDriver.new()
			d.out_dir = a.trim_prefix("--shots=")
			get_tree().root.add_child.call_deferred(d)
			return
		if a.begins_with("--net-host=") or a.begins_with("--net-join="):
			var d := TestDriver.new()
			d.net_role = "host" if a.begins_with("--net-host=") else "join"
			d.out_dir = a.split("=")[1]
			get_tree().root.add_child.call_deferred(d)
			return
		if a.begins_with("--clicktest="):
			var d := TestDriver.new()
			d.click_test = true
			d.out_dir = a.trim_prefix("--clicktest=")
			get_tree().root.add_child.call_deferred(d)
			return
		if a.begins_with("--editortest="):
			var d := TestDriver.new()
			d.editor_test = true
			d.out_dir = a.trim_prefix("--editortest=")
			get_tree().root.add_child.call_deferred(d)
			return
		if a.begins_with("--shoptest="):
			var d := TestDriver.new()
			d.shop_test = true
			d.out_dir = a.trim_prefix("--shoptest=")
			get_tree().root.add_child.call_deferred(d)
			return
		if a == "--autoplay":
			var d := TestDriver.new()
			d.autoplay_only = true
			get_tree().root.add_child.call_deferred(d)
			return
	Session.goto("menu")
