extends Node
# ── TitleScreen ───────────────────────────────────────────────────
# Design System Claude — slide 02 Main Menu.
# Palette : bg #07070e | gold #b89a4e | gold-dim #6b5a28 | text #cfc8b8 | text-dim #7a7060

const DEBUG     = false
const SAVE_PATH = "user://records.json"

# ── Design tokens ─────────────────────────────────────────────────
const C_BG       := Color(0.027, 0.027, 0.055)        # #07070e
const C_GOLD     := Color(0.722, 0.604, 0.306)        # #b89a4e
const C_GOLD_DIM := Color(0.420, 0.353, 0.157)        # #6b5a28
const C_TEXT     := Color(0.812, 0.784, 0.722)        # #cfc8b8
const C_TEXT_DIM := Color(0.478, 0.439, 0.376)        # #7a7060
const C_STONE    := Color(0.047, 0.035, 0.024)        # #0c0906
const C_STONE_LN := Color(0.086, 0.063, 0.031)        # #161008

var records : Dictionary = {}

@onready var best_score_label : Label        = $UI/BestScoreLabel
@onready var scores_panel     : Control      = $UI/ScoresPanel
@onready var btn_new_game     : Button       = $UI/Center/TitlePanel/MenuBox/BtnNewGame
@onready var btn_scores       : Button       = $UI/Center/TitlePanel/MenuBox/BtnScores
@onready var content_label    : Label        = $UI/ScoresPanel/Panel/VBox/Content

func _dbg(msg: String):
	if not DEBUG: return
	print("[TitleScreen] " + msg)

func _ready():
	_dbg("_ready() debut")
	_load_records()
	_dbg("load_records OK — records=%s" % str(records))
	_draw_stone_grid()
	_dbg("draw_stone_grid OK")
	_style_ui()
	_dbg("style_ui OK")
	_update_best_score()
	_dbg("ready TERMINE")

# ── Records ───────────────────────────────────────────────────────
func _load_records():
	if not FileAccess.file_exists(SAVE_PATH):
		records = {}
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		records = {}
		return
	var json = JSON.new()
	if json.parse(f.get_as_text()) == OK:
		records = json.get_data()
	f.close()

# ── Grille de pierres ─────────────────────────────────────────────
func _draw_stone_grid():
	var stone_node = $StoneGrid
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	for row in 11:
		for col in 17:
			var rect = ColorRect.new()
			var b = rng.randf_range(0.035, 0.072)
			# Teinte chaude sombre (tons marron-pierre)
			rect.color = Color(b * 1.05, b * 0.8, b * 0.55, 1.0)
			rect.position = Vector2(col * 76, row * 68)
			rect.size     = Vector2(74, 66)
			stone_node.add_child(rect)

# ── Styles ────────────────────────────────────────────────────────
func _style_ui():
	# Police serif (Palatino sur Windows, Georgia en fallback)
	var serif := SystemFont.new()
	serif.font_names = ["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "Times New Roman"]

	# ── Sous-titre "Un jeu de dark fantasy" ──
	var sub : Label = $UI/Center/TitlePanel/SubtitleLabel
	sub.add_theme_font_override("font", serif)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", C_TEXT_DIM)

	# ── "T H E" ──
	var lbl_the : Label = $UI/Center/TitlePanel/TitleBox/TheLabel
	lbl_the.add_theme_font_override("font", serif)
	lbl_the.add_theme_font_size_override("font_size", 14)
	lbl_the.add_theme_color_override("font_color", C_GOLD_DIM)

	# ── "DOOR" (grand, gras) ──
	var lbl_door : Label = $UI/Center/TitlePanel/TitleBox/DoorLabel
	lbl_door.add_theme_font_override("font", serif)
	lbl_door.add_theme_font_size_override("font_size", 72)
	lbl_door.add_theme_color_override("font_color", C_TEXT)

	# ── "B E N E A T H" ──
	var lbl_ben : Label = $UI/Center/TitlePanel/TitleBox/BeneathLabel
	lbl_ben.add_theme_font_override("font", serif)
	lbl_ben.add_theme_font_size_override("font_size", 14)
	lbl_ben.add_theme_color_override("font_color", C_GOLD_DIM)

	# ── Séparateurs "— ✦ —" ──
	for sep_path in ["Sep0", "Sep1", "Sep2"]:
		var sep_lbl : Label = $UI/Center/TitlePanel/MenuBox.get_node(sep_path)
		sep_lbl.add_theme_font_override("font", serif)
		sep_lbl.add_theme_font_size_override("font_size", 11)
		sep_lbl.add_theme_color_override("font_color", C_GOLD_DIM)

	# ── Boutons fantôme ──
	_style_ghost_button(btn_new_game, serif, C_TEXT, 13)
	_style_ghost_button(btn_scores,   serif, C_TEXT, 13)

	# ── Meilleur score (bas de page) ──
	best_score_label.add_theme_font_override("font", serif)
	best_score_label.add_theme_font_size_override("font_size", 13)
	best_score_label.add_theme_color_override("font_color", C_TEXT_DIM)

	# ── Panel scores (overlay) ──
	_style_scores_panel(serif)

func _style_ghost_button(btn: Button, font: Font, col: Color, size: int) -> void:
	# Transparent, pas de bordure, texte uppercase letter-spaced
	var style_empty  := StyleBoxEmpty.new()
	var style_hover  := StyleBoxFlat.new()
	style_hover.bg_color = Color(1, 1, 1, 0.04)
	style_hover.border_width_bottom = 1
	style_hover.border_color = C_GOLD_DIM
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(1, 1, 1, 0.08)

	for state in ["normal", "focus"]:
		btn.add_theme_stylebox_override(state, style_empty)
	btn.add_theme_stylebox_override("hover",   style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", size)
	btn.add_theme_color_override("font_color",        col)
	btn.add_theme_color_override("font_hover_color",  C_GOLD)
	btn.add_theme_color_override("font_pressed_color", C_GOLD)
	btn.add_theme_color_override("font_focus_color",  col)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.custom_minimum_size = Vector2(280, 36)

func _style_scores_panel(serif: Font) -> void:
	# Fond du panel (StyleBoxFlat sombre avec bordure dorée)
	var panel_node = $UI/ScoresPanel/Panel
	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.047, 0.035, 0.024, 0.97)  # #0c0906
	style.border_width_left  = 1; style.border_width_right  = 1
	style.border_width_top   = 1; style.border_width_bottom = 1
	style.border_color = C_GOLD_DIM
	style.corner_radius_top_left = 2; style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2; style.corner_radius_bottom_right = 2
	style.content_margin_left   = 32; style.content_margin_right = 32
	style.content_margin_top    = 24; style.content_margin_bottom = 24
	panel_node.add_theme_stylebox_override("panel", style)

	var title_lbl = $UI/ScoresPanel/Panel/VBox/Title
	title_lbl.add_theme_font_override("font", serif)
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", C_GOLD)

	content_label.add_theme_font_override("font", serif)
	content_label.add_theme_font_size_override("font_size", 15)
	content_label.add_theme_color_override("font_color", C_TEXT)

	var btn_retour = $UI/ScoresPanel/Panel/VBox/BtnRetour
	_style_ghost_button(btn_retour, serif, C_TEXT_DIM, 12)

# ── Meilleur score ────────────────────────────────────────────────
func _update_best_score():
	if records.has("best_gold"):
		best_score_label.text = "Meilleur score : %d 💰  ·  Salle %d  ·  Niveau %d" % [
			int(records.get("best_gold", 0)),
			int(records.get("best_room", 0)),
			int(records.get("best_level", 0))
		]
	else:
		best_score_label.text = ""

# ── Actions ───────────────────────────────────────────────────────
func _on_nouvelle_partie_pressed():
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_meilleurs_scores_pressed():
	_fill_scores_panel()
	scores_panel.visible = true

func _on_retour_pressed():
	scores_panel.visible = false

func _fill_scores_panel():
	if records.is_empty() or not records.has("best_room"):
		content_label.text = "Aucune partie jouée pour l'instant."
		return

	var best_secs = int(records.get("best_time", 0))
	var fav_text  = "-"
	if records.has("fav_weapon") and records["fav_weapon"] != "":
		var wid = records["fav_weapon"]
		if GameData.WEAPON_DEFS.has(wid):
			var wdef = GameData.WEAPON_DEFS[wid]
			fav_text = "%s %s" % [wdef.icon, wdef.name]

	var kills_g = int(records.get("total_kills_g", 0))
	var kills_b = int(records.get("total_kills_b", 0))
	var kills_r = int(records.get("total_kills_r", 0))
	var runs    = int(records.get("total_runs", 0))

	content_label.text = (
		"🏆  Meilleur score     :  %d or\n" % int(records.get("best_gold", 0)) +
		"🏰  Salle la plus loin :  %d\n"  % int(records.get("best_room", 0)) +
		"⭐  Niveau max         :  %d\n"  % int(records.get("best_level", 0)) +
		"⏱  Meilleur temps     :  %02d:%02d\n" % [best_secs / 60, best_secs % 60] +
		"⚔  Arme préférée      :  %s\n"  % fav_text +
		"💀  Monstres tués      :  %d verts · %d bleus · %d rouges\n" % [kills_g, kills_b, kills_r] +
		"🎮  Parties jouées     :  %d" % runs
	)
