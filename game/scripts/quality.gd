class_name Quality
extends Node
## Keeps the frame rate smooth by changing the 3D render resolution on the fly.
## Phones start at a lower resolution, upscaled with FSR, and adjust from there.

var mobile := false
var target_fps := 45.0
var min_scale := 0.5
var max_scale := 1.0
var scale := 1.0
var _acc := 0.0
var _frames := 0


func setup(is_mobile: bool, config: Dictionary) -> void:
	mobile = is_mobile
	target_fps = config.get("target_fps_mobile", 40.0) if mobile else config.get("target_fps_pc", 58.0)
	min_scale = 0.45 if mobile else 0.6
	max_scale = 0.8 if mobile else 1.0
	scale = 0.62 if mobile else 1.0
	var vp := get_viewport()
	# FSR upscaling needs the Forward+ renderer; phones use plain bilinear.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if mobile else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = 0.4
	if mobile:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		Engine.max_fps = 60


func _process(delta: float) -> void:
	_acc += delta
	_frames += 1
	if _acc < 1.5:
		return
	var fps := _frames / _acc
	_acc = 0.0
	_frames = 0
	if fps < target_fps - 4.0 and scale > min_scale:
		scale = maxf(min_scale, scale - 0.07)
	elif fps > target_fps + 10.0 and scale < max_scale:
		scale = minf(max_scale, scale + 0.04)
	get_viewport().scaling_3d_scale = scale
