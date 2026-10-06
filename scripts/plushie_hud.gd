extends Control
const OpenSourceLicenses = preload("res://scripts/manus/open_source_licenses.gd")
## Native, responsive UI. All state changes are requests to the game owners.
const TITLE_ART := preload("res://assets/template/ui/title.webp")
const PAUSE_ART := preload("res://assets/template/ui/pause.webp")
const BACKGROUND := preload("res://assets/template/plushies/background/arcade.webp")
const UsernameInput := preload("res://scripts/core/username_input.gd")
const MobileSheet := preload("res://scripts/ui/mobile_sheet.gd")
const PlushStyle := preload("res://scripts/ui/plush_style.gd")
const TitleFx := preload("res://scripts/ui/title_fx.gd")
const TitleMarquee := preload("res://scripts/ui/title_marquee.gd")
const TitleRibbon := preload("res://scripts/ui/title_ribbon.gd")
const MenuCursor := preload("res://scripts/ui/menu_cursor.gd")
# Plush arcade palette: candy buttons, cream felt, lilac marquee felt and pink stitching.
const CANDY := Color("f596b0")
const CANDY_HI := Color("ffadc3")
const CANDY_DOWN := Color("e9829f")
const CANDY_LIP := Color("c9678a")
const CREAM_LIP := Color("e2c3d1")
const FELT := Color("fff7ee")
const STITCH := Color("e791ad")
const PLUM := Color("4a2a3f")
const FOCUS_RING := Color("b24d7c")
const CANDY_TEXT := Color("fffaf7")
const CANDY_OUTLINE := Color("a13f69")
# The logo gets a candy gradient fill and a periodic shine sweep; outline and shadow stay flat.
const LOGO_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(400.0, 160.0);
uniform float progress = -1.0;
uniform vec4 top_color : source_color = vec4(1.0, 0.98, 0.99, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.74, 0.83, 1.0);
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	float light = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	float fill = smoothstep(0.80, 0.96, light);
	vec2 uv = local / max(size, vec2(1.0));
	vec3 candy = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.30, 0.72, uv.y));
	float band = smoothstep(0.08, 0.0, abs(uv.x + (uv.y - 0.5) * 0.35 - progress));
	COLOR.rgb = mix(COLOR.rgb, candy + vec3(band * 0.55), fill);
}
"""
const FONT_SCALE := 4.0
const CONTROL_HEIGHT := 68.0
const TITLE_PADDING := 24.0
const TEXT_BORDER_CLEARANCE := 8.0
const CONTROL_PADDING := Vector2(16,TEXT_BORDER_CLEARANCE+3) # Includes the widest focus border.
const ART_SAFE_INSETS := Vector4(144,88,144,88) # Beyond bows, lace and scalloped corners.
const INK := Color("593c49")
const MUTED := Color("866476")
const CREAM := Color("fff8ed")
const PINK := Color("ebacb7")
const LILAC := Color("cfb9df")
const LOGO_SHADOW := Color("e98aa8")
var game: Node
var base: Control
var modals: Array[Control] = []
var modal_kinds: Array[String] = []
var current_route := ""
var metrics: Dictionary = {}
var collection_views: Array[Dictionary] = []
var controls: Dictionary = {}
var filter: ColorRect
var mobile_header := Rect2()
var mobile_footer := Rect2()
var background_layer: CanvasLayer
var background: TextureRect
var shade: ColorRect
var compact := false
var mobile := false
var margin := 24.0
var last_text_scale := 1.0
var _audio_index := 0
var _board_size := Vector2.ZERO
var _updating := false
var _refresh_queued := false
var _rebuild_queued := false
var _building_gameplay := false
var _building_pause := false
var _building_dialog := false
var _hud_cards: Dictionary = {}
var _hud_layout_queued := false
var _hud_board_rect := Rect2()
var _focus_epoch := 0
var _scroll_restore_callback: Callable
var _pending_scroll_offsets: Dictionary = {}
var _pending_scroll_route := ""
# Entrance animations play once per route/modal visit, not on every responsive rebuild.
var _intro_seen: Dictionary = {}
var _intro_route := ""
var _last_score := -1
var _time_meter: Control
var _vignette_texture: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_layer = CanvasLayer.new()
	background_layer.layer = -5
	game.add_child(background_layer)
	background = TextureRect.new()
	background.texture = BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_layer.add_child(background)
	shade = ColorRect.new()
	shade.color = Color(0.98,0.94,0.90,0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(shade)
	# A soft plum vignette frames the cabinet like arcade lighting.
	var vignette := TextureRect.new()
	vignette.texture = vignette_texture()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(vignette)
	_theme()
	rebuild()

func vignette_texture() -> GradientTexture2D:
	if _vignette_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0,Color(PLUM,0.0))
		gradient.set_color(1,Color(PLUM,0.34))
		gradient.add_point(0.62,Color(PLUM,0.0))
		_vignette_texture = GradientTexture2D.new()
		_vignette_texture.gradient = gradient
		_vignette_texture.fill = GradientTexture2D.FILL_RADIAL
		_vignette_texture.fill_from = Vector2(0.5,0.5)
		_vignette_texture.fill_to = Vector2(1.08,0.5)
		_vignette_texture.width = 128
		_vignette_texture.height = 128
	return _vignette_texture

func _theme() -> void:
	theme = Theme.new()
	theme.default_font = game.locale.font
	theme.default_font_size = int(17 * font_scale() * float(game.tweaks.value("ui.text.scale")))
	theme.set_color("font_color","Label",INK)
	for type in ["Button","CheckButton","OptionButton","LineEdit","SpinBox"]:
		theme.set_color("font_color",type,INK)
		theme.set_color("font_hover_color",type,INK)
		theme.set_color("font_focus_color",type,INK)
		theme.set_color("font_pressed_color",type,INK)
		var kind := "field" if type in ["LineEdit","SpinBox"] else "cream"
		for state in ["normal","hover","pressed","disabled","focus"]:
			theme.set_stylebox(state,type,plush(kind,state))
		if type == "LineEdit": theme.set_stylebox("read_only",type,plush(kind,"disabled"))
		theme.set_color("font_disabled_color",type,Color(MUTED,0.62))
		if type != "LineEdit": theme.set_font("font",type,game.locale.medium_font)
	theme.set_color("font_placeholder_color","LineEdit",MUTED)
	theme.set_color("caret_color","LineEdit",FOCUS_RING)
	theme.set_color("selection_color","LineEdit",Color(CANDY,0.35))
	theme.set_constant("separation","VBoxContainer",10)
	theme.set_constant("separation","HBoxContainer",10)
	var popup := plush("felt")
	_margins(popup,10,8,8)
	theme.set_stylebox("panel","PopupMenu",popup)
	var popup_hover := PlushStyle.make({"fill":Color(CANDY,0.45),"radius":10})
	theme.set_stylebox("hover","PopupMenu",popup_hover)
	theme.set_color("font_color","PopupMenu",INK)
	theme.set_color("font_hover_color","PopupMenu",INK)
	theme.set_constant("v_separation","PopupMenu",22)
	theme.set_stylebox("panel","TooltipPanel",style(CREAM,Color("d9bdce")))
	theme.set_color("font_color","TooltipLabel",INK)
	theme.set_font_size("font_size","TooltipLabel",18)
	var groove := StyleBoxLine.new()
	groove.color = Color(STITCH,0.55)
	groove.thickness = 2
	theme.set_stylebox("separator","HSeparator",groove)
	theme.set_stylebox("scroll","VScrollBar",PlushStyle.make({"fill":Color(LILAC,0.35),"radius":6}))
	theme.set_stylebox("grabber","VScrollBar",PlushStyle.make({"fill":Color("d7a9c3"),"radius":6}))
	theme.set_stylebox("grabber_highlight","VScrollBar",PlushStyle.make({"fill":CANDY,"radius":6}))
	theme.set_stylebox("grabber_pressed","VScrollBar",PlushStyle.make({"fill":CANDY_DOWN,"radius":6}))

func _margins(box: StyleBox,horizontal: float,top: float,bottom := -1.0) -> StyleBox:
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = top
	box.content_margin_bottom = top if bottom < 0 else bottom
	return box

## Code-drawn material for a UI role and state. Buttons keep 2*CONTROL_PADDING.y of total
## vertical padding so existing height budgets stay exact; the candy lip lives inside it.
func plush(kind: String,state := "normal",unit := 1.0) -> StyleBox:
	var v := {}
	match kind:
		"candy","cream":
			var candy := kind == "candy"
			var depth := maxf(3.0,roundf(6.0*unit))
			var presses := {"normal":roundf(2*unit),"hover":0.0,"pressed":depth-1.0,"disabled":roundf(3*unit),"focus":roundf(2*unit)}
			var fills := {"normal":CANDY if candy else CREAM,"hover":CANDY_HI if candy else Color("fffdf9"),"pressed":CANDY_DOWN if candy else Color("fbe6ea"),"disabled":Color(CREAM,0.62),"focus":Color(0,0,0,0)}
			v = {"fill":fills.get(state,CREAM),"depth":depth,"press":presses.get(state,0.0),"radius":int(18*unit)}
			if state == "focus":
				v.merge({"lip":Color(0,0,0,0),"rim":FOCUS_RING,"rim_width":maxi(2,int(3*unit)),"glow":Color(CANDY,0.5),"glow_size":int(8*unit)})
			elif state == "disabled":
				v.merge({"lip":Color(CREAM_LIP,0.4),"rim":Color("ead7df"),"rim_width":1})
			else:
				v.merge({"lip":CANDY_LIP if candy else CREAM_LIP,"gloss":(0.28 if candy else 0.55)+(0.1 if state == "hover" else 0.0),
					"rim":Color("ffc4d4") if candy else Color("ecd6e0"),"rim_width":1,
					"stitch":Color(1,1,1,0.62) if candy else Color(STITCH,0.5),"stitch_inset":5.0*unit,"stitch_dash":6.0*unit,"stitch_gap":4.0*unit,"stitch_width":maxf(1.0,1.5*unit),
					"shadow":Color(PLUM,0.1 if state == "pressed" else 0.2),"shadow_size":int((8 if state == "hover" else 5)*unit),"shadow_offset":Vector2(0,3*unit)})
			var box := PlushStyle.make(v)
			var vertical := maxf(2.0,CONTROL_PADDING.y-depth*0.5)
			return _margins(box,CONTROL_PADDING.x,vertical+v.press,vertical+depth-v.press)
		"felt":
			v = {"fill":FELT,"rim":Color("e4cbd8"),"rim_width":2,"radius":int(22*unit),"shade":0.06,
				"stitch":Color(STITCH,0.7),"stitch_inset":8.0*unit,"stitch_dash":7.0*unit,"stitch_gap":5.0*unit,"stitch_width":maxf(1.2,2.0*unit),
				"shadow":Color(PLUM,0.18),"shadow_size":int(14*unit),"shadow_offset":Vector2(0,6*unit)}
		"lilac":
			v = {"fill":Color("ccb2e3"),"rim":Color("b094d0"),"rim_width":2,"radius":int(30*unit),"shade":0.16,"shade_color":Color("7a58a0"),"gloss":0.12,
				"stitch":Color(1,0.96,0.99,0.9),"stitch_inset":8.0*unit,"stitch_dash":8.0*unit,"stitch_gap":5.0*unit,"stitch_width":maxf(1.2,2.2*unit),
				"shadow":Color(PLUM,0.30),"shadow_size":int(20*unit),"shadow_offset":Vector2(0,10*unit)}
		"band":
			v = {"fill":Color("d4bde8"),"rim":Color("b598d3"),"rim_width":2,"radius":0,"shade":0.1,"shade_color":Color("7a58a0"),
				"stitch":Color(1,0.96,0.99,0.85),"stitch_inset":6.0,"stitch_dash":7.0,"stitch_gap":5.0,"stitch_width":1.5}
		"pocket":
			v = {"fill":Color("fff1e5"),"rim":Color("eed7e1"),"rim_width":1,"radius":int(16*unit),
				"stitch":Color(STITCH,0.45),"stitch_inset":6.0*unit,"stitch_dash":5.0*unit,"stitch_gap":4.0*unit,"stitch_width":maxf(1.0,1.5*unit)}
		"field":
			var focused := state == "focus"
			v = {"fill":Color(0,0,0,0) if focused else (Color(CREAM,0.6) if state == "disabled" else Color("fffdf9")),"rim":FOCUS_RING if focused else Color("e0c6d4"),"rim_width":2,
				"radius":int(14*unit),"shade":0.0 if focused else 0.09,"glow":Color(CANDY,0.45) if focused else Color(0,0,0,0),"glow_size":int(6*unit) if focused else 0}
			return _margins(PlushStyle.make(v),CONTROL_PADDING.x,CONTROL_PADDING.y)
		"chip","chip_lilac","chip_cream":
			var fills := {"chip":Color("fbd8e2"),"chip_lilac":Color("e8dbf6"),"chip_cream":Color(CREAM,0.92)}
			v = {"fill":fills[kind],"radius":99,"rim":Color(1,1,1,0.7),"rim_width":1}
			return _margins(PlushStyle.make(v),10*unit,2*unit)
		"key":
			v = {"fill":Color("fffaf4"),"lip":Color("d7bfcc"),"depth":maxf(2.0,3.0*unit),"press":0.0,"radius":int(7*unit),"rim":Color("e3cdd8"),"rim_width":1,"gloss":0.5}
			return _margins(PlushStyle.make(v),7*unit,2*unit,2*unit+v.depth)
	return PlushStyle.make(v)

func style(color: Color,border := Color.TRANSPARENT,width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(14)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = CONTROL_PADDING.y
	box.content_margin_bottom = CONTROL_PADDING.y
	return box

func _rect(node: Control,rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size

func t(key: String, placeholders: Dictionary = {}) -> String:
	return game.t(key,placeholders)

func font_scale() -> float:
	if _building_pause or _building_dialog:
		if mobile: return 1.0
		return clampf(get_viewport_rect().size.y / 768.0,1.0,1.3)
	if _building_gameplay and not mobile:
		return 1.5 * clampf(get_viewport_rect().size.y / 900.0,0.65,1.0)
	return 1.25 if mobile else FONT_SCALE

func control_height() -> float:
	if _building_pause or _building_dialog or (_building_gameplay and not mobile):
		var font_size := int(17 * font_scale() * float(game.tweaks.value("ui.text.scale")))
		if _building_pause:
			return ceilf(maxf(clampf(get_viewport_rect().size.y * 0.065,44,56),game.locale.font.get_height(font_size)+2*CONTROL_PADDING.y))
		return ceilf(maxf(clampf(get_viewport_rect().size.y * 0.075,44,64),game.locale.font.get_height(font_size)+2*CONTROL_PADDING.y))
	return 52.0 if mobile else 120.0

func owner_footer_height() -> float:
	return 0.0

func text_label(parent: Node, key: String, font_size := 17, placeholders: Dictionary = {}) -> Label:
	var label := Label.new()
	label.text = t(key,placeholders)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",int(font_size * font_scale() * float(game.tweaks.value("ui.text.scale"))))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func display(label: Label,kind := "heading") -> Label:
	# Titles, headings and large counters use the display pair; body copy uses the UI face.
	label.add_theme_font_override("font",game.locale.title_font if kind == "title" else game.locale.heading_font)
	return label

func button(parent: Node,key: String,action: Callable,primary := false) -> Button:
	var result := Button.new()
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.name = key.replace(".","_")
	result.text = t(key)
	if key == "ui.leaderboard": result.disabled = not game.leaderboard_available()
	result.tooltip_text = result.text
	result.custom_minimum_size = Vector2(0,control_height())
	if _building_pause or _building_dialog or (_building_gameplay and not mobile):
		result.add_theme_font_size_override("font_size",int(17 * font_scale() * float(game.tweaks.value("ui.text.scale"))))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary: candy(result)
	result.mouse_entered.connect(func(): game.audio.play_ui("hover"))
	result.focus_entered.connect(func(): game.audio.play_ui("focus"))
	result.button_down.connect(_squash.bind(weakref(result),true))
	result.button_up.connect(_squash.bind(weakref(result),false))
	result.pressed.connect(func():
		if mobile: dismiss_editor()
		result.grab_focus()
		game.audio.ensure_music_playing()
		game.audio.play_ui("confirm")
		action.call())
	parent.add_child(result)
	controls[key] = result
	return result

## Primary candy button: glossy pink body, stitched seam, cream lettering with a berry outline.
func candy(control: Button,unit := 1.0) -> Button:
	for state in ["normal","hover","pressed","disabled","focus"]:
		control.add_theme_stylebox_override(state,plush("candy",state,unit))
	for color in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
		control.add_theme_color_override(color,CANDY_TEXT)
	control.add_theme_color_override("font_outline_color",CANDY_OUTLINE)
	# Outline scales with the lettering so small (and CJK) labels stay crisp.
	control.add_theme_constant_override("outline_size",clampi(roundi(control.get_theme_font_size("font_size")*0.16),3,6))
	control.add_theme_font_override("font",game.locale.heading_font)
	return control

## Press squash / release pop. Pure presentation; skipped when motion is reduced.
func _squash(reference: WeakRef,down: bool) -> void:
	var control := reference.get_ref() as Control
	if control == null or not control.is_inside_tree() or game.reduced_motion(): return
	control.pivot_offset = control.size*0.5
	var tween := control.create_tween()
	if down:
		tween.tween_property(control,"scale",Vector2(1.03,0.94),0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(control,"scale",Vector2(0.98,1.03),0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(control,"scale",Vector2.ONE,0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _claim_intro(key: String) -> bool:
	if game.reduced_motion() or _intro_seen.has(key): return false
	_intro_seen[key] = true
	return true

## Soft cream curtain that dissolves as a screen transition.
func _curtain(parent: Node,duration := 0.45,color := Color("fbeee6")) -> void:
	var curtain := ColorRect.new()
	curtain.name = "Curtain"
	curtain.color = color
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(curtain)
	var tween := curtain.create_tween()
	tween.tween_property(curtain,"modulate:a",0.0,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(curtain.queue_free)

## Pop a modal frame in: fade the dim, then scale the frame from slightly small (no overshoot
## so tests and small screens never see it exceed its fitted rectangle).
func _pop_in(cover: Control,frame: Control,key: String) -> void:
	if not _claim_intro(key): return
	cover.modulate.a = 0.0
	var fade := cover.create_tween()
	fade.tween_property(cover,"modulate:a",1.0,0.18)
	if frame == null: return
	frame.scale = Vector2.ONE*0.9
	frame.set_deferred("pivot_offset",frame.size*0.5)
	var pop := frame.create_tween()
	pop.tween_callback(func(): if is_instance_valid(frame): frame.pivot_offset = frame.size*0.5)
	pop.tween_property(frame,"scale",Vector2.ONE,0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Small felt label chip ("SCORE", "NEXT"...), hugging its text.
func chip(parent: Node,key: String,kind := "chip",font_size := 13,placeholders: Dictionary = {}) -> Label:
	var label := Label.new()
	label.text = t(key,placeholders)
	label.add_theme_stylebox_override("normal",plush(kind))
	label.add_theme_font_override("font",game.locale.heading_font)
	label.add_theme_font_size_override("font_size",int(font_size*font_scale()*float(game.tweaks.value("ui.text.scale"))))
	label.add_theme_color_override("font_color",Color("7b4a66"))
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

## Keyboard/gamepad prompt keycap, e.g. [Enter] or [Space].
func keycap(parent: Node,text: String,font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_stylebox_override("normal",plush("key"))
	label.add_theme_font_override("font",game.locale.bold_font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

## Dashed stitch divider between HUD groups.
func stitch_divider(parent: Node) -> Control:
	var line := Control.new()
	line.custom_minimum_size.y = 6
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func():
		var x := 2.0
		while x < line.size.x-2.0:
			line.draw_line(Vector2(x,3),Vector2(minf(x+7.0,line.size.x-2.0),3),Color(STITCH,0.65),2.0,true)
			x += 12.0)
	parent.add_child(line)
	return line

func check_button(parent: Node,key: String,value: bool,action: Callable) -> CheckButton:
	var result := CheckButton.new()
	result.text = t(key)
	result.tooltip_text = result.text
	result.custom_minimum_size.y = control_height()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.button_pressed = value
	result.toggled.connect(func(on: bool): game.audio.play_ui("toggle"); action.call(on))
	result.focus_entered.connect(func(): game.audio.play_ui("focus"))
	result.mouse_entered.connect(func(): game.audio.play_ui("hover"))
	parent.add_child(result)
	return result

func row(parent: Node) -> HBoxContainer:
	var result := HBoxContainer.new()
	parent.add_child(result)
	return result

func column(parent: Node) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func panel(parent: Node,rect: Rect2,art := false,art_padding := ART_SAFE_INSETS) -> VBoxContainer:
	var outer: Control = Control.new() if art else PanelContainer.new()
	if not art: outer.add_theme_stylebox_override("panel",_margins(plush("felt"),18,14))
	parent.add_child(outer)
	outer.set_meta("ui_safe_insets",art_padding if art else Vector4(22,18,22,18))
	outer.set_meta("ui_frame_kind","ribbon" if art else "rounded")
	_rect(outer,rect)
	if art:
		var frame := NinePatchRect.new()
		frame.texture = PAUSE_ART
		frame.patch_margin_left = 144
		frame.patch_margin_right = 144
		frame.patch_margin_top = 144
		frame.patch_margin_bottom = 96
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var padding := MarginContainer.new()
	var sides := ["left","top","right","bottom"]
	for index in range(sides.size()):
		padding.add_theme_constant_override("margin_"+sides[index],int(art_padding[index]) if art else 4)
	outer.add_child(padding)
	if art: padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padding.add_child(scroll)
	var content := column(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return content

func rebuild() -> void:
	if not is_node_ready() or is_queued_for_deletion(): return
	if _updating:
		_queue_refresh(true)
		return
	_updating = true
	var focused := get_viewport().gui_get_focus_owner()
	var surface := active_surface()
	var valid_focus := is_instance_valid(focused) and focused.is_visible_in_tree() and is_instance_valid(surface) and (surface == focused or surface.is_ancestor_of(focused))
	var focus_name := String(focused.name) if valid_focus else ""
	var epoch := _focus_epoch
	var edit_text: String = focused.text if focused is LineEdit else ""
	var edit_caret: int = focused.caret_column if focused is LineEdit else 0
	var scroll_offsets: Dictionary = {}
	if mobile and is_instance_valid(surface) and not focused is LineEdit:
		for scroll in surface.find_children("*","ScrollContainer",true,false):
			if scroll.is_visible_in_tree(): scroll_offsets[str(scroll.name)] = scroll.scroll_vertical
		if not _pending_scroll_offsets.is_empty() and _pending_scroll_route == game.routes.route+"/"+game.routes.modal():
			scroll_offsets = _pending_scroll_offsets.duplicate()
	mobile = game.device.use_mobile_hud(get_viewport_rect().size)
	_theme()
	current_route = ""
	_sync_routes()
	if mobile and not scroll_offsets.is_empty():
		if _scroll_restore_callback.is_valid() and get_tree().process_frame.is_connected(_scroll_restore_callback):
			get_tree().process_frame.disconnect(_scroll_restore_callback)
		_pending_scroll_offsets = scroll_offsets
		_pending_scroll_route = game.routes.route+"/"+game.routes.modal()
		_scroll_restore_callback = _restore_scroll_offsets.bind(weakref(active_surface()),scroll_offsets,epoch)
		get_tree().process_frame.connect(_scroll_restore_callback,CONNECT_ONE_SHOT)
	if focus_name != "":
		var replacement := active_surface().find_child(focus_name,true,false) as Control
		if replacement != null:
			if replacement is LineEdit:
				replacement.text = edit_text
				# A second resize can rebuild again before deferred focus runs.
				# Restore now as well, so that rebuild sees the active editor.
				_restore_edit_focus(weakref(replacement),edit_caret,epoch)
				call_deferred("_restore_edit_focus",weakref(replacement),edit_caret,epoch)
			else: call_deferred("_focus_if_valid",weakref(replacement))
	_updating = false

func active_surface() -> Control:
	if not modals.is_empty() and is_instance_valid(modals.back()): return modals.back()
	return base

func _restore_scroll_offsets(reference: WeakRef,offsets: Dictionary,epoch: int) -> void:
	_pending_scroll_offsets = {}
	var surface = reference.get_ref()
	if epoch != _focus_epoch or not is_instance_valid(surface) or surface != active_surface(): return
	for scroll in surface.find_children("*","ScrollContainer",true,false):
		if offsets.has(str(scroll.name)): scroll.scroll_vertical = int(offsets[str(scroll.name)])

func dismiss_editor() -> void:
	_focus_epoch += 1
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit: focused.release_focus()
	if mobile and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()

func _restore_edit_focus(reference: WeakRef,caret: int,epoch: int) -> void:
	var field = reference.get_ref()
	if epoch != _focus_epoch or not is_instance_valid(field) or not field.is_inside_tree() or not field.is_visible_in_tree(): return
	if not field.editable: return
	var surface := active_surface()
	if not is_instance_valid(surface) or not surface.is_ancestor_of(field): return
	field.caret_column = mini(caret,field.text.length())
	field.grab_focus()

func sync_routes() -> void:
	if not is_node_ready() or is_queued_for_deletion(): return
	if _updating:
		_queue_refresh(false)
		return
	_updating = true
	_sync_routes()
	_updating = false

func _queue_refresh(rebuild_all: bool) -> void:
	if is_queued_for_deletion(): return
	_rebuild_queued = _rebuild_queued or rebuild_all
	if _refresh_queued: return
	_refresh_queued = true
	call_deferred("_flush_refresh")

func _flush_refresh() -> void:
	var rebuild_all := _rebuild_queued
	_refresh_queued = false
	_rebuild_queued = false
	if not is_inside_tree() or is_queued_for_deletion(): return
	if rebuild_all: rebuild()
	else: sync_routes()

func _clear_view() -> void:
	_hud_cards.clear()
	_hud_layout_queued = false
	_hud_board_rect = Rect2()
	# Retiring controls emit focus/tree/layout signals; invalidate references first.
	metrics.clear()
	controls.clear()
	collection_views.clear()
	modals.clear()
	modal_kinds.clear()
	base = null
	filter = null
	for node in get_children():
		remove_child(node)
		node.queue_free()

func _sync_routes() -> void:
	var view := get_viewport_rect().size
	mobile = game.device.use_mobile_hud(view)
	compact = mobile or view.x / view.y < 1.3
	margin = 16 if compact else 28
	if game.routes.route != _intro_route:
		_intro_seen.clear()
		_intro_route = game.routes.route
	var open_kinds := {}
	for entry in game.routes.stack: open_kinds["modal:"+str(entry.kind)] = true
	for key in _intro_seen.keys():
		if str(key).begins_with("modal:") and not open_kinds.has(key): _intro_seen.erase(key)
	if current_route != game.routes.route:
		_clear_view()
		current_route = game.routes.route
		base = Control.new()
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(base)
		if current_route == "title": _title(view)
		elif current_route in ["gameplay","debrief"]:
			_building_gameplay = true
			_gameplay(view)
			_building_gameplay = false
			if current_route == "gameplay" and _claim_intro("route:gameplay"): _curtain(base,0.35)
			if current_route == "debrief": _debrief(view)
		elif current_route == "error":
			_building_dialog = not mobile
			base.theme = _dialog_theme()
			var body := panel(base,center_rect(view,560,360))
			display(text_label(body,"error.title",28))
			text_label(body,game.error_key)
			button(body,"ui.title",game.return_title,true)
			_building_dialog = false
		filter = ColorRect.new()
		filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(filter)
		apply_presentation()
		if current_route in ["title","debrief","error"]:
			var first := _first_focus(base)
			if first != null: call_deferred("_focus_if_valid",weakref(first))
	while modals.size() > game.routes.stack.size():
		var old: Control = modals.pop_back()
		modal_kinds.pop_back()
		remove_child(old)
		old.queue_free()
	while modals.size() < game.routes.stack.size():
		var kind: String = game.routes.stack[modals.size()].kind
		var overlay := _build_modal(kind,view)
		modals.append(overlay)
		modal_kinds.append(kind)
	for index in range(modals.size()): modals[index].visible = index == modals.size()-1
	if not modals.is_empty(): modals.back().move_to_front()
	if is_instance_valid(base): base.visible = not mobile or modals.is_empty()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.mushiesSetLocale?.(%s)" % JSON.stringify(game.locale.locale))


func center_rect(view: Vector2,width: float,height: float) -> Rect2:
	if mobile:
		var inset: Vector4 = game.device.safe_insets
		var available := Rect2(inset.x+12,inset.y+12,view.x-inset.x-inset.z-24,view.y-inset.y-inset.w-24)
		var panel_size := Vector2(minf(width,available.size.x),minf(height,available.size.y))
		return Rect2(available.get_center()-panel_size*0.5,panel_size)
	var available := Rect2(margin,margin,view.x-2*margin,view.y-2*margin-owner_footer_height())
	var panel_size := Vector2(minf(width,available.size.x),minf(height,available.size.y))
	return Rect2(available.get_center()-panel_size*0.5,panel_size)

## Title screen: the claw-machine key art is the hero. A lilac felt marquee with chasing
## bulbs carries the logo, a ribbon carries the tagline, and the menu is a list of items with
## a gliding heart cursor instead of a card of bordered boxes.
func _title_unit(view: Vector2) -> float:
	if mobile: return clampf(minf(view.x/390.0,view.y/844.0),0.72,1.4)
	var unit := clampf(minf(view.x/1440.0,view.y/900.0),0.5,1.6)
	return maxf(0.3,minf(unit,(view.y-owner_footer_height()-24.0)/800.0))

func _title_art_rect(view: Vector2) -> Rect2:
	var texture := Vector2(TITLE_ART.get_size())
	var cover := maxf(view.x/texture.x,view.y/texture.y)
	var art_size := texture*cover
	# Portrait screens centre the claw machine instead of the empty wall.
	var focus := Vector2(0.74 if view.x < view.y else 0.5,0.5)
	var offset := (view*0.5-art_size*focus).clamp(view-art_size,Vector2.ZERO)
	return Rect2(offset,art_size)

func _art_to_screen(art: Rect2,texel: Rect2) -> Rect2:
	var k := art.size.x/float(TITLE_ART.get_width())
	return Rect2(art.position+texel.position*k,texel.size*k)

func _title_scrim(rect: Rect2,radial: bool,strength: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0,Color(CREAM,strength))
	gradient.set_color(1,Color(CREAM,0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	if radial:
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5,0.5)
		texture.fill_to = Vector2(1.0,0.5)
	else:
		texture.fill_from = Vector2(0.5,1.0)
		texture.fill_to = Vector2(0.5,0.0)
	var scrim := TextureRect.new()
	scrim.texture = texture
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(scrim)
	_rect(scrim,rect)
	return scrim

func _title(view: Vector2) -> void:
	var unit := _title_unit(view)
	var reduced: bool = game.reduced_motion()
	var intro := _claim_intro("title")
	var text_scale := float(game.tweaks.value("ui.text.scale"))
	var art_rect := _title_art_rect(view)
	var art := TextureRect.new()
	art.name = "TitleArt"
	art.texture = TITLE_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(art)
	_rect(art,art_rect)
	art.pivot_offset = view*0.5-art_rect.position
	if not reduced:
		# Slow "breathing" push-in on the key art.
		var drift := art.create_tween().set_loops()
		drift.tween_property(art,"scale",Vector2.ONE*1.025,7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(art,"scale",Vector2.ONE,7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var sparkles := TitleFx.new()
	sparkles.name = "TitleSparkles"
	sparkles.mode = "sparkle"
	sparkles.area = _art_to_screen(art_rect,Rect2(711,160,436,329))
	sparkles.unit = unit
	sparkles.reduced = reduced
	base.add_child(sparkles)
	var inset: Vector4 = game.device.safe_insets if mobile else Vector4.ZERO
	var col_w: float
	var col_x: float
	var top: float
	if mobile:
		col_w = minf(view.x-inset.x-inset.z-32.0,400.0*unit)
		col_x = inset.x+roundf((view.x-inset.x-inset.z-col_w)*0.5)
		top = inset.y+roundf(14.0*unit)
	else:
		col_w = roundf(minf(500.0*unit,view.x*0.44))
		col_x = roundf(maxf(margin,72.0*unit))
		top = roundf(maxf(16.0,40.0*unit))
		_title_scrim(Rect2(col_x-220.0*unit,-120.0*unit,col_w+440.0*unit,view.y+240.0*unit),true,0.7)
	var hearts := TitleFx.new()
	hearts.name = "TitleHearts"
	hearts.mode = "hearts"
	# Hearts rise in the open wall gutter beside the menu, never across its lettering.
	hearts.area = Rect2(col_x+col_w+16.0*unit,top+60.0*unit,150.0*unit,view.y-top-60.0*unit) if not mobile else Rect2(view.x*0.62,top+80.0*unit,view.x*0.34,view.y*0.4)
	hearts.unit = unit
	hearts.reduced = reduced
	base.add_child(hearts)

	# Marquee + logo lockup.
	var marquee := TitleMarquee.new()
	marquee.name = "TitleMarquee"
	marquee.unit = unit
	marquee.reduced = reduced
	marquee.plaque = plush("lilac","normal",unit)
	var marquee_rect := Rect2(col_x,top,col_w,roundf((124.0 if mobile else 188.0)*unit))
	base.add_child(marquee)
	_rect(marquee,marquee_rect)
	var logo := Label.new()
	logo.name = "TitleLogo"
	logo.text = t("app.title")
	logo.add_theme_font_override("font",game.locale.title_font)
	var logo_size := int((70.0 if mobile else 104.0)*unit)
	while logo_size > 20 and game.locale.title_font.get_string_size(logo.text,HORIZONTAL_ALIGNMENT_LEFT,-1,logo_size).x > marquee_rect.size.x-48.0*unit:
		logo_size -= 1
	logo.add_theme_font_size_override("font_size",logo_size)
	logo.add_theme_color_override("font_color",Color.WHITE)
	logo.add_theme_color_override("font_outline_color",Color("6a3a59"))
	logo.add_theme_constant_override("outline_size",maxi(6,int(15*unit)))
	logo.add_theme_color_override("font_shadow_color",LOGO_SHADOW)
	logo.add_theme_constant_override("shadow_offset_x",0)
	logo.add_theme_constant_override("shadow_offset_y",maxi(3,int(7*unit)))
	logo.add_theme_constant_override("shadow_outline_size",maxi(6,int(15*unit)))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marquee.add_child(logo)
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.offset_bottom = -6.0*unit
	var shine := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = LOGO_SHADER
	shine.shader = shader
	shine.set_shader_parameter("size",marquee_rect.size)
	logo.material = shine
	logo.pivot_offset = marquee_rect.size*0.5
	if not reduced:
		var sweep := logo.create_tween().set_loops()
		sweep.tween_interval(1.1)
		sweep.tween_method(func(value: float): shine.set_shader_parameter("progress",value),-0.3,1.3,1.0).set_trans(Tween.TRANS_SINE)
		sweep.tween_interval(2.6)
		var breathe := logo.create_tween().set_loops()
		breathe.tween_property(logo,"scale",Vector2.ONE*1.03,1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		breathe.tween_property(logo,"scale",Vector2.ONE,1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Tagline ribbon overlapping the marquee's lower edge.
	var ribbon := TitleRibbon.new()
	ribbon.name = "TitleRibbon"
	ribbon.unit = unit
	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.text = t("app.tagline")
	tagline.add_theme_font_override("font",game.locale.heading_font)
	tagline.add_theme_font_size_override("font_size",int((16.0 if mobile else 21.0)*unit*text_scale))
	tagline.add_theme_color_override("font_color",CANDY_TEXT)
	tagline.add_theme_color_override("font_outline_color",CANDY_OUTLINE)
	tagline.add_theme_constant_override("outline_size",maxi(3,int(5*unit)))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_child(tagline)
	var ribbon_h := roundf((36.0 if mobile else 46.0)*unit)
	var ribbon_w := clampf(tagline.get_minimum_size().x+56.0*unit,col_w*0.56,col_w-64.0*unit)
	var ribbon_rect := Rect2(col_x+roundf((col_w-ribbon_w)*0.5),marquee_rect.end.y-roundf(16.0*unit),ribbon_w,ribbon_h)
	base.add_child(ribbon)
	_rect(ribbon,ribbon_rect)
	tagline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ribbon.pivot_offset = ribbon_rect.size*0.5

	# Menu list: one candy primary action, then text items with a shared heart cursor.
	var cursor := MenuCursor.new()
	cursor.name = "TitleCursor"
	cursor.unit = unit
	cursor.reduced = reduced
	cursor.pill = PlushStyle.make({"fill":Color(CREAM,0.94),"rim":Color("f1d6e1"),"rim_width":1,"radius":int(16*unit),"gloss":0.4,
		"stitch":Color(STITCH,0.55),"stitch_inset":5.0*unit,"stitch_dash":6.0*unit,"stitch_gap":4.0*unit,"stitch_width":maxf(1.0,1.5*unit),
		"shadow":Color(PLUM,0.16),"shadow_size":int(8*unit),"shadow_offset":Vector2(0,3*unit)})
	base.add_child(cursor)
	var menu := VBoxContainer.new()
	menu.name = "TitleMenu"
	menu.add_theme_constant_override("separation",int((7.0 if mobile else 10.0)*unit))
	base.add_child(menu)
	var side := roundf((30.0 if mobile else 38.0)*unit)
	var items: Array[BaseButton] = []
	items.append(_title_item(button(menu,"ui.start",func(): game.start_stage(0),true),true,unit))
	if game.device.local_splitscreen_allowed(view):
		items.append(_title_item(button(menu,"ui.multiplayer",func(): game.open_multiplayer()),false,unit))
	items.append(_title_item(button(menu,"ui.leaderboard",func(): game.open_modal("leaderboard")),false,unit))
	items.append(_title_item(button(menu,"ui.help",func(): game.open_modal("help")),false,unit))
	items.append(_title_item(button(menu,"ui.settings",func(): game.open_modal("settings")),false,unit))
	cursor.items = items
	var gap := Control.new()
	gap.custom_minimum_size.y = roundf((4.0 if mobile else 12.0)*unit)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(gap)
	var footer: Array[Control] = []
	footer.append(language_row(menu,unit))
	var licenses := button(menu,"ui.open_source_licenses",OpenSourceLicenses.open.bind(self))
	licenses.name = "OpenSourceLicensesButton"
	licenses.custom_minimum_size.y = maxf(28.0,30.0*unit)
	licenses.add_theme_font_size_override("font_size",int(maxf(12.0,14.0*unit)*text_scale))
	licenses.add_theme_color_override("font_color",MUTED)
	licenses.add_theme_color_override("font_hover_color",INK)
	licenses.add_theme_color_override("font_focus_color",INK)
	licenses.add_theme_color_override("font_pressed_color",INK)
	licenses.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	licenses.autowrap_mode = TextServer.AUTOWRAP_OFF
	for state in ["normal","hover","pressed","disabled"]:
		licenses.add_theme_stylebox_override(state,_margins(PlushStyle.make({"fill":Color(CREAM,{"normal":0.0,"hover":0.7,"pressed":0.9,"disabled":0.0}[state]),"radius":99}),14,3))
	licenses.add_theme_stylebox_override("focus",_margins(PlushStyle.make({"fill":Color(0,0,0,0),"rim":FOCUS_RING,"rim_width":2,"radius":99}),14,3))
	footer.append(licenses)
	if not mobile:
		var hints := HBoxContainer.new()
		hints.name = "TitleHints"
		hints.alignment = BoxContainer.ALIGNMENT_CENTER
		hints.add_theme_constant_override("separation",int(6*unit))
		hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu.add_child(hints)
		var hint_size := int(maxf(11.0,13.0*unit))
		keycap(hints,"↑↓",hint_size)
		_hint_label(hints,"ui.hint_move",hint_size)
		var spacer := Control.new()
		spacer.custom_minimum_size.x = 10*unit
		hints.add_child(spacer)
		keycap(hints,t("ui.key_enter"),hint_size)
		_hint_label(hints,"ui.hint_confirm",hint_size)
		footer.append(hints)
	var menu_w := col_w-side*2.0
	var menu_h := menu.get_combined_minimum_size().y
	var menu_y := ribbon_rect.end.y+roundf(26.0*unit)
	if mobile:
		var floor_y := view.y-inset.w-owner_footer_height()-12.0
		menu_y = maxf(ribbon_rect.end.y+8.0,floor_y-menu_h)
		_title_scrim(Rect2(0,menu_y-120.0*unit,view.x,view.y-menu_y+120.0*unit),false,0.94)
		base.move_child(base.get_child(base.get_child_count()-1),hearts.get_index()+1)
	_rect(menu,Rect2(col_x+side,menu_y,menu_w,menu_h))
	if intro: _title_intro(marquee,ribbon,items,footer,[sparkles,hearts],view)

func _hint_label(parent: Node,key: String,font_size: int) -> Label:
	var label := Label.new()
	label.text = t(key)
	label.add_theme_font_override("font",game.locale.medium_font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",MUTED)
	label.add_theme_color_override("font_outline_color",Color(CREAM,0.9))
	label.add_theme_constant_override("outline_size",4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _title_item(control: Button,primary: bool,unit: float) -> Button:
	var text_scale := float(game.tweaks.value("ui.text.scale"))
	control.add_theme_font_override("font",game.locale.heading_font)
	if primary:
		control.add_theme_font_size_override("font_size",int((23.0 if mobile else 30.0)*unit*text_scale))
		candy(control,unit)
		control.set_meta("cursor_pill",false)
		control.custom_minimum_size.y = roundf(maxf(52.0,(60.0 if mobile else 72.0)*unit))
		return control
	control.custom_minimum_size.y = roundf(maxf(44.0,(46.0 if mobile else 50.0)*unit))
	control.add_theme_font_size_override("font_size",int((19.0 if mobile else 24.0)*unit*text_scale))
	control.add_theme_color_override("font_outline_color",Color(CREAM,0.95))
	control.add_theme_constant_override("outline_size",0 if mobile else maxi(4,int(8*unit)))
	control.add_theme_color_override("font_disabled_color",Color(MUTED,0.55))
	# Touch layouts keep a visible felt pill per item; the cursor adds the selection state.
	for state in ["normal","hover","pressed","disabled","focus"]:
		var fill := Color(0,0,0,0)
		if mobile and state != "focus": fill = Color(CREAM,0.5 if state == "disabled" else 0.82)
		if state == "pressed": fill = Color("fbe1e8")
		var box := PlushStyle.make({"fill":fill,"radius":int(16*unit),"rim":Color("efd8e2") if mobile and state != "focus" else Color(0,0,0,0),"rim_width":1 if mobile else 0})
		control.add_theme_stylebox_override(state,_margins(box,CONTROL_PADDING.x,4,4))
	return control

func _title_intro(marquee: Control,ribbon: Control,items: Array[BaseButton],footer: Array[Control],ambient: Array,view: Vector2) -> void:
	_curtain(base,0.5)
	var home := marquee.position
	marquee.position.y = -marquee.size.y-40.0
	var drop := marquee.create_tween()
	drop.tween_interval(0.08)
	drop.tween_property(marquee,"position",home,0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ribbon.scale = Vector2(0.2,0.2)
	ribbon.modulate.a = 0.0
	var pop := ribbon.create_tween().set_parallel(true)
	pop.tween_property(ribbon,"scale",Vector2.ONE,0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.5)
	pop.tween_property(ribbon,"modulate:a",1.0,0.2).set_delay(0.5)
	for item in items: item.modulate.a = 0.0
	for control in footer: control.modulate.a = 0.0
	for node in ambient:
		node.modulate.a = 0.0
		node.create_tween().tween_property(node,"modulate:a",1.0,0.8).set_delay(0.3)
	# Slide menu items in once their container has placed them.
	(func():
		for index in range(items.size()):
			var item := items[index]
			if not is_instance_valid(item): continue
			var x := item.position.x
			item.position.x = x-44.0
			var slide := item.create_tween().set_parallel(true)
			var delay := 0.62+index*0.07
			slide.tween_property(item,"position:x",x,0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
			slide.tween_property(item,"modulate:a",1.0,0.22).set_delay(delay)
		for index in range(footer.size()):
			var control := footer[index]
			if is_instance_valid(control):
				control.create_tween().tween_property(control,"modulate:a",1.0,0.35).set_delay(1.0+index*0.06)
	).call_deferred()

func language_row(parent: Node,unit := 1.0) -> Control:
	var line := HBoxContainer.new()
	line.name = "LanguageRow"
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation",int(10*unit))
	parent.add_child(line)
	var text_scale := float(game.tweaks.value("ui.text.scale"))
	var label := text_label(line,"ui.language",16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size",int(maxf(13.0,15.0*unit)*text_scale))
	label.add_theme_font_override("font",game.locale.medium_font)
	label.add_theme_color_override("font_color",MUTED)
	label.add_theme_color_override("font_outline_color",Color(CREAM,0.9))
	label.add_theme_constant_override("outline_size",0 if mobile else 4)
	var select := OptionButton.new()
	select.name = "LanguageSelect"
	select.alignment = HORIZONTAL_ALIGNMENT_CENTER
	select.custom_minimum_size = Vector2(roundf(maxf(150.0,190.0*unit)),roundf(maxf(44.0 if mobile else 36.0,42.0*unit)))
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL if mobile else Control.SIZE_SHRINK_CENTER
	select.add_theme_font_size_override("font_size",int(maxf(14.0,17.0*unit)*text_scale))
	select.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# A candy chip; the leading gutter mirrors Godot's trailing arrow so text stays centred.
	var arrow_space: float = select.get_theme_icon("arrow").get_width()+maxi(0,select.get_theme_constant("h_separation"))
	var fills := {"normal":Color(CREAM,0.94),"hover":Color("fffdf9"),"pressed":Color("fbe1e8"),"disabled":Color(CREAM,0.6),"focus":Color(0,0,0,0)}
	for state in fills:
		var focus: bool = state == "focus"
		var box := PlushStyle.make({"fill":fills[state],"radius":99,"rim":FOCUS_RING if focus else Color("e7cbd8"),"rim_width":2 if focus else 1,
			"glow":Color(CANDY,0.45 if focus else 0.0),"glow_size":int(6*unit) if focus else 0,"gloss":0.0 if focus else 0.45,
			"shadow":Color(PLUM,0.0 if focus else 0.14),"shadow_size":int(5*unit),"shadow_offset":Vector2(0,2*unit)})
		var horizontal := roundf(14.0*unit)
		box.content_margin_left = horizontal+arrow_space
		box.content_margin_right = horizontal
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		select.add_theme_stylebox_override(state,box)
	select.add_item(t("ui.english"))
	select.add_item(t("ui.chinese"))
	select.selected = 1 if game.locale.locale == "zh_CN" else 0
	select.item_selected.connect(func(index: int): game.audio.play_ui("select"); game.setting("locale","zh_CN" if index else "en"))
	select.pressed.connect(func(): game.audio.play_ui("open"))
	line.add_child(select)
	select.get_popup().about_to_popup.connect(_prepare_language_popup.bind(weakref(select)))
	return line

func _prepare_language_popup(reference: WeakRef) -> void:
	var select := reference.get_ref() as OptionButton
	if not is_instance_valid(select): return
	var popup := select.get_popup()
	# Embedded popups inherit the canvas transform; native windows may not.
	var popup_scale := select.get_global_transform().get_scale().abs() if popup.is_embedded() else Vector2.ONE
	popup_scale = popup_scale.max(Vector2(0.01,0.01))
	var screen_font := maxf(14,select.get_theme_font_size("font_size")*select.get_global_transform().get_scale().y)
	popup.add_theme_font_size_override("font_size",ceili(screen_font/popup_scale.y))
	popup.add_theme_constant_override("v_separation",ceili(22/popup_scale.y))
	var box := plush("felt")
	box.content_margin_left = ceilf((CONTROL_PADDING.x+4)/popup_scale.x)
	box.content_margin_right = box.content_margin_left
	box.content_margin_top = ceilf((CONTROL_PADDING.y+2)/popup_scale.y)
	box.content_margin_bottom = box.content_margin_top
	popup.add_theme_stylebox_override("panel",box)

func _metric(parent: Node,id: String,key: String,values: Dictionary = {},font_size := 19) -> Label:
	var label := text_label(parent,key,font_size,values)
	metrics[id] = label
	return label

func toy_card(parent: Node,tier: int,key: String) -> TextureRect:
	# Toy portrait in a stitched felt badge, a label chip and the toy name.
	var line := row(parent)
	line.add_theme_constant_override("separation",12)
	var icon_size := clampf(get_viewport_rect().size.y * 0.07,44,68)
	var badge := Control.new()
	badge.name = key.capitalize()+"Badge"
	badge.custom_minimum_size = Vector2(icon_size,icon_size)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint := Color("fde6ec") if key == "goal" else Color("efe5f9")
	badge.draw.connect(func():
		var center := badge.size*0.5
		var radius := minf(center.x,center.y)
		badge.draw_circle(center+Vector2(0,2),radius,Color(PLUM,0.12),true,-1.0,true)
		badge.draw_circle(center,radius,tint,true,-1.0,true)
		badge.draw_circle(center,radius,Color(1,1,1,0.9),false,1.5,true)
		for index in range(18):
			var start := TAU*index/18.0
			badge.draw_arc(center,radius-4.5,start,start+TAU/36.0,3,Color(STITCH,0.75),1.5,true))
	line.add_child(badge)
	var texture := TextureRect.new()
	texture.texture = game.toy_texture(tier)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(texture)
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT,SIDE_TOP]: texture.set_offset(side,5)
	for side in [SIDE_RIGHT,SIDE_BOTTOM]: texture.set_offset(side,-5)
	var info := column(line)
	info.add_theme_constant_override("separation",2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if key == "goal":
		metrics["stage"] = chip(info,"hud.stage","chip",12,{"index":game.session.goals_reached+1})
	else:
		chip(info,"hud.next_label","chip_lilac",12)
	var name_label := _metric(info,key,"toy.bomb",{},16)
	name_label.text = _toy_readout(key)
	name_label.add_theme_font_override("font",game.locale.medium_font)
	metrics[key+"_texture"] = texture
	return texture

func _toy_readout(key: String) -> String:
	if key == "next": return game.toy_name(game.next_tier)
	var toy: String = game.toy_name(game.session.goal_tier)
	return t("hud.goal_value",{"toy":toy,"count":game.session.goal_quantity}) if game.session.goal_quantity > 1 else toy

func _counter(label: Label) -> Label:
	# Big HUD numbers: display face with a soft candy drop for depth.
	label.add_theme_color_override("font_shadow_color",Color(CANDY,0.5))
	label.add_theme_constant_override("shadow_offset_x",0)
	label.add_theme_constant_override("shadow_offset_y",3)
	return label

func _meter(parent: Node) -> Control:
	# Segmented, stitched countdown meter under the timer.
	var meter := Control.new()
	meter.name = "TimeMeter"
	meter.custom_minimum_size.y = 12
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := PlushStyle.make({"fill":Color("f1e3ee"),"rim":Color("dcc6dd"),"rim_width":1,"radius":6,"shade":0.08})
	var calm := PlushStyle.make({"fill":Color("c7a4e6"),"radius":4,"gloss":0.35})
	var hurry := PlushStyle.make({"fill":Color("e8637f"),"radius":4,"gloss":0.35})
	meter.draw.connect(func():
		var budget := maxf(1.0,game.session.time_budget())
		var remaining: float = game.session.remaining_time()
		var fraction := clampf(remaining/budget,0.0,1.0)
		var rect := Rect2(Vector2(0,2),Vector2(meter.size.x,9))
		meter.draw_style_box(track,rect)
		if fraction > 0.0:
			var fill_rect := Rect2(rect.position+Vector2(1,1),Vector2(maxf(7.0,(rect.size.x-2)*fraction),rect.size.y-2))
			meter.draw_style_box(hurry if remaining <= 30.0 else calm,fill_rect)
		for index in range(1,6):
			var x := rect.position.x+rect.size.x*index/6.0
			meter.draw_line(Vector2(x,rect.position.y+2),Vector2(x,rect.end.y-2),Color(1,1,1,0.7),1.0))
	parent.add_child(meter)
	return meter

func _key_hint(control: Button,text: String) -> Label:
	# Controller/keyboard prompt tucked into the right end of an action button.
	var cap := keycap(control,text,int(12*font_scale()*float(game.tweaks.value("ui.text.scale"))))
	cap.anchor_left = 1.0
	cap.anchor_right = 1.0
	cap.anchor_top = 0.5
	cap.anchor_bottom = 0.5
	cap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cap.grow_vertical = Control.GROW_DIRECTION_BOTH
	cap.offset_left = -14
	cap.offset_right = -14
	cap.offset_top = -3
	cap.offset_bottom = -3
	return cap

func _collection(parent: Node) -> void:
	var heading := display(text_label(parent,"hud.discovery",14,{"count":game.discovered.count(true)}))
	var icons: Array[TextureRect] = []
	for tier in range(11):
		var line := row(parent)
		var icon := TextureRect.new()
		icon.texture = PlushieBody.TEXTURES[tier]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(54,54)
		line.add_child(icon)
		icons.append(icon)
		text_label(line,"toy.%d" % tier,14)
	collection_views.append({"heading":weakref(heading),"icons":icons})

func goal_text() -> String:
	var toy: String = game.toy_name(game.session.goal_tier)
	return t("hud.goal_count",{"toy":toy,"count":game.session.goal_quantity}) if game.session.goal_quantity > 1 else t("hud.goal",{"toy":toy})

func _gameplay(view: Vector2) -> void:
	if mobile:
		_mobile_gameplay(view)
	elif not compact:
		var side_width := clampf(view.x*0.28,300,460)
		# Cards start at their minimum; measured content owns their final height.
		var stats := panel(base,Rect2(margin,margin,side_width,0))
		_track_hud_card("stats",stats)
		stats.add_theme_constant_override("separation",6)
		# Counters: chip label over a big display number; the timer carries a meter.
		var counters := row(stats)
		counters.add_theme_constant_override("separation",14)
		var score_box := column(counters)
		score_box.size_flags_stretch_ratio = 1.5
		score_box.add_theme_constant_override("separation",0)
		chip(score_box,"hud.score_label")
		_counter(display(_metric(score_box,"score","hud.score_value",{"score":game.score},24)))
		var time_box := column(counters)
		time_box.add_theme_constant_override("separation",0)
		chip(time_box,"hud.time_label","chip_lilac")
		_counter(display(_metric(time_box,"time","hud.time_short",{"time":"3:00"},24)))
		_time_meter = _meter(time_box)
		stitch_divider(stats)
		toy_card(stats,game.session.goal_tier,"goal")
		toy_card(stats,game.next_tier,"next")
		var drops := _metric(stats,"drops","hud.drops",{"count":game.drop_count},12)
		drops.add_theme_color_override("font_color",MUTED)
		drops.add_theme_font_override("font",game.locale.heading_font)
		drops.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var actions := panel(base,Rect2(margin,margin,side_width,0))
		_track_hud_card("actions",actions)
		_key_hint(button(actions,"ui.drop",func(): game.request_drop(),true),t("ui.key_space"))
		_key_hint(button(actions,"ui.pause",game.toggle_pause),t("ui.key_esc"))
		button(actions,"ui.collection",func(): game.open_modal("collection"))
		var collection_width := clampf(view.x*0.22,420,620) if view.x >= 2200 else 0.0
		if collection_width > 0:
			var collection := panel(base,Rect2(view.x-margin-collection_width,margin,collection_width,view.y-margin*2-owner_footer_height()))
			_track_hud_card("collection",collection)
			_collection(collection)
	else:
		var top := panel(base,Rect2(margin,margin,minf(view.x-2*margin,960),0))
		_track_hud_card("top",top)
		var line := row(top)
		display(_metric(line,"score","hud.score",{"score":game.score},20))
		var time_label := display(_metric(line,"time","hud.time_short",{"time":"3:00"},17))
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_label.size_flags_horizontal = Control.SIZE_FILL
		time_label.custom_minimum_size.x = 94
		_metric(top,"goal","hud.goal",{"toy":game.toy_name(game.session.goal_tier)},17)
		var lower := panel(base,Rect2(margin,margin,minf(view.x-2*margin,960),0))
		_track_hud_card("lower",lower)
		_metric(lower,"next","hud.next",{"toy":game.toy_name(game.next_tier)},16)
		var aim_row := row(lower)
		var left := button(aim_row,"ui.left",func(): pass)
		var drop := button(aim_row,"ui.drop",func(): game.request_drop(),true)
		var right := button(aim_row,"ui.right",func(): pass)
		left.text = t("ui.arrow_left")
		left.tooltip_text = t("ui.left")
		right.text = t("ui.arrow_right")
		right.tooltip_text = t("ui.right")
		drop.text = t("ui.drop_short")
		left.button_down.connect(func(): game.held_axis = -1)
		left.button_up.connect(func(): game.held_axis = 0)
		right.button_down.connect(func(): game.held_axis = 1)
		right.button_up.connect(func(): game.held_axis = 0)
		drop.custom_minimum_size.x = 130
		var menus := row(lower)
		var pause := button(menus,"ui.pause",game.toggle_pause)
		pause.size_flags_horizontal = Control.SIZE_FILL
		pause.custom_minimum_size.x = 125
		button(menus,"ui.settings",func(): game.open_modal("settings"))
	if not mobile: _layout_gameplay_cards()
	if not mobile: _queue_hud_layout()

func _track_hud_card(role: String,body: VBoxContainer) -> void:
	var frame: Node = body.get_parent()
	while frame != null and not frame is PanelContainer: frame = frame.get_parent()
	if frame == null: return
	frame.name = "GameplayHUD_"+role
	_hud_cards[role] = {"body":body,"frame":frame}
	body.minimum_size_changed.connect(_queue_hud_layout)

func _queue_hud_layout() -> void:
	if _hud_layout_queued or mobile or _hud_cards.is_empty() or not is_inside_tree() or is_queued_for_deletion(): return
	_hud_layout_queued = true
	_layout_gameplay_cards.call_deferred()

func _fit_hud_card(role: String,at: Vector2,width: float,maximum_height: float) -> Rect2:
	var card: Dictionary = _hud_cards[role]
	var body: VBoxContainer = card.body
	var frame: PanelContainer = card.frame
	if not is_instance_valid(body) or not is_instance_valid(frame): return Rect2()
	# panel() contributes its style insets plus the four-pixel inner margin.
	var box: StyleBox = frame.get_theme_stylebox("panel")
	var insets := box.get_content_margin(SIDE_TOP)+box.get_content_margin(SIDE_BOTTOM)+8.0
	var desired := ceilf(body.get_combined_minimum_size().y+insets)
	var rect := Rect2(at,Vector2(width,minf(desired,maxf(insets+24,maximum_height))))
	if not frame.position.is_equal_approx(rect.position): frame.position = rect.position
	if not frame.size.is_equal_approx(rect.size): frame.size = rect.size
	frame.set_meta("hud_content_height",desired)
	return Rect2(frame.position,frame.size)

func _layout_gameplay_cards() -> void:
	_hud_layout_queued = false
	if mobile or _hud_cards.is_empty() or not is_inside_tree() or is_queued_for_deletion(): return
	for card in _hud_cards.values():
		if not is_instance_valid(card.body) or card.body.is_queued_for_deletion(): return
	var view := get_viewport_rect().size
	var board := Rect2()
	if _hud_cards.has("top"):
		var width := minf(view.x-2*margin,960.0)
		var x := (view.x-width)*0.5
		var owner_space := 0.0
		var available := view.y-2*margin-owner_space
		var top := _fit_hud_card("top",Vector2(x,margin),width,available*0.28)
		var lower := _fit_hud_card("lower",Vector2(x,margin),width,available*0.42)
		lower.position.y = view.y-margin-owner_space-lower.size.y
		_hud_cards.lower.frame.position = lower.position
		board = Rect2(margin,top.end.y,view.x-2*margin,maxf(1,lower.position.y-top.end.y))
	else:
		var width := clampf(view.x*0.28,300,460)
		var available := view.y-2*margin
		var actions := _fit_hud_card("actions",Vector2(margin,margin),width,available*0.46)
		var stats := _fit_hud_card("stats",Vector2(margin,margin),width,available-actions.size.y-12)
		_hud_cards.actions.frame.position = Vector2(margin,stats.end.y+12)
		var collection_width := clampf(view.x*0.22,420,620) if _hud_cards.has("collection") else 0.0
		if collection_width > 0:
			_fit_hud_card("collection",Vector2(view.x-margin-collection_width,margin),collection_width,available)
		board = Rect2(margin+width+12,0,view.x-width-collection_width-margin*2-24,view.y)
	if not board.is_equal_approx(_hud_board_rect):
		_hud_board_rect = board
		game.project_board(board)

func _floating_panel(rect: Rect2) -> VBoxContainer:
	var outer := PanelContainer.new()
	var box := PlushStyle.make({"fill":Color(FELT,0.96),"rim":Color("e6cedb"),"rim_width":1,"radius":16,"gloss":0.3,
		"stitch":Color(STITCH,0.55),"stitch_inset":4.0,"stitch_dash":5.0,"stitch_gap":4.0,"stitch_width":1.2,
		"shadow":Color(PLUM,0.16),"shadow_size":6,"shadow_offset":Vector2(0,2)})
	_margins(box,12,11)
	outer.add_theme_stylebox_override("panel",box)
	outer.set_meta("ui_safe_insets",Vector4(12,11,12,11))
	base.add_child(outer)
	_rect(outer,rect)
	var content := column(outer)
	content.add_theme_constant_override("separation",0)
	return content

func _mobile_gameplay(view: Vector2) -> void:

	var inset: Vector4 = game.device.safe_insets
	var left := inset.x+12
	var right := view.x-inset.z-12
	var top := inset.y+8
	var width := right-left
	# Two full name lines are reserved from the actual face metrics. Counts and
	# longer localized toy names can wrap without overlapping the cabinet.
	var value_font_size := int(13 * font_scale() * float(game.tweaks.value("ui.text.scale")))
	var value_height := ceilf(game.locale.font.get_height(value_font_size))*2+get_theme_constant("line_spacing","Label")
	var name_card_height := 28+value_height+22
	var header_height := 8+74+name_card_height+8
	var footer_height := 0.0
	mobile_header = Rect2(0,0,view.x,inset.y+header_height)
	mobile_footer = Rect2(0,view.y-inset.w-footer_height,view.x,footer_height+inset.w)
	for region in [mobile_header,mobile_footer]:
		if not region.has_area(): continue
		var backing := PanelContainer.new()
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Lilac felt band, like the claw machine's padded roof and base.
		backing.add_theme_stylebox_override("panel",plush("band"))
		base.add_child(backing)
		_rect(backing,region)
	game.project_board(Rect2(inset.x,mobile_header.end.y,view.x-inset.x-inset.z,mobile_footer.position.y-mobile_header.end.y))
	var card_width := (width-8)*0.5
	var score := _floating_panel(Rect2(left,top,card_width,52))
	var score_line := column(score)
	score_line.add_theme_constant_override("separation",0)
	_caption(text_label(score_line,"hud.score_label",11))
	var score_value := display(_metric(score_line,"score","hud.score_value",{"score":game.score},18))
	score_value.autowrap_mode = TextServer.AUTOWRAP_OFF
	score_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	score_value.set_meta("ui_max_font_size",score_value.get_theme_font_size("font_size"))
	var time := _floating_panel(Rect2(right-card_width,top,card_width-52,52))
	var time_value := display(_metric(time,"time","hud.time_short",{"time":"3:00"},22 if card_width >= 135 else 18))
	time_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_value.autowrap_mode = TextServer.AUTOWRAP_OFF
	time_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	time_value.set_meta("ui_max_font_size",time_value.get_theme_font_size("font_size"))
	var pause := button(base,"ui.pause",game.toggle_pause)
	pause.text = ""
	pause.draw.connect(func():
		var center := pause.size*0.5
		pause.draw_rect(Rect2(center+Vector2(-10,-11),Vector2(6,22)),INK)
		pause.draw_rect(Rect2(center+Vector2(4,-11),Vector2(6,22)),INK))
	pause.tooltip_text = t("ui.pause")
	_rect(pause,Rect2(right-44,top,44,52))
	for index in range(2):
		var key := "goal" if index == 0 else "next"
		var tier: int = game.session.goal_tier if index == 0 else game.next_tier
		var content := _floating_panel(Rect2(left if index == 0 else right-card_width,top+74,card_width,name_card_height))
		var line := row(content)
		line.add_theme_constant_override("separation",5)
		var icon := TextureRect.new()
		icon.texture = game.toy_texture(tier)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(28,28)
		line.add_child(icon)
		metrics[key+"_texture"] = icon
		_caption(text_label(line,"hud."+key+"_label",11))
		var value := _metric(content,key,"toy.bomb",{},13)
		value.text = game.toy_name(tier)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		value.custom_minimum_size.y = value_height
		value.set_meta("ui_max_font_size",value.get_theme_font_size("font_size"))
		value.set_meta("ui_max_lines",2)

func _caption(label: Label) -> Label:
	label.add_theme_font_override("font",game.locale.heading_font)
	label.add_theme_color_override("font_color",Color("9a5c80"))
	return label

func _new_sheet(parent: Node,title: String,close_key: String,action: Callable) -> Control:
	var sheet := MobileSheet.new()
	sheet.hud = self
	sheet.title_key = title
	sheet.close_key = close_key
	sheet.close_action = action
	sheet.theme = _dialog_theme()
	parent.add_child(sheet)
	return sheet

func _mobile_debrief() -> void:
	_building_dialog = true
	var sheet := _new_sheet(base,"result.game_over","mp.return",game.return_title)
	sheet.name = "MobileResults"
	sheet.scroll.name = "ResultsScroll"
	var body: VBoxContainer = sheet.body
	_score_hero(body,_claim_intro("route:debrief"))
	text_label(body,"result.summary",20,{"score":game.score,"merges":game.merge_count,"seconds":int(game.session.elapsed)})
	text_label(body,"result."+game.session.reason,15)
	text_label(body,"result.tuned" if game.tweaks.tainted else "result.baseline",13)
	if not game.is_sandbox_mode() and not game.leaderboard.saved: text_label(body,"result.save_failed",14)
	if game.is_sandbox_mode(): text_label(body,"leaderboard.practice",14)
	var actions := row(sheet.footer)
	var restart := button(actions,"ui.restart",game.restart_game,true)
	restart.text = t("ui.restart_short")
	button(actions,"ui.leaderboard",func(): game.open_modal("leaderboard"))
	controls["ui.title"] = sheet.close_button
	_building_dialog = false

func _mobile_modal(kind: String) -> Control:
	_building_dialog = true
	var titles := {"leaderboard":"ui.leaderboard","pause":"ui.pause_title","help":"ui.help","collection":"ui.collection","confirm":"ui.confirm_title","tweaks":"ui.tweaks"}
	var sheet := _new_sheet(self,titles.get(kind,"app.title"),"ui.close",game.close_modal)
	sheet.name = "Modal_"+kind
	var body: VBoxContainer = sheet.body
	match kind:
		"leaderboard":
			if not game.leaderboard_available(): text_label(body,"leaderboard.practice",16)
			else:
				_username_input(body)
				var ranking := preload("res://scripts/score/leaderboard_panel.gd").new()
				ranking.hud = self
				body.add_child(ranking)
		"pause":
			button(body,"ui.resume",game.close_modal,true)
			button(body,"ui.restart",func(): game.confirm_loss("restart"))
			button(body,"ui.settings",func(): game.open_modal("settings"))
			button(body,"ui.collection",func(): game.open_modal("collection"))
			button(body,"ui.title",func(): game.confirm_loss("title"))
		"help":
			_how_to_play(body)
		"collection": _collection(body)
		"confirm":
			text_label(body,"ui.confirm_body",17)
			var actions := row(sheet.footer)
			button(actions,"ui.cancel",game.close_modal,true)
			button(actions,"ui.confirm",game.confirm_action)
	_building_dialog = false
	call_deferred("_focus_if_valid",weakref(sheet.close_button))
	_pop_in(sheet,null,"modal:"+kind)
	return sheet

func _debrief(view: Vector2) -> void:
	if mobile:
		_mobile_debrief()
		return
	_building_dialog = not mobile
	var cover := _cover(base)
	cover.theme = _dialog_theme()
	var body := panel(cover,center_rect(view,960 if not mobile else 800,720 if not mobile else 920),not compact)
	if not mobile: body.add_theme_constant_override("separation",4 if view.y < 700 else 6)
	var scroll := body.get_parent() as ScrollContainer
	scroll.name = "ResultsScroll"
	# Preserve touch/wheel/keyboard scrolling and the full inner content width.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	var intro := _claim_intro("route:debrief")
	# Short windows put the reason beside the heading and use a smaller hero number so
	# results never need scrolling.
	var short := view.y < 700
	var head_line: Control = row(body) if short else body
	if short: (head_line as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	var heading := display(text_label(head_line,"result.game_over",29))
	var reason := text_label(head_line,"result."+game.session.reason,17)
	reason.add_theme_color_override("font_color",MUTED)
	if short:
		for label in [heading,reason]:
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hero := _score_hero(body,intro)
	var summary := display(text_label(body,"result.summary",18,{"score":game.score,"merges":game.merge_count,"seconds":int(game.session.elapsed)}))
	var notes: Array[Label] = [text_label(body,"result.tuned" if game.tweaks.tainted else "result.baseline",14)]
	if not game.is_sandbox_mode() and not game.leaderboard.saved: notes.append(text_label(body,"result.save_failed",14))
	if game.is_sandbox_mode(): notes.append(text_label(body,"leaderboard.practice",14))
	for label in [heading,reason,summary]+notes: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for label in notes: label.add_theme_color_override("font_color",MUTED)
	if not short:
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(gap)
	var actions: Control = body if mobile else row(body)
	button(actions,"ui.restart",game.restart_game,game.session.outcome != "victory")
	button(actions,"ui.leaderboard",func(): game.open_modal("leaderboard"))
	button(actions,"ui.title",game.return_title)
	if intro:
		var frame_node := body.get_parent().get_parent().get_parent() as Control
		cover.modulate.a = 0.0
		cover.create_tween().tween_property(cover,"modulate:a",1.0,0.25)
		frame_node.scale = Vector2.ONE*0.9
		var pop := frame_node.create_tween()
		pop.tween_callback(func(): if is_instance_valid(frame_node): frame_node.pivot_offset = frame_node.size*0.5)
		pop.tween_property(frame_node,"scale",Vector2.ONE,0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if hero != null: hero.modulate.a = 0.0
	for control in body.find_children("*","Control",true,false):
		if control.focus_mode != Control.FOCUS_NONE:
			control.focus_entered.connect(_reveal_result_control.bind(weakref(scroll),weakref(control)),CONNECT_DEFERRED)
	if not mobile:
		var frame := scroll.get_parent().get_parent() as Control
		var fit := _fit_result_frame.bind(weakref(body),weakref(scroll),weakref(frame),center_rect(view,960,view.y))
		body.minimum_size_changed.connect(fit,CONNECT_DEFERRED)
		fit.call_deferred()
	_building_dialog = false

## Big animated score reveal flanked by felt hearts, with the local best as a chip.
func _score_hero(body: VBoxContainer,intro: bool) -> Control:
	var line := HBoxContainer.new()
	line.name = "ScoreHero"
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation",14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(line)
	var size := int((36 if mobile else (28 if get_viewport_rect().size.y < 700 else 46))*font_scale()*float(game.tweaks.value("ui.text.scale")))
	var hearts: Array[Control] = []
	for side in range(2):
		var heart := Control.new()
		heart.custom_minimum_size = Vector2.ONE*size*0.62
		heart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart.draw.connect(func(): TitleFx.draw_heart(heart,heart.size*0.5,heart.size.x*0.95,CANDY,Color.WHITE,2.0))
		hearts.append(heart)
	line.add_child(hearts[0])
	var value := Label.new()
	value.name = "ScoreValue"
	value.text = t("hud.score_value",{"score":game.score})
	value.add_theme_font_override("font",game.locale.heading_font)
	value.add_theme_font_size_override("font_size",size)
	value.add_theme_color_override("font_color",Color("e0668c"))
	value.add_theme_color_override("font_outline_color",Color.WHITE)
	value.add_theme_constant_override("outline_size",maxi(4,int(size*0.16)))
	value.add_theme_color_override("font_shadow_color",Color(PLUM,0.25))
	value.add_theme_constant_override("shadow_offset_y",4)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	line.add_child(hearts[1])
	var best: int = game.best_score
	if best > 0:
		var fresh: bool = not game.is_sandbox_mode() and game.score > 0 and game.score >= best
		# Phones stack the badge under the number so long scores never widen the sheet.
		var badge := chip(line if not mobile else body,"result.new_best" if fresh else "hud.best","chip" if fresh else "chip_lilac",13,{"score":best})
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if mobile: badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if intro:
		var total: int = game.score
		value.text = t("hud.score_value",{"score":0})
		var count := value.create_tween()
		count.tween_interval(0.2)
		count.tween_callback(func(): line.modulate.a = 1.0)
		count.tween_method(func(amount: float): value.text = t("hud.score_value",{"score":int(round(amount))}),0.0,float(total),clampf(0.4+total/4000.0,0.4,1.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		count.tween_callback(func():
			value.pivot_offset = value.size*0.5
			var punch := value.create_tween()
			punch.tween_property(value,"scale",Vector2.ONE*1.18,0.08)
			punch.tween_property(value,"scale",Vector2.ONE,0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return line

func _fit_result_frame(body_ref: WeakRef,scroll_ref: WeakRef,frame_ref: WeakRef,available: Rect2) -> void:
	var body := body_ref.get_ref() as Control
	var scroll := scroll_ref.get_ref() as ScrollContainer
	var frame := frame_ref.get_ref() as Control
	if body == null or scroll == null or frame == null or not body.is_inside_tree() or body.is_queued_for_deletion(): return
	# Keep authored frame insets and current text sizes; only remove unused height.
	var padding := scroll.get_parent() as MarginContainer
	var chrome := float(padding.get_theme_constant("margin_top")+padding.get_theme_constant("margin_bottom"))
	if frame is PanelContainer: chrome += frame.get_theme_stylebox("panel").get_minimum_size().y
	var height := minf(available.size.y,ceilf(body.get_combined_minimum_size().y+chrome+4))
	var target := Rect2(available.get_center()-Vector2(available.size.x,height)*0.5,Vector2(available.size.x,height))
	if not frame.get_rect().is_equal_approx(target): _rect(frame,target)

func _reveal_result_control(scroll_ref: WeakRef,control_ref: WeakRef) -> void:
	var scroll := scroll_ref.get_ref() as ScrollContainer
	var control := control_ref.get_ref() as Control
	if scroll == null or control == null or not control.is_inside_tree() or not control.has_focus(): return
	# Godot's built-in focus reveal ignores a scrollbar in SHOW_NEVER mode.
	var viewport_rect := scroll.get_global_rect()
	var bounds := control.get_global_rect()
	if bounds.end.y > viewport_rect.end.y:
		scroll.scroll_vertical += ceili(bounds.end.y-viewport_rect.end.y)
	elif bounds.position.y < viewport_rect.position.y:
		scroll.scroll_vertical += floori(bounds.position.y-viewport_rect.position.y)

func _dialog_theme() -> Theme:
	var result := theme.duplicate() as Theme
	result.default_font_size = int(17 * font_scale() * float(game.tweaks.value("ui.text.scale")))
	return result

func _cover(parent: Node) -> Control:
	var cover := ColorRect.new()
	cover.color = Color(0.20,0.10,0.19,0.40)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(cover)
	# Dim plus a plum vignette keeps focus on the felt frame without a flat grey sheet.
	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = vignette_texture()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return cover

func _desktop_help(view: Vector2) -> Control:
	_building_dialog = true
	var cover := _cover(self)
	cover.name = "Modal_help"
	cover.theme = _dialog_theme()
	var card := PanelContainer.new()
	card.name = "HelpCard"
	card.add_theme_stylebox_override("panel",_margins(plush("felt"),24,20))
	cover.add_child(card)
	_rect(card,center_rect(view,840,900))
	var layout := column(card)
	var header := row(layout)
	display(text_label(header,"ui.help",26))
	var close := button(header,"ui.close",game.close_modal)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size.x = 88
	var scroll := ScrollContainer.new()
	scroll.name = "HelpScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var body := column(scroll)
	body.add_theme_constant_override("separation",8)
	_how_to_play(body)
	_building_dialog = false
	call_deferred("_focus_if_valid",weakref(close))
	_pop_in(cover,card,"modal:help")
	return cover

func _build_modal(kind: String,view: Vector2) -> Control:
	if not mobile and kind == "help": return _desktop_help(view)
	if mobile and kind != "settings": return _mobile_modal(kind)
	if kind == "settings":
		var settings_dialog := preload("res://scripts/ui/settings_dialog.gd").new()
		settings_dialog.hud = self
		add_child(settings_dialog)
		call_deferred("_focus_if_valid",weakref(settings_dialog.close_button))
		return settings_dialog
	_building_dialog = not mobile
	var cover := _cover(self)
	cover.theme = _dialog_theme()
	cover.name = "Modal_"+kind
	_building_pause = kind == "pause" and not mobile
	var height := 1000.0 if kind in ["settings","leaderboard","tweaks","collection","pause"] else 900.0
	var width := 1020.0 if kind == "tweaks" else 840.0
	var art_padding := ART_SAFE_INSETS
	var pause_columns := 2 if _building_pause and view.y < 760 else 1
	if _building_pause:
		width = 740.0 if pause_columns == 2 else 640.0
		var scale := font_scale() * float(game.tweaks.value("ui.text.scale"))
		# Fit the title, subtitle and five actions, including whole-pixel layout rounding.
		height = ceilf(game.locale.heading_font.get_height(int(26 * scale))) + ceilf(game.locale.font.get_height(int(17 * scale)))
		var action_rows := ceili(5.0/pause_columns)
		height += control_height()*action_rows + 4*(action_rows+1) + art_padding.y + art_padding.w + 8
	var body := panel(cover,center_rect(view,width,height),_building_pause,art_padding)
	if _building_pause: body.add_theme_constant_override("separation",4)
	match kind:
		"pause":
			var heading := display(text_label(body,"ui.pause_title",26))
			var subtitle := text_label(body,"ui.pause_body",17)
			heading.add_theme_color_override("font_color",Color("6a3a59"))
			heading.add_theme_color_override("font_shadow_color",Color(CANDY,0.45))
			heading.add_theme_constant_override("shadow_offset_y",3)
			if _building_pause:
				heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				subtitle.add_theme_color_override("font_color",MUTED)
				var gap := Control.new()
				gap.custom_minimum_size.y = 4
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				body.add_child(gap)
			var actions: Control = body
			if pause_columns == 2:
				var grid := GridContainer.new()
				grid.columns = 2
				grid.add_theme_constant_override("h_separation",8)
				grid.add_theme_constant_override("v_separation",4)
				body.add_child(grid)
				actions = grid
			button(actions,"ui.resume",game.close_modal,true)
			button(actions,"ui.restart",func(): game.confirm_loss("restart"))
			button(actions,"ui.settings",func(): game.open_modal("settings"))
			button(actions,"ui.collection",func(): game.open_modal("collection"))
			button(actions,"ui.title",func(): game.confirm_loss("title"))
		"confirm":
			display(text_label(body,"ui.confirm_title",29))
			text_label(body,"ui.confirm_body")
			button(body,"ui.cancel",game.close_modal,true)
			button(body,"ui.confirm",game.confirm_action)
		"leaderboard": _leaderboard(body)
		"collection":
			_collection(body)
			button(body,"ui.close",game.close_modal)
	_building_pause = false
	_building_dialog = false
	var first := _first_focus(body)
	if first != null: call_deferred("_focus_if_valid",weakref(first))
	_pop_in(cover,body.get_parent().get_parent().get_parent() as Control,"modal:"+kind)
	return cover

func _first_focus(node: Node) -> Control:
	for child in node.get_children():
		# A username is edited on click/tap or Tab, without opening a phone keyboard on entry.
		if child is UsernameInput: continue
		if child is Control and child.focus_mode == Control.FOCUS_ALL: return child
		var nested := _first_focus(child)
		if nested != null: return nested
	return null

func _how_to_play(body: VBoxContainer) -> void:
	for key in ["ui.help_body","help.rules","help.bombs","help.rescue"]:
		text_label(body,key,16)
	for method in ["keyboard","pointer","touch","gamepad"]:
		text_label(body,"help.input."+method,16)

func _username_input(body: VBoxContainer) -> LineEdit:
	if not mobile: text_label(body,"ui.name",16)
	var name_input := UsernameInput.new(game)
	name_input.custom_minimum_size.y = control_height()
	body.add_child(name_input)
	return name_input

func _leaderboard(body: VBoxContainer) -> void:
	if not game.leaderboard_available():
		text_label(body,"leaderboard.practice",18)
		button(body,"ui.close",game.close_modal)
		return
	display(text_label(body,"ui.leaderboard",28))
	_username_input(body)
	var panel := preload("res://scripts/score/leaderboard_panel.gd").new()
	panel.hud = self
	body.add_child(panel)
	button(body,"ui.close",game.close_modal)

func apply_presentation() -> void:
	if is_instance_valid(controls.get("ui.leaderboard")):
		controls["ui.leaderboard"].disabled = not game.leaderboard_available()
	if not is_node_ready(): return
	if is_instance_valid(filter):
		filter.visible = game.tweaks.value("environment.filter.enabled")
		filter.color = Color(0.88,0.55,0.34,float(game.tweaks.value("environment.filter.intensity"))*0.12)
	if is_instance_valid(base): base.modulate.a = float(game.tweaks.value("ui.hud.opacity")) if current_route == "gameplay" else 1.0
	var text_scale: float = game.tweaks.value("ui.text.scale")
	if not is_equal_approx(text_scale,last_text_scale):
		last_text_scale = text_scale
		call_deferred("rebuild")

func _process(_delta: float) -> void:
	if _updating or _refresh_queued: return
	for key in metrics:
		var control = metrics[key]
		if not is_instance_valid(control) or control.is_queued_for_deletion() or not control.is_inside_tree():
			_queue_refresh(true)
			return
	if current_route not in ["gameplay","debrief"]: return
	# Chip layouts (mobile and the desktop sidebar) caption values separately; the compact
	# desktop strip keeps self-describing "SCORE 30" style readouts.
	var captioned := mobile or not compact
	if metrics.has("score"):
		metrics.score.text = t("hud.score_value" if captioned else "hud.score",{"score":game.score})
		metrics.score.visible = game.tweaks.value("ui.score.visible")
		if game.score != _last_score:
			if _last_score >= 0 and game.score > _last_score and not compact: _punch(metrics.score)
			_last_score = game.score
	var remaining: int = ceili(game.session.remaining_time())
	if metrics.has("time"):
		metrics.time.text = t("hud.time_short",{"time":"%d:%02d" % [remaining/60,remaining%60]})
		# The last half minute pulses berry red; purely a readout colour.
		var hurry := remaining <= 30 and current_route == "gameplay"
		var pulse := 0.5+0.5*sin(Time.get_ticks_msec()*0.008) if hurry and not game.reduced_motion() else (1.0 if hurry else 0.0)
		metrics.time.add_theme_color_override("font_color",INK.lerp(Color("d9436a"),pulse))
	if is_instance_valid(_time_meter): _time_meter.queue_redraw()
	if metrics.has("drops"): metrics.drops.text = t("hud.drops",{"count":game.drop_count})
	if metrics.has("stage"): metrics.stage.text = t("hud.stage",{"index":game.session.goals_reached+1})
	if metrics.has("goal"): metrics.goal.text = _toy_readout("goal") if captioned else goal_text()
	if metrics.has("goal_texture"): metrics.goal_texture.texture = PlushieBody.TEXTURES[game.session.goal_tier]
	if metrics.has("next"): metrics.next.text = _toy_readout("next") if captioned else t("hud.next",{"toy":game.toy_name(game.next_tier)})
	if metrics.has("next_texture"): metrics.next_texture.texture = game.toy_texture(game.next_tier)
	if mobile:
		for key in ["score","time","goal","next"]:
			if metrics.has(key): _fit_mobile_readout(metrics[key])
	if metrics.has("state"):
		metrics.state.text = t("hud.settling" if not game.session.can_drop() else ("hud.ready" if game.claw_state == game.ClawState.HOLDING else "hud.reloading"))
	for collection in collection_views.duplicate():
		var heading = collection.heading.get_ref()
		if not is_instance_valid(heading) or not heading.is_inside_tree():
			collection_views.erase(collection)
			continue
		heading.text = t("hud.discovery",{"count":game.discovered.count(true)})
		for tier in range(11): collection.icons[tier].modulate.a = 1.0 if game.discovered[tier] else 0.3

func _punch(label: Label) -> void:
	# Score tick: a quick scale pop on the number whenever points land.
	if game.reduced_motion() or not label.is_inside_tree(): return
	label.pivot_offset = Vector2(0,label.size.y*0.5) if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT else label.size*0.5
	var tween := label.create_tween()
	tween.tween_property(label,"scale",Vector2.ONE*1.22,0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"scale",Vector2.ONE,0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _fit_mobile_readout(label: Label) -> void:
	if label.size.x <= 0 or not label.has_meta("ui_max_font_size"): return
	var font: Font = label.get_theme_font("font")
	var font_size := int(label.get_meta("ui_max_font_size"))
	var max_lines := int(label.get_meta("ui_max_lines",1))
	var signature := [label.text,label.size.x,font_size,max_lines,font.get_instance_id()]
	if label.get_meta("ui_fit_signature",[]) == signature: return
	label.set_meta("ui_fit_signature",signature)
	while font_size > 14:
		var fits := font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x <= label.size.x
		if max_lines > 1:
			var paragraph := TextParagraph.new()
			paragraph.width = label.size.x
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.add_string(label.text,font,font_size)
			fits = paragraph.get_line_count() <= max_lines
		if fits: break
		font_size -= 1
	if label.get_theme_font_size("font_size") != font_size:
		label.add_theme_font_size_override("font_size",font_size)

func _focus_if_valid(reference: WeakRef) -> void:
	var control = reference.get_ref()
	if not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree(): return
	var current := get_viewport().gui_get_focus_owner()
	if current is LineEdit and current.is_visible_in_tree(): return
	var surface := active_surface()
	if is_instance_valid(surface) and (surface == control or surface.is_ancestor_of(control)): control.grab_focus()

func blocks_pointer(at: Vector2) -> bool:
	for node in find_children("*","Control",true,false):
		if (node is BaseButton or node is PanelContainer) and node.is_visible_in_tree() and node.get_global_rect().has_point(at): return true
	return false
