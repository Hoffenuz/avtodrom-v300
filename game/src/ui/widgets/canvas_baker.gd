class_name CanvasBaker
extends RefCounted
## Draws a widget's still parts once into a texture, so the HUD costs one
## textured quad per widget instead of a draw call for every antialiased
## circle, arc and icon stroke in it (a round button alone was ~8).
##
## The picture is rendered by a small SubViewport that updates once and then
## keeps its texture. The caller owns the returned viewport (it is added as
## the caller's child) and frees it when the picture changes.


## False where nothing is rendered (headless runs): callers draw directly.
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


## `drawer(ci: CanvasItem)` draws in the caller's units; `scale` maps those
## to texture pixels (the canvas stretch, so the picture stays sharp).
static func bake(owner: Node, units: Vector2, scale: float, drawer: Callable) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(1, ceili(units.x * scale)), maxi(1, ceili(units.y * scale)))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var ci := Node2D.new()
	ci.scale = Vector2(scale, scale)
	ci.draw.connect(func() -> void: drawer.call(ci))
	vp.add_child(ci)
	owner.add_child(vp)
	return vp


## Baked pictures hold colour already multiplied by alpha (they were blended
## onto a transparent target); widgets drawing them use this material.
static func premultiplied() -> CanvasItemMaterial:
	if _premult == null:
		_premult = CanvasItemMaterial.new()
		_premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return _premult


static var _premult: CanvasItemMaterial


## Scale from a CanvasItem's units to screen pixels.
static func pixel_scale(ci: CanvasItem) -> float:
	return clampf(ci.get_global_transform_with_canvas().get_scale().x, 0.5, 4.0)
