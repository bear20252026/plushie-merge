extends Node
class_name GameAudio

const BrowserBgmPlayer = preload("res://scripts/manus/browser_bgm_player.gd")

signal cue_played(cue_name: StringName)

const BANK := preload("res://scripts/sound_bank.gd")
const BGM_STREAM := preload("res://assets/template/audio_v2/runtime/cotton_candy_circuit.ogg")
const MUSIC_ACTIVE_DB := -8.0
const MUSIC_DUCKED_DB := -12.0
const MUSIC_GAME_OVER_DB := -15.0
const CHAIN_WINDOW := 1.2

enum MusicMood { ACTIVE, DUCKED, GAME_OVER }

var muted := false
var music_enabled := true
var sfx_enabled := true
var music_mood := MusicMood.ACTIVE
var _music_player: BrowserBgmPlayer
var _sfx_players: Dictionary = {}
var _carriage: AudioStreamPlayer
var _clock := 0.0
var _last_play: Dictionary = {}
var _last_impact := -99.0
var _impact_variant := 0
var _last_merge := -99.0
var chain_count := 0
var _priority_until := 0.0
var _duck_until := 0.0
var _motion_speed := 0.0
var _motion_expires := 0.0
var music_start_count := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _music_player = BrowserBgmPlayer.new()
    _music_player.name = "ContinuousBackgroundMusic"
    _music_player.bus = &"Music"
    _music_player.volume_db = MUSIC_ACTIVE_DB
    var loop_stream := BGM_STREAM.duplicate() as AudioStreamOggVorbis
    loop_stream.loop = true
    _music_player.stream = loop_stream
    _music_player.buffer_key = BGM_STREAM.resource_path
    add_child(_music_player)
    for key in BANK.STREAMS:
        var player := AudioStreamPlayer.new()
        player.name = String(key).to_pascal_case()
        player.bus = &"UI" if key in [&"ui_click", &"ui_open"] else &"SFX"
        player.volume_db = BANK.LEVELS[key]
        player.max_polyphony = 3 if key in [&"merge_small",&"merge_large"] else 2
        if key == &"carriage_loop":
            var motor_stream := (BANK.STREAMS[key] as AudioStream).duplicate() as AudioStreamOggVorbis
            motor_stream.loop = true
            player.stream = motor_stream
            player.max_polyphony = 1
            player.volume_db = -60.0
            _carriage = player
        else:
            player.stream = BANK.STREAMS[key]
        add_child(player)
        _sfx_players[key] = player
    _apply_bus_mutes()
    ensure_music_playing()

func _process(delta: float) -> void:
    _clock += delta
    if not is_instance_valid(_music_player): return
    var target := MUSIC_ACTIVE_DB
    if music_mood == MusicMood.DUCKED: target = MUSIC_DUCKED_DB
    elif music_mood == MusicMood.GAME_OVER: target = MUSIC_GAME_OVER_DB
    if _clock < _duck_until: target -= 3.0
    _music_player.volume_db = move_toward(_music_player.volume_db,target,delta*20.0)
    var moving := not muted and sfx_enabled and music_mood == MusicMood.ACTIVE and _clock < _motion_expires and _clock >= _priority_until and _motion_speed > 12.0
    var motor_target := -60.0
    if moving:
        motor_target = lerpf(-24.0,-19.0,clampf(_motion_speed/900.0,0,1))
        _carriage.pitch_scale = lerpf(0.96,1.06,clampf(_motion_speed/900.0,0,1))
        if not _carriage.playing:
            _carriage.volume_db = -60.0
            _carriage.play()
            cue_played.emit(&"carriage_loop")
    _carriage.volume_db = move_toward(_carriage.volume_db,motor_target,delta*240.0)
    if not moving and _carriage.volume_db <= -59.0:
        _carriage.stop()

func ensure_music_playing() -> void:
    if muted or not music_enabled or not is_instance_valid(_music_player): return
    if not _music_player.playing:
        _music_player.play()
        music_start_count += 1

func set_muted(value: bool) -> void:
    muted = value
    _apply_bus_mutes()
    if muted:
        _motion_speed = 0
        _motion_expires = 0
        _last_merge = -99
        _stop_one_shots()
        if is_instance_valid(_carriage): _carriage.stop()
    else:
        ensure_music_playing()

func set_music_enabled(value: bool) -> void:
    music_enabled = value
    _apply_bus_mutes()
    if music_enabled and not muted: ensure_music_playing()

func set_sfx_enabled(value: bool) -> void:
    sfx_enabled = value
    _apply_bus_mutes()
    if not sfx_enabled:
        _motion_speed = 0
        _motion_expires = 0
        _stop_one_shots()
        if is_instance_valid(_carriage): _carriage.stop()

func _apply_bus_mutes() -> void:
    var bus_mutes := {&"Music":muted or not music_enabled,
        &"SFX":muted or not sfx_enabled, &"UI":muted or not sfx_enabled}
    for bus in bus_mutes:
        var index := AudioServer.get_bus_index(bus)
        if index >= 0: AudioServer.set_bus_mute(index,bus_mutes[bus])

func set_music_mood(mood: MusicMood) -> void:
    if music_mood == mood: return
    music_mood = mood
    if mood != MusicMood.ACTIVE:
        _motion_speed = 0
        _motion_expires = 0
        _last_merge = -99
        for cue in BANK.LOW_PRIORITY:
            get_cue_player(cue).stop()
        if is_instance_valid(_carriage): _carriage.stop()

func set_carriage_motion(speed: float) -> void:
    _motion_speed = absf(speed)
    _motion_expires = _clock + 0.10

func play_drop(tier: int) -> void:
    _play_cue(&"claw_open",1.02-minf(float(tier),10.0)*0.007)

func play_release() -> void:
    _play_cue(&"release_whoosh")

func play_claw_close() -> void:
    _play_cue(&"claw_close")

func play_bomb_pop() -> void:
    _play_cue(&"bomb_pop")

func play_impact(strength: float = 0.5,tier: int = 0,wall: bool = false) -> void:
    if muted or not sfx_enabled or music_mood != MusicMood.ACTIVE or strength < 0.20 or _clock-_last_impact < 0.10 or _clock < _priority_until: return
    var cue := &"impact_soft_a"
    if wall:
        cue = &"wall_tap"
    elif tier >= 6 or strength > 0.8:
        cue = &"impact_heavy"
    else:
        cue = &"impact_soft_a" if _impact_variant%2==0 else &"impact_soft_b"
    if _play_cue(cue,randf_range(0.95,1.05),lerpf(-5.0,0.0,clampf(strength,0,1))):
        _last_impact = _clock
        if cue == &"impact_soft_a" or cue == &"impact_soft_b": _impact_variant += 1

func play_merge(tier: int,first_discovery: bool = false) -> void:
    chain_count = chain_count+1 if _clock-_last_merge <= CHAIN_WINDOW else 1
    _last_merge = _clock
    if muted or not sfx_enabled: return
    _duck_until = maxf(_duck_until,_clock+0.8)
    if tier >= 10:
        _stop_one_shots()
        _priority_until = _clock+1.5
        _duck_until = _clock+1.8
        _play_cue(&"dragon_arrival")
        return
    if _clock < _priority_until: return
    _play_cue(&"merge_small" if tier<=5 else &"merge_large",0.97+float(tier)*0.012)
    if first_discovery:
        _play_cue(&"discovery")
    if chain_count>=2:
        _play_cue(&"chain_bonus",1.0+minf(float(chain_count-2),3)*0.035)

func play_danger() -> void:
    if muted or not sfx_enabled: return
    _duck_until = maxf(_duck_until,_clock+0.6)
    _play_cue(&"danger")

func play_game_over() -> void:
    _stop_one_shots()
    if is_instance_valid(_carriage): _carriage.stop()
    _priority_until = _clock+1.4
    _play_cue(&"game_over")

func play_ui_click() -> void:
    _play_cue(&"ui_click")

func play_ui_open() -> void:
    _play_cue(&"ui_open")

func play_ui_soft() -> void:
    play_ui_click()

func play_restart() -> void:
    _stop_one_shots()
    _last_play.clear()
    _last_merge = -99
    chain_count = 0
    _priority_until = 0
    _duck_until = 0
    _last_impact = -99
    _motion_speed = 0
    _motion_expires = 0
    if is_instance_valid(_carriage): _carriage.stop()
    set_music_mood(MusicMood.ACTIVE)
    _play_cue(&"restart")

func get_cue_player(cue: StringName) -> AudioStreamPlayer:
    return _sfx_players.get(cue) as AudioStreamPlayer

func _play_cue(cue: StringName,pitch: float = 1.0,gain_offset: float = 0.0) -> bool:
    if muted or not sfx_enabled: return false
    if cue in BANK.LOW_PRIORITY and _clock < _priority_until: return false
    if _clock-float(_last_play.get(cue,-99.0)) < float(BANK.COOLDOWNS.get(cue,0.05)): return false
    var player := get_cue_player(cue)
    if not is_instance_valid(player): return false
    ensure_music_playing()
    player.pitch_scale = pitch
    player.volume_db = float(BANK.LEVELS[cue])+gain_offset
    player.play()
    _last_play[cue] = _clock
    cue_played.emit(cue)
    return true

func _stop_one_shots() -> void:
    for key in _sfx_players:
        if key != &"carriage_loop": (_sfx_players[key] as AudioStreamPlayer).stop()

func _exit_tree() -> void:
    if is_instance_valid(_music_player):
        _music_player.stop()
        _music_player.stream = null
    for player in _sfx_players.values():
        if is_instance_valid(player):
            (player as AudioStreamPlayer).stop()
            (player as AudioStreamPlayer).stream = null
    _sfx_players.clear()

func play_ui(semantic: String) -> void:
    # Shared original cues intentionally cover a family of interface actions.
    var pitch := 1.0
    var gain := 0.0
    var cue := &"ui_click"
    match semantic:
        "hover", "focus": pitch = 1.2; gain = -8.0
        "cancel": pitch = 0.85
        "invalid": pitch = 0.75; gain = -3.0
        "toggle", "select": pitch = 1.08; gain = -3.0
        "open": cue = &"ui_open"
    _play_cue(cue, pitch, gain)

func play_victory() -> void:
    if muted or not sfx_enabled: return
    _duck_until = _clock + 1.5
    _play_cue(&"dragon_arrival")

func clear_transients() -> void:
    _stop_one_shots()
    _last_play.clear()
    _last_merge = -99
    _last_impact = -99
    _priority_until = 0
    _duck_until = 0
    _motion_speed = 0
    _motion_expires = 0
    chain_count = 0
    if is_instance_valid(_carriage): _carriage.stop()

func apply_settings(values: Dictionary, tuning: Dictionary) -> void:
    for pair in [["Master","master"],["Music","music"],["SFX","sfx"],["UI","ui"]]:
        var index := AudioServer.get_bus_index(pair[0])
        var gain: float = tuning.get("audio." + pair[1] + ".gain", 0.0)
        if index >= 0:
            AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001,float(values[pair[1]]))) + gain)
    set_music_enabled(bool(values.get("music_enabled",true)))
    set_sfx_enabled(bool(values.get("sfx_enabled",true)))
    set_muted(bool(values.muted))
