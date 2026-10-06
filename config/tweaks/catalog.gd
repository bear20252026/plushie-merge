extends RefCounted
## Authoritative descriptors. The panel and validation consume this same catalog.
const VERSION := 1
const CATEGORIES := ["UI", "GAMEPLAY", "AUDIO", "PLAYER", "ENEMIES", "ENVIRONMENT"]

static func descriptors() -> Array[Dictionary]:
    return [
        d("ui.hud.opacity", "UI", "float", 1.0, 0.55, 1.0, 0.05, "LIVE", "COSMETIC"),
        d("ui.text.scale", "UI", "float", 1.0, 0.9, 1.2, 0.05, "LIVE", "COSMETIC"),
        d("ui.score.visible", "UI", "bool", true, 0, 1, 1, "LIVE", "COSMETIC"),
        d("ui.reduced_motion", "UI", "bool", false, 0, 1, 1, "LIVE", "COSMETIC"),
        d("gameplay.time_limit", "GAMEPLAY", "float", 180.0, 30, 300, 15, "NEXT_RUN", "GAMEPLAY", "seconds"),
        d("gameplay.score.multiplier", "GAMEPLAY", "float", 1.0, 0.25, 3.0, 0.25, "NEXT_RUN", "SCORE_AFFECTING"),
        d("gameplay.settle_seconds", "GAMEPLAY", "float", 3.0, 2, 6, 0.5, "NEXT_RUN", "GAMEPLAY", "seconds"),
        d("gameplay.overflow_seconds", "GAMEPLAY", "float", 2.8, 1.4, 5.6, 0.2, "NEXT_RUN", "GAMEPLAY", "seconds"),
        d("audio.master.gain", "AUDIO", "float", 0.0, -24, 0, 1, "LIVE", "COSMETIC", "db"),
        d("audio.music.gain", "AUDIO", "float", 0.0, -24, 0, 1, "LIVE", "COSMETIC", "db"),
        d("audio.sfx.gain", "AUDIO", "float", 0.0, -24, 0, 1, "LIVE", "COSMETIC", "db"),
        d("audio.ui.gain", "AUDIO", "float", 0.0, -24, 0, 1, "LIVE", "COSMETIC", "db"),
        d("player.aim.speed", "PLAYER", "float", 420.0, 180, 660, 30, "NEXT_ACTION", "GAMEPLAY", "speed"),
        d("player.claw.open_seconds", "PLAYER", "float", 0.18, 0.12, 0.36, 0.02, "NEXT_ACTION", "GAMEPLAY", "seconds"),
        d("player.claw.reload_seconds", "PLAYER", "float", 0.55, 0.35, 1.15, 0.05, "NEXT_ACTION", "GAMEPLAY", "seconds"),
        d("player.release.spin", "PLAYER", "float", 0.35, 0, 0.7, 0.05, "NEXT_ACTION", "GAMEPLAY"),
        d("enemies.toy.bounce", "ENEMIES", "float", 0.46, 0.1, 0.7, 0.02, "NEXT_SPAWN", "GAMEPLAY"),
        d("enemies.toy.friction", "ENEMIES", "float", 0.68, 0.2, 1.0, 0.02, "NEXT_SPAWN", "GAMEPLAY"),
        d("enemies.toy.gravity", "ENEMIES", "float", 1.0, 0.5, 1.5, 0.1, "NEXT_SPAWN", "GAMEPLAY"),
        d("enemies.toy.squish", "ENEMIES", "float", 0.5, 0, 1, 0.1, "LIVE", "COSMETIC"),
        d("environment.filter.enabled", "ENVIRONMENT", "bool", true, 0, 1, 1, "LIVE", "COSMETIC"),
        d("environment.filter.intensity", "ENVIRONMENT", "float", 0.18, 0, 0.5, 0.02, "LIVE", "COSMETIC"),
        d("environment.particles", "ENVIRONMENT", "float", 1.0, 0, 1.5, 0.25, "LIVE", "COSMETIC"),
        d("environment.ambient", "ENVIRONMENT", "bool", true, 0, 1, 1, "LIVE", "COSMETIC"),
        d("environment.danger.line", "ENVIRONMENT", "float", 354.0, 320, 394, 2, "NEXT_RUN", "GAMEPLAY", "pixels")
    ]

static func d(id: String, category: String, type: String, default: Variant, low: float, high: float,
        step: float, mode: String, integrity: String, unit := "number") -> Dictionary:
    return {"id":id, "category":category, "type":type, "default":default, "min":low, "max":high,
        "step":step, "options":[], "unit":"unit." + unit, "apply_mode":mode, "integrity":integrity,
        "label_key":"tweak." + id + ".label", "description_key":"tweak." + id + ".description",
        "tags":[category.to_lower()]}
