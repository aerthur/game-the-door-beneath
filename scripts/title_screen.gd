extends Node
# ── TitleScreen ───────────────────────────────────────────────────

const DEBUG     = true   # ← mettre false pour désactiver les prints de debug
const SAVE_PATH = "user://records.json"

var records : Dictionary = {}

@onready var best_score_label : Label   = $UI/BestScoreLabel
@onready var scores_panel     : Control = $UI/ScoresPanel
@onready var title_label      : Label   = $UI/TitlePanel/TitleLabel
@onready var sub_label        : Label   = $UI/TitlePanel/SubLabel
@onready var btn_new_game     : Button  = $UI/TitlePanel/BtnNewGame
@onready var btn_scores       : Button  = $UI/TitlePanel/BtnScores
@onready var content_label    : Label   = $UI/ScoresPanel/Panel/VBox/Content

func _dbg(msg: String):
	if not DEBUG: return
	print("[TitleScreen] " + msg)
	push_warning("[TitleScreen] " + msg)  # visible dans Debugger→Errors même après fermeture

func _ready():
	_dbg("_ready() debut")
	_dbg("nodes: best_score_label=%s title_label=%s btn_new_game=%s" % [
		str(best_score_label), str(title_label), str(btn_new_game)])
	_load_records()
	_dbg("load_records OK — records=%s" % str(records))
	_draw_stone_grid()
	_dbg("draw_stone_grid OK")
	_style_ui()
	_dbg("style_ui OK")
	_update_best_score()
	_dbg("ready TERMINE")

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

func _draw_stone_grid():
	var stone_node = $StoneGrid
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	for row in 11:
		for col in 17:
			var rect = ColorRect.new()
			var b = rng.randf_range(0.04, 0.09)
			rect.color = Color(b * 0.9, b * 0.7, b * 1.3, 1.0)
			rect.position = Vector2(col * 76, row * 68)
			rect.size = Vector2(74, 66)
			stone_node.add_child(rect)

func _style_ui():
	_dbg("_style_ui: title_label")
	title_label.add_theme_font_size_override("font_size", 58)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.38))
	_dbg("_style_ui: sub_label")
	sub_label.add_theme_font_size_override("font_size", 16)
	sub_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.60))
	_dbg("_style_ui: buttons")
	btn_new_game.add_theme_font_size_override("font_size", 22)
	btn_scores.add_theme_font_size_override("font_size", 20)
	_dbg("_style_ui: best_score_label")
	best_score_label.add_theme_font_size_override("font_size", 14)
	best_score_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.60))
	_dbg("_style_ui: ScoresPanel/Title")
	$UI/ScoresPanel/Panel/VBox/Title.add_theme_font_size_override("font_size", 20)
	_dbg("_style_ui: content_label")
	content_label.add_theme_font_size_override("font_size", 17)
	_dbg("_style_ui: terminé ✓")

func _update_best_score():
	if records.has("best_gold"):
		best_score_label.text = "Meilleur score : %d 💰" % int(records["best_gold"])
	else:
		best_score_label.text = ""

func _on_nouvelle_partie_pressed():
	btn_new_game.text = "CLICK OK";title_label.text = "TITLE DEBUG OK";sub_label.text = "LE CODE MODIFIE TOURNE";await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_meilleurs_scores_pressed():
	_fill_scores_panel()
	scores_panel.visible = true

func _on_retour_pressed():
	scores_panel.visible = false

func _fill_scores_panel():
	if records.is_empty() or not records.has("best_room"):
		content_label.text = "Aucune partie jouée pour l'instant"
		return

	var best_secs = int(records.get("best_time", 0))
	var mins = best_secs / 60
	var secs = best_secs % 60

	var fav_text = "-"
	if records.has("fav_weapon") and records["fav_weapon"] != "":
		var wid = records["fav_weapon"]
		if GameData.WEAPON_DEFS.has(wid):
			var wdef = GameData.WEAPON_DEFS[wid]
			fav_text = "%s %s" % [wdef.icon, wdef.name]

	var kills_g = int(records.get("total_kills_g", 0))
	var kills_b = int(records.get("total_kills_b", 0))
	var kills_r = int(records.get("total_kills_r", 0))

	content_label.text = (
		"🏆 Meilleur score : %d\n" % int(records.get("best_gold", 0)) +
		"🏰 Salle la plus loin : %d\n" % int(records.get("best_room", 0)) +
		"⏱ Meilleur temps : %02d:%02d\n" % [mins, secs] +
		"⚔ Arme préférée : %s\n" % fav_text +
		"💀 Monstres tués : %d verts, %d bleus, %d rouges" % [kills_g, kills_b, kills_r]
	)
