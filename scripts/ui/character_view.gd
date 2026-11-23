class_name CharacterView
extends Node2D
## A shared pose track keeps the skin, outfit, expression and hat registered.
## Each beat specifies the body frame, portrait frame and time held in seconds.
const TRACKS := {
	"idle": [Vector3(0, 0, 1.35), Vector3(1, 0, 0.32), Vector3(2, 0, 0.68), Vector3(3, 1, 0.12)],
	"anticipate": [Vector3(4, 2, 0.28), Vector3(5, 3, 0.12), Vector3(6, 2, 0.18), Vector3(7, 3, 0.15)],
	"cheer": [Vector3(5, 2, 0.10), Vector3(8, 4, 0.09), Vector3(9, 4, 0.08),
		Vector3(10, 5, 0.20), Vector3(11, 4, 0.11), Vector3(8, 4, 0.15), Vector3(0, 0, 0.24)],
	"sulk": [Vector3(12, 6, 0.22), Vector3(13, 7, 0.65), Vector3(14, 6, 0.18), Vector3(15, 6, 0.34)],
	"walk": [Vector3(0, 0, 0.08), Vector3(1, 0, 0.08), Vector3(2, 0, 0.08), Vector3(3, 0, 0.08)],
}
const DIR := "res://assets/sprites/character/"
const WALK_OUTFIT := preload("res://assets/sprites/character/walk_outfit.png")
const WALK_BODY := preload("res://assets/sprites/character/walk_body.png")

var portrait: bool = false
var anim: String = "idle"
var _beat: int = 0
var _elapsed: float = 0.0
var _hold: float = 0.0
var _layers: Array[Sprite2D] = []
var _body: Sprite2D
var _body_sheet: Texture2D
var _outfit: Sprite2D
var _outfit_sheet: Texture2D
var _facing_left: bool = false


func setup(look: Dictionary, is_portrait: bool) -> CharacterView:
	portrait = is_portrait
	for layer in _layers:
		layer.hide()
		layer.queue_free()
	_layers.clear()
	var prefix := "portrait_" if portrait else ""
	var skin: Color = Cosmetics.find("skin", look.get("skin", "")).color
	var outfit: Color = Cosmetics.find("outfit", look.get("outfit", "")).color
	var hat: Dictionary = Cosmetics.find("hat", look.get("hat", ""))
	var hat_color: Color = Cosmetics.find("hat_color", look.get("hat_color", "")).color
	var face: String = Cosmetics.find("tycoon", look.get("tycoon", "")).face
	_body = _add_layer(DIR + ("portrait.png" if portrait else "body.png"), skin)
	_body_sheet = _body.texture if _body else null
	_outfit = _add_layer(DIR + prefix + "outfit.png", outfit)
	_outfit_sheet = _outfit.texture if _outfit else null
	_add_layer(DIR + prefix + face + ".png", Color.WHITE)
	if hat.get("style", "none") != "none":
		_add_layer(DIR + prefix + "hat_%s.png" % hat.style, hat_color)
	_apply()
	return self


func _add_layer(path: String, tint: Color) -> Sprite2D:
	var texture := UiKit.tex(path)
	if texture == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = 2 if portrait else 4
	sprite.vframes = 4
	sprite.centered = false
	sprite.flip_h = _facing_left
	sprite.modulate = tint
	add_child(sprite)
	_layers.append(sprite)
	return sprite


func face_left(left: bool) -> void:
	_facing_left = left
	for layer in _layers:
		layer.flip_h = left


func frame_size() -> Vector2i:
	return Vector2i(24, 24) if portrait else Vector2i(32, 48)


## With a positive hold time the reaction returns to idle automatically.
func play(anim_name: String, hold: float = 0.0) -> void:
	anim = anim_name if TRACKS.has(anim_name) else "idle"
	_beat = 0
	_elapsed = 0.0
	_hold = hold
	_apply()


func _process(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			play("idle")
			return
	var track: Array = TRACKS[anim]
	_elapsed += delta
	if _elapsed < track[_beat].z:
		return
	while _elapsed >= track[_beat].z:
		_elapsed -= track[_beat].z
		_beat = (_beat + 1) % track.size()
	_apply()


func _apply() -> void:
	var pose: Vector3 = TRACKS[anim][_beat]
	var walking := anim == "walk" and not portrait
	if _body:
		_body.texture = WALK_BODY if walking else _body_sheet
		_body.vframes = 1 if walking else 4
	if _outfit:
		_outfit.texture = WALK_OUTFIT if walking else _outfit_sheet
		_outfit.vframes = 1 if walking else 4
	for layer in _layers:
		layer.frame = int(pose.y if portrait else pose.x)
