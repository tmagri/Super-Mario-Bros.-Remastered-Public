class_name FontUpdater
extends Node

var main_font: Resource = null
var score_font: Resource = null
var ga_font: Resource = null
var jp_font: Resource = null

var FONT_MAIN = preload("uid://bl7sbw4nx3l1t")
var SCORE_FONT = preload("uid://cflgloiossd8a")


static var current_font: Font = null

func _ready() -> void:
	update_fonts()
	Global.level_theme_changed.connect(update_fonts)

func update_fonts() -> void:
	FONT_MAIN.base_font = main_font
	SCORE_FONT.base_font = score_font
