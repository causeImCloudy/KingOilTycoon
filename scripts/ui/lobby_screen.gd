extends Control
## Multiplayer lobby. One player hosts (Steam lobby or LAN), friends join, the host fills the
## remaining seats with AI and starts. Up to 6 players.

var status_l: Label
var slots_box: VBoxContainer
var host_box: HFlowContainer
var connect_box: VBoxContainer
var ip_edit: LineEdit
var lobby_edit: LineEdit
var start_btn: Button
var invite_btn: Button


func _ready() -> void:
	UiKit.backdrop(self)
	UiKit.header(self, "Multiplayer", _leave)
	Net.status.connect(func(t): status_l.text = t)
	Net.lobby_changed.connect(func(_s): _refresh())

	connect_box = UiKit.vbox(5)
	var cp := UiKit.panel(8)
	cp.position = Vector2(16, 32)
	cp.custom_minimum_size = Vector2(240, 0)
	add_child(cp)
	cp.add_child(connect_box)
	connect_box.add_child(UiKit.label("Steam (recommended)", 10))
	connect_box.add_child(UiKit.button("Host Steam Lobby", func(): Net.host_steam()))
	var lr := UiKit.hbox(4)
	lobby_edit = LineEdit.new()
	lobby_edit.placeholder_text = "Lobby ID"
	lobby_edit.custom_minimum_size = Vector2(150, 16)
	lr.add_child(lobby_edit)
	lr.add_child(UiKit.button("Join", func():
		if lobby_edit.text.is_valid_int():
			Net.join_steam_lobby(int(lobby_edit.text)), 8))
	connect_box.add_child(lr)
	connect_box.add_child(UiKit.label("LAN / direct", 10))
	connect_box.add_child(UiKit.button("Host on LAN", func(): Net.host_lan()))
	var ir := UiKit.hbox(4)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(150, 16)
	ir.add_child(ip_edit)
	ir.add_child(UiKit.button("Join", func(): Net.join_lan(ip_edit.text.strip_edges()), 8))
	connect_box.add_child(ir)
	status_l = UiKit.label("Choose how to connect.", 8, Color("7a2a1a"))
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size = Vector2(214, 0)
	connect_box.add_child(status_l)

	var sp := UiKit.panel(8)
	sp.position = Vector2(266, 32)
	sp.custom_minimum_size = Vector2(358, 0)
	add_child(sp)
	var sv := UiKit.vbox(4)
	sp.add_child(sv)
	sv.add_child(UiKit.label("Seats", 10))
	slots_box = UiKit.vbox(2)
	sv.add_child(slots_box)
	host_box = HFlowContainer.new()
	host_box.add_theme_constant_override("h_separation", 6)
	sv.add_child(host_box)
	host_box.add_child(UiKit.label("Map", 8))
	host_box.add_child(UiKit.option(["Procedural", "Classic (2-4)"], 0, func(i): Net.set_lobby_setting("map_type", "classic" if i == 1 else "procedural")))
	host_box.add_child(UiKit.label("Pace", 8))
	host_box.add_child(UiKit.option(["Classic", "Online", "Blitz"], 1, func(i): Net.set_lobby_setting("speed", MatchSpeed.SPEED_IDS[i])))
	var br := UiKit.hbox(6)
	sv.add_child(br)
	invite_btn = UiKit.button("Invite Friends", func(): Net.invite_friends())
	br.add_child(invite_btn)
	start_btn = UiKit.button("Start Match", func(): Net.start_match())
	br.add_child(start_btn)
	_refresh()


func _refresh() -> void:
	for c in slots_box.get_children():
		c.queue_free()
	var connected := Net.active()
	host_box.visible = Net.is_host
	start_btn.visible = Net.is_host
	invite_btn.visible = Net.is_host and Net.transport == "steam"
	if not connected:
		slots_box.add_child(UiKit.label("Not connected.", 8))
		return
	for i in GameConst.MAX_PLAYERS:
		var s: Dictionary = Net.slots[i] if i < Net.slots.size() else {"kind": "open"}
		var row := UiKit.hbox(4)
		var sw := ColorRect.new()
		sw.color = GameConst.PLAYER_COLORS[i]
		sw.custom_minimum_size = Vector2(8, 14)
		row.add_child(sw)
		var txt := ""
		match s.kind:
			"human": txt = "%s%s" % [s.name, "  (host)" if s.get("net_id", 0) == 1 else ""]
			"ai": txt = "%s (AI)" % s.name
			"closed": txt = "Closed"
			_: txt = "Open - waiting for a player"
		var l := UiKit.label(txt, 8)
		l.custom_minimum_size = Vector2(200, 0)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = txt
		row.add_child(l)
		if Net.is_host and i > 0 and s.kind != "human":
			var idx := i
			var kinds := ["open", "ai", "closed"]
			row.add_child(UiKit.option(["Open", "AI", "Closed"], maxi(0, kinds.find(s.kind)), func(k): Net.set_slot_kind(idx, kinds[k])))
		slots_box.add_child(row)
	if Net.transport == "steam" and Net.lobby_id != 0:
		slots_box.add_child(UiKit.label("Lobby id: %d" % Net.lobby_id, 8, Color("5a4632")))


func _leave() -> void:
	Net.leave()
	Session.goto("menu")
