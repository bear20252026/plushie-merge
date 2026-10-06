extends Node2D
## Integrates the physical board with narrow session, route and presentation owners.
const Plush := preload("res://scripts/plushie_body.gd")
const Bomb := preload("res://scripts/bomb_plushie.gd")
const BombDefinition := preload("res://data/actors/bomb.gd")
const HUD := preload("res://scripts/plushie_hud.gd")
const Audio := preload("res://scripts/game_audio.gd")
const Routes := preload("res://scripts/core/routes.gd")
const Settings := preload("res://scripts/core/settings.gd")
const Localization := preload("res://scripts/core/localization.gd")
const Session := preload("res://scripts/core/session.gd")
const Stages := preload("res://data/stages/registry.gd")
const Leaderboard := preload("res://scripts/score/leaderboard.gd")
const Tweaks := preload("res://scripts/tuning/tweak_service.gd")
const Feedback := preload("res://scripts/vfx/feedback.gd")
const CURSOR := preload("res://assets/template/ui/cursor.png")
const AIM_CURSOR := preload("res://assets/template/ui/aim_cursor.png")
const BoardInk := preload("res://scripts/vfx/board_ink.gd")
const DeviceLayout := preload("res://scripts/core/device_layout.gd")
const StorageMigration := preload("res://scripts/core/storage_migration.gd")
const TANK := Rect2(400,176,640,596)
const EXTRA_PILE_DEPTH := 80.0
const CABINET_TOP := 128.0
const CABINET_WIDTH := 712.0
const FLOOR_TRIM := 53.0
const DANGER_Y := 354.0
const OVERFLOW_SECONDS := 2.8
const MAX_TOYS := 80

enum ClawState { HOLDING, OPENING, RELOADING }
var routes := Routes.new()
var settings := Settings.new()
var locale := Localization.new()
var session := Session.new()
var leaderboard := Leaderboard.new()
var _sandbox_run := false
var tweaks := Tweaks.new(Tweaks.owner_build())
var device := DeviceLayout.new()
var audio: GameAudio
var feedback: Node2D
var _hud: Control
var _ink: Node2D
var stage_index := 0
var claw_state := ClawState.HOLDING
var claw_timer := 0.0
var claw_openness := 0.0
var held_toy: PlushieBody
var held_tier := 0
var next_tier := 0
var aim_x := 720.0
var discovered: Array[bool] = []
var overflow_time := 0.0
var danger_armed := true
var _impact_cooldown := 0.0
var _last_audio_x := 720.0
var _run_generation := 0
var _recorded := false
var _confirm_action := ""
var _touch_start := Vector2.ZERO
var _touch_dragged := false
var _aim_touch_index := -1
var input_method := "keyboard"
var error_key := "error.stage"
var active_open_seconds := 0.18
var active_reload_seconds := 0.55
var board_screen_rect := Rect2()
var tank_rect := Rect2(TANK.position,TANK.size+Vector2(0,EXTRA_PILE_DEPTH))
var _walls: Array[StaticBody2D] = []
var held_axis := 0.0
var _device_callback: JavaScriptObject
var _touch_cancel_callback: JavaScriptObject
var _viewport_updating := false
var _screen_size := Vector2i.ZERO
var _resize_ended := false
var _resize_banner: CanvasLayer
var _multiplayer_screen: Control
var _multiplayer_layer: CanvasLayer

var score: int:
    get: return session.score.total
var best_score: int:
    get: return int(leaderboard.rows[0].score) if not leaderboard.rows.is_empty() else 0
var drop_count: int:
    get: return session.drops
var merge_count: int:
    get: return session.merges
var is_paused: bool:
    get: return routes.modal() == "pause"
var show_help: bool:
    get: return routes.modal() == "help"
var is_game_over: bool:
    get: return routes.route == "debrief"
var audio_muted: bool:
    get: return bool(settings.values.muted)

func _ready() -> void:
    StorageMigration.run()
    device.refresh(get_viewport_rect().size)
    if device.mobile: input_method = "touch"
    if OS.has_feature("web"): DeviceLayout.apply_window_scale(get_window(),device.css_viewport)
    if OS.has_feature("android") or OS.has_feature("ios"):
        DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
    discovered.resize(11)
    discovered.fill(false)
    Input.set_custom_mouse_cursor(CURSOR,Input.CURSOR_ARROW,Vector2(6,2))
    Input.set_custom_mouse_cursor(CURSOR,Input.CURSOR_POINTING_HAND,Vector2(6,2))
    Input.set_custom_mouse_cursor(AIM_CURSOR,Input.CURSOR_CROSS,Vector2(16,16))
    settings.load_data()
    settings.apply_detected_locale(OS.get_locale())
    locale.locale = settings.values.locale
    TranslationServer.set_locale(locale.locale)
    leaderboard.load_data()
    _create_walls()
    feedback = Feedback.new()
    feedback.bounds = tank_rect
    feedback.z_index = 8
    add_child(feedback)
    _ink = BoardInk.new()
    _ink.game = self
    _ink.z_index = 7
    add_child(_ink)
    audio = Audio.new()
    audio.muted = audio_muted
    add_child(audio)
    var layer := CanvasLayer.new()
    layer.layer = 20
    add_child(layer)
    _hud = HUD.new()
    _hud.game = self
    layer.add_child(_hud)
    var scroll_edge := preload("res://scripts/ui/mobile_scroll_edge.gd").new()
    scroll_edge.game = self
    add_child(scroll_edge)
    _resize_banner = preload("res://scripts/ui/resize_banner.gd").new()
    _resize_banner.font = locale.font_for_weight(700)
    add_child(_resize_banner)
    reset_resize_guard()
    routes.changed.connect(_route_changed)
    tweaks.changed.connect(_apply_presentation)
    get_viewport().size_changed.connect(_viewport_changed)
    _apply_presentation()
    _route_changed()
    if OS.has_feature("web"):
        _device_callback = JavaScriptBridge.create_callback(_browser_device_changed)
        JavaScriptBridge.get_interface("window").mushiesDeviceChanged = _device_callback
        _touch_cancel_callback = JavaScriptBridge.create_callback(_browser_touch_cancelled)
        JavaScriptBridge.get_interface("window").mushiesTouchCancelled = _touch_cancel_callback

func _browser_device_changed(_arguments: Array) -> void:
    _viewport_changed()

func _browser_touch_cancelled(_arguments: Array) -> void:
    # Godot Web maps touchcancel to a normal release. Clear gesture ownership
    # from the browser capture phase before that release reaches gameplay.
    _aim_touch_index = -1
    if multiplayer_active() and is_instance_valid(_multiplayer_screen.local_board):
        _multiplayer_screen.local_board.cancel_touch()

func t(key: String, values: Dictionary = {}) -> String:
    return locale.t(key, values)

func toy_name(tier: int) -> String:
    if tier == BombDefinition.TIER: return t("toy.bomb")
    return t("toy.%d" % tier)

func toy_texture(tier: int) -> Texture2D:
    return Bomb.TEXTURE if tier == BombDefinition.TIER else Plush.TEXTURES[tier]

func is_frozen() -> bool:
    return routes.frozen() or device.portrait_blocked

func _viewport_changed() -> void:
    if _viewport_updating: return
    _viewport_updating = true
    var was_mobile := device.mobile
    device.refresh(get_viewport_rect().size)
    var next_size := _measured_screen_size()
    var changed := _screen_size != Vector2i.ZERO and next_size != _screen_size
    _screen_size = next_size
    if changed: _end_for_resize()
    if device.mobile and not was_mobile: input_method = "touch"
    if OS.has_feature("web"): DeviceLayout.apply_window_scale(get_window(),device.css_viewport)
    if device.portrait_blocked:
        _aim_touch_index = -1
        held_axis = 0
    if multiplayer_active():
        # The local duel owns its fixed arena projection. Rebuilding the hidden
        # solo HUD here would resize its tank and transform all multiplayer input.
        get_viewport().canvas_transform = Transform2D.IDENTITY
        _multiplayer_screen.set_app_visible(device.app_visible)
        _multiplayer_screen.on_device_changed()
        _viewport_updating = false
        return
    _hud.rebuild()
    _route_changed()
    _viewport_updating = false

func _measured_screen_size() -> Vector2i:
    # CSS pixels are the browser's playing area, even with a fixed virtual canvas.
    # Native windows/SubViewports use their actual pixel size, not HUD geometry.
    if OS.has_feature("web") and device.css_viewport.x > 0 and device.css_viewport.y > 0:
        return device.css_viewport
    return get_viewport().size

func reset_resize_guard() -> void:
    device.refresh(get_viewport_rect().size)
    _screen_size = _measured_screen_size()
    set_resize_ended(false)

func set_resize_ended(ended: bool) -> void:
    if _resize_ended == ended: return
    _resize_ended = ended
    if is_instance_valid(_resize_banner): _resize_banner.visible = ended and not OS.has_feature("web")
    if OS.has_feature("web"):
        JavaScriptBridge.eval("window.mushiesSetResizeEnded?.("+JSON.stringify(ended)+")",true)

func _end_for_resize() -> void:
    if multiplayer_active():
        _multiplayer_screen.end_for_resize()
        return
    if routes.route != "gameplay" or session.outcome != "": return
    _aim_touch_index = -1
    held_axis = 0
    session.finish("defeat","resize")
    set_resize_ended(true)
    _finish_run()

func reduced_motion() -> bool:
    return settings.values.reduced_motion or tweaks.value("ui.reduced_motion")

func project_board(rect: Rect2) -> void:
    if rect.size.x <= 0 or rect.size.y <= 0: return
    var minimum_height := TANK.end.y+EXTRA_PILE_DEPTH+FLOOR_TRIM-CABINET_TOP
    var factor := minf(rect.size.x/CABINET_WIDTH,rect.size.y/minimum_height)
    _resize_tank(CABINET_TOP+rect.size.y/factor-FLOOR_TRIM)
    var cabinet := cabinet_bounds()
    board_screen_rect = Rect2(Vector2(rect.get_center().x-CABINET_WIDTH*factor*0.5,rect.position.y),Vector2(CABINET_WIDTH*factor,rect.size.y))
    var offset := board_screen_rect.position-cabinet.position*factor
    get_viewport().canvas_transform = Transform2D(Vector2(factor,0),Vector2(0,factor),offset)

func cabinet_bounds() -> Rect2:
    return Rect2(364,CABINET_TOP,CABINET_WIDTH,tank_rect.end.y+FLOOR_TRIM-CABINET_TOP)

func _resize_tank(floor_y: float) -> void:
    var shift := floor_y-tank_rect.end.y
    if is_zero_approx(shift): return
    tank_rect.size.y += shift
    # Preserve the pile's height above the floor through viewport changes.
    for toy in get_board_toys():
        if not toy.is_queued_for_deletion(): toy.position.y += shift
    _update_walls()
    if is_instance_valid(feedback): feedback.bounds = tank_rect
    queue_redraw()
    if is_instance_valid(_ink): _ink.queue_redraw()

func _process(delta: float) -> void:
    if multiplayer_active(): return
    if not is_frozen():
        var axis := Input.get_axis("ui_left", "ui_right") + held_axis
        for device in Input.get_connected_joypads():
            var stick := Input.get_joy_axis(device,JOY_AXIS_LEFT_X)
            if absf(stick) > 0.18 and absf(stick) > absf(axis): axis = stick
        if Input.is_key_pressed(KEY_A): axis -= 1
        if Input.is_key_pressed(KEY_D): axis += 1
        if absf(axis) > 0.1:
            tweaks.apply("NEXT_ACTION")
            aim_x += clampf(axis,-1,1) * float(tweaks.value("player.aim.speed")) * delta
            _clamp_aim()
        _advance_claw(delta)
        _impact_cooldown = maxf(0, _impact_cooldown-delta)
    audio.set_carriage_motion(0.0 if is_frozen() else absf(aim_x-_last_audio_x)/maxf(delta,0.001))
    _last_audio_x = aim_x
    if is_instance_valid(held_toy): held_toy.position = Vector2(aim_x,held_y())
    feedback.paused = is_frozen()
    _ink.queue_redraw()

func _physics_process(delta: float) -> void:
    if is_frozen(): return
    session.tick(delta)
    if session.outcome != "":
        _finish_run()
        return
    var maximum := 0.0
    var settled := true
    for toy in get_board_toys():
        if toy.held or toy.destroy_pending or toy.is_queued_for_deletion(): continue
        if toy.merge_locked: settled = false; continue
        toy.age += delta
        if toy.linear_velocity.length() > 25: settled = false
        if toy.age > 1.35 and toy.linear_velocity.length() < 55 and toy.world_bounds().position.y <= danger_y()+Session.RESCUE_DISTANCE:
            # During reload the released slot has already been consumed.
            var offset := 0 if claw_state == ClawState.RELOADING else 1
            if session.grant_rescue_bomb(offset):
                next_tier = BombDefinition.TIER
        if toy.age > 1.35 and toy.world_bounds().position.y < danger_y() and toy.linear_velocity.length() < 55:
            toy.danger_time += delta
            maximum = maxf(maximum,toy.danger_time)
        else: toy.danger_time = 0.0
    overflow_time = maximum
    if overflow_time > 0.8 and danger_armed:
        danger_armed = false
        audio.play_danger()
    elif overflow_time < 0.15: danger_armed = true
    if overflow_time >= float(tweaks.value("gameplay.overflow_seconds")):
        session.finish("defeat", "overflow")
    elif not session.can_drop() and not is_instance_valid(held_toy):
        session.exhausted_time += delta
        if (settled and session.exhausted_time >= float(tweaks.value("gameplay.settle_seconds"))) or session.exhausted_time >= 12:
            session.finish("defeat", "drops")
    if session.outcome != "": _finish_run()

func danger_y() -> float:
    return float(tweaks.value("environment.danger.line"))

func held_y() -> float:
    var height := 88.0
    if is_instance_valid(held_toy): height = held_toy.render_size.y
    return 242.0 + height * 0.46

func request_drop() -> void:
    if is_frozen(): return
    if not session.can_drop() or claw_state != ClawState.HOLDING or not is_instance_valid(held_toy):
        audio.play_ui("invalid")
        return
    tweaks.apply("NEXT_ACTION")
    active_open_seconds = tweaks.value("player.claw.open_seconds")
    active_reload_seconds = tweaks.value("player.claw.reload_seconds")
    claw_state = ClawState.OPENING
    claw_timer = 0
    audio.play_drop(held_tier)

func _advance_claw(delta: float) -> void:
    if claw_state == ClawState.OPENING:
        claw_timer += delta
        claw_openness = clampf(claw_timer / active_open_seconds,0,1)
        if claw_timer >= active_open_seconds:
            _release_held()
            claw_state = ClawState.RELOADING
            claw_timer = 0
    elif claw_state == ClawState.RELOADING:
        claw_timer += delta
        claw_openness = 1.0-clampf(claw_timer / active_reload_seconds,0,1)
        if claw_timer >= active_reload_seconds and session.can_drop():
            held_tier = session.next_tier()
            next_tier = session.next_tier(1)
            _load_claw()
            audio.play_claw_close()
            claw_state = ClawState.HOLDING
            claw_openness = 0
            claw_timer = 0

func _release_held() -> void:
    if not is_instance_valid(held_toy): return
    held_toy.position = Vector2(aim_x,held_y())
    held_toy.release()
    audio.play_release()
    held_toy = null
    session.record_drop()

func _load_claw() -> void:
    held_toy = _spawn(held_tier,Vector2(aim_x,280),true)
    if not is_instance_valid(held_toy): return
    held_toy.position.y = held_y()
    if held_tier < discovered.size(): discovered[held_tier] = true
    _clamp_aim()

func _spawn(tier: int, where: Vector2, held := false) -> PlushieBody:
    if get_board_toys().size() >= MAX_TOYS: return null
    tweaks.apply("NEXT_SPAWN")
    var toy := (Bomb.new() if tier == BombDefinition.TIER else Plush.new()) as PlushieBody
    toy.configure(tier,self)
    toy.position = where
    toy.held = held
    toy.freeze = held
    toy.collision_layer = 0 if held else 1
    toy.collision_mask = 0 if held else 1
    add_child(toy)
    if not held:
        toy.add_to_group("plushies")
        if toy is Bomb: toy.armed = true
    return toy

func get_board_toys() -> Array[PlushieBody]:
    # SceneTree groups span all viewports, rooms and worlds. Ownership does not.
    var result: Array[PlushieBody] = []
    if not is_inside_tree(): return result
    for node in get_tree().get_nodes_in_group("plushies"):
        if node is PlushieBody and node.manager == self and not node.is_queued_for_deletion():
            result.append(node)
    return result

func _clamp_aim() -> void:
    var half := (BombDefinition.SPAN if held_tier == BombDefinition.TIER else float(PlushieBody.SPANS[held_tier])) * 0.5 + 16
    if is_instance_valid(held_toy): half = held_toy.render_size.x * 0.56 + 12
    aim_x = clampf(aim_x,tank_rect.position.x+half,tank_rect.end.x-half)

func request_merge(a: PlushieBody, b: PlushieBody) -> void:
    if is_frozen() or not is_instance_valid(a) or not is_instance_valid(b): return
    if a.manager != self or b.manager != self: return
    if a == b or a.held or b.held or a.merge_locked or b.merge_locked or a.destroy_pending or b.destroy_pending: return
    if a.tier != b.tier or a.tier >= 10: return
    a.merge_locked = true
    b.merge_locked = true
    call_deferred("_merge",a,b,_run_generation)

func _merge(a: PlushieBody,b: PlushieBody,generation: int) -> void:
    if generation != _run_generation: return
    if is_instance_valid(a) and a.manager != self or is_instance_valid(b) and b.manager != self: return
    if not is_instance_valid(a) or not is_instance_valid(b) or a.is_queued_for_deletion() or b.is_queued_for_deletion() or a.destroy_pending or b.destroy_pending:
        for survivor in [a,b]:
            if is_instance_valid(survivor) and not survivor.is_queued_for_deletion() and not survivor.destroy_pending: survivor.merge_locked = false
        return
    if is_frozen():
        a.merge_locked = false
        b.merge_locked = false
        return
    var tier := a.tier + 1
    var at := (a.position+b.position)*0.5
    var velocity := (a.linear_velocity+b.linear_velocity)*0.35
    a.remove_from_group("plushies")
    b.remove_from_group("plushies")
    a.queue_free()
    b.queue_free()
    var toy := _spawn(tier,at)
    if toy == null: return
    var extent := toy.render_size*0.5
    toy.position.x = clampf(at.x,tank_rect.position.x+extent.x+4,tank_rect.end.x-extent.x-4)
    toy.position.y = minf(at.y,tank_rect.end.y-extent.y-4)
    toy.linear_velocity = velocity+Vector2(0,-90)
    toy.squish_velocity = 4.5
    toy.halo = 0.0 if reduced_motion() else 0.6
    var first_discovery := not discovered[tier]
    discovered[tier] = true
    session.merge(tier)
    feedback.burst(toy.position)
    audio.play_merge(tier,first_discovery)
    if session.outcome != "": _finish_run()

func request_bomb_detonation(bomb: Bomb,contacts: Array) -> void:
    if is_frozen() or not is_instance_valid(bomb) or bomb.manager != self or bomb.destroy_pending: return
    var victims: Array[PlushieBody] = [bomb]
    for other in get_board_toys():
        if other is PlushieBody and other != bomb and other.manager == self and not other.held and not other.destroy_pending and not other.is_queued_for_deletion():
            if contacts.has(other) or bomb.reaches(other): victims.append(other)
    # Claim the blast snapshot before any deferred merge can consume it.
    for toy in victims: toy.destroy_pending = true
    call_deferred("_detonate_bomb",bomb,victims,_run_generation)

func _detonate_bomb(bomb: Bomb,victims: Array[PlushieBody],generation: int) -> void:
    if generation != _run_generation or not is_instance_valid(bomb) or bomb.manager != self or bomb.is_queued_for_deletion(): return
    if is_frozen():
        for toy in victims:
            if is_instance_valid(toy): toy.destroy_pending = false
        bomb.detonation_requested = false
        return
    feedback.bomb_burst(bomb.position)
    audio.play_bomb_pop()
    for toy in victims:
        if not is_instance_valid(toy) or toy.manager != self or toy.is_queued_for_deletion(): continue
        if toy.is_in_group("plushies"): toy.remove_from_group("plushies")
        toy.queue_free()

func plushie_impact(strength: float,tier := 0,wall := false) -> void:
    if _impact_cooldown > 0 or is_frozen(): return
    _impact_cooldown = 0.18
    if strength > 0.35: audio.play_impact(strength,tier,wall)

func _finish_run() -> void:
    if _recorded or session.outcome == "": return
    _recorded = true
    var name_text: String = settings.values.name if not str(settings.values.name).strip_edges().is_empty() else t("ui.player")
    var result := session.score.finish({"run_id":session.run_id,"name":name_text,
        "stage":session.stage.id,"stage_index":stage_index,"outcome":session.outcome,
        "timestamp":int(Time.get_unix_time_from_system()),"duration":snappedf(session.elapsed,0.01),
        "config":tweaks.marker()+"-"+JSON.stringify({"stage":session.stage,"goal_time_bonus":Session.GOAL_TIME_BONUS_SECONDS,"pile_depth":tank_rect.end.y-danger_y(),"bomb_percent":BombDefinition.CHANCE_PERCENT,"bomb_fuse":BombDefinition.FUSE_SECONDS,"bomb_margin":BombDefinition.BLAST_MARGIN,"rescue_distance":Session.RESCUE_DISTANCE}).sha256_text().left(8),"eligible":session.reason != "resize" and not tweaks.tainted and not is_sandbox_mode(),"merges":session.merges,
        "reason":session.reason,"goals_reached":session.goals_reached})
    if not is_sandbox_mode(): leaderboard.record(result)
    tweaks.running = false
    audio.set_music_mood(GameAudio.MusicMood.GAME_OVER)
    if session.outcome == "defeat": audio.play_game_over()
    else: audio.play_victory()
    routes.go("debrief")

func start_stage(index := 0, definition: Dictionary = {}) -> bool:
    var stage: Dictionary = definition.duplicate(true) if not definition.is_empty() else Stages.STAGES[clampi(index,0,Stages.STAGES.size()-1)].duplicate(true)
    if not Stages.validate(stage) or not Plush.resources_valid() or not Bomb.bomb_resources_valid():
        error_key = "error.stage" if not Stages.validate(stage) else "error.assets"
        routes.go("error")
        return false
    _clear_run()
    stage_index = index
    _sandbox_run = tweaks.enabled
    tweaks.begin_run()
    if tweaks.requested["gameplay.time_limit"] != tweaks.by_id["gameplay.time_limit"].default:
        stage.time_limit = tweaks.value("gameplay.time_limit")
    session.start(stage,float(tweaks.value("gameplay.score.multiplier")))
    for record in stage.initial:
        _spawn(record.tier,Vector2(record.x,record.y+tank_rect.end.y-TANK.end.y))
        discovered[record.tier] = true
    held_tier = session.next_tier()
    next_tier = session.next_tier(1)
    _load_claw()
    audio.play_restart()
    routes.go("gameplay")
    reset_resize_guard()
    return true

func restart_game() -> void:
    start_stage(stage_index)

func return_title() -> void:
    if multiplayer_active():
        _close_multiplayer()
        return
    _clear_run()
    tweaks.running = false
    routes.go("title")

func multiplayer_active() -> bool:
    return is_instance_valid(_multiplayer_screen)

func open_multiplayer() -> void:
    if multiplayer_active() or routes.route != "title" or routes.modal() != "": return
    if not device.local_splitscreen_allowed(get_viewport_rect().size): return
    var screen_script = load("res://scripts/multiplayer/multiplayer_screen.gd")
    if screen_script == null: return
    _clear_run()
    _multiplayer_layer = CanvasLayer.new()
    _multiplayer_layer.layer = 40
    add_child(_multiplayer_layer)
    _multiplayer_screen = screen_script.new()
    _multiplayer_screen.game = self
    _multiplayer_screen.closed.connect(_close_multiplayer)
    _hud.sync_routes()
    _hud.hide()
    get_viewport().canvas_transform = Transform2D.IDENTITY
    _multiplayer_layer.add_child(_multiplayer_screen)
    _multiplayer_screen.set_app_visible(device.app_visible)

func _close_multiplayer() -> void:
    set_resize_ended(false)
    if is_instance_valid(_multiplayer_layer): _multiplayer_layer.queue_free()
    _multiplayer_screen = null
    _multiplayer_layer = null
    _hud.show()
    routes.go("title")
    _hud.rebuild()

func _clear_run() -> void:
    set_resize_ended(false)
    _sandbox_run = false
    _run_generation += 1
    for toy in get_board_toys():
        toy.remove_from_group("plushies")
        toy.queue_free()
    if is_instance_valid(held_toy): held_toy.queue_free()
    held_toy = null
    overflow_time = 0
    danger_armed = true
    claw_state = ClawState.HOLDING
    claw_timer = 0
    claw_openness = 0
    discovered.fill(false)
    aim_x = 720
    _last_audio_x = aim_x
    _impact_cooldown = 0
    held_axis = 0
    _aim_touch_index = -1
    _recorded = false
    feedback.clear()
    audio.clear_transients()

func open_modal(kind: String) -> void:
    # Retired solo controls must not open a Paused route over a live match.
    # Multiplayer owns its Audio/Leave overlays and keeps its authority running.
    if multiplayer_active(): return
    if kind == "help" and (routes.route != "title" or not routes.modal().is_empty()): return
    if kind == "tweaks": return
    if kind == "leaderboard" and not leaderboard_available(): return
    if kind == "share": return # This template records standings only on this device.
    held_axis = 0
    _aim_touch_index = -1
    _hud.dismiss_editor()
    routes.open(kind,get_viewport().gui_get_focus_owner())
    audio.play_ui("open")

func close_modal() -> void:
    _hud.dismiss_editor()
    routes.close()
    audio.play_ui("cancel")

func toggle_pause() -> void:
    if multiplayer_active(): return
    if routes.modal() != "": close_modal()
    elif routes.route == "gameplay": open_modal("pause")

func toggle_help() -> void:
    if multiplayer_active() or routes.route != "title": return
    if routes.modal() == "help": close_modal()
    else: open_modal("help")

func confirm_loss(action: String) -> void:
    if routes.route != "gameplay":
        if action == "restart": restart_game()
        else: return_title()
        return
    _confirm_action = action
    open_modal("confirm")

func confirm_action() -> void:
    if _confirm_action == "restart": restart_game()
    else: return_title()

func toggle_audio() -> void:
    setting("muted",not audio_muted)
    if not audio_muted: audio.play_ui("toggle")

func setting(key: String, value: Variant) -> void:
    settings.set_value(key,value)
    if key == "locale":
        locale.locale = settings.values.locale
        TranslationServer.set_locale(locale.locale)
        if OS.has_feature("web"):
            JavaScriptBridge.eval("try { localStorage.setItem('plushie_locale'," + JSON.stringify(locale.locale) + ") } catch (_) {}")
        if multiplayer_active():
            _multiplayer_screen.on_device_changed()
        else:
            _hud.rebuild()
    _apply_presentation()

func _apply_presentation() -> void:
    if not is_instance_valid(audio): return
    if is_sandbox_mode():
        if routes.modal() == "leaderboard": routes.close()
    audio.apply_settings(settings.values, tweaks.active)
    feedback.reduced_motion = reduced_motion()
    if reduced_motion():
        feedback.particles.clear()
        for toy in get_board_toys():
            toy.visual_scale = Vector2.ONE
            toy.halo = 0
            toy.queue_redraw()
    feedback.intensity = tweaks.value("environment.particles")
    feedback.ambient = tweaks.value("environment.ambient")
    if is_instance_valid(_hud): _hud.apply_presentation()

func _route_changed() -> void:
    var freeze_now := is_frozen()
    Input.set_default_cursor_shape(Input.CURSOR_ARROW)
    for toy in get_board_toys(): toy.freeze = freeze_now
    visible = routes.route == "gameplay" or routes.route == "debrief"
    if routes.route != "debrief":
        audio.set_music_mood(GameAudio.MusicMood.DUCKED if freeze_now else GameAudio.MusicMood.ACTIVE)
    feedback.paused = freeze_now
    _hud.sync_routes()

func _notification(what: int) -> void:
    if what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_IN,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
        device.app_visible = what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_WM_WINDOW_FOCUS_IN]
        if multiplayer_active():
            _multiplayer_screen.set_app_visible(device.app_visible)
            return
    if multiplayer_active(): return
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not is_frozen(): open_modal("pause")

func _input(event: InputEvent) -> void:
    if multiplayer_active(): return
    if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1: return
    if event is InputEventScreenTouch or event is InputEventScreenDrag: input_method = "touch"
    elif event is InputEventJoypadButton or event is InputEventJoypadMotion: input_method = "gamepad"
    elif event is InputEventKey: input_method = "keyboard"
    elif event is InputEventMouseButton or event is InputEventMouseMotion: input_method = "pointer"
    if is_instance_valid(audio) and event.is_pressed(): audio.ensure_music_playing()

func _unhandled_input(event: InputEvent) -> void:
    if multiplayer_active(): return
    # Emulated mouse input serves native UI controls; the original touch owns play.
    if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == -1: return
    audio.ensure_music_playing()
    if event is InputEventKey and event.pressed and not event.echo:
        input_method = "keyboard"
        if event.keycode == KEY_ESCAPE or event.keycode == KEY_P: toggle_pause()
        elif event.keycode == KEY_H: toggle_help()
        elif event.keycode == KEY_M: toggle_audio()
        elif event.keycode == KEY_R and routes.modal() == "" and routes.route == "gameplay": confirm_loss("restart")
        elif event.keycode in [KEY_SPACE,KEY_ENTER] and routes.modal() == "" and routes.route == "gameplay": request_drop()
    elif event is InputEventJoypadButton and event.pressed:
        input_method = "gamepad"
        if event.button_index == JOY_BUTTON_START: toggle_pause()
        elif event.button_index == JOY_BUTTON_A and not is_frozen(): request_drop()
        elif event.button_index == JOY_BUTTON_B and routes.modal() != "": close_modal()
    elif event is InputEventJoypadMotion: input_method = "gamepad"
    elif event is InputEventMouseMotion and not is_frozen():
        input_method = "pointer"
        if board_screen_rect.has_point(event.position):
            Input.set_default_cursor_shape(Input.CURSOR_CROSS)
            _aim_pointer(event.position)
        else: Input.set_default_cursor_shape(Input.CURSOR_ARROW)
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        input_method = "pointer"
        _pointer(event.position)
    elif event is InputEventScreenTouch:
        input_method = "touch"
        if event.pressed:
            if _aim_touch_index < 0 and not is_frozen() and board_screen_rect.has_point(event.position) and not _hud.blocks_pointer(event.position):
                _aim_touch_index = event.index
                _touch_start = event.position
                _touch_dragged = false
                _aim_pointer(event.position)
        elif event.index == _aim_touch_index:
            _aim_touch_index = -1
            if not _hud.blocks_pointer(event.position): _pointer(event.position)
    elif event is InputEventScreenDrag and not is_frozen() and event.index == _aim_touch_index:
        input_method = "touch"
        _touch_dragged = _touch_dragged or event.position.distance_to(_touch_start) > 12
        if board_screen_rect.has_point(event.position):
            Input.set_default_cursor_shape(Input.CURSOR_CROSS)
            _aim_pointer(event.position)
        else: Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _aim_pointer(at: Vector2) -> void:
    aim_x = (get_viewport().canvas_transform.affine_inverse() * at).x
    _clamp_aim()

func _pointer(at: Vector2) -> void:
    if is_frozen() or not tank_rect.has_point(get_viewport().canvas_transform.affine_inverse() * at): return
    _aim_pointer(at)
    request_drop()

func _create_walls() -> void:
    for index in range(3):
        var wall := StaticBody2D.new()
        wall.add_to_group("cabinet_walls" if index < 2 else "cabinet_floor")
        var collision := CollisionShape2D.new()
        collision.shape = RectangleShape2D.new()
        wall.add_child(collision)
        add_child(wall)
        _walls.append(wall)
    _update_walls()

func _update_walls() -> void:
    var rects := [Rect2(tank_rect.position-Vector2(20,0),Vector2(20,tank_rect.size.y+30)),
        Rect2(tank_rect.end.x,tank_rect.position.y,20,tank_rect.size.y+30),
        Rect2(tank_rect.position.x-20,tank_rect.end.y,tank_rect.size.x+40,30)]
    for index in range(_walls.size()):
        _walls[index].position = rects[index].get_center()
        _walls[index].get_child(0).shape.size = rects[index].size

func _box(rect: Rect2, color: Color, border: Color, radius := 24, width := 2) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(width)
    style.set_corner_radius_all(radius)
    draw_style_box(style,rect)

func _draw() -> void:
    var extension := tank_rect.size.y-TANK.size.y
    _box(Rect2(365,128,710,680+extension),Color("cbb1db"),Color("aa8fb9"),40,3)
    _box(Rect2(378,140,684,650+extension),Color("eee1f0"),Color("f8f0f7"),32,3)
    _box(Rect2(390,162,660,620+extension),Color("9e7c96"),Color("b095a5"),24,3)
    _box(tank_rect,Color("f9ecdf"),Color("d9b8a9"),16,2)
    draw_line(Vector2(411,216),Vector2(411,730+extension),Color(1,1,1,0.62),4,true)
    draw_line(Vector2(1028,246),Vector2(1028,729+extension),Color(1,1,1,0.45),2,true)

func _exit_tree() -> void:
    if OS.has_feature("web"):
        JavaScriptBridge.get_interface("window").mushiesDeviceChanged = null
        JavaScriptBridge.get_interface("window").mushiesTouchCancelled = null
    for shape in [Input.CURSOR_ARROW,Input.CURSOR_POINTING_HAND,Input.CURSOR_CROSS]:
        Input.set_custom_mouse_cursor(null,shape)
    get_viewport().canvas_transform = Transform2D.IDENTITY

func is_sandbox_mode() -> bool:
    return tweaks.enabled or _sandbox_run

func leaderboard_available() -> bool:
    return not is_sandbox_mode() and routes.modal() != "tweaks"
