extends RefCounted
const Score := preload("res://scripts/score/score_service.gd")
const Stages := preload("res://data/stages/registry.gd")
const Bomb := preload("res://data/actors/bomb.gd")
const GOAL_TIME_BONUS_SECONDS := 60.0
const RESCUE_DISTANCE := 80.0
var rescue_bomb_granted := false
var _rescue_drop_index := -1
var stage: Dictionary = {}
var score := Score.new()
var elapsed := 0.0
var drops := 0
var merges := 0
var highest := 0
var goal_tier := 3
var goals_reached := 0
var goal_quantity := 1
var dragons_collected := 0
var outcome := ""
var reason := ""
var exhausted_time := 0.0
var run_id := ""
var rng := RandomNumberGenerator.new()
var _drop_rng := RandomNumberGenerator.new()
var _bomb_rng := RandomNumberGenerator.new()
var _drop_queue: Array[int] = []

func start(definition: Dictionary, multiplier := 1.0) -> bool:
    if not Stages.validate(definition): return false
    stage = definition.duplicate(true)
    rescue_bomb_granted = false
    _rescue_drop_index = -1
    elapsed = 0.0
    drops = 0
    merges = 0
    highest = 0
    goal_tier = int(stage.target)
    goals_reached = 0
    goal_quantity = 1
    dragons_collected = 0
    outcome = ""
    reason = ""
    exhausted_time = 0.0
    run_id = "%d-%d" % [Time.get_unix_time_from_system() * 1000, Time.get_ticks_usec()]
    rng.seed = int(stage.seed)
    _drop_rng.seed = int(stage.seed) ^ 0x44524F50
    _bomb_rng.seed = int(stage.seed) ^ 0x424F4D42
    _drop_queue.clear()
    if uses_random_drops():
        for index in range(2): _drop_queue.append(_roll_drop())
    score.reset(multiplier)
    return true

func tick(delta: float) -> void:
    if outcome != "": return
    elapsed += maxf(0, delta)
    if remaining_time() <= 0.0: finish("defeat", "timeout")

func time_budget() -> float:
    # Derive earned time from completed goals so each goal grants it exactly once.
    return float(stage.get("time_limit",180)) + goals_reached * GOAL_TIME_BONUS_SECONDS

func remaining_time() -> float:
    return maxf(0.0,time_budget()-elapsed)

func merge(tier: int) -> int:
    if outcome != "": return 0
    merges += 1
    highest = maxi(highest, tier)
    var points := score.award("merge", tier)
    if tier == 10: dragons_collected += 1
    if tier >= goal_tier:
        goals_reached += 1
        score.award("goal_reached")
        goal_tier = mini(10,tier+1)
        # After the final tier, keep collecting dragons in the same run.
        goal_quantity = dragons_collected+1 if tier == 10 else 1
    return points

func finish(result: String, why: String) -> void:
    if outcome != "": return
    outcome = result
    reason = why

func next_tier(offset := 0) -> int:
    if stage.is_empty(): return 0
    if drops+offset == _rescue_drop_index: return Bomb.TIER
    if uses_random_drops(): return _drop_queue[clampi(offset,0,1)]
    var index: int = (drops+offset) % stage.drops.size() if stage.get("repeat_drops",false) else mini(drops+offset,stage.drops.size()-1)
    return int(stage.drops[index])

func uses_random_drops() -> bool:
    return stage.get("drop_mode","authored") == "goal_random"

func _roll_drop() -> int:
    var ordinary := _drop_rng.randi_range(0,clampi(goal_tier-2,0,8))
    return Bomb.TIER if _bomb_rng.randi_range(0,99) < Bomb.CHANCE_PERCENT else ordinary

func record_drop() -> void:
    if not can_drop(): return
    drops += 1
    if uses_random_drops():
        # Preserve the promised preview; only the newly queued toy is randomized.
        _drop_queue.pop_front()
        _drop_queue.append(_roll_drop())

func can_drop() -> bool:
    return outcome == "" and not stage.is_empty() and (uses_random_drops() or stage.get("repeat_drops",false) or drops < stage.drops.size())

func grant_rescue_bomb(offset := 1) -> bool:
    if rescue_bomb_granted or not can_drop(): return false
    rescue_bomb_granted = true
    _rescue_drop_index = drops+offset
    return true
