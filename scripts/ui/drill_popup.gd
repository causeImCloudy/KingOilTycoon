class_name DrillPopup
extends Control
## The cut-away drill reveal: a slice of ground with three strata. The bit bores down and oil
## bursts out at the stratum where it hits, or it goes all the way through and comes up dry.
## The player's full-body character stands next to the rig and reacts.

const GROUND_Y: int = 24
const STRATUM_H: int = 32
const BG_SIZE := Vector2(200, 120)
## Extra sky above the cut-away so the rig and character fit.
const TOP: int = 40

var _bg: TextureRect
var _rig: TextureRect
var _bit: TextureRect
var _pipe: ColorRect
var _oil: ColorRect
var _character: CharacterView
var _caption: Label
var _frame: PanelContainer
var _labels: Array[Label] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func build(screen: Vector2) -> void:
	size = screen
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = screen
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_frame = UiKit.panel(4)
	var center := CenterContainer.new()
	center.size = screen
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(_frame)
	var content := UiKit.vbox(3)
	_frame.add_child(content)
	var outer := Control.new()
	outer.custom_minimum_size = BG_SIZE + Vector2(0, TOP)
	outer.clip_contents = true
	content.add_child(outer)
	var sky := ColorRect.new()
	sky.color = Color("f0a35e")
	sky.size = Vector2(BG_SIZE.x, TOP)
	outer.add_child(sky)
	var inner := Control.new()
	inner.position = Vector2(0, TOP)
	outer.add_child(inner)
	_bg = TextureRect.new()
	_bg.texture = UiKit.tex("res://assets/ui/cutaway_bg.png")
	_bg.size = BG_SIZE
	inner.add_child(_bg)
	for i in 3:
		var l := UiKit.label(GameConst.DEPTH_NAMES[i], 8, Color("f4ecd8"))
		l.position = Vector2(4, GROUND_Y + i * STRATUM_H + 2)
		l.add_theme_color_override("font_outline_color", Color("1d1611"))
		l.add_theme_constant_override("outline_size", 1)
		inner.add_child(l)
		_labels.append(l)
	_pipe = ColorRect.new()
	_pipe.color = Color("4e555b")
	_pipe.position = Vector2(99, GROUND_Y)
	_pipe.size = Vector2(2, 0)
	inner.add_child(_pipe)
	_oil = ColorRect.new()
	_oil.color = Color("15100d")
	inner.add_child(_oil)
	_bit = TextureRect.new()
	_bit.texture = UiKit.tex("res://assets/sprites/drill_bit.png")
	_bit.position = Vector2(96, GROUND_Y - 4)
	inner.add_child(_bit)
	_rig = TextureRect.new()
	_rig.texture = UiKit.tex("res://assets/sprites/cutaway_rig.png")
	_rig.position = Vector2(76, GROUND_Y - 46)
	inner.add_child(_rig)
	_character = CharacterView.new()
	_character.position = Vector2(140, GROUND_Y - 48 + 2)
	inner.add_child(_character)
	_caption = UiKit.label("", 8)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size.x = BG_SIZE.x
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_caption)


## Plays the full reveal. ev = drill event from GameState.
func play(ev: Dictionary, look: Dictionary, player_name: String, speed: float) -> void:
	visible = true
	_character.setup(look, false)
	_character.play("anticipate")
	_caption.text = "%s is drilling..." % player_name
	_oil.size = Vector2.ZERO
	_pipe.size = Vector2(2, 0)
	_bit.position = Vector2(96, GROUND_Y - 4)
	for l in _labels:
		l.modulate = Color.WHITE
	_frame.scale = Vector2(0.9, 0.9)
	_frame.pivot_offset = _frame.size / 2
	var tw := create_tween()
	tw.tween_property(_frame, "scale", Vector2.ONE, 0.12 / speed)
	await tw.finished
	var engine := AudioStreamPlayer.new()
	engine.stream = preload("res://assets/audio/sfx/drill_loop.ogg")
	engine.volume_db = linear_to_db(maxf(0.001, float(Profile.setting("sfx"))))
	add_child(engine)
	engine.play()

	var depth: int = ev.depth
	var target_layer := depth if depth >= 0 else 2
	var bottom := GROUND_Y + (target_layer + 1) * STRATUM_H - 6 if depth >= 0 else GROUND_Y + 3 * STRATUM_H - 2
	if depth >= 0:
		bottom = GROUND_Y + target_layer * STRATUM_H + STRATUM_H / 2
	# Bore down layer by layer, with a little shudder.
	var y := float(GROUND_Y - 4)
	var per_px := 0.012 / speed
	while y < bottom - 8:
		y += 2.0
		_bit.position = Vector2(96 + (1 if int(y) % 4 == 0 else 0), y)
		_pipe.size = Vector2(2, maxf(0.0, y - GROUND_Y + 2))
		await get_tree().create_timer(per_px * 2.0).timeout
	_bit.position.x = 96
	engine.stop()
	engine.queue_free()

	if depth >= 0:
		_labels[depth].modulate = Color("f2c14e")
		# Oil floods up the pipe and bursts out above the rig.
		_oil.position = Vector2(96, bottom - 4)
		_oil.size = Vector2(8, 6)
		var burst := create_tween().set_parallel(true)
		burst.tween_property(_oil, "position:y", GROUND_Y - 58.0, 0.45 / speed)
		burst.tween_property(_oil, "size:y", bottom - GROUND_Y + 54.0, 0.45 / speed)
		Sfx.play("gusher")
		await burst.finished
		_character.play("cheer")
		_caption.text = "%s oil!  Cost %s" % [GameConst.DEPTH_NAMES[depth], UiKit.money(ev.cost)]
	else:
		Sfx.play("dry_hole")
		_character.play("sulk")
		_caption.text = "Dry hole.  Cost %s" % UiKit.money(ev.cost)
		var shake := create_tween()
		for i in 3:
			shake.tween_property(_bit, "position:x", 94.0, 0.04 / speed)
			shake.tween_property(_bit, "position:x", 98.0, 0.04 / speed)
		await shake.finished
	await get_tree().create_timer(1.1 / speed).timeout
	var out := create_tween()
	out.tween_property(_frame, "scale", Vector2(0.9, 0.0), 0.1 / speed)
	await out.finished
	_frame.scale = Vector2.ONE
	visible = false
