extends RefCounted
## Named score events and a copy-on-read final result.
const LIMIT := 10000000
var total := 0
var multiplier := 1.0
var finalized := false
var _result: Dictionary = {}

func reset(factor := 1.0) -> void:
    total = 0
    finalized = false
    _result.clear()
    multiplier = clampf(factor, 0.25, 3.0)

func award(event: String, tier := 0) -> int:
    if finalized: return 0
    var base := 0
    match event:
        "merge":
            if tier < 1 or tier > 10: return 0
            base = 10 * (1 << tier)
        "goal_reached": base = 1000
        _: return 0
    var points := int(round(base * multiplier))
    total = clampi(total + points, 0, LIMIT)
    return points

func finish(metadata: Dictionary) -> Dictionary:
    if not finalized:
        _result = metadata.duplicate(true)
        _result.score = total
        finalized = true
    return _result.duplicate(true)

func result() -> Dictionary:
    return _result.duplicate(true)
