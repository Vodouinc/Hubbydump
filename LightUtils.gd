class_name LightUtils
extends RefCounted

static var _cached_radial_texture: Texture2D = null

## Generates a smooth, procedural 2D radial light texture in memory
static func get_radial_texture(size: int = 128, falloff: float = 2.0) -> Texture2D:
	if _cached_radial_texture != null:
		return _cached_radial_texture

	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half = size * 0.5
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - half + 0.5, y - half + 0.5).length() / half
			var alpha = clampf(pow(maxf(0.0, 1.0 - dist), falloff), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_cached_radial_texture = ImageTexture.create_from_image(img)
	return _cached_radial_texture

## Helper to create and attach a configured PointLight2D
static func create_point_light(color: Color, energy: float = 1.0, scale_factor: float = 2.0) -> PointLight2D:
	var light = PointLight2D.new()
	light.texture = get_radial_texture()
	light.color = color
	light.energy = energy
	light.texture_scale = scale_factor
	return light
