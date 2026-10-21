@tool
extends CompositorEffect
## Speed / nitro radial blur. Verified on Godot 4.7.2 Forward+ / Metal 4 (M1 Max).
## Runs on the HDR colour buffer after the transparent pass (before glow + tonemap).
## Usage:  var c := Compositor.new(); c.compositor_effects = [preload("radial_blur_effect.gd").new()]
##         camera.compositor = c        (or WorldEnvironment.compositor = c)
## Drive `strength` from gameplay: 0.0 = off (pass skipped), 0.06 cruise, 0.15 nitro, 0.25 max.

@export_range(0.0, 0.5) var strength := 0.12
@export var center := Vector2(0.5, 0.55)   # UV; slightly below middle = car / horizon
@export_range(4, 32) var samples := 12

var rd: RenderingDevice
var copy_shader: RID
var copy_pipeline: RID
var blur_shader: RID
var blur_pipeline: RID
var linear_sampler: RID

const CTX := &"radial_blur"
const TMP := &"tmp"

const COPY_GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D src_image;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst_image;
layout(push_constant, std430) uniform Params { vec2 size; vec2 pad; } p;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) return;
	imageStore(dst_image, px, imageLoad(src_image, px));
}
"""

const BLUR_GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D src_tex;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D color_image;
layout(push_constant, std430) uniform Params { vec2 size; vec2 center; float strength; float samples; vec2 pad; } p;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) return;
	vec2 uv = (vec2(px) + 0.5) / p.size;
	vec2 dir = p.center - uv;
	float falloff = smoothstep(0.05, 0.6, length(dir));   // centre stays sharp
	vec4 acc = vec4(0.0);
	int n = int(p.samples);
	for (int i = 0; i < n; i++) {
		float t = float(i) / float(n);
		acc += textureLod(src_tex, uv + dir * t * p.strength * falloff, 0.0);
	}
	imageStore(color_image, px, acc / float(n));
}
"""

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_compute)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd:
		for r in [copy_pipeline, copy_shader, blur_pipeline, blur_shader, linear_sampler]:
			if r.is_valid(): rd.free_rid(r)   # freeing a shader also frees its pipeline; guard keeps it safe

func _compile(src: String) -> RID:
	var s := RDShaderSource.new()
	s.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	s.source_compute = src
	var spirv := rd.shader_compile_spirv_from_source(s)
	if spirv.compile_error_compute != "":
		push_error("radial_blur compile: " + spirv.compile_error_compute)
		return RID()
	return rd.shader_create_from_spirv(spirv)

func _init_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null: return   # Compatibility renderer: no RenderingDevice
	copy_shader = _compile(COPY_GLSL)
	blur_shader = _compile(BLUR_GLSL)
	if copy_shader.is_valid(): copy_pipeline = rd.compute_pipeline_create(copy_shader)
	if blur_shader.is_valid(): blur_pipeline = rd.compute_pipeline_create(blur_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler = rd.sampler_create(ss)

func _image_uniform(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if rd == null or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT: return
	if strength <= 0.001 or not copy_pipeline.is_valid() or not blur_pipeline.is_valid(): return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null: return
	var size: Vector2i = buffers.get_internal_size()   # internal res (smaller than window with FSR/MetalFX)
	if size.x == 0 or size.y == 0: return
	var view_count := buffers.get_view_count()
	# Managed temp texture: recreated automatically by the engine when the viewport is resized.
	if not buffers.has_texture(CTX, TMP):
		var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		buffers.create_texture(CTX, TMP, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, size, view_count, 1, true, false)
	var gx := ceili(size.x / 8.0)
	var gy := ceili(size.y / 8.0)
	var pc_copy := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()          # 16 bytes
	var pc_blur := PackedFloat32Array([size.x, size.y, center.x, center.y,
		strength, float(samples), 0.0, 0.0]).to_byte_array()                                 # 32 bytes
	for view in view_count:
		var color: RID = buffers.get_color_layer(view)
		var tmp: RID = buffers.get_texture_slice(CTX, TMP, view, 0, 1, 1)
		var copy_set := UniformSetCacheRD.get_cache(copy_shader, 0, [_image_uniform(0, color), _image_uniform(1, tmp)])
		var su := RDUniform.new()
		su.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		su.binding = 0
		su.add_id(linear_sampler)
		su.add_id(tmp)
		var blur_set := UniformSetCacheRD.get_cache(blur_shader, 0, [su, _image_uniform(1, color)])
		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, copy_pipeline)
		rd.compute_list_bind_uniform_set(cl, copy_set, 0)
		rd.compute_list_set_push_constant(cl, pc_copy, pc_copy.size())
		rd.compute_list_dispatch(cl, gx, gy, 1)
		rd.compute_list_add_barrier(cl)
		rd.compute_list_bind_compute_pipeline(cl, blur_pipeline)
		rd.compute_list_bind_uniform_set(cl, blur_set, 0)
		rd.compute_list_set_push_constant(cl, pc_blur, pc_blur.size())
		rd.compute_list_dispatch(cl, gx, gy, 1)
		rd.compute_list_end()
