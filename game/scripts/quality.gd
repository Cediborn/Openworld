class_name Quality
extends Node
## Keeps the frame rate smooth by changing the 3D render resolution on the fly.
## Phones start at a lower resolution, upscaled with FSR, and adjust from there.

var mobile := false
## Laptop / weak-PC profile (see setup_lite).
var lite := false
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


## Laptops and PCs with built-in graphics: render the 3D view at a lower
## resolution (FSR sharpens it back up), smaller and cheaper shadow maps, and
## let the resolution drop further when the frame rate dips.
func setup_lite() -> void:
	lite = true
	target_fps = 45.0
	min_scale = 0.5
	max_scale = 0.85
	scale = 0.72
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = 0.3
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	vp.positional_shadow_atlas_size = 1024
	# Distant objects switch to their simpler versions sooner.
	vp.mesh_lod_threshold = 4.0


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


## Player-chosen graphics preset: battery (30 fps, lower resolution),
## balanced (default) or sharp (higher resolution, may run warmer).
func set_preset(preset: String) -> void:
	if lite and not mobile:
		_set_lite_preset(preset)
		return
	var base := 0.62 if mobile else 1.0
	match preset:
		"battery":
			max_scale = 0.6 if mobile else 0.8
			min_scale = 0.4 if mobile else 0.5
			Engine.max_fps = 30
			target_fps = 28.0
		"sharp":
			max_scale = 1.0
			min_scale = 0.6 if mobile else 0.75
			Engine.max_fps = 60
			target_fps = 40.0 if mobile else 55.0
		_:
			max_scale = 0.8 if mobile else 1.0
			min_scale = 0.45 if mobile else 0.6
			Engine.max_fps = 60 if mobile else 0
			target_fps = 40.0 if mobile else 58.0
	scale = clampf(base, min_scale, max_scale)
	get_viewport().scaling_3d_scale = scale


func _set_lite_preset(preset: String) -> void:
	match preset:
		"battery":
			max_scale = 0.7
			min_scale = 0.45
			Engine.max_fps = 30
			target_fps = 28.0
		"sharp":
			max_scale = 1.0
			min_scale = 0.6
			Engine.max_fps = 0
			target_fps = 45.0
		_:
			max_scale = 0.85
			min_scale = 0.5
			Engine.max_fps = 0
			target_fps = 45.0
	scale = clampf(0.72, min_scale, max_scale)
	get_viewport().scaling_3d_scale = scale
