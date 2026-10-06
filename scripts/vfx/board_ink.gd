extends Node2D
const FOREGROUND := preload("res://assets/template/foregrounds/cabinet_trim.webp")
var game: Node

func _draw() -> void:
    if not is_instance_valid(game): return
    var x: float = game.aim_x
    draw_line(Vector2(415,195),Vector2(1025,195),Color("a19c99"),10,true)
    draw_line(Vector2(415,192),Vector2(1025,192),Color("fffcf4"),3,true)
    draw_line(Vector2(x,197),Vector2(x,236),Color("807482"),10,true)
    draw_circle(Vector2(x,234),18,Color("b4aebb"))
    var half_width := 43.0
    var height := 84.0
    if is_instance_valid(game.held_toy):
        half_width = game.held_toy.render_size.x * 0.5
        height = game.held_toy.render_size.y
    var spread: float = game.claw_openness
    for side in [-1.0,1.0]:
        var root_point := Vector2(x+side*13,233)
        var elbow := Vector2(x+side*(half_width+9+spread*25),254+height*0.16)
        var tip := Vector2(x+side*(half_width*0.66+spread*54),game.held_y()+height*0.25-spread*17)
        var points := PackedVector2Array([root_point,elbow,tip])
        draw_polyline(points,Color("7c7480"),11,true)
        draw_polyline(points,Color("d5d2d7"),7,true)
        draw_polyline(points,Color("fffaf0"),2,true)
        draw_circle(tip,4,Color("d4ced9"))
    var danger_alpha := 0.5 + clampf(game.overflow_time / game.OVERFLOW_SECONDS,0,1) * 0.5
    draw_dashed_line(Vector2(416,game.danger_y()),Vector2(1024,game.danger_y()),Color(0.64,0.24,0.34,danger_alpha),2,10,true)
    # Preserve the generated cushion ends; only the plain central padding stretches.
    var trim_y: float = game.tank_rect.end.y-17
    draw_texture_rect_region(FOREGROUND,Rect2(364,trim_y,84,70),Rect2(0,0,84,70))
    draw_texture_rect_region(FOREGROUND,Rect2(448,trim_y,544,70),Rect2(84,0,168,70))
    draw_texture_rect_region(FOREGROUND,Rect2(992,trim_y,84,70),Rect2(252,0,84,70))
