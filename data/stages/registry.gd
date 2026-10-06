extends RefCounted
const STAGES := [
    {"id":"first_hugs", "name_key":"stage.first_hugs", "target":3, "time_limit":180.0, "drop_mode":"goal_random",
     "initial":[], "seed":104729},
    {"id":"pocket_workshop", "name_key":"stage.pocket_workshop", "target":5, "time_limit":180.0, "drop_mode":"goal_random",
     "initial":[{"tier":3,"x":550.0,"y":670.0},{"tier":3,"x":870.0,"y":670.0}],
     "seed":130363}
]

static func validate(stage: Dictionary) -> bool:
    for key in ["id","name_key","target","time_limit","initial","seed"]:
        if not stage.has(key): return false
    if not stage.id is String or stage.id.is_empty() or not stage.name_key is String: return false
    if not stage.target is int or stage.target < 1 or stage.target > 10: return false
    if not (stage.time_limit is float or stage.time_limit is int): return false
    if not is_finite(float(stage.time_limit)) or stage.time_limit < 15 or stage.time_limit > 600: return false
    if not stage.initial is Array or stage.initial.size() > 16 or not stage.seed is int: return false
    if stage.get("drop_mode","authored") not in ["authored","goal_random"]: return false
    var random_drops: bool = stage.get("drop_mode","authored") == "goal_random"
    if random_drops and stage.target < 2: return false
    if not stage.get("repeat_drops",false) is bool: return false
    var mass_units := 0
    if not random_drops:
        if not stage.get("drops") is Array or stage.drops.is_empty() or stage.drops.size() > 64: return false
        for tier in stage.drops:
            if not tier is int or tier < 0 or tier >= stage.target: return false
            mass_units += 1 << tier
    for toy in stage.initial:
        if not toy is Dictionary: return false
        for key in ["tier","x","y"]:
            if not toy.has(key): return false
        if not toy.tier is int or toy.tier < 0 or toy.tier >= stage.target: return false
        for axis in ["x","y"]:
            if not (toy[axis] is int or toy[axis] is float) or not is_finite(float(toy[axis])): return false
        if toy.x < 500 or toy.x > 940 or toy.y < 510 or toy.y > 680: return false
        mass_units += 1 << toy.tier
    return random_drops or stage.get("repeat_drops",false) or mass_units >= (1 << stage.target)
