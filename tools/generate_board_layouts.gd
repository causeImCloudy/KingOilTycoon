extends SceneTree
## Auto-fills a decoration layout (data/boards/<map>.json) for every campaign level and the Classic
## boards, from each level's board_theme. Existing layouts are kept (they may be hand-edited in the
## map editor), only upgraded: per-property fields become the free-paint field grid. Pass
## -- --force to rebuild them all.
##   godot --headless --path . --script res://tools/generate_board_layouts.gd [-- --force]


func _init() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	var f := FileAccess.open("res://data/campaign.json", FileAccess.READ)
	var campaign: Dictionary = JSON.parse_string(f.get_as_text())
	var made := 0
	for i in campaign.maps.size():
		var m: Dictionary = campaign.maps[i]
		var board := BoardMap.create(m.map_type, int(m.seed), 1 + m.rivals.size(), "level_%02d" % (i + 1))
		made += _make("level_%02d" % (i + 1), board, str(m.get("board_theme", "farm")), int(m.seed), force)
	made += _make("classic", BoardMap.create("classic", 1, 4), "farm", 1974, force)
	made += _make("classic_1974", BoardMap.create("classic_1974", 1, 4), "farm", 1974, false)
	print("Board layouts written: %d (existing kept unless --force)" % made)
	quit()


func _make(map_id: String, board: BoardMap, theme: String, seed_value: int, force: bool) -> int:
	if not force and FileAccess.file_exists(BoardDecor.layout_path(map_id)):
		var saved := BoardDecor.load_layout(map_id)
		if saved.has("field_grid"):
			return 0
		BoardDecor.field_grid(board, saved)
		BoardDecor.compact_field_grid(board, saved)
		BoardDecor.save_layout(map_id, saved)
		print("  %s: upgraded to the field grid" % map_id)
		return 1
	var layout := BoardDecor.auto_layout(board, theme, seed_value)
	BoardDecor.compact_field_grid(board, layout)
	BoardDecor.save_layout(map_id, layout)
	print("  %s (%s): %d props, %d lines" % [map_id, theme, layout.props.size(), layout.lines.size()])
	return 1
