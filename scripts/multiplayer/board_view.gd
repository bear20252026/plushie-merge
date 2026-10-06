extends Control
## Presentation-only cabinet. Each local board owns its plushies' physics.
signal aimed(world_x: float)
signal dropped
const Toys := preload("res://scripts/plushie_body.gd")
const Bomb := preload("res://scripts/bomb_plushie.gd")
const TRIM := preload("res://assets/template/foregrounds/cabinet_trim.webp")
const SHELL_INSET := 4.0
const TEXT_BORDER_CLEARANCE := 8.0
const BOMB_BADGE_FONT_SIZE := 24
const BOMB_BADGE_BORDER_WIDTH := 3.0
var local_player := false
var input_enabled := false:
	set(value):
		input_enabled = value
		if not value: cancel_touch()
var tint := Color("86bfe4")
var border := Color("4f89b2")
var board: Dictionary = {}
var rendered: Dictionary = {}
var world_rect := Rect2(352,116,736,804)
var world_scale := 1.0
var world_offset := Vector2.ZERO
var font: Font
var reduced_motion := false
var _touch_index := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS if local_player else Control.CURSOR_ARROW
	clip_contents = true
	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(cancel_touch)

func cancel_touch() -> void:
	_touch_index = -1

func _on_resized() -> void:
	cancel_touch()
	queue_redraw()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): cancel_touch()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		cancel_touch()

func _input(event: InputEvent) -> void:
	if _touch_index < 0: return
	if not local_player or not input_enabled or not is_visible_in_tree():
		cancel_touch()
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag) or event.index != _touch_index: return
	# GUI touch capture does not guarantee a release outside this Control. Track
	# only the finger acquired in _gui_input, using viewport-to-local coordinates.
	var at: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
	if event is InputEventScreenTouch:
		if event.canceled:
			cancel_touch()
		elif not event.pressed:
			cancel_touch()
			if _aim_touch(at) and local_player and input_enabled: dropped.emit()
	elif event is InputEventScreenDrag:
		_aim_touch(at)
	get_viewport().set_input_as_handled()

func _aim_touch(at: Vector2) -> bool:
	if not get_glass_rect().has_point(at) or world_scale <= 0: return false
	var tank := _tank()
	var world_x := (at.x-world_offset.x)/world_scale
	aimed.emit(clampf(world_x,tank.position.x+15,tank.end.x-15))
	return true

func set_snapshot(snapshot: Dictionary) -> void:
	board = snapshot
	var active := {}
	for toy in snapshot.get("toys",[]):
		var id := str(toy.get("id",0))
		active[id] = true
		if not rendered.has(id): rendered[id] = toy.duplicate()
	for id in rendered.keys():
		if not active.has(id): rendered.erase(id)
	queue_redraw()

func _process(delta: float) -> void:
	var weight := 1.0 if reduced_motion else 1.0-exp(-delta*24.0)
	for toy in board.get("toys",[]):
		var id := str(toy.get("id",0))
		if not rendered.has(id): continue
		var shown: Dictionary = rendered[id]
		shown.x = lerpf(float(shown.get("x",0)),float(toy.get("x",0)),weight)
		shown.y = lerpf(float(shown.get("y",0)),float(toy.get("y",0)),weight)
		shown.rotation = lerp_angle(float(shown.get("rotation",0)),float(toy.get("rotation",0)),weight)
		if toy.has("bomb_fuse"): shown.bomb_fuse = toy.bomb_fuse
		if toy.has("armed"): shown.armed = toy.armed
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not local_player or not input_enabled: return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _touch_index < 0:
			_touch_index = event.index
			if not _aim_touch(event.position): cancel_touch()
		accept_event()
		return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		if event.device == -1: return
		_update_projection()
		if world_scale <= 0: return
		var world: Vector2 = (event.position-world_offset)/world_scale
		var tank := _tank()
		if tank.grow(12).has_point(world):
			aimed.emit(clampf(world.x,tank.position.x+15,tank.end.x-15))
			if event is InputEventMouseButton: dropped.emit()
		accept_event()

func _tank() -> Rect2:
	var values: Array = board.get("tank",[400,176,640,676])
	return Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))

func _box(rect: Rect2,color: Color,edge: Color,radius := 24,width := 2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	draw_style_box(box,rect)

func _update_projection() -> void:
	var tank := _tank()
	world_rect = Rect2(tank.position-Vector2(48,60),tank.size+Vector2(96,126))
	world_scale = minf(size.x/world_rect.size.x,size.y/world_rect.size.y)
	world_offset = (size-world_rect.size*world_scale)*0.5-world_rect.position*world_scale

func get_cabinet_rect() -> Rect2:
	# The visible shell is inset inside the aspect-fit world, not the Control bounds.
	_update_projection()
	var shell := world_rect.grow(-SHELL_INSET)
	return Rect2(world_offset+shell.position*world_scale,shell.size*world_scale)

func get_glass_rect() -> Rect2:
	_update_projection()
	var glass := _tank()
	# The irregular trim starts above the physical floor; its embroidered peaks
	# need their own exclusion zone rather than the cabinet's rectangular bounds.
	glass.size.y -= 28
	return Rect2(world_offset+glass.position*world_scale,glass.size*world_scale)

func bomb_badge_radius(text: String) -> float:
	if font == null: return 28.0
	var extent := Vector2(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,BOMB_BADGE_FONT_SIZE).x,font.get_height(BOMB_BADGE_FONT_SIZE))
	# A circular border must clear the text rectangle's corners, not just its
	# width and height. Keep this in viewport pixels as the cabinet scales down.
	return ceilf(extent.length()*0.5+TEXT_BORDER_CLEARANCE+BOMB_BADGE_BORDER_WIDTH*0.5)

func _draw() -> void:
	_update_projection()
	var tank := _tank()
	draw_set_transform(world_offset,0,Vector2.ONE*world_scale)
	_box(world_rect.grow(-SHELL_INSET),tint,border,38,3)
	_box(world_rect.grow(-17),tint.lightened(0.57),Color("fff9f0"),30,3)
	_box(tank.grow(9),border.darkened(0.13),border,22,2)
	_box(tank,Color("f9f2e8").lerp(tint,0.13),tint.lightened(0.34),16,2)
	# Tint the glass and machine shell; plushie colors retain their identity.
	draw_line(tank.position+Vector2(12,35),Vector2(tank.position.x+12,tank.end.y-24),Color(1,1,1,0.64),4,true)
	draw_line(tank.position+Vector2(tank.size.x-13,64),tank.end-Vector2(13,24),Color(1,1,1,0.43),2,true)
	var danger_y := float(board.get("danger_y",tank.position.y+145))
	draw_dashed_line(Vector2(tank.position.x+16,danger_y),Vector2(tank.end.x-16,danger_y),Color(0.68,0.31,0.40,0.52+minf(float(board.get("overflow",0))*0.3,0.48)),2,10,true)
	for toy in rendered.values(): _draw_toy(toy)
	var held: Variant = board.get("held",{})
	if held is Dictionary and not held.is_empty(): _draw_toy(held)
	_draw_claw(tank,held if held is Dictionary else {})
	var bottom := Rect2(tank.position.x-36,tank.end.y-17,tank.size.x+72,70)
	draw_texture_rect_region(TRIM,Rect2(bottom.position,Vector2(84,70)),Rect2(0,0,84,70),tint.lightened(0.56))
	draw_texture_rect_region(TRIM,Rect2(bottom.position+Vector2(84,0),Vector2(bottom.size.x-168,70)),Rect2(84,0,168,70),tint.lightened(0.56))
	draw_texture_rect_region(TRIM,Rect2(bottom.end.x-84,bottom.position.y,84,70),Rect2(252,0,84,70),tint.lightened(0.56))
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func _draw_toy(toy: Dictionary) -> void:
	var tier := int(toy.get("tier",0))
	var texture: Texture2D = Bomb.TEXTURE if tier == 11 else Toys.TEXTURES[clampi(tier,0,10)]
	var span: float = 148.0 if tier == 11 else Toys.SPANS[clampi(tier,0,10)]
	var fallback := texture.get_size()*span/maxf(texture.get_width(),texture.get_height())
	var extent := Vector2(float(toy.get("width",fallback.x)),float(toy.get("height",fallback.y)))
	var at := Vector2(float(toy.get("x",0)),float(toy.get("y",0)))
	var rotation_radians := float(toy.get("rotation",0))
	draw_set_transform(world_offset+at*world_scale,rotation_radians,Vector2.ONE*world_scale)
	draw_texture_rect(texture,Rect2(-extent*0.5,extent),false)
	if bool(toy.get("armed",false)) and toy.has("bomb_fuse") and float(toy.bomb_fuse) > 0:
		var text := str(maxi(1,ceili(float(toy.bomb_fuse))))
		var radius := bomb_badge_radius(text)
		var center := world_offset+(at-Vector2(0,extent.y*0.5))*world_scale-Vector2(0,radius+4)
		var safe := get_glass_rect().grow(-radius-2)
		center = center.clamp(safe.position,safe.end)
		draw_set_transform(center,0,Vector2.ONE)
		draw_circle(Vector2.ZERO,radius,Color("fff8ed"))
		draw_arc(Vector2.ZERO,radius,-PI*0.5,-PI*0.5+TAU*float(toy.bomb_fuse)/5.0,32,Color("bd6389"),BOMB_BADGE_BORDER_WIDTH,true)
		if font != null:
			var baseline := (font.get_ascent(BOMB_BADGE_FONT_SIZE)-font.get_descent(BOMB_BADGE_FONT_SIZE))*0.5
			draw_string(font,Vector2(-font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,BOMB_BADGE_FONT_SIZE).x*0.5,baseline),text,HORIZONTAL_ALIGNMENT_LEFT,-1,BOMB_BADGE_FONT_SIZE,Color("593c49"))
	draw_set_transform(world_offset,0,Vector2.ONE*world_scale)

func _draw_claw(tank: Rect2,held: Dictionary) -> void:
	var x := float(board.get("aim_x",tank.get_center().x))
	var rail := tank.position.y+19
	var hub := rail+39
	draw_line(Vector2(tank.position.x+15,rail),Vector2(tank.end.x-15,rail),Color("a19c99"),10,true)
	draw_line(Vector2(tank.position.x+15,rail-3),Vector2(tank.end.x-15,rail-3),Color("fffcf4"),3,true)
	draw_line(Vector2(x,rail),Vector2(x,hub),Color("807482"),10,true)
	draw_circle(Vector2(x,hub),18,Color("b4aebb"))
	var half_width := float(held.get("width",86))*0.5
	var height := float(held.get("height",84))
	var held_y := float(held.get("y",hub+45))
	var spread := float(board.get("claw_openness",0))
	for side in [-1.0,1.0]:
		var points := PackedVector2Array([Vector2(x+side*13,hub),Vector2(x+side*(half_width+9+spread*25),hub+20+height*0.16),Vector2(x+side*(half_width*0.66+spread*54),held_y+height*0.25-spread*17)])
		draw_polyline(points,Color("7c7480"),11,true)
		draw_polyline(points,Color("d5d2d7"),7,true)
		draw_polyline(points,Color("fffaf0"),2,true)
