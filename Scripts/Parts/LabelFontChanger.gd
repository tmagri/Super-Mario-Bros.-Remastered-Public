class_name LabelFontChanger
extends Node

@export var labels: Array[Label]

const MAIN_FONT = preload("uid://bl7sbw4nx3l1t")
const SCORE_FONT = preload("uid://bk0no5p6sifgu")

@export var use_score_font := false

static var current_font: Font = null

func _ready() -> void:
	refresh_font()
	Global.level_theme_changed.connect(refresh_font)

func refresh_font() -> void:
	update_labels()

func update_labels() -> void:
	for i in labels:
		if i == null:
			continue
		i.remove_theme_font_override("font")
		i.add_theme_font_override("font", MAIN_FONT)
