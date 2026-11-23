extends Control
## Map editor (dev tool). Opened from the main menu in debug builds ("Map Editor").
##
## Edits two things per map:
##   - the board itself (property shapes and drill sites), saved to data/boards/<map>.board.json
##     and used by every match on that map (BoardMap.create looks for it);
##   - the decoration (fields, props, lines), saved to data/boards/<map>.json.
##
## Tools (keys 1-5):
##   Plots:  paint cells into the selected property (click or drag). "+ New property" starts a new
##           one; "Erase (no land)" removes cells. Right-click picks the property under the cursor.
##   Sites:  click a cell to add or remove a drill site (right-click removes). Price = $1,000/site.
##   Fields: paint the selected field anywhere with a square brush (click or drag; sizes 4-32 px),
##           not tied to the properties. Bucket fills the connected patch of one field; Shift+click
##           fills a whole property. Right-click picks the field under the cursor.
##   Props:  click to place the selected prop (F flips it). Click a placed prop to pick it up and
##           move it; Shift+click places on top of another. Right-click deletes the prop under
##           the cursor. Red ghost = covers a drill site, straddles a border, or sits on a line.
##   Lines:  click cell corners to lay a road/rail/creek/fence/tree line (bends are added
##           automatically). Enter or right-click finishes; Esc cancels. Right-click on a line
##           (when not drawing) deletes it.
## Ctrl+Z undoes, Ctrl+S saves. Save refuses an unplayable board (a property with no drill sites,
## or fewer properties than players).

const SCREEN := Vector2(640, 360)
const BOARD_POS := Vector2(6, 26)
const SIDE_X: float = 370.0
const TOOLS: Array[String] = ["Plots", "Sites", "Fields", "Props", "Lines"]
const T_PLOTS := 0
const T_SITES := 1
const T_FIELDS := 2
const T_PROPS := 3
const T_LINES := 4
const NEW_PLOT := "new"
const ERASE := "erase"

var maps: Array = [] # [{id, label, board, theme, seed, map_type, players}]
var map_index: int = 0
var board: BoardMap
var layout: Dictionary = {}
var tool: int = T_PROPS
var palette_ids: Array = []
var selected: String = ""
var flip: bool = false
var held: Dictionary = {} # prop picked up for moving
var line_pts: Array = [] # points of the line being drawn
var mouse_px := Vector2(-1, -1)
var undo_stack: Array = []
var dirty: bool = false
## The board differs from what's on disk; board_custom = it should be saved as an edited board
## (false after "Reset board": saving then deletes the edited board file).
var board_dirty: bool = false
var board_custom: bool = false
var _painting: bool = false
## Fields tool: brush width in field-grid cells (BoardDecor.FIELD_CELL px each), or the bucket.
var brush: int = 2
var bucket: bool = false
var brush_row: HBoxContainer
var brush_buttons: Dictionary = {}
var _discard_armed: bool = false
var _auto_rng := RandomNumberGenerator.new()
var _swatches: Dictionary = {}

var board_view: BoardView
var map_pick: OptionButton
var theme_pick: OptionButton
var tool_buttons: Array[Button] = []
var palette: ItemList
var status: Label
var title_label: Label


func _ready() -> void:
	_auto_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color("3a2a1f")
	bg.size = SCREEN
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_collect_maps()
	_build_ui()
	_load_map(0)


func _collect_maps() -> void:
	for i in Session.campaign.maps.size():
		var m: Dictionary = Session.campaign.maps[i]
		maps.append({"id": "level_%02d" % (i + 1), "label": "Level %d: %s" % [i + 1, m.title],
			"theme": str(m.get("board_theme", "farm")), "seed": int(m.seed), "map_type": str(m.map_type),
			"players": 1 + m.rivals.size()})
	maps.append({"id": "classic", "label": "Legacy board", "theme": "farm", "seed": 1974,
		"map_type": "classic", "players": 4})
	maps.append({"id": "classic_1974", "label": "Classic board (1974)", "theme": "farm", "seed": 1974,
		"map_type": "classic_1974", "players": 4})


## The board a map would get with no edits (what "Reset board" goes back to).
func _generated_board(m: Dictionary) -> BoardMap:
	if m.players <= 4 and m.map_type == "classic_1974":
		return BoardMap.create_survey()
	if m.players <= 4 and m.map_type == "classic":
		return BoardMap.create_classic()
	return BoardMap.create_procedural(m.seed, m.players)


func _build_ui() -> void:
	var top := ColorRect.new()
	top.color = Color("1d1611")
	top.size = Vector2(SCREEN.x, 22)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var back := UiKit.button("Back", func(): Session.goto("menu"), 8)
	back.position = Vector2(4, 1)
	back.size = Vector2(44, 20)
	add_child(back)
	title_label = UiKit.label("Map Editor", 8, Color("efe3c6"))
	title_label.position = Vector2(66, 3)
	add_child(title_label)
	map_pick = UiKit.option(maps.map(func(m): return m.label), 0, _on_map_picked)
	map_pick.position = Vector2(370, 1)
	map_pick.size = Vector2(200, 20)
	map_pick.clip_text = true
	map_pick.fit_to_longest_item = false
	add_child(map_pick)
	var save := UiKit.button("Save", _save, 8)
	save.position = Vector2(576, 1)
	save.size = Vector2(60, 20)
	add_child(save)

	var frame := ColorRect.new()
	frame.color = Color("1d1611")
	frame.position = BOARD_POS - Vector2(2, 2)
	frame.size = BoardDecor.BOARD_PX + Vector2(4, 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	board_view = BoardView.new()
	board_view.position = BOARD_POS
	board_view.interactive = false
	board_view.overlay_draw = _draw_overlay
	add_child(board_view)

	var side := UiKit.panel(4)
	side.position = Vector2(SIDE_X, 26)
	side.custom_minimum_size = Vector2(266, 330)
	side.size = side.custom_minimum_size
	side.clip_contents = true
	add_child(side)
	var v := UiKit.vbox(3)
	side.add_child(v)
	# Two rows: board tools (shape the properties) and decoration tools.
	var board_tools := UiKit.hbox(3)
	v.add_child(board_tools)
	board_tools.add_child(UiKit.label("Board", 8))
	var decor_tools := UiKit.hbox(3)
	v.add_child(decor_tools)
	decor_tools.add_child(UiKit.label("Decor", 8))
	for i in TOOLS.size():
		var tools_row: HBoxContainer = board_tools if i <= T_SITES else decor_tools
		var b := UiKit.button(TOOLS[i], func(): _set_tool(i), 8)
		b.tooltip_text = "Key %d" % (i + 1)
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 18)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools_row.add_child(b)
		tool_buttons.append(b)
	palette = ItemList.new()
	palette.custom_minimum_size = Vector2(240, 132)
	palette.fixed_icon_size = Vector2i(16, 16)
	palette.item_selected.connect(func(i): selected = palette_ids[i])
	v.add_child(palette)
	# Fields brush: sizes in pixels, or the bucket (shown only with the Fields tool).
	brush_row = UiKit.hbox(3)
	v.add_child(brush_row)
	var brush_group := ButtonGroup.new()
	for spec in [[1, "S"], [2, "M"], [4, "L"], [8, "XL"], [0, "Bucket"]]:
		var size_cells: int = spec[0]
		var b := UiKit.button(spec[1], func(): _set_brush(size_cells), 8)
		b.toggle_mode = true
		b.button_group = brush_group
		b.custom_minimum_size = Vector2(0, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 2.0 if size_cells == 0 else 1.0
		b.tooltip_text = "Fill the connected patch of one field" if size_cells == 0 else "%d px square brush" % (size_cells * BoardDecor.FIELD_CELL)
		brush_row.add_child(b)
		brush_buttons[size_cells] = b
	brush_buttons[brush].button_pressed = true
	var board_row := UiKit.hbox(3)
	v.add_child(board_row)
	for spec in [["Check board", _check_board], ["Reset board", _reset_board]]:
		var b := UiKit.button(spec[0], spec[1], 8)
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board_row.add_child(b)
	var row := UiKit.hbox(3)
	v.add_child(row)
	row.add_child(UiKit.label("Theme", 8))
	var theme_ids: Array = BoardDecor.kit().themes.keys()
	theme_pick = UiKit.option(theme_ids.map(func(t): return BoardDecor.kit().themes[t].name), 0, func(_i): pass)
	theme_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_pick.clip_text = true
	theme_pick.fit_to_longest_item = false
	theme_pick.custom_minimum_size = Vector2(0, 18)
	row.add_child(theme_pick)
	var row2 := UiKit.hbox(3)
	v.add_child(row2)
	for spec in [["Auto-fill", _auto_fill], ["Clear", _clear_props], ["Undo", _undo]]:
		var b := UiKit.button(spec[0], spec[1], 8)
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(b)
	var props_toggle := CheckBox.new()
	props_toggle.text = "Show props"
	props_toggle.button_pressed = true
	props_toggle.toggled.connect(func(on: bool):
		board_view.show_props = on
		board_view.queue_redraw())
	v.add_child(props_toggle)

	var stat_panel := UiKit.panel(4)
	stat_panel.position = Vector2(4, 274)
	stat_panel.custom_minimum_size = Vector2(SIDE_X - 8, 82)
	stat_panel.size = stat_panel.custom_minimum_size
	stat_panel.clip_contents = true
	add_child(stat_panel)
	status = UiKit.label("", 8, Color("5a3a22"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(SIDE_X - 32, 0)
	stat_panel.add_child(status)


# --- Maps ----------------------------------------------------------------------------------------

func _on_map_picked(i: int) -> void:
	if i == map_index:
		return
	if dirty and not _discard_armed:
		_discard_armed = true
		map_pick.select(map_index)
		status.text = "Unsaved changes on this map. Save first, or pick the other map again to discard them."
		return
	_load_map(i)


func _load_map(i: int) -> void:
	map_index = i
	map_pick.select(i)
	_discard_armed = false
	var m: Dictionary = maps[i]
	board_custom = BoardMap.has_custom(m.id)
	board = BoardMap.load_custom(m.id) if board_custom else _generated_board(m)
	board_dirty = false
	layout = BoardDecor.load_layout(m.id)
	var fresh := layout.is_empty()
	if fresh:
		layout = BoardDecor.auto_layout(board, m.theme, m.seed)
	_apply_board()
	board_view.decor = layout
	var theme_ids: Array = BoardDecor.kit().themes.keys()
	theme_pick.select(maxi(0, theme_ids.find(layout.get("theme", m.theme))))
	undo_stack.clear()
	line_pts.clear()
	held = {}
	dirty = fresh
	_refresh_title()
	_set_tool(tool)
	status.text = ("No saved layout yet: this is an auto-fill. " if fresh else "Loaded %s%s. " % [
		BoardDecor.layout_path(m.id), " and an edited board" if board_custom else ""]) + _help()


## Points the board view at the current board (after loading or editing it).
func _apply_board() -> void:
	board_view.setup(board, [], BoardDecor.BOARD_PX)
	board_view.plot_owner = []
	board_view.site_state = []
	for p in board.plots:
		board_view.plot_owner.append(-1)
	for s in board.sites:
		board_view.site_state.append(GameConst.SITE_OPEN)
	board_view.queue_redraw()


func _save() -> void:
	var m: Dictionary = maps[map_index]
	var notes: Array[String] = []
	if board_dirty:
		if board_custom:
			_compact_plots()
			var problem := board.check_playable(m.players)
			if problem != "":
				status.text = "Not saved: %s. Fix the board first (Check lists problems)." % problem
				return
			if not BoardMap.save_custom(m.id, board):
				status.text = "Couldn't write %s." % BoardMap.custom_path(m.id)
				return
			notes.append(BoardMap.custom_path(m.id))
			var split := board.split_plots()
			if not split.is_empty():
				notes.append("note: properties %s are in separate pieces" % ", ".join(split.map(func(p): return str(p + 1))))
		elif BoardMap.has_custom(m.id):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(BoardMap.custom_path(m.id)))
			notes.append("removed the edited board (back to generated)")
		board_dirty = false
	BoardDecor.compact_field_grid(board, layout)
	if BoardDecor.save_layout(m.id, layout):
		notes.push_front(BoardDecor.layout_path(m.id))
		dirty = false
		_discard_armed = false
		status.text = "Saved %s." % ", ".join(notes)
	else:
		status.text = "Couldn't write %s." % BoardDecor.layout_path(m.id)
	_refresh_title()


func _refresh_title() -> void:
	title_label.text = "Map Editor  %s%s" % [maps[map_index].id, "  (unsaved)" if dirty else ""]


func _changed() -> void:
	dirty = true
	_discard_armed = false
	_refresh_title()
	board_view.queue_redraw()


func _snapshot() -> void:
	undo_stack.append({"layout": layout.duplicate(true), "board": board.to_custom(),
		"board_dirty": board_dirty, "board_custom": board_custom})
	if undo_stack.size() > 60:
		undo_stack.pop_front()


func _undo() -> void:
	if undo_stack.is_empty():
		status.text = "Nothing to undo."
		return
	var snap: Dictionary = undo_stack.pop_back()
	layout = snap.layout
	board_dirty = snap.board_dirty
	board_custom = snap.board_custom
	var d: Dictionary = snap.board
	board = _board_from(d.cells, _site_cells(d.sites), d.names, d.labels)
	_apply_board()
	board_view.decor = layout
	_refresh_palette()
	_changed()


func _auto_fill() -> void:
	_snapshot()
	var theme_ids: Array = BoardDecor.kit().themes.keys()
	var theme: String = theme_ids[theme_pick.selected]
	layout = BoardDecor.auto_layout(board, theme, _auto_rng.randi())
	board_view.decor = layout
	_changed()
	status.text = "Auto-filled with the %s theme. Press again for another arrangement; Undo to go back." % BoardDecor.kit().themes[theme].name


func _clear_props() -> void:
	_snapshot()
	layout.props = []
	_changed()


# --- Board editing -------------------------------------------------------------------------------

func _site_cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in list:
		out.append(Vector2i(int(s[0]), int(s[1])))
	return out


func _board_from(cell_list: Array, site_cells: Array[Vector2i], names: Array, labels: Array) -> BoardMap:
	var cells := PackedInt32Array()
	for c in cell_list:
		cells.append(int(c))
	return BoardMap.from_cells(board.map_type, board.map_seed, board.width, board.height, cells, site_cells, names, labels)


## Rebuilds the board after an edit to its cells or sites.
func _rebuild(cells: PackedInt32Array, site_cells: Array[Vector2i]) -> void:
	var d := board.to_custom()
	board = _board_from(Array(cells), site_cells, d.names, d.labels)
	board_dirty = true
	board_custom = true
	_apply_board()
	_changed()


func _current_sites() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in board.sites:
		out.append(Vector2i(int(s.x), int(s.y)))
	return out


func _cell_at(local: Vector2) -> Vector2i:
	var cell := BoardDecor.cell_size(board)
	return Vector2i(clampi(floori(local.x / cell), 0, board.width - 1), clampi(floori(local.y / cell), 0, board.height - 1))


func _paint_cell(c: Vector2i) -> void:
	var target := -1
	if selected == NEW_PLOT:
		target = board.plots.size()
		# Name the new property after the first unused name.
		var used := board.plots.map(func(p): return p.name)
		var plot_name := "Property %d" % (target + 1)
		for n in GameConst.PLOT_NAMES:
			if not (n in used):
				plot_name = n
				break
		var cells := board.cells.duplicate()
		cells[c.y * board.width + c.x] = target
		var d := board.to_custom()
		d.names.append(plot_name)
		d.labels.append([c.x, c.y])
		board = _board_from(Array(cells), _current_sites(), d.names, d.labels)
		board_dirty = true
		board_custom = true
		_apply_board()
		_changed()
		_refresh_palette()
		selected = str(target)
		palette.select(palette_ids.find(selected))
		status.text = "New property %d (%s). Keep painting its cells, then add drill sites with the Sites tool." % [target + 1, plot_name]
		return
	elif selected != ERASE:
		target = int(selected)
	if board.cell_plot(c.x, c.y) == target:
		return
	var cells2 := board.cells.duplicate()
	cells2[c.y * board.width + c.x] = target
	_rebuild(cells2, _current_sites())
	_refresh_palette()


func _toggle_site(c: Vector2i, remove_only: bool) -> void:
	var sites := _current_sites()
	var i := sites.find(c)
	if i >= 0:
		_snapshot()
		sites.remove_at(i)
	elif remove_only:
		return
	elif board.cell_plot(c.x, c.y) < 0:
		status.text = "No land here: paint a property first."
		return
	else:
		_snapshot()
		sites.append(c)
	_rebuild(board.cells, sites)
	_refresh_palette()
	var p := board.cell_plot(c.x, c.y)
	if p >= 0:
		status.text = "Property %d (%s): %d drill sites, price %s." % [p + 1, board.plots[p].name,
			board.plots[p].sites.size(), UiKit.money(board.plots[p].price)]


## Drops properties with no land and renumbers the rest.
func _compact_plots() -> void:
	var counts := {}
	for c in board.cells:
		counts[c] = counts.get(c, 0) + 1
	var remap := {}
	var n := 0
	for p in board.plots:
		if counts.has(p.id):
			remap[p.id] = n
			n += 1
	if n == board.plots.size():
		return
	var d := board.to_custom()
	var cells := PackedInt32Array()
	for c in board.cells:
		cells.append(remap.get(c, -1))
	var names: Array = []
	var labels: Array = []
	for p in board.plots:
		if remap.has(p.id):
			names.append(d.names[p.id])
			labels.append(d.labels[p.id])
	board = _board_from(Array(cells), _current_sites(), names, labels)
	_apply_board()
	_refresh_palette()


func _check_board() -> void:
	var m: Dictionary = maps[map_index]
	var notes: Array[String] = []
	var problem := board.check_playable(m.players)
	if problem != "":
		notes.append("Unplayable: %s." % problem)
	var split := board.split_plots()
	if not split.is_empty():
		notes.append("In separate pieces: %s." % ", ".join(split.map(func(p): return str(p + 1))))
	var covered := 0
	for p in layout.get("props", []):
		if BoardDecor.sites_in(board, BoardDecor.foot_rect(p.id, p.x, p.y)) > BoardDecor.site_allowance(p.id):
			covered += 1
	if covered > 0:
		notes.append("%d prop%s cover drill sites (Props tool shows them in red when moved)." % [covered, "" if covered == 1 else "s"])
	var total := 0
	for p in board.plots:
		total += p.sites.size()
	notes.append("%d properties, %d drill sites, for up to %d players." % [board.plots.size(), total, m.players])
	status.text = " ".join(notes) if problem != "" or not split.is_empty() or covered > 0 else "Board is fine. " + notes[-1]


func _reset_board() -> void:
	_snapshot()
	board = _generated_board(maps[map_index])
	board_dirty = true
	board_custom = false
	_apply_board()
	_refresh_palette()
	_changed()
	status.text = "Board reset to the generated one. Save to remove the edited board file."


# --- Tools ---------------------------------------------------------------------------------------

func _set_tool(t: int) -> void:
	tool = t
	line_pts.clear()
	held = {}
	for i in tool_buttons.size():
		tool_buttons[i].button_pressed = i == t
	brush_row.visible = t == T_FIELDS
	_refresh_palette()
	status.text = _help()
	board_view.queue_redraw()


func _refresh_palette() -> void:
	var keep_sel := selected
	palette.clear()
	palette_ids.clear()
	var k := BoardDecor.kit()
	match tool:
		T_PLOTS:
			for p in board.plots:
				palette.add_item("%d. %s (%d sites)" % [p.id + 1, p.name, p.sites.size()], _swatch(_plot_color(p.id)))
				palette_ids.append(str(p.id))
			palette.add_item("+ New property", _swatch(Color("f2c14e")))
			palette_ids.append(NEW_PLOT)
			palette.add_item("Erase (no land)", _swatch(Color("1d1611")))
			palette_ids.append(ERASE)
		T_SITES:
			for p in board.plots:
				palette.add_item("%d. %s: %d sites, %s" % [p.id + 1, p.name, p.sites.size(), UiKit.money(p.price)], _swatch(_plot_color(p.id)))
				palette_ids.append(str(p.id))
		T_FIELDS:
			for id in k.fields:
				palette.add_item(k.fields[id].name, BoardDecor.field_texture(id))
				palette_ids.append(id)
		T_PROPS:
			var ids: Array = k.props.keys()
			ids.sort_custom(func(a, b): return [k.props[a].cat, k.props[a].name] < [k.props[b].cat, k.props[b].name])
			for id in ids:
				palette.add_item("%s (%dx%d)" % [k.props[id].name, k.props[id].size[0], k.props[id].size[1]], BoardDecor.prop_texture(id))
				palette_ids.append(id)
		T_LINES:
			for id in k.lines:
				palette.add_item(k.lines[id].name, BoardDecor.line_texture(id, "straight"))
				palette_ids.append(id)
	var keep := palette_ids.find(keep_sel)
	if keep < 0:
		keep = 0
	if palette_ids.is_empty():
		selected = ""
		return
	palette.select(keep)
	selected = palette_ids[keep]


func _plot_color(p: int) -> Color:
	return Color.from_hsv(fmod(p * 0.618034, 1.0), 0.55, 0.95)


func _swatch(c: Color) -> Texture2D:
	var key := c.to_html()
	if not _swatches.has(key):
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color("1d1611"))
		img.fill_rect(Rect2i(1, 1, 14, 14), c)
		_swatches[key] = ImageTexture.create_from_image(img)
	return _swatches[key]


func _help() -> String:
	match tool:
		T_PLOTS: return "PLOTS: click or drag to paint cells into the selected property. Right-click picks a property. Save asks for a playable board."
		T_SITES: return "SITES: click a cell to add or remove a drill site (right-click removes). Each site adds $1,000 to the price."
		T_FIELDS: return "FIELDS: click or drag to paint anywhere (brush 4-32 px), Bucket fills a patch, Shift+click fills a property. Right-click picks a field."
		T_PROPS: return "PROPS: click to place, F flips, click a prop to move it (Shift+click stacks). Right-click deletes."
		_: return "LINES: click cell corners to draw; Enter or right-click finishes, Esc cancels. Right-click a line to delete it."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)
		return
	if not event is InputEventMouse:
		return
	# The event's own position in board space (not the OS cursor), like BoardView does.
	var local: Vector2 = (board_view.make_input_local(event) as InputEventMouse).position
	var inside := Rect2(Vector2.ZERO, BoardDecor.BOARD_PX).has_point(local)
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = false
	if event is InputEventMouseMotion:
		mouse_px = local if inside else Vector2(-1, -1)
		if inside:
			if _painting and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				if tool == T_PLOTS:
					_paint_cell(_cell_at(local))
				elif tool == T_FIELDS:
					_brush_at(local)
			_hover_status(local)
		board_view.queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed) or not inside:
		return
	get_viewport().set_input_as_handled()
	var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	if event.button_index != MOUSE_BUTTON_LEFT and not right:
		return
	match tool:
		T_PLOTS: _plots_click(local, right)
		T_SITES: _toggle_site(_cell_at(local), right)
		T_FIELDS: _field_click(local, right, event.shift_pressed)
		T_PROPS: _prop_click(local, right, event.shift_pressed)
		T_LINES: _line_click(local, right)


func _plots_click(local: Vector2, right: bool) -> void:
	var c := _cell_at(local)
	if right:
		var p := board.cell_plot(c.x, c.y)
		var id := str(p) if p >= 0 else ERASE
		selected = id
		palette.select(palette_ids.find(id))
		status.text = ("Painting property %d (%s)." % [p + 1, board.plots[p].name]) if p >= 0 else "Erasing land."
		return
	_snapshot() # one undo step per stroke
	_painting = true
	_paint_cell(c)


func _on_key(event: InputEventKey) -> void:
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_undo()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		_save()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
		_set_tool(event.keycode - KEY_1)
	elif event.keycode == KEY_F:
		if not held.is_empty():
			held.flip = not held.get("flip", false)
		flip = not flip
		board_view.queue_redraw()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_finish_line()
	elif event.keycode == KEY_ESCAPE:
		if not held.is_empty():
			layout.props.append(held) # drop it back where it was
			held = {}
		line_pts.clear()
		board_view.queue_redraw()


func _hover_status(local: Vector2) -> void:
	if tool in [T_PLOTS, T_SITES]:
		var c := _cell_at(local)
		var p := board.cell_plot(c.x, c.y)
		if not _painting:
			status.text = ("Cell %d,%d: property %d (%s), %d sites." % [c.x, c.y, p + 1, board.plots[p].name, board.plots[p].sites.size()]) \
				if p >= 0 else "Cell %d,%d: no land." % [c.x, c.y]
		return
	if tool != T_PROPS or selected == "":
		return
	var id: String = held.id if not held.is_empty() else selected
	var why := _spot_problem(id, local.round())
	if why != "":
		status.text = "%s here: %s." % [BoardDecor.kit().props[id].name, why]


## Why a prop shouldn't go here ("" = fine). Placing is still allowed; this is a warning.
func _spot_problem(id: String, pos: Vector2) -> String:
	var r := BoardDecor.foot_rect(id, pos.x, pos.y)
	if BoardDecor.plot_of_rect(board, r) < 0:
		return "its base crosses a property border or the board edge"
	if not Rect2(Vector2.ZERO, BoardDecor.BOARD_PX).encloses(BoardDecor.prop_rect({"id": id, "x": pos.x, "y": pos.y})):
		return "it sticks out past the board edge"
	var n := BoardDecor.sites_in(board, r)
	if n > BoardDecor.site_allowance(id):
		return "covers %d drill site%s" % [n, "" if n == 1 else "s"]
	for lr in BoardDecor.line_rects(board, layout):
		if lr.intersects(r):
			return "sits on a road, rail, creek or fence"
	return ""


func _set_brush(size_cells: int) -> void:
	bucket = size_cells == 0
	if not bucket:
		brush = size_cells
	status.text = "Bucket: fills the connected patch of one field." if bucket else \
		"Brush: %d px square. Drag to paint." % (brush * BoardDecor.FIELD_CELL)
	board_view.queue_redraw()


func _grid_at(local: Vector2) -> Vector2i:
	return Vector2i(floori(local.x / BoardDecor.FIELD_CELL), floori(local.y / BoardDecor.FIELD_CELL))


## Grid cells under the square brush centered on `local`.
func _brush_cells(local: Vector2) -> Array:
	var c := _grid_at(local)
	var start := c - Vector2i(brush / 2, brush / 2)
	var out: Array = []
	for dy in brush:
		for dx in brush:
			out.append(start + Vector2i(dx, dy))
	return out


func _brush_at(local: Vector2) -> void:
	if selected == "":
		return
	if BoardDecor.paint_field(board, layout, _brush_cells(local), selected) > 0:
		_changed()


func _field_click(local: Vector2, right: bool, whole_plot: bool) -> void:
	var g := _grid_at(local)
	var current := BoardDecor.field_at(board, layout, g.x, g.y)
	if current == "":
		return
	if right:
		var i := palette_ids.find(current)
		if i >= 0:
			palette.select(i)
			selected = current
		status.text = "Painting %s." % BoardDecor.kit().fields[current].name
		return
	if selected == "":
		return
	_snapshot() # one undo step per click or stroke
	if whole_plot:
		var p := BoardDecor.plot_at_px(board, local)
		if p >= 0 and BoardDecor.paint_field(board, layout, BoardDecor.grid_cells_of_plot(board, p), selected) > 0:
			_changed()
	elif bucket:
		if current != selected and BoardDecor.paint_field(board, layout, BoardDecor.grid_region(board, layout, g), selected) > 0:
			_changed()
	else:
		_painting = true
		_brush_at(local)


func _prop_under(local: Vector2) -> int:
	var best := -1
	for i in layout.props.size():
		if BoardDecor.prop_rect(layout.props[i]).has_point(local):
			if best < 0 or float(layout.props[i].y) >= float(layout.props[best].y):
				best = i
	return best


func _prop_click(local: Vector2, right: bool, stack: bool) -> void:
	var pos := local.round()
	if right:
		if not held.is_empty():
			held = {} # deleting the prop being moved
			_changed()
			return
		var i := _prop_under(local)
		if i >= 0:
			_snapshot()
			layout.props.remove_at(i)
			_changed()
		return
	if not held.is_empty():
		held.x = pos.x
		held.y = pos.y
		layout.props.append(held)
		held = {}
		_changed()
		return
	var under := _prop_under(local)
	if under >= 0 and not stack:
		_snapshot()
		held = layout.props[under]
		layout.props.remove_at(under)
		board_view.queue_redraw()
		status.text = "Moving %s: click to drop it, Esc puts it back, right-click deletes it." % BoardDecor.kit().props[held.id].name
		return
	_snapshot()
	layout.props.append({"id": selected, "x": pos.x, "y": pos.y, "flip": flip})
	var why := _spot_problem(selected, pos)
	status.text = ("Placed, but %s." % why) if why != "" else "Placed %s." % BoardDecor.kit().props[selected].name
	_changed()


func _corner_at(local: Vector2) -> Vector2i:
	var cell := BoardDecor.cell_size(board)
	return Vector2i(clampi(roundi(local.x / cell), 0, board.width), clampi(roundi(local.y / cell), 0, board.height))


func _line_click(local: Vector2, right: bool) -> void:
	if right:
		if line_pts.size() >= 2:
			_finish_line()
			return
		if not line_pts.is_empty():
			line_pts.clear()
			board_view.queue_redraw()
			return
		var hit := _line_under(local)
		if hit >= 0:
			_snapshot()
			layout.lines.remove_at(hit)
			_changed()
		return
	var c := _corner_at(local)
	if line_pts.is_empty():
		line_pts.append([c.x, c.y])
	else:
		var last := Vector2i(line_pts[-1][0], line_pts[-1][1])
		if c == last:
			return
		if c.x != last.x and c.y != last.y:
			line_pts.append([c.x, last.y]) # bend: across, then down
		line_pts.append([c.x, c.y])
	board_view.queue_redraw()


func _finish_line() -> void:
	if line_pts.size() >= 2:
		_snapshot()
		layout.lines.append({"kind": selected, "points": line_pts.duplicate(true)})
		_changed()
		status.text = "%s added." % BoardDecor.kit().lines[selected].name
	line_pts.clear()
	board_view.queue_redraw()


func _line_under(local: Vector2) -> int:
	var cell := BoardDecor.cell_size(board)
	for i in range(layout.lines.size() - 1, -1, -1):
		var pts: Array = layout.lines[i].points
		for j in range(pts.size() - 1):
			var a := Vector2(pts[j][0], pts[j][1]) * cell
			var b := Vector2(pts[j + 1][0], pts[j + 1][1]) * cell
			if Rect2(a.min(b), (b - a).abs()).grow(5).has_point(local):
				return i
	return -1


# --- Overlay (drawn by the BoardView on top of the decoration) ----------------------------------

func _draw_overlay(ci: CanvasItem) -> void:
	var cell := BoardDecor.cell_size(board)
	if tool in [T_PLOTS, T_SITES]:
		_draw_plot_map(ci, cell)
	if mouse_px.x < 0 and line_pts.is_empty():
		return
	match tool:
		T_PLOTS, T_SITES:
			var c := _cell_at(mouse_px)
			ci.draw_rect(Rect2(Vector2(c) * cell, Vector2(cell, cell)), Color.WHITE, false, 1.0)
		T_FIELDS:
			if Input.is_key_pressed(KEY_SHIFT):
				var p := BoardDecor.plot_at_px(board, mouse_px)
				if p >= 0:
					_outline_plot(ci, p, cell)
			elif bucket:
				var g := _grid_at(mouse_px)
				ci.draw_rect(Rect2(Vector2(g) * BoardDecor.FIELD_CELL, Vector2.ONE * BoardDecor.FIELD_CELL), Color.WHITE, false, 1.0)
			else:
				var start: Vector2i = _brush_cells(mouse_px)[0]
				ci.draw_rect(Rect2(Vector2(start) * BoardDecor.FIELD_CELL, Vector2.ONE * brush * BoardDecor.FIELD_CELL), Color.WHITE, false, 1.0)
		T_PROPS:
			var id: String = held.id if not held.is_empty() else selected
			if id == "" or mouse_px.x < 0:
				return
			var pos := mouse_px.round()
			var ghost := {"id": id, "x": pos.x, "y": pos.y, "flip": held.get("flip", flip) if not held.is_empty() else flip}
			var bad := _spot_problem(id, pos) != ""
			BoardDecor.draw_props(ci, {"props": [ghost]}, func(_p): return Color(1, 0.45, 0.4, 0.8) if bad else Color(1, 1, 1, 0.8))
			ci.draw_rect(BoardDecor.foot_rect(id, pos.x, pos.y), Color("ff5a3a") if bad else Color("b8f08a"), false, 1.0)
		T_LINES:
			var pts: Array = line_pts.duplicate()
			if mouse_px.x >= 0:
				var c := _corner_at(mouse_px)
				ci.draw_circle(Vector2(c) * cell, 2.5, Color("f2c14e"))
				if not pts.is_empty():
					var last := Vector2i(pts[-1][0], pts[-1][1])
					if c.x != last.x and c.y != last.y:
						pts.append([c.x, last.y])
					pts.append([c.x, c.y])
			for j in range(pts.size() - 1):
				ci.draw_line(Vector2(pts[j][0], pts[j][1]) * cell, Vector2(pts[j + 1][0], pts[j + 1][1]) * cell, Color("f2c14e"), 2.0)


## Plots and Sites tools: every property in its own color with its number, sites ringed.
func _draw_plot_map(ci: CanvasItem, cell: int) -> void:
	for y in board.height:
		for x in board.width:
			var p := board.cell_plot(x, y)
			if p < 0:
				ci.draw_rect(Rect2(x * cell, y * cell, cell, cell), Color(0, 0, 0, 0.45))
				continue
			var c := _plot_color(p)
			c.a = 0.45 if str(p) == selected else 0.3
			ci.draw_rect(Rect2(x * cell, y * cell, cell, cell), c)
	for s in board.sites:
		var pos := Vector2((s.x + 0.5) * cell, (s.y + 0.5) * cell)
		ci.draw_arc(pos, maxf(2.5, cell * 0.38), 0, TAU, 12, Color.WHITE, 1.0)
	var font := ThemeDB.fallback_font
	for p in board.plots:
		var at := Vector2(p.center_x * cell, p.center_y * cell)
		var txt := str(p.id + 1)
		ci.draw_string_outline(font, at + Vector2(-8, 4), txt, HORIZONTAL_ALIGNMENT_CENTER, 16, 10, 3, Color("1d1611"))
		ci.draw_string(font, at + Vector2(-8, 4), txt, HORIZONTAL_ALIGNMENT_CENTER, 16, 10, Color.WHITE)


func _outline_plot(ci: CanvasItem, p: int, cell: int) -> void:
	for y in board.height:
		for x in board.width:
			if board.cell_plot(x, y) != p:
				continue
			var r := Rect2(x * cell, y * cell, cell, cell)
			ci.draw_rect(r, Color(1, 1, 1, 0.15))
			if board.cell_plot(x - 1, y) != p:
				ci.draw_line(r.position, Vector2(r.position.x, r.end.y), Color("f2c14e"), 1.0)
			if board.cell_plot(x + 1, y) != p:
				ci.draw_line(Vector2(r.end.x, r.position.y), r.end, Color("f2c14e"), 1.0)
			if board.cell_plot(x, y - 1) != p:
				ci.draw_line(r.position, Vector2(r.end.x, r.position.y), Color("f2c14e"), 1.0)
			if board.cell_plot(x, y + 1) != p:
				ci.draw_line(Vector2(r.position.x, r.end.y), r.end, Color("f2c14e"), 1.0)
