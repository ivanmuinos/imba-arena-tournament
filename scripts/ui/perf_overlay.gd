class_name PerfOverlay
extends CanvasLayer
## F3: FPS, frame time, CPU/GPU render time, draw calls, objects, primitives, render resolution and quality level.
## Also the source of the numbers `--perf` prints (see PerfOverlay.sample()).

var label: Label
var _acc := 0.0
var _frames := 0
var _worst := 0.0
var info := {}   # latest sampled numbers
var extra := ""  # set by the match: quality level, units...


static func fmt_ms(v: float) -> String:
	return "%.1f ms" % v


func _init() -> void:
	layer = 100
	visible = false
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#c8ff9a"))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func toggle() -> void:
	visible = not visible
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## Snapshot of the render statistics (0 when headless).
static func sample(vp: Viewport) -> Dictionary:
	var rid := vp.get_viewport_rid()
	return {
		"fps": Engine.get_frames_per_second(),
		"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
		"draws": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
		"prims": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scale": vp.scaling_3d_scale,
		"size": Vector2i(vp.get_visible_rect().size) if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and false else Vector2i(vp.size),
	}


func _process(delta: float) -> void:
	delta /= maxf(Engine.time_scale, 0.01)  # real frame time even under --time-scale
	_acc += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if _acc < 0.5:
		return
	info = sample(get_viewport())
	info["avg_ms"] = _acc / _frames * 1000.0
	info["worst_ms"] = _worst * 1000.0
	if visible:
		var win := get_window()
		label.text = "%d fps  |  frame %s (peor %s)\nCPU render %s  GPU %s  script %s\nllamadas %d  objetos %d  primitivas %dk  nodos %d\npantalla %dx%d  3D x%.2f  %s" % [
			info.fps, fmt_ms(info.avg_ms), fmt_ms(info.worst_ms), fmt_ms(info.cpu_ms), fmt_ms(info.gpu_ms), fmt_ms(info.process_ms),
			info.draws, info.objects, info.prims / 1000, info.nodes, win.size.x, win.size.y, info.scale, extra]
	_acc = 0.0
	_frames = 0
	_worst = 0.0
