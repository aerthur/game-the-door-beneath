extends CanvasLayer
# Dernière mise à jour : 2026-05-04
# Design System — HUD in-game.
# Layout : TopBar pleine largeur (HP gauche | Info centre | Armes droite)
# Palette (tokens identiques au menu — title_screen.gd) :
#   bg #07070e | gold #b89a4e | gold-dim #6b5a28 | text #cfc8b8 | text-dim #7a7060

# ── Nœuds TopBar ──────────────────────────────────────────────────
@onready var hp_bar     : ProgressBar    = $TopBar/Layout/HPZone/HPBar
@onready var hp_label   : Label          = $TopBar/Layout/HPZone/HPLabel
@onready var room_label : Label          = $TopBar/Layout/InfoZone/RoomLabel
@onready var gold_label : Label          = $TopBar/Layout/InfoZone/ScoreLabel
@onready var weapon_row : HBoxContainer  = $TopBar/Layout/WeaponRow

# ── Autres nœuds ──────────────────────────────────────────────────
@onready var xp_bar     : ProgressBar    = $XPZone/VBox/XPBar
@onready var xp_label   : Label          = $XPZone/VBox/XPLabel
@onready var door_hint  : Label          = $DoorHint
@onready var lvlup_panel: Control        = $LevelUp
@onready var lvlup_hbox : HBoxContainer  = $LevelUp/Panel/VBox/Cards
@onready var go_panel      : Control     = $GameOver
@onready var version_label : Label       = $VersionLabel
@onready var touch_buttons    : Control  = $TouchButtons
@onready var btn_next_room    : Button   = $TouchButtons/BtnNextRoom
@onready var portrait_warning : Control  = $PortraitWarning

var _current_choices : Array = []
var _touch_enabled   : bool  = false
var _serif           : Font  = null    # police serif partagée

# ── Cooldown live ─────────────────────────────────────────────────
var _game_ref              = null       # Node game (groupe "game"), init lazy dans _process
var _weapon_cooldown_bars  : Array = [] # Array[ProgressBar] — une entrée par arme active
var _cd_bar_states         : Array = [] # Array[bool] — true = état "prêt" affiché

# StyleBoxes pré-construites pour les barres de cooldown (évite new à chaque frame)
var _cd_fill_charging : StyleBoxFlat = null
var _cd_fill_ready    : StyleBoxFlat = null

# ── Design tokens ─────────────────────────────────────────────────
const C_BG       := Color(0.027, 0.027, 0.055)    # #07070e
const C_GOLD     := Color(0.722, 0.604, 0.306)    # #b89a4e
const C_GOLD_DIM := Color(0.420, 0.353, 0.157)    # #6b5a28
const C_TEXT     := Color(0.812, 0.784, 0.722)    # #cfc8b8
const C_TEXT_DIM := Color(0.478, 0.439, 0.376)    # #7a7060
const C_STONE    := Color(0.047, 0.035, 0.024)    # #0c0906
const C_HP_FILL  := Color(0.600, 0.118, 0.118)    # #991e1e — barre HP (rouge profond)
const C_XP_FILL  := Color(0.435, 0.337, 0.122)    # #6f561f — barre XP (or sombre)


func _ready():
	door_hint.visible   = false
	lvlup_panel.visible = false
	go_panel.visible    = false
	btn_next_room.visible = false
	version_label.text  = "v" + ProjectSettings.get_setting("application/config/version", "0.1.0")

	_touch_enabled = DisplayServer.is_touchscreen_available()
	touch_buttons.visible = _touch_enabled

	# Connexion programmatique des boutons Game Over
	var btn_restart = $GameOver/Panel/VBox/Restart
	var btn_menu    = $GameOver/Panel/VBox/MenuPrincipal
	if not btn_restart.pressed.is_connected(_on_restart_pressed):
		btn_restart.pressed.connect(_on_restart_pressed)
	if not btn_menu.pressed.is_connected(_on_menu_principal_pressed):
		btn_menu.pressed.connect(_on_menu_principal_pressed)

	# Contrôles tactiles
	var btn_left  : Button = $TouchButtons/BtnLeft
	var btn_right : Button = $TouchButtons/BtnRight
	btn_left.button_down.connect(_on_touch_left)
	btn_right.button_down.connect(_on_touch_right)
	btn_next_room.button_down.connect(_on_touch_next_room)
	btn_left.add_theme_font_size_override("font_size", 36)
	btn_right.add_theme_font_size_override("font_size", 36)
	btn_next_room.add_theme_font_size_override("font_size", 22)
	$PortraitWarning/Panel/VBox/Icon.add_theme_font_size_override("font_size", 80)
	$PortraitWarning/Panel/VBox/Message.add_theme_font_size_override("font_size", 26)

	get_viewport().size_changed.connect(_check_orientation)
	_check_orientation()

	_style_hud()


# ── Mise à jour live des cooldowns (lecture passive du jeu) ───────
func _process(_delta: float) -> void:
	if _weapon_cooldown_bars.is_empty(): return
	if _game_ref == null:
		_game_ref = get_tree().get_first_node_in_group("game")
		if _game_ref == null: return

	var awpns : Array = _game_ref.active_weapons
	for i in mini(awpns.size(), _weapon_cooldown_bars.size()):
		var cd_bar : ProgressBar = _weapon_cooldown_bars[i]
		if not is_instance_valid(cd_bar): continue
		var w   : Dictionary = awpns[i]
		var def : Dictionary = GameData.WEAPON_DEFS.get(w.id, {})
		if def.is_empty() or def.get("cd", 0.0) <= 0.0: continue

		var ratio : float = clampf(w.acc / def.cd, 0.0, 1.0)
		cd_bar.value = ratio

		# Bascule couleur une seule fois quand on franchit le seuil "prêt"
		var now_ready : bool = ratio >= 0.88
		if i < _cd_bar_states.size() and now_ready != _cd_bar_states[i]:
			_cd_bar_states[i] = now_ready
			cd_bar.add_theme_stylebox_override("fill",
				_cd_fill_ready if now_ready else _cd_fill_charging)


# ── HP ───────────────────────────────────────────────────────────
func update_health(cur: int, mx: int):
	hp_bar.max_value = mx
	hp_bar.value     = cur
	hp_label.text    = "❤  %d / %d" % [cur, mx]

# ── Info ─────────────────────────────────────────────────────────
func update_room(n: int):   room_label.text = "Salle  %d" % n
func update_gold(n: int):   gold_label.text = "💰 Or : %d" % n
func update_lane(_n: int):  pass  # supprimé de l'UI — conservé pour compatibilité

# ── XP ───────────────────────────────────────────────────────────
func update_xp(cur: int, needed: int, lv: int):
	xp_bar.max_value = needed
	xp_bar.value     = cur
	xp_label.text    = "Niveau %d   —   %d / %d XP" % [lv, cur, needed]

# ── Armes — cartes icône + cooldown dans la TopBar ───────────────
func update_weapons(weapons: Array):
	# Vider les cartes existantes
	for child in weapon_row.get_children():
		child.queue_free()
	_weapon_cooldown_bars.clear()
	_cd_bar_states.clear()

	for w in weapons:
		var def      : Dictionary = GameData.WEAPON_DEFS[w.id]
		var icon_str : String     = def.get("icon", "")

		# ── Carte arme ───────────────────────────────────────────
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(72, 0)
		card.add_theme_stylebox_override("panel", _make_panel_style(
			Color(0.047, 0.035, 0.024, 0.88), C_GOLD_DIM, 5))

		var vb = VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 2)
		card.add_child(vb)

		# Ligne icône + nom/niveau
		var hb = HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 4)
		vb.add_child(hb)

		var icon_path : String = def.get("icon_path", "")
		if icon_path != "":
			var tex_rect = TextureRect.new()
			tex_rect.custom_minimum_size = Vector2(22, 22)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.texture = load(icon_path)
			hb.add_child(tex_rect)
		else:
			var icon_lbl = Label.new()
			icon_lbl.text = icon_str
			icon_lbl.add_theme_font_size_override("font_size", 16)
			hb.add_child(icon_lbl)

		var name_lbl = Label.new()
		name_lbl.text = "%s  Nv.%d" % [def.name, w.level]
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		if _serif:
			name_lbl.add_theme_font_override("font", _serif)
		hb.add_child(name_lbl)

		# Barre de cooldown
		var cd_bar = ProgressBar.new()
		cd_bar.custom_minimum_size = Vector2(0, 5)
		cd_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cd_bar.max_value = 1.0
		cd_bar.value     = 0.0
		cd_bar.show_percentage = false
		_style_cd_bar(cd_bar)
		vb.add_child(cd_bar)

		_weapon_cooldown_bars.append(cd_bar)
		_cd_bar_states.append(false)

		weapon_row.add_child(card)


# ── Orientation mobile ───────────────────────────────────────────
func _check_orientation() -> void:
	if not _touch_enabled:
		portrait_warning.visible = false
		return
	var size := get_viewport().get_visible_rect().size
	portrait_warning.visible = size.y > size.x

# ── Contrôles tactiles ───────────────────────────────────────────
func _on_touch_left() -> void:
	var ev := InputEventAction.new()
	ev.action = "lane_left"
	ev.pressed = true
	Input.parse_input_event(ev)

func _on_touch_right() -> void:
	var ev := InputEventAction.new()
	ev.action = "lane_right"
	ev.pressed = true
	Input.parse_input_event(ev)

func _on_touch_next_room() -> void:
	var ev := InputEventAction.new()
	ev.action = "next_room"
	ev.pressed = true
	Input.parse_input_event(ev)

# ── Porte ────────────────────────────────────────────────────────
func show_door():
	door_hint.visible = true
	btn_next_room.visible = _touch_enabled

func hide_door():
	door_hint.visible = false
	btn_next_room.visible = false

# ── Level up ─────────────────────────────────────────────────────
func show_level_up(choices: Array):
	_current_choices = choices
	lvlup_panel.visible = true

	for child in lvlup_hbox.get_children():
		child.queue_free()

	var game = get_tree().get_first_node_in_group("game")

	for i in choices.size():
		var choice = choices[i]
		var def = GameData.WEAPON_DEFS[choice.weapon_id]

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(240, 180)
		card.add_theme_stylebox_override("panel", _make_panel_style(
			Color(0.047, 0.035, 0.024, 0.97), C_GOLD_DIM, 12))

		var vb = VBoxContainer.new()
		card.add_child(vb)

		var badge = Label.new()
		if choice.type == "new":
			badge.text = "✦  NOUVELLE ARME"
			badge.add_theme_color_override("font_color", Color(0.55, 0.80, 0.55))
		else:
			badge.text = "▲  AMÉLIORATION  Nv.%d → %d" % [choice.current_level, choice.current_level + 1]
			badge.add_theme_color_override("font_color", C_GOLD)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 10)
		if _serif:
			badge.add_theme_font_override("font", _serif)
		vb.add_child(badge)

		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(48, 48)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.visible = false
		vb.add_child(tex_rect)

		var icon_lbl = Label.new()
		var icon_str = def.get("icon", "")
		var icon_path = def.get("icon_path", "")
		if icon_path != "":
			tex_rect.texture = load(icon_path)
			tex_rect.visible = true
			icon_lbl.visible = false
		else:
			icon_lbl.text = icon_str
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 48)
		vb.add_child(icon_lbl)

		var name_lbl = Label.new()
		name_lbl.text = def.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", C_TEXT)
		if _serif:
			name_lbl.add_theme_font_override("font", _serif)
		vb.add_child(name_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = def.desc
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		desc_lbl.add_theme_font_size_override("font_size", 11)
		if _serif:
			desc_lbl.add_theme_font_override("font", _serif)
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
		dmg_lbl.add_theme_font_size_override("font_size", 11)
		if _serif:
			dmg_lbl.add_theme_font_override("font", _serif)
		vb.add_child(dmg_lbl)

		var btn = Button.new()
		btn.text = "Choisir"
		btn.pressed.connect(_on_choice_selected.bind(i))
		if _serif:
			_style_ghost_btn(btn, _serif, C_TEXT, 12)
		btn.custom_minimum_size = Vector2(0, 30)
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
	$GameOver/Panel/VBox/LScore.text = "Or gagné  :  %d 💰" % s
	$GameOver/Panel/VBox/LRoom.text  = "Salle atteinte  :  %d" % r

func _on_restart_pressed():
	print("[HUD] Restart pressed")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main.tscn")

func _on_menu_principal_pressed():
	print("[HUD] Menu principal pressed")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/title_screen.tscn")


# ═══════════════════════════════════════════════════════════════
# ── Design system — helpers ────────────────────────────────────
# ═══════════════════════════════════════════════════════════════

func _make_panel_style(bg: Color, border: Color, pad: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color              = bg
	style.border_width_left     = 1; style.border_width_right   = 1
	style.border_width_top      = 1; style.border_width_bottom  = 1
	style.border_color          = border
	style.corner_radius_top_left     = 2; style.corner_radius_top_right     = 2
	style.corner_radius_bottom_left  = 2; style.corner_radius_bottom_right  = 2
	style.content_margin_left   = float(pad)
	style.content_margin_right  = float(pad)
	style.content_margin_top    = float(pad / 2)
	style.content_margin_bottom = float(pad / 2)
	return style


func _style_progress_bar(bar: ProgressBar, fill_color: Color, bg_color: Color) -> void:
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color            = bg_color
	bg_s.border_width_left   = 1; bg_s.border_width_right  = 1
	bg_s.border_width_top    = 1; bg_s.border_width_bottom = 1
	bg_s.border_color        = C_GOLD_DIM
	bg_s.corner_radius_top_left    = 3; bg_s.corner_radius_top_right    = 3
	bg_s.corner_radius_bottom_left = 3; bg_s.corner_radius_bottom_right = 3

	var fill_s := StyleBoxFlat.new()
	fill_s.bg_color                  = fill_color
	fill_s.corner_radius_top_left    = 3; fill_s.corner_radius_top_right    = 3
	fill_s.corner_radius_bottom_left = 3; fill_s.corner_radius_bottom_right = 3

	bar.add_theme_stylebox_override("background", bg_s)
	bar.add_theme_stylebox_override("fill",       fill_s)


## Barre de cooldown arme — fond pierre, fill or-sombre (→ or vif quand prêt)
func _style_cd_bar(bar: ProgressBar) -> void:
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color   = C_STONE
	bg_s.border_width_bottom = 1
	bg_s.border_color = Color(C_GOLD_DIM.r, C_GOLD_DIM.g, C_GOLD_DIM.b, 0.6)
	bg_s.corner_radius_top_left    = 2; bg_s.corner_radius_top_right    = 2
	bg_s.corner_radius_bottom_left = 2; bg_s.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_s)
	# Fill initial = charging (sera basculé dans _process au franchissement du seuil)
	if _cd_fill_charging != null:
		bar.add_theme_stylebox_override("fill", _cd_fill_charging)


func _style_ghost_btn(btn: Button, font: Font, col: Color, size: int) -> void:
	var style_empty   := StyleBoxEmpty.new()
	var style_hover   := StyleBoxFlat.new()
	style_hover.bg_color             = Color(1, 1, 1, 0.04)
	style_hover.border_width_bottom  = 1
	style_hover.border_color         = C_GOLD_DIM
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(1, 1, 1, 0.08)

	for state in ["normal", "focus"]:
		btn.add_theme_stylebox_override(state, style_empty)
	btn.add_theme_stylebox_override("hover",   style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_font_override("font",            font)
	btn.add_theme_font_size_override("font_size",  size)
	btn.add_theme_color_override("font_color",         col)
	btn.add_theme_color_override("font_hover_color",   C_GOLD)
	btn.add_theme_color_override("font_pressed_color", C_GOLD)
	btn.add_theme_color_override("font_focus_color",   col)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER


# ═══════════════════════════════════════════════════════════════
# ── Design system — application principale ────────────────────
# ═══════════════════════════════════════════════════════════════

func _style_hud() -> void:
	# ── Police serif ─────────────────────────────────────────────
	var serif := SystemFont.new()
	serif.font_names = ["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "Times New Roman"]
	_serif = serif

	# ── StyleBoxes cooldown pré-construites ───────────────────────
	_cd_fill_charging = StyleBoxFlat.new()
	_cd_fill_charging.bg_color                  = C_GOLD_DIM
	_cd_fill_charging.corner_radius_top_left    = 2; _cd_fill_charging.corner_radius_top_right    = 2
	_cd_fill_charging.corner_radius_bottom_left = 2; _cd_fill_charging.corner_radius_bottom_right = 2

	_cd_fill_ready = StyleBoxFlat.new()
	_cd_fill_ready.bg_color                  = C_GOLD
	_cd_fill_ready.corner_radius_top_left    = 2; _cd_fill_ready.corner_radius_top_right    = 2
	_cd_fill_ready.corner_radius_bottom_left = 2; _cd_fill_ready.corner_radius_bottom_right = 2

	# ── TopBar — fond dark fantasy ────────────────────────────────
	$TopBar.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.027, 0.020, 0.016, 0.94), C_GOLD_DIM, 12))

	# ── Barre HP ─────────────────────────────────────────────────
	_style_progress_bar(hp_bar, C_HP_FILL, C_STONE)
	hp_label.add_theme_font_override("font", serif)
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_label.add_theme_color_override("font_color", C_TEXT)

	# ── Labels InfoZone ───────────────────────────────────────────
	room_label.add_theme_font_override("font", serif)
	room_label.add_theme_font_size_override("font_size", 13)
	room_label.add_theme_color_override("font_color", C_TEXT)

	gold_label.add_theme_font_override("font", serif)
	gold_label.add_theme_font_size_override("font_size", 12)
	gold_label.add_theme_color_override("font_color", C_TEXT_DIM)

	# ── Barre XP ─────────────────────────────────────────────────
	_style_progress_bar(xp_bar, C_XP_FILL, C_STONE)
	$XPZone.add_theme_constant_override("margin_left",  14)
	$XPZone.add_theme_constant_override("margin_right", 14)
	xp_label.add_theme_font_override("font", serif)
	xp_label.add_theme_font_size_override("font_size", 11)
	xp_label.add_theme_color_override("font_color", C_TEXT_DIM)

	# ── DoorHint ─────────────────────────────────────────────────
	door_hint.add_theme_font_override("font", serif)
	door_hint.add_theme_font_size_override("font_size", 14)
	door_hint.add_theme_color_override("font_color", C_GOLD)

	# ── Version Label ─────────────────────────────────────────────
	version_label.add_theme_font_override("font", serif)
	version_label.add_theme_font_size_override("font_size", 10)
	version_label.add_theme_color_override("font_color", C_TEXT_DIM)
	version_label.modulate.a = 0.45

	# ── Panel Level Up ────────────────────────────────────────────
	_style_lvlup_panel(serif)

	# ── Panel Game Over ───────────────────────────────────────────
	_style_gameover_panel(serif)

	# ── Portrait warning (mobile) ─────────────────────────────────
	$PortraitWarning/Panel/VBox/Icon.add_theme_color_override("font_color", C_GOLD)
	$PortraitWarning/Panel/VBox/Message.add_theme_font_override("font", serif)
	$PortraitWarning/Panel/VBox/Message.add_theme_color_override("font_color", C_TEXT)


func _style_lvlup_panel(serif: Font) -> void:
	$LevelUp/Panel.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.047, 0.035, 0.024, 0.97), C_GOLD_DIM, 20))

	var lup_title : Label = $LevelUp/Panel/VBox/Title
	lup_title.add_theme_font_override("font", serif)
	lup_title.add_theme_font_size_override("font_size", 18)
	lup_title.add_theme_color_override("font_color", C_GOLD)

	var lup_sub : Label = $LevelUp/Panel/VBox/Subtitle
	lup_sub.add_theme_font_override("font", serif)
	lup_sub.add_theme_font_size_override("font_size", 12)
	lup_sub.add_theme_color_override("font_color", C_TEXT_DIM)


func _style_gameover_panel(serif: Font) -> void:
	$GameOver/Panel.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.047, 0.035, 0.024, 0.97), C_GOLD_DIM, 24))

	var go_title : Label = $GameOver/Panel/VBox/Title
	go_title.add_theme_font_override("font", serif)
	go_title.add_theme_font_size_override("font_size", 20)
	go_title.add_theme_color_override("font_color", C_GOLD)

	for path in ["LScore", "LRoom"]:
		var lbl : Label = $GameOver/Panel/VBox.get_node(path)
		lbl.add_theme_font_override("font", serif)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", C_TEXT)

	_style_ghost_btn($GameOver/Panel/VBox/Restart,       serif, C_TEXT,     13)
	_style_ghost_btn($GameOver/Panel/VBox/MenuPrincipal, serif, C_TEXT_DIM, 12)
