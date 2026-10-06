extends Node2D
const MAX_PARTICLES := 160
var particles: Array[Dictionary] = []
var reduced_motion := false
var intensity := 1.0
var ambient := true
var pulse := 0.0
var clock := 0.0
var paused := false
var bounds := Rect2(400,176,640,676)

func burst(at: Vector2) -> void:
    pulse = 0.6
    if reduced_motion: return
    for index in range(int(12 * intensity)):
        if particles.size() >= MAX_PARTICLES: particles.pop_front()
        var angle := index * 2.399963
        particles.append({"p":at,"v":Vector2(cos(angle),sin(angle)) * (70 + index * 5),"life":0.75})

func bomb_burst(at: Vector2) -> void:
    if reduced_motion: return
    for index in range(int(24 * intensity)):
        if particles.size() >= MAX_PARTICLES: particles.pop_front()
        var angle := index * 2.399963
        particles.append({"p":at,"v":Vector2(cos(angle),sin(angle))*(100+index*3),"life":0.6,"bomb":true})

func clear() -> void:
    particles.clear()
    pulse = 0
    clock = 0

func _process(delta: float) -> void:
    if paused: return
    clock += delta
    pulse = maxf(0, pulse - delta * 2)
    for particle in particles:
        particle.p += particle.v * delta
        particle.v.y += 180 * delta
        particle.life -= delta
    particles = particles.filter(func(p: Dictionary) -> bool: return p.life > 0)
    queue_redraw()

func _draw() -> void:
    for particle in particles:
        var is_bomb: bool = particle.get("bomb",false)
        draw_circle(particle.p, 7 if is_bomb else 3, Color(0.80,0.66,0.88,particle.life) if is_bomb else Color(0.88,0.52,0.32,particle.life))
    if ambient and not reduced_motion:
        for index in range(12):
            var x := bounds.position.x+15.0+fmod(index*83.0+clock*7,bounds.size.x-30)
            var y := bounds.get_center().y+sin(index*2.3+clock*0.4)*bounds.size.y*0.35
            draw_circle(Vector2(x,y), 1.6, Color(1,0.88,0.6,0.4))
    if pulse > 0:
        draw_rect(bounds,Color(0.96,0.6,0.42,pulse * 0.35),false,3)
