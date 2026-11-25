extends Node
## Host-authoritative networking over Steam (GodotSteam's SteamMultiplayerPeer) or plain ENet
## for LAN/testing. The host runs the rules; clients send actions and receive events plus a
## public state snapshot (no hidden oil, no deck order).

signal lobby_changed(slots: Array)
signal status(text: String)
signal match_started(public_state: Dictionary)
signal update_received(events: Array, public_state: Dictionary)
signal action_received(peer_id: int, action: Dictionary)
signal peer_left(peer_id: int)
signal connection_lost
signal error_received(text: String)

const ENET_PORT: int = 24565
const STEAM_APP_ID: int = 480 # Spacewar test ID until we have a real App ID.

var transport: String = "" # "steam" or "enet"
var is_host: bool = false
var steam_ready: bool = false
var lobby_id: int = 0
## Lobby slots (host-owned): [{kind: "human"|"ai"|"closed"|"open", name, net_id, character, ai_level}]
var slots: Array = []
var lobby_settings: Dictionary = {"speed": "online", "map_type": "procedural"}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Connection failed."))
	multiplayer.server_disconnected.connect(func():
		status.emit("Disconnected from host.")
		connection_lost.emit())


func _process(_delta: float) -> void:
	if steam_ready:
		Steam.run_callbacks()


# --- Steam ------------------------------------------------------------------------

func init_steam() -> bool:
	if steam_ready:
		return true
	if not Engine.has_singleton("Steam") and not ClassDB.class_exists("Steam"):
		status.emit("GodotSteam is not available in this build.")
		return false
	var res: Dictionary = Steam.steamInitEx(STEAM_APP_ID, false)
	if int(res.get("status", 1)) != 0:
		status.emit("Steam is not running (%s). Use LAN instead." % res.get("verbal", "unknown"))
		return false
	steam_ready = true
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_join_requested)
	return true


func steam_name() -> String:
	return Steam.getPersonaName() if steam_ready else Profile.data.name


func host_steam() -> void:
	if not init_steam():
		return
	transport = "steam"
	is_host = true
	status.emit("Creating Steam lobby...")
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, GameConst.MAX_PLAYERS)


func invite_friends() -> void:
	if steam_ready and lobby_id != 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)


func join_steam_lobby(id: int) -> void:
	if not init_steam():
		return
	transport = "steam"
	is_host = false
	status.emit("Joining lobby...")
	Steam.joinLobby(id)


func _on_lobby_created(connect_result: int, id: int) -> void:
	if connect_result != 1:
		status.emit("Could not create lobby (%d)." % connect_result)
		return
	lobby_id = id
	Steam.setLobbyData(id, "game", "standard_oil")
	var peer := SteamMultiplayerPeer.new()
	var err := peer.host_with_lobby(id)
	if err != OK:
		status.emit("Steam host failed (%d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	_reset_slots()
	status.emit("Lobby open. Invite friends through Steam.")


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if is_host:
		return
	if response != 1:
		status.emit("Could not join lobby (%d)." % response)
		return
	lobby_id = id
	var peer := SteamMultiplayerPeer.new()
	var err := peer.connect_to_lobby(id)
	if err != OK:
		status.emit("Steam connect failed (%d)." % err)
		return
	multiplayer.multiplayer_peer = peer


func _on_join_requested(id: int, _friend: int) -> void:
	join_steam_lobby(id)
	Session.goto("lobby")


# --- ENet (LAN) --------------------------------------------------------------------

func host_lan(bind_ip: String = "*") -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	var err := peer.create_server(ENET_PORT, GameConst.MAX_PLAYERS)
	if err != OK:
		status.emit("Could not open port %d (%d)." % [ENET_PORT, err])
		return
	transport = "enet"
	is_host = true
	multiplayer.multiplayer_peer = peer
	_reset_slots()
	status.emit("Hosting on LAN port %d." % ENET_PORT)


func join_lan(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, ENET_PORT)
	if err != OK:
		status.emit("Could not connect (%d)." % err)
		return
	transport = "enet"
	is_host = false
	multiplayer.multiplayer_peer = peer
	status.emit("Connecting to %s..." % address)


func leave() -> void:
	if steam_ready and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	transport = ""
	slots = []


func active() -> bool:
	return transport != "" and multiplayer.multiplayer_peer != null \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


# --- Lobby -------------------------------------------------------------------------

func _reset_slots() -> void:
	slots = [{"kind": "human", "name": steam_name() if transport == "steam" else Profile.data.name,
		"net_id": 1, "character": Profile.look()}]
	for i in 3:
		slots.append({"kind": "open"})
	_broadcast_lobby()


func set_slot_kind(i: int, kind: String) -> void:
	if not is_host or i <= 0 or i >= GameConst.MAX_PLAYERS:
		return
	while slots.size() <= i:
		slots.append({"kind": "open"})
	if slots[i].kind == "human":
		return
	slots[i] = {"kind": kind, "name": "Rival AI %d" % i, "ai_level": GameConst.AI_MEDIUM}
	_broadcast_lobby()


func set_lobby_setting(key: String, value) -> void:
	lobby_settings[key] = value
	_broadcast_lobby()


func _on_peer_connected(id: int) -> void:
	if is_host:
		status.emit("A player connected.")
	else:
		pass


func _on_connected() -> void:
	status.emit("Connected. Waiting for host...")
	_register.rpc_id(1, Profile.data.name if transport != "steam" else steam_name(), Profile.look())


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	for i in slots.size():
		if slots[i].get("net_id", -1) == id:
			slots[i] = {"kind": "open"}
	_broadcast_lobby()
	peer_left.emit(id)


@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, look: Dictionary) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	for i in slots.size():
		if slots[i].kind == "open":
			slots[i] = {"kind": "human", "name": player_name, "net_id": id, "character": look}
			_broadcast_lobby()
			return
	if slots.size() < GameConst.MAX_PLAYERS:
		slots.append({"kind": "human", "name": player_name, "net_id": id, "character": look})
		_broadcast_lobby()
		return
	_error.rpc_id(id, "The lobby is full.")


func _broadcast_lobby() -> void:
	lobby_changed.emit(slots)
	if is_host and active():
		_lobby_state.rpc(slots, lobby_settings)


@rpc("authority", "call_remote", "reliable")
func _lobby_state(new_slots: Array, settings: Dictionary) -> void:
	slots = new_slots
	lobby_settings = settings
	lobby_changed.emit(slots)


## Host: builds the match config from the lobby and starts everyone.
func start_match() -> bool:
	if not is_host:
		return false
	var players: Array = []
	for s in slots:
		match s.kind:
			"human":
				players.append({"name": s.name, "is_ai": false, "net_id": s.net_id, "character": s.character})
			"ai":
				var r := RandomNumberGenerator.new()
				r.randomize()
				players.append({"name": s.name, "is_ai": true, "ai_level": s.get("ai_level", 1), "character": Cosmetics.random_look(r)})
	if players.size() < 2:
		status.emit("Need at least 2 players (add an AI or wait for friends).")
		return false
	for i in players.size():
		players[i]["color"] = i
	var config := {"seed": 0, "map_type": lobby_settings.map_type, "speed": lobby_settings.speed, "players": players}
	var s := GameState.new_match(config)
	Session.net_mode = "host"
	Session.campaign_index = -1
	Session.campaign_county = -1
	Session.resume_state = s.to_dict(true)
	_start_client.rpc(s.to_dict(false))
	Session.goto("match")
	return true


@rpc("authority", "call_remote", "reliable")
func _start_client(public_state: Dictionary) -> void:
	Session.net_mode = "client"
	Session.campaign_index = -1
	Session.campaign_county = -1
	Session.resume_state = public_state
	match_started.emit(public_state)
	Session.goto("match")


# --- In-match ----------------------------------------------------------------------

func send_action(action: Dictionary) -> void:
	_action.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _action(action: Dictionary) -> void:
	if is_host:
		action_received.emit(multiplayer.get_remote_sender_id(), action)


func broadcast_update(events: Array, public_state: Dictionary) -> void:
	if is_host and active():
		_update.rpc(events, public_state)


@rpc("authority", "call_remote", "reliable")
func _update(events: Array, public_state: Dictionary) -> void:
	update_received.emit(events, public_state)


func send_error(peer_id: int, text: String) -> void:
	_error.rpc_id(peer_id, text)


@rpc("authority", "call_remote", "reliable")
func _error(text: String) -> void:
	error_received.emit(text)
	status.emit(text)
