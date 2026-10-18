class_name CursorKit
extends RefCounted
## Hardware mouse cursors drawn as vector art (molten gold on dark, like the UI) and rasterised at the size the window needs,
## so they stay crisp on Retina and scale with the UI. Kinds: arrow (default pointer), enemy (sword), enemy_far (sword, can't
## reach), friend (hand with a plus), friend_far, ground (reticle). Hotspots are given in the 32x32 design grid.

const KINDS := ["arrow", "enemy", "enemy_far", "friend", "friend_far", "ground"]
const GOLD := "#ffc15a"
const DARK := "#1a0c06"
const RED := "#ff5a52"
const GREEN := "#7dff9a"

const SVG_HEAD := '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
const ART := {
	"arrow": '<path d="M4 3 L4 24 L9.5 19 L13.5 28 L17.5 26.2 L13.6 17.6 L21 17.2 Z" fill="#1a0c06" stroke="#ffc15a" stroke-width="2" stroke-linejoin="round"/><path d="M6.6 8.5 L6.6 19.4 L9.6 16.6" fill="none" stroke="#fff0c8" stroke-width="1" stroke-opacity="0.55" stroke-linecap="round"/>',
	"enemy": '<path d="M4 4 L21 21" stroke="#1a0c06" stroke-width="6" stroke-linecap="round"/><path d="M4 4 L21 21" stroke="#ffe9b0" stroke-width="3" stroke-linecap="round"/><path d="M14 25 L25 14" stroke="#1a0c06" stroke-width="6" stroke-linecap="round"/><path d="M14 25 L25 14" stroke="#ffc15a" stroke-width="3" stroke-linecap="round"/><path d="M21 21 L28 28" stroke="#1a0c06" stroke-width="6" stroke-linecap="round"/><path d="M21 21 L28 28" stroke="#c8741a" stroke-width="3" stroke-linecap="round"/><circle cx="28" cy="28" r="2.4" fill="#ffc15a" stroke="#1a0c06" stroke-width="1.2"/>',
	"friend": '<path d="M9 15 V8 a2 2 0 0 1 4 0 V14 V6 a2 2 0 0 1 4 0 V14 V7 a2 2 0 0 1 4 0 V15 V10 a2 2 0 0 1 4 0 V19 C25 25 21 29 16 29 C12 29 9 26 7 22 L5 18 a2 2 0 0 1 3.4 -2 Z" fill="#1a0c06" stroke="#7dff9a" stroke-width="2.4" stroke-linejoin="round"/><path d="M10 15 V8 M14 14 V6 M18 14 V7 M22 15 V10" stroke="#e8fff0" stroke-width="1" stroke-opacity="0.5" stroke-linecap="round"/><path d="M16 17.5 V25 M12.5 21.2 H19.5" stroke="#7dff9a" stroke-width="2.4" stroke-linecap="round"/>',
	"ground": '<circle cx="16" cy="16" r="9" fill="none" stroke="#1a0c06" stroke-width="4.4"/><circle cx="16" cy="16" r="9" fill="none" stroke="#ffc15a" stroke-width="2"/><path d="M16 2 V9 M16 23 V30 M2 16 H9 M23 16 H30" stroke="#1a0c06" stroke-width="4.4" stroke-linecap="round"/><path d="M16 2 V9 M16 23 V30 M2 16 H9 M23 16 H30" stroke="#ffc15a" stroke-width="2" stroke-linecap="round"/><circle cx="16" cy="16" r="1.8" fill="#fff0c8"/>',
}
## Where the pointer's tip is in the 32x32 grid.
const HOTSPOT := {"arrow": Vector2(4, 3), "enemy": Vector2(4, 4), "enemy_far": Vector2(4, 4), "friend": Vector2(16, 6), "friend_far": Vector2(16, 6), "ground": Vector2(16, 16)}

static var _tex := {}
static var _kind := "arrow"
static var _px := 0


## Cursor edge in pixels for a window: proportional to the HUD scale (so it follows Retina and window size), clamped.
static func size_for(win_px: Vector2) -> int:
	return clampi(roundi(26.0 * Hud.ui_scale_for(win_px)), 24, 96)


## Which cursor to show. rel: "" (nothing), "enemy", "friend"; dist/range in metres (range <= 0: no limit).
static func kind_for(rel: String, dist: float, reach: float, placing_ground: bool) -> String:
	if placing_ground:
		return "ground"
	match rel:
		"enemy":
			return "enemy_far" if (reach > 0.0 and dist > reach) else "enemy"
		"friend":
			return "friend_far" if (reach > 0.0 and dist > reach) else "friend"
	return "arrow"


static func svg_for(kind: String) -> String:
	var base := kind.replace("_far", "")
	var art: String = ART[base]
	if kind.ends_with("_far"):
		# "can't": the same shape dimmed, with a red slash across it
		art = '<g opacity="0.55">%s</g><path d="M5 5 L27 27" stroke="#1a0c06" stroke-width="5.4" stroke-linecap="round"/><path d="M5 5 L27 27" stroke="%s" stroke-width="2.6" stroke-linecap="round"/>' % [art, RED]
	return SVG_HEAD + art + "</svg>"


static func render(kind: String, px: int) -> Image:
	var img := Image.new()
	img.load_svg_from_string(svg_for(kind), float(px) / 32.0)
	img.convert(Image.FORMAT_RGBA8)
	return img


## Resizes the cached cursors when the window (or its scale) changes.
static func refit(win_px: Vector2) -> void:
	var px := size_for(win_px)
	if px == _px:
		return
	_px = px
	_tex.clear()
	var k := _kind
	_kind = "x"
	set_kind(k)


static func set_kind(kind: String) -> void:
	if kind == _kind or DisplayServer.get_name() == "headless":
		_kind = kind
		return
	_kind = kind
	if _px == 0:
		_px = 32
	if not _tex.has(kind):
		_tex[kind] = ImageTexture.create_from_image(render(kind, _px))
	var hot: Vector2 = (HOTSPOT[kind] as Vector2) * float(_px) / 32.0
	Input.set_custom_mouse_cursor(_tex[kind], Input.CURSOR_ARROW, hot)


static func reset() -> void:
	_kind = "x"
	set_kind("arrow")
