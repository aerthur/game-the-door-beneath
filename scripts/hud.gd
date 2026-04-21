extends CanvasLayer
# Dernière mise à jour : 2026-04-21

@onready var hp_bar     : ProgressBar = $TopLeft/VBox/HPBar
@onready var hp_label   : Label       = $TopLeft/VBox/HPLabel
@onready var room_label : Label       = $TopRight/VBox/RoomLabel
@onready var score_label: Label       = $TopRight/VBox/ScoreLabel
@onready var lane_label : Label       = $TopRight/VBox/LaneLabel
@onready var xp_bar     : ProgressBar = $XPZone/VBox/XPBar
@onready var xp_label   : Label       = $XPZone/VBox/XPLabel
@onready var weapon_vbox: VBoxContainer = $WeaponPanel/VBox
@onready var door_hint  : Label       = $DoorHint
@onready var lvlup_panel: Control     = $LevelUp
@onready var lvlup_hbox : HBoxContainer = $LevelUp/Panel/VBox/Cards
@onready var go_panel      : Control = $GameOver
@onready var version_label : Label   = $VersionLabel

var _current_choices : Array = []

func _ready():
	door_hint.visible   = false
	lvlup_panel.visible = false
	go_panel.visible    = false
	version_label.text  = "v" + ProjectSettings.get_setting("application/config/version", "0.1.0")

# ── HP ───────────────────────────────────────────────────────────
func update_health(cur: int, mx: int):
	hp_bar.max_value = mx
	hp_bar.value     = cur
	hp_label.text    = "❤  %d / %d" % [cur, mx]

# ── Info ─────────────────────────────────────────────────────────
func update_room(n: int):   room_label.text  = "Salle  %d" % n
func update_score(n: int):  score_label.text = "Score  %d" % n
func update_lane(n: int):   lane_label.text  = "File  %d"  % n

# ── XP ───────────────────────────────────────────────────────────
func update_xp(cur: int, needed: int, lv: int):
	xp_bar.max_value = needed
	xp_bar.value     = cur
	xp_label.text    = "Niveau %d   —   %d / %d XP" % [lv, cur, needed]

# ── Armes (panel droit) ──────────────────────────────────────────
func update_weapons(weapons: Array):
	for child in weapon_vbox.get_children():
		if child.name != "Title": child.queue_free()

	for w in weapons:
		var def = get_tree().get_first_node_in_group("game").WEAPON_DEFS[w.id]
		var lbl = Label.new()
		lbl.text = "%s  Nv.%d\n  dmg: %d  cd: %.1fs" % [
			def.name, w.level,
			int(def.base_dmg * (1.0 + (w.level - 1) * 0.5)),
			def.cd
		]
		lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
		var sep = ColorRect.new()
		sep.custom_minimum_size = Vector2(0, 1)
		sep.color = Color(0.3, 0.3, 0.3)
		weapon_vbox.add_child(sep)
		weapon_vbox.add_child(lbl)

# ── Porte ────────────────────────────────────────────────────────
func show_door(): door_hint.visible = true
func hide_door(): door_hint.visible = false

# ── Level up ─────────────────────────────────────────────────────
func show_level_up(choices: Array):
	_current_choices = choices
	lvlup_panel.visible = true

	for child in lvlup_hbox.get_children():
		child.queue_free()

	var game = get_tree().get_first_node_in_group("game")

	for i in choices.size():
		var choice = choices[i]
		var def = game.WEAPON_DEFS[choice.weapon_id]

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(240, 180)

		var vb = VBoxContainer.new()
		card.add_child(vb)

		var badge = Label.new()
		if choice.type == "new":
			badge.text = "✦  NOUVELLE ARME"
			badge.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		else:
			badge.text = "▲  AMÉLIORATION  Nv.%d → %d" % [choice.current_level, choice.current_level + 1]
			badge.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(badge)

		var name_lbl = Label.new()
		name_lbl.text = def.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 20)
		vb.add_child(name_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = def.desc
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vb.add_child(desc_lbl)

		var lvl = choice.current_level if choice.type == "upgrade" else 1
		var next_lvl = lvl + 1 if choice.type == "upgrade" else 1
		var base_dmg = def.base_dmg
		var dmg_lbl = Label.new()
		dmg_lbl.text = "Dégâts : %d → %d" % [
			int(base_dmg * (1.0 + (lvl - 1) * 0.5)),
			int(base_dmg * (1.0 + (next_lvl - 1) * 0.5))
		]
		dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dmg_lbl.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		vb.add_child(dmg_lbl)

		var btn = Button.new()
		btn.text = "Choisir"
		btn.pressed.connect(_on_choice_selected.bind(i))
		vb.add_child(btn)

		lvlup_hbox.add_child(card)

func _on_choice_selected(index: int):
	var game = get_tree().get_first_node_in_group("game")
	game.apply_level_up_choice(_current_choices[index])

func hide_level_up():
	lvlup_panel.visible = false

# ── Game Over ────────────────────────────────────────────────────
func show_game_over(s: int, r: int):
	go_panel.visible = true
	$GameOver/Panel/VBox/LScore.text = "Score  :  %d" % s
	$GameOver/Panel/VBox/LRoom.text  = "Salle atteinte  :  %d" % r

func _on_restart_pressed():
	get_tree().reload_current_scene()
