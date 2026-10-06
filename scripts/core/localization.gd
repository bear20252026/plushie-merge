extends RefCounted
# Body UI: Nunito with Noto Sans SC Chinese at the same weight (subset WOFF2, no system fallback).
const UI_REGULAR := preload("res://assets/template/fonts/ui_regular.tres")
const UI_MEDIUM := preload("res://assets/template/fonts/ui_medium.tres")
const UI_BOLD := preload("res://assets/template/fonts/ui_bold.tres")
# Display faces: logo lockup, and headings / big numbers (Latin -> ZCOOL KuaiLe -> Noto Sans SC).
const TITLE_FONT := preload("res://assets/template/fonts/display/mushies_title.tres")
const HEADING_FONT := preload("res://assets/template/fonts/display/mushies_heading.tres")
var locale := "en"
var dictionaries: Dictionary = {}
var font: Font
var medium_font: Font
var bold_font: Font
var title_font: Font = TITLE_FONT
var heading_font: Font = HEADING_FONT

func _init() -> void:
    dictionaries.en = JSON.parse_string(FileAccess.get_file_as_string("res://localization/en.json"))
    dictionaries.zh_CN = JSON.parse_string(FileAccess.get_file_as_string("res://localization/zh_CN.json"))
    TranslationServer.set_locale(locale)
    font = UI_REGULAR
    medium_font = UI_MEDIUM
    bold_font = UI_BOLD

func font_for_weight(weight := 400) -> Font:
    if weight >= 600: return bold_font
    if weight >= 500: return medium_font
    return font

func t(key: String, placeholders: Dictionary = {}) -> String:
    var text: String = dictionaries.get(locale, dictionaries.en).get(key, dictionaries.en.get(key, key))
    for name in placeholders:
        text = text.replace("{" + String(name) + "}", str(placeholders[name]))
    return text
