class_name Quality
extends RefCounted
## Graphics quality levels (alta / media / baja). "auto" picks one and drops it when fps stays low.

const LEVELS := ["alta", "media", "baja"]
const TABLE := {
	"alta": {"scale": 1.0, "msaa": 2, "shadows": true, "shadow_size": 4096, "glow": true, "ssao": true, "ssr": true,
		"volumetric_fog": true, "particles": 1.0, "embers": 260, "decals": true, "sdfgi": false, "fx_lights": true, "dof": true},
	"media": {"scale": 1.0, "msaa": 0, "shadows": true, "shadow_size": 2048, "glow": true, "ssao": true, "ssr": false,
		"volumetric_fog": false, "particles": 0.6, "embers": 140, "decals": true, "sdfgi": false, "fx_lights": true, "dof": false},
	"baja": {"scale": 0.75, "msaa": 0, "shadows": false, "shadow_size": 1024, "glow": false, "ssao": false, "ssr": false,
		"volumetric_fog": false, "particles": 0.3, "embers": 50, "decals": false, "sdfgi": false, "fx_lights": false, "dof": false},
}


## Debug overrides from the command line (--render-scale=0.6 --upscaler=metalfx|fsr2|bilinear --shadows=0 --ssr=0 ...), used by tools/perf.sh.
static var overrides := {}


## Settings for `level` on a window of `win_px` pixels: the table plus the render scale/upscaler that fit the pixel budget.
static func effective(level: String, win_px: Vector2i) -> Dictionary:
	var d := settings(level)
	if not overrides.has("scale"):
		d["scale"] = minf(float(d.scale), auto_scale(win_px, level))
	if not overrides.has("upscaler"):
		d["upscaler"] = upscaler_for(OS.get_name(), float(d.scale))
	return d


static func settings(level: String) -> Dictionary:
	var d: Dictionary = (TABLE.get(level, TABLE.alta) as Dictionary).duplicate()
	for k in overrides:
		d[k] = overrides[k]
	return d


## choice: alta | media | baja | auto; `current` is the level auto is running at.
static func resolve(choice: String, current: String) -> String:
	if choice == "auto":
		return current if TABLE.has(current) else "alta"
	return choice if TABLE.has(choice) else "alta"


static func lower(level: String) -> String:
	var i := LEVELS.find(level)
	return LEVELS[mini(i + 1, LEVELS.size() - 1)] if i >= 0 else "alta"


## Megapixels the 3D pass may render per level; bigger windows (Retina) get a render scale below 1 and are upscaled.
const PIXEL_BUDGET := {"alta": 4.6e6, "media": 3.4e6, "baja": 1.6e6}


## 3D render scale that keeps `px` (window pixels) within the level's pixel budget (never below 0.5, never above 1).
static func auto_scale(px: Vector2i, level: String) -> float:
	var budget: float = PIXEL_BUDGET.get(level, PIXEL_BUDGET.media)
	var pixels := float(px.x) * float(px.y)
	if pixels <= budget:
		return 1.0
	return clampf(snappedf(sqrt(budget / pixels), 0.05), 0.5, 1.0)


## Spatial upscaler to use when rendering below native: MetalFX on macOS (cheap and sharp), plain bilinear elsewhere.
static func upscaler_for(os_name: String, scale: float) -> String:
	if scale >= 0.999:
		return "bilinear"
	return "metalfx" if os_name == "macOS" else "bilinear"


## Starting level for "auto": weaker GPUs start lower, and the OpenGL fallback renderer always uses "baja".
static func initial_level(device_type: int, compatibility_renderer: bool) -> String:
	if compatibility_renderer or device_type == RenderingDevice.DEVICE_TYPE_CPU:
		return "baja"
	if device_type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return "alta"
	return "media"


static func compatibility_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"
