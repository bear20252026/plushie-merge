extends RigidBody2D
class_name PlushieBody

const NAMES := ["Mochi Chick", "Strawberry Slime", "Dumpling Cat", "Floppy Bunny", "Pudding Pup", "Pocket Octo", "Star Pillow", "Cloud Sheep", "Chonky Axolotl", "Moon Moth", "Dream Dragon"]
const KEYS := ["chick", "slime", "cat", "bunny", "pup", "octo", "star", "sheep", "axolotl", "moth", "dragon"]
const SIZE_MULTIPLIER := 1.2
const SPANS := [88.0*SIZE_MULTIPLIER, 102.0*SIZE_MULTIPLIER, 118.0*SIZE_MULTIPLIER, 134.0*SIZE_MULTIPLIER, 150.0*SIZE_MULTIPLIER, 168.0*SIZE_MULTIPLIER, 188.0*SIZE_MULTIPLIER, 210.0*SIZE_MULTIPLIER, 236.0*SIZE_MULTIPLIER, 270.0*SIZE_MULTIPLIER, 306.0*SIZE_MULTIPLIER]
const SQUISH_AMOUNT := 0.5
const TEXTURES: Array[Texture2D] = [
    preload("res://assets/template/plushies/runtime/chick.webp"),
    preload("res://assets/template/plushies/runtime/slime.webp"),
    preload("res://assets/template/plushies/runtime/cat.webp"),
    preload("res://assets/template/plushies/runtime/bunny.webp"),
    preload("res://assets/template/plushies/runtime/pup.webp"),
    preload("res://assets/template/plushies/runtime/octo.webp"),
    preload("res://assets/template/plushies/runtime/star.webp"),
    preload("res://assets/template/plushies/runtime/sheep.webp"),
    preload("res://assets/template/plushies/runtime/axolotl.webp"),
    preload("res://assets/template/plushies/runtime/moth.webp"),
    preload("res://assets/template/plushies/runtime/dragon.webp")
]
const SILHOUETTE = preload("res://scripts/sprite_silhouette.gd")
var convex_pieces: Array[PackedVector2Array] = []
var tier := 0
var manager: Node
var held := false
var merge_locked := false
var destroy_pending := false
var age := 0.0
var danger_time := 0.0
var render_size := Vector2(88,88)
var texture_asset: Texture2D
var render_span := 88.0
var outline := PackedVector2Array()
var piece_count := 0
var squish := 0.0
var squish_velocity := 0.0
var visual_scale := Vector2.ONE
var halo := 0.0
var _impact_cooldown := 0.0
var _last_velocity := Vector2.ZERO
var has_surface_contact := false

static func resources_valid() -> bool:
    if not FileAccess.file_exists("res://assets/template/plushies/runtime/manifest.json"): return false
    var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/template/plushies/runtime/manifest.json"))
    if not raw is Dictionary or not raw.get("assets") is Array or raw.assets.size() != 11: return false
    for record in raw.assets:
        if not record is Dictionary or not record.get("outline") is Array or record.outline.size() < 8: return false
        for point in record.outline:
            if not point is Array or point.size() != 2: return false
            for number in point:
                if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 0.6: return false
    return true

func configure(new_tier: int, owner_game: Node) -> void:
    tier = clampi(new_tier, 0, 10)
    manager = owner_game
    texture_asset = TEXTURES[tier]
    render_span = float(SPANS[tier])
    var texture_size := texture_asset.get_size()
    render_size = texture_size * (render_span / maxf(texture_size.x,texture_size.y))
    _configure_outline()
    _configure_physics(0.6 + float(tier) * 0.30)

func _configure_outline() -> void:
    var geometry: Dictionary = SILHOUETTE.geometry(texture_asset,render_size)
    if not geometry.error.is_empty():
        push_error("Plushie collision fallback: "+str(geometry.error))
    outline = geometry.outline
    convex_pieces.assign(geometry.pieces)

func _configure_physics(weight: float) -> void:
    var pieces := convex_pieces
    piece_count = pieces.size()
    for i in range(pieces.size()):
        var collider := CollisionShape2D.new()
        collider.name = "PlushShape%d" % i
        var shape := ConvexPolygonShape2D.new()
        shape.points = pieces[i]
        collider.shape = shape
        add_child(collider)
    mass = weight
    gravity_scale = 1.0 if not is_instance_valid(manager) else float(manager.tweaks.value("enemies.toy.gravity"))
    linear_damp = 0.32
    angular_damp = 1.2
    continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
    contact_monitor = true
    max_contacts_reported = 12
    physics_material_override = PhysicsMaterial.new()
    physics_material_override.bounce = 0.46 if not is_instance_valid(manager) else float(manager.tweaks.value("enemies.toy.bounce"))
    physics_material_override.friction = 0.68 if not is_instance_valid(manager) else float(manager.tweaks.value("enemies.toy.friction"))
    z_index = 3
    queue_redraw()

func _ready() -> void:
    body_entered.connect(_on_contact)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    has_surface_contact = state.get_contact_count() > 0
    var delta_v := (state.linear_velocity - _last_velocity).length()
    if state.get_contact_count() > 0 and delta_v > 55.0 and _impact_cooldown <= 0.0:
        var side_wall := false
        for index in range(state.get_contact_count()):
            var other := state.get_contact_collider_object(index) as Node
            if is_instance_valid(other) and other.is_in_group("cabinet_walls"):
                side_wall = true
                break
        impact(minf(delta_v / 600.0, 1.0),side_wall)
    _last_velocity = state.linear_velocity

func impact(strength: float,wall: bool = false) -> void:
    squish_velocity += clampf(strength,0.0,1.0) * 5.0
    _impact_cooldown = 0.15
    if is_instance_valid(manager) and strength > 0.20:
        manager.plushie_impact(strength,tier,wall)

func _process(delta: float) -> void:
    if is_instance_valid(manager) and manager.is_frozen():
        return
    _impact_cooldown = maxf(0.0,_impact_cooldown-delta)
    halo = maxf(0.0,halo-delta)
    var dt := minf(delta,0.033)
    squish_velocity += (-120.0*squish - 13.0*squish_velocity)*dt
    squish = clampf(squish + squish_velocity*dt,-0.10,0.18)
    if held:
        squish = 0.035
        squish_velocity = 0.0
    var full_squish_scale := Vector2(1.0+squish, 1.0/(1.0+squish))
    var amount := SQUISH_AMOUNT
    if is_instance_valid(manager):
        amount = 0.0 if manager.reduced_motion() else float(manager.tweaks.value("enemies.toy.squish"))
    # Cosmetic deformation must not separate contacting skins from rigid
    # colliders. This also preserves opposing contacts in a supported stack;
    # airborne/held squash and actual rigid-body rotation and bounce remain.
    visual_scale = Vector2.ONE if has_surface_contact and not held else Vector2.ONE.lerp(full_squish_scale, amount)
    queue_redraw()

func _on_contact(other: Node) -> void:
    if held or merge_locked or destroy_pending:
        return
    if other is PlushieBody and is_instance_valid(manager) and other.manager == manager:
        manager.request_merge(self, other)

func world_bounds() -> Rect2:
    var first := true
    var result := Rect2()
    for point in outline:
        var world := to_global(point)
        if first:
            result = Rect2(world,Vector2.ZERO)
            first = false
        else:
            result = result.expand(world)
    return result

func release() -> void:
    has_surface_contact = false
    held = false
    freeze = false
    sleeping = false
    collision_layer = 1
    collision_mask = 1
    age = 0.0
    linear_velocity = Vector2(0,35)
    var spin := 0.35 if not is_instance_valid(manager) else float(manager.tweaks.value("player.release.spin"))
    angular_velocity = 0.0 if not is_instance_valid(manager) else manager.session.rng.randf_range(-spin,spin)
    add_to_group("plushies")

func _draw() -> void:
    if halo > 0:
        draw_arc(Vector2.ZERO,render_span*0.5+(0.6-halo)*34,0,TAU,48,Color(1.0,0.75,0.40,halo),3,true)
    draw_set_transform(Vector2.ZERO,0,visual_scale)
    draw_texture_rect(texture_asset,Rect2(-render_size*0.5,render_size),false)
    draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
