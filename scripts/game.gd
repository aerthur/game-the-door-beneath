extends Node
# Dernière mise à jour : 2026-04-21

# ── Grille ───────────────────────────────────────────────────────
const LANES    = 5
const ROWS     = 8
const LANE_W   = 180
const ROW_H    = 68
const GRID_X   = (1280 - LANES * LANE_W) / 2
const GRID_Y   = 30
const PLAYER_Y = GRID_Y + ROWS * ROW_H + 24

# ── Lore inter-salles ────────────────────────────────────────────
const LORE_TEXTS = {
	1:  "L'air est humide. Mes bottes résonnent dans le silence. Je descends.",
	2:  "Ces créatures... elles étaient plus nombreuses que prévu. Je continue quand même.",
	3:  "Quelque chose remonte des profondeurs. Une odeur. Ancienne.",
	4:  "Mes mains tremblent légèrement. Je les ignore. La porte m'attend.",
	5:  "Ce monstre... il gardait cette porte. Pourquoi garder une porte ?",
	6:  "Plus bas. Toujours plus bas. La lumière du jour n'existe plus ici.",
	7:  "Je repense aux histoires qu'on racontait sur ce donjon. Je regrette de ne pas avoir écouté.",
	8:  "Ils se multiplient. Comme si le donjon lui-même voulait me repousser.",
	9:  "Je ne sais plus depuis combien de temps je descends. Le temps est différent ici.",
	10: "Ce gardien était plus fort. Beaucoup plus fort. Ce qui suit sera pire.",
	11: "Mes flèches s'épuisent. Heureusement quelque chose dans ce donjon me réapprovisionne. Je préfère ne pas savoir quoi.",
	12: "J'ai entendu une voix. Très loin en dessous. Elle semblait... m'attendre.",
	13: "Le sol vibre légèrement sous mes pieds. Quelque chose de gigantesque se déplace là-dessous.",
	14: "Je pourrais faire demi-tour. Cette pensée me traverse l'esprit à chaque salle. Je ne le ferai pas.",
	15: "Ce gardien rouge... ses yeux étaient intelligents. Il savait qui j'étais. Comment est-ce possible ?",
}

# ── Composition des 10 salles ────────────────────────────────────
# "g" = vert, "b" = bleu (salle 3+), "r" = rouge (salle 6+)
const ROOM_WAVES = {
	1:  ["g","g","g"],
	2:  ["g","g","g","g"],
	3:  ["g","g","g","b"],
	4:  ["g","g","b","b"],
	5:  ["g","b","b","b","b"],
	6:  ["g","g","b","b","b"],
	7:  ["g","b","b","b","b","b"],
	8:  ["b","b","b","b","r","r"],
	9:  ["b","b","b","r","r","r","r"],
	10: ["b","b","r","r","r","r","r"],
}

# ── 8 Armes ──────────────────────────────────────────────────────
const WEAPON_DEFS = {
	"arc":        {"name": "Arc",        "base_dmg": 25, "cd": 1.0,  "desc": "1 ennemi dans la file active",       "icon": "🏹", "icon_path": ""},
	"arbalete":   {"name": "Arbalète",   "base_dmg": 55, "cd": 2.0,  "desc": "Perce 2 ennemis dans la file",       "icon": "🎯", "icon_path": ""},
	"dague":      {"name": "Dague",      "base_dmg": 10, "cd": 0.35, "desc": "Très rapide, file active",           "icon": "🗡️", "icon_path": ""},
	"bombe":      {"name": "Bombe",      "base_dmg": 20, "cd": 2.5,  "desc": "Explose sur 3 files voisines",       "icon": "💣", "icon_path": ""},
	"eclair":     {"name": "Eclair",     "base_dmg": 16, "cd": 1.5,  "desc": "Frappe tous les ennemis de la file", "icon": "⚡", "icon_path": ""},
	"tourbillon": {"name": "Tourbillon", "base_dmg": 12, "cd": 2.0,  "desc": "1ère rangée de chaque file",         "icon": "🌀", "icon_path": ""},
	"givre":      {"name": "Givre",      "base_dmg": 8,  "cd": 1.5,  "desc": "Ralentit l'ennemi 2 ticks",          "icon": "❄️", "icon_path": ""},
	"sismique":   {"name": "Sismique",   "base_dmg": 9,  "cd": 3.0,  "desc": "2 dernières rangées, toutes files",  "icon": "🪨", "icon_path": ""},
}

# ── État ─────────────────────────────────────────────────────────
var player_lane : int  = 2
var player_hp   : int  = 100
var player_max  : int  = 100
var room_num    : int  = 1
var score       : int  = 0
var xp          : int  = 0
var xp_needed   : int  = 60
var hero_level  : int  = 1
var monsters_remaining : int = 0
var spawns_in_flight   : int = 0   # nb de _on_monster_escaped en cours (async)
var room_clear  : bool = false
var game_over   : bool = false
var leveling_up : bool = false

var active_weapons : Array = [{"id": "arc", "level": 1, "acc": 0.0}]
var grid : Array = []
var active_gems : Array = []

var tick_acc : float = 0.0
var tick_interval : float = 1.0

@onready var monsters_node : Node2D      = $Monsters
@onready var player_node   : Node2D      = $Player
@onready var hud           : CanvasLayer = $HUD
@onready var bg            : Node2D      = $Background

var blob_scene  = preload("res://scenes/monster_blob.tscn")
var blue_scene  = preload("res://scenes/monster_blue.tscn")
var red_scene   = preload("res://scenes/monster_red.tscn")
var gem_scene   = preload("res://scenes/gem.tscn")

# ═════════════════════════════════════════════════════════════════
func _ready():
	add_to_group("game")
	_init_grid()
	_draw_background()
	_place_player()
	_start_room(1)
	hud.update_weapons(active_weapons)
	hud.update_xp(xp, xp_needed, hero_level)

# ── Grille ───────────────────────────────────────────────────────
func _init_grid():
	grid.clear()
	for _r in ROWS:
		var row = []
		for _l in LANES: row.append(null)
		grid.append(row)

func grid_pos(row: int, lane: int) -> Vector2:
	return Vector2(GRID_X + lane * LANE_W + LANE_W * 0.5,
				   GRID_Y + row  * ROW_H  + ROW_H  * 0.5)

# ── Fond ─────────────────────────────────────────────────────────
func _draw_background():
	var floor_rect = ColorRect.new()
	floor_rect.color = Color(0.07, 0.05, 0.04)
	floor_rect.size  = Vector2(1280, 720)
	bg.add_child(floor_rect)
	for r in ROWS:
		for l in LANES:
			var cell = ColorRect.new()
			cell.position = Vector2(GRID_X + l * LANE_W, GRID_Y + r * ROW_H)
			cell.size     = Vector2(LANE_W - 2, ROW_H - 2)
			cell.color    = Color(0.13, 0.10, 0.08) if (r + l) % 2 == 0 else Color(0.11, 0.09, 0.07)
			bg.add_child(cell)
	for l in LANES:
		var lbl = Label.new()
		lbl.text = "F%d" % (l + 1)
		lbl.position = Vector2(GRID_X + l * LANE_W + LANE_W * 0.5 - 10, GRID_Y + ROWS * ROW_H + 4)
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		bg.add_child(lbl)

# ── Joueur ───────────────────────────────────────────────────────
func _place_player():
	player_node.position = Vector2(GRID_X + player_lane * LANE_W + LANE_W * 0.5, PLAYER_Y)

func _move_player(dir: int):
	player_lane = clamp(player_lane + dir, 0, LANES - 1)
	var tw = create_tween()
	tw.tween_property(player_node, "position",
		Vector2(GRID_X + player_lane * LANE_W + LANE_W * 0.5, PLAYER_Y), 0.08)
	hud.update_lane(player_lane + 1)

# ── Salle ────────────────────────────────────────────────────────
func _start_room(num: int):
	room_num   = num
	room_clear       = false
	spawns_in_flight = 0
	for child in monsters_node.get_children(): child.queue_free()
	for g in active_gems:
		if is_instance_valid(g.node): g.node.queue_free()
	active_gems.clear()
	_init_grid()
	hud.update_room(room_num)
	hud.hide_door()

	var composition = _get_composition(num)
	monsters_remaining = composition.size()
	print("[SALLE %d] Démarrage — %d monstres à tuer — composition: %s" % [num, monsters_remaining, composition])
	_spawn_wave(composition)

func _get_composition(room: int) -> Array:
	if ROOM_WAVES.has(room):
		return ROOM_WAVES[room].duplicate()
	# Au-delà de la salle 10 : que des rouges, de plus en plus
	var extra = room - 10
	var reds = min(LANES + extra, LANES * 2)
	var result = []
	for i in reds: result.append("r")
	return result

func _spawn_wave(composition: Array):
	var lanes_list = range(LANES)
	lanes_list.shuffle()
	# On spawne les monstres sur des files différentes ; s'il y en a plus que 5, on empile
	for i in composition.size():
		var lane = lanes_list[i % LANES]
		_spawn_monster(0, lane, composition[i])

func _spawn_monster(row: int, lane: int, type: String) -> bool:
	var target_lane = _find_spawn_lane(lane)
	if target_lane == -1: return false   # toutes colonnes pleines

	var r = row
	while r < ROWS and grid[r][target_lane] != null:
		r += 1
	if r >= ROWS: return false

	var scene = blob_scene
	if   type == "b": scene = blue_scene
	elif type == "r": scene = red_scene
	var m = scene.instantiate()
	monsters_node.add_child(m)
	m.position   = grid_pos(r, target_lane)
	m.grid_row   = r
	m.grid_lane  = target_lane
	grid[r][target_lane] = m
	return true

func _find_spawn_lane(preferred: int) -> int:
	# Colonne préférée libre ?
	if grid[0][preferred] == null:
		return preferred
	# Sinon essayer les colonnes adjacentes par ordre de proximité
	for offset in [1, -1, 2, -2, 3, -3, 4, -4]:
		var l = preferred + offset
		if l >= 0 and l < LANES and grid[0][l] == null:
			return l
	return -1   # toutes colonnes pleines

# ── Boucle ───────────────────────────────────────────────────────
func _process(delta: float):
	if game_over or leveling_up: return
	if room_clear: return   # attente ESPACE, pas de ticks ni tirs

	tick_acc += delta
	if tick_acc >= tick_interval:
		tick_acc = 0.0
		_do_tick()

	for w in active_weapons:
		var def = WEAPON_DEFS[w.id]
		w.acc += delta
		if w.acc >= def.cd:
			w.acc = 0.0
			_fire_weapon(w)

# ── Tick ─────────────────────────────────────────────────────────
func _do_tick():
	for r in range(ROWS - 1, -1, -1):
		for l in range(LANES):
			var m = grid[r][l]
			if m == null: continue
			m.tick_freeze()
			if m.frozen_ticks > 0: continue

			var new_row = r + m.move_speed
			if new_row >= ROWS:
				var dmg   = m.damage
				var mtype = m.monster_type
				grid[r][l] = null
				m.queue_free()
				if l == player_lane:
					_hit_player(dmg)
				# Dans tous les cas : revient doublé en haut de sa file
				_on_monster_escaped(l, mtype)
			else:
				# Si bloqué par un autre monstre, reste sur place
				if grid[new_row][l] == null:
					grid[new_row][l] = m
					grid[r][l] = null
					m.grid_row  = new_row
					m.grid_lane = l
					var tw = create_tween()
					tw.tween_property(m, "position", grid_pos(new_row, l), 0.25)

func _on_monster_escaped(lane: int, mtype: String):
	spawns_in_flight += 1
	var before = monsters_remaining
	monsters_remaining += 1   # le monstre qui s'est échappé comptera comme un nouveau à tuer

	var s1 = _spawn_monster(0, lane, mtype)
	if not s1:
		monsters_remaining -= 1
		print("[ESCAPE] File %d type=%s — spawn1 RATÉ — remaining: %d→%d" % [lane+1, mtype, before, monsters_remaining])
	else:
		print("[ESCAPE] File %d type=%s — spawn1 ok — remaining: %d→%d" % [lane+1, mtype, before, monsters_remaining])

	await get_tree().create_timer(0.35).timeout

	if not game_over:
		var s2 = _spawn_monster(0, lane, mtype)
		if not s2:
			monsters_remaining -= 1
			print("[ESCAPE] File %d type=%s — spawn2 RATÉ — remaining: %d" % [lane+1, mtype, monsters_remaining])
		else:
			print("[ESCAPE] File %d type=%s — spawn2 ok — remaining: %d" % [lane+1, mtype, monsters_remaining])

	spawns_in_flight -= 1
	_check_room_clear()

# ── 8 ARMES ──────────────────────────────────────────────────────
func _get_dmg(w: Dictionary) -> int:
	return int(WEAPON_DEFS[w.id].base_dmg * (1.0 + (w.level - 1) * 0.5))

func _fire_weapon(w: Dictionary):
	match w.id:
		"arc":        _w_arc(w)
		"arbalete":   _w_arbalete(w)
		"dague":      _w_dague(w)
		"bombe":      _w_bombe(w)
		"eclair":     _w_eclair(w)
		"tourbillon": _w_tourbillon(w)
		"givre":      _w_givre(w)
		"sismique":   _w_sismique(w)

func _w_arc(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			var t = 0.15 + r * 0.02
			_shoot_arrow(player_lane, r, t, Color(0.95, 0.85, 0.3))
			await get_tree().create_timer(t).timeout
			if is_instance_valid(m): _deal_and_check(m, r, player_lane, _get_dmg(w))
			return

func _w_arbalete(w: Dictionary):
	var hit = 0
	for r in range(ROWS - 1, -1, -1):
		if hit >= 2: break
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			_shoot_arrow(player_lane, r, 0.18 + r * 0.015, Color(0.6, 0.6, 1.0), 5.0)
			await get_tree().create_timer(0.18 + r * 0.015).timeout
			if is_instance_valid(m): _deal_and_check(m, r, player_lane, _get_dmg(w))
			hit += 1

func _w_dague(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			_show_slash(player_lane, r)
			_deal_and_check(grid[r][player_lane], r, player_lane, _get_dmg(w))
			return

func _w_bombe(w: Dictionary):
	for l in [player_lane - 1, player_lane, player_lane + 1]:
		if l < 0 or l >= LANES: continue
		for r in range(ROWS - 1, -1, -1):
			if grid[r][l] != null:
				_show_explosion(l, r)
				await get_tree().create_timer(0.1).timeout
				if grid[r][l] != null: _deal_and_check(grid[r][l], r, l, _get_dmg(w))
				break

func _w_eclair(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			_show_lightning(player_lane, r)
			_deal_and_check(grid[r][player_lane], r, player_lane, _get_dmg(w))

func _w_tourbillon(w: Dictionary):
	_show_whirlwind()
	for l in LANES:
		for r in range(ROWS - 1, -1, -1):
			if grid[r][l] != null:
				_deal_and_check(grid[r][l], r, l, _get_dmg(w))
				break

func _w_givre(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			_shoot_arrow(player_lane, r, 0.2, Color(0.4, 0.85, 1.0), 3.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(m):
				m.freeze(2)
				_deal_and_check(m, r, player_lane, _get_dmg(w))
			return

func _w_sismique(w: Dictionary):
	_show_quake()
	for r in [ROWS - 1, ROWS - 2]:
		for l in LANES:
			if r >= 0 and grid[r][l] != null:
				_deal_and_check(grid[r][l], r, l, _get_dmg(w))

# ── Combat ───────────────────────────────────────────────────────
func _deal_and_check(m: Node2D, _row: int, _lane: int, dmg: int):
	if not is_instance_valid(m): return
	var xp_val = m.xp_value
	m.take_damage(dmg)
	if m.hp <= 0:
		# Utiliser la position ACTUELLE du monstre (pas celle capturée au moment du tir)
		var row   = m.grid_row
		var lane  = m.grid_lane
		var mtype = m.monster_type
		grid[row][lane] = null
		var pos = m.position
		m.queue_free()
		_play_death_anim(pos, mtype, false)
		_on_monster_killed(lane, pos, xp_val)

func _on_monster_killed(lane: int, kill_pos: Vector2, xp_val: int):
	score += 10 * room_num
	monsters_remaining -= 1
	print("[KILL] File %d — remaining: %d — grid_empty: %s — in_flight: %d" % [lane+1, monsters_remaining, _grid_empty(), spawns_in_flight])
	hud.update_score(score)
	_spawn_gem(lane, kill_pos, xp_val)
	_check_room_clear()

func _check_room_clear():
	if room_clear or game_over: return
	# Vérité terrain : la salle est vidée si la grille est physiquement vide
	# ET qu'aucune coroutine d'escape n'est encore en train de spawner.
	# Le compteur monsters_remaining peut dériver à cause des awaits concurrents,
	# mais _grid_empty() + spawns_in_flight == 0 est toujours fiable.
	if _grid_empty() and spawns_in_flight == 0:
		if monsters_remaining != 0:
			print("[CLEAR] Correction compteur dérivé: remaining %d → 0" % monsters_remaining)
			monsters_remaining = 0
		print("[CLEAR] Salle vidée → _room_cleared()")
		_room_cleared()

func _grid_empty() -> bool:
	for r in ROWS:
		for l in LANES:
			if grid[r][l] != null: return false
	return true

func _room_cleared():
	await _play_door_animation()
	# room_clear est mis à true à la fin de _play_door_animation, après le lore
	_start_room(room_num + 1)

func _get_room_xp_bonus(room: int) -> int:
	var table = {1: 30, 2: 60, 3: 100, 4: 150, 5: 200, 6: 260, 7: 330, 8: 410, 9: 500}
	if table.has(room):
		return table[room]
	return 500 + (room - 10) * 80

func _play_door_animation():
	var door_w  = 200
	var door_h  = 280
	var cx      = 640
	var cy      = 340
	var door_x  = cx - door_w / 2
	var door_y  = cy - door_h / 2

	var stone = ColorRect.new()
	stone.size     = Vector2(door_w + 20, door_h + 20)
	stone.position = Vector2(door_x - 10, door_y - 10)
	stone.color    = Color(0.45, 0.42, 0.40)
	bg.add_child(stone)

	var glow = ColorRect.new()
	glow.size     = Vector2(door_w, door_h)
	glow.position = Vector2(door_x, door_y)
	glow.color    = Color(1.0, 0.85, 0.2, 0.0)
	bg.add_child(glow)

	var left_panel = ColorRect.new()
	left_panel.size     = Vector2(door_w / 2, door_h)
	left_panel.position = Vector2(door_x, door_y)
	left_panel.color    = Color(0.35, 0.2, 0.1)
	bg.add_child(left_panel)

	var right_panel = ColorRect.new()
	right_panel.size     = Vector2(door_w / 2, door_h)
	right_panel.position = Vector2(cx, door_y)
	right_panel.color    = Color(0.35, 0.2, 0.1)
	bg.add_child(right_panel)

	_play_jackpot_sound()

	var t0 = Time.get_ticks_msec() / 1000.0
	var has_lore = LORE_TEXTS.has(room_num)
	if has_lore:
		_show_lore_text(room_num)

	var tw = create_tween()
	tw.tween_property(left_panel,  "position:x", float(door_x - door_w / 2), 0.8)
	tw.parallel().tween_property(right_panel, "position:x", float(cx + door_w / 2), 0.8)
	tw.parallel().tween_property(glow, "color", Color(1.0, 0.85, 0.2, 0.6), 0.4)
	await tw.finished

	# +XP doré au-dessus du joueur
	var xp_bonus = _get_room_xp_bonus(room_num)
	_add_xp(xp_bonus)
	var pcx = GRID_X + player_lane * LANE_W + LANE_W * 0.5
	var py  = float(PLAYER_Y) - 80.0
	var xp_lbl = Label.new()
	xp_lbl.text = "+%d XP" % xp_bonus
	xp_lbl.custom_minimum_size = Vector2(200, 0)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_lbl.position = Vector2(pcx - 100.0, py)
	xp_lbl.add_theme_font_size_override("font_size", 52)
	xp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	bg.add_child(xp_lbl)
	var tw2 = create_tween()
	tw2.tween_property(xp_lbl, "position:y", py - 110.0, 1.1)
	tw2.parallel().tween_property(xp_lbl, "modulate", Color(1, 1, 1, 0), 1.1)
	await tw2.finished
	if is_instance_valid(xp_lbl): xp_lbl.queue_free()

	var tw3 = create_tween()
	tw3.tween_property(stone,       "modulate", Color(1, 1, 1, 0), 0.4)
	tw3.parallel().tween_property(glow,        "modulate", Color(1, 1, 1, 0), 0.4)
	tw3.parallel().tween_property(left_panel,  "modulate", Color(1, 1, 1, 0), 0.4)
	tw3.parallel().tween_property(right_panel, "modulate", Color(1, 1, 1, 0), 0.4)
	await tw3.finished

	for n in [stone, glow, left_panel, right_panel]:
		if is_instance_valid(n): n.queue_free()

	if has_lore:
		var lore_total = 0.3 + 2.5 + 0.3
		var elapsed = Time.get_ticks_msec() / 1000.0 - t0
		var remain = lore_total - elapsed
		if remain > 0.0:
			await get_tree().create_timer(remain).timeout

	room_clear = true

func _show_lore_text(rnum: int):
	var text = LORE_TEXTS.get(rnum, "")
	if text.is_empty():
		return

	var panel_w = 800
	var panel_h = 68
	var panel_x = 640.0 - panel_w / 2.0
	var panel_y = 498.0

	var panel = ColorRect.new()
	panel.color    = Color(0.0, 0.0, 0.0, 0.60)
	panel.size     = Vector2(panel_w, panel_h)
	panel.position = Vector2(panel_x, panel_y)
	panel.modulate.a = 0.0
	bg.add_child(panel)

	var lbl = RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content    = true
	lbl.scroll_active  = false
	lbl.text           = "[center][i]" + text + "[/i][/center]"
	lbl.size           = Vector2(panel_w - 24, panel_h)
	lbl.position       = Vector2(panel_x + 12, panel_y + 10)
	lbl.add_theme_font_size_override("normal_font_size", 17)
	lbl.add_theme_color_override("default_color", Color(0.9, 0.88, 0.8))
	lbl.modulate.a = 0.0
	bg.add_child(lbl)

	var tw = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.3)
	await tw.finished

	await get_tree().create_timer(2.5).timeout

	var tw2 = create_tween()
	tw2.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw2.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3)
	await tw2.finished

	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(lbl): lbl.queue_free()

func _play_jackpot_sound():
	var player = AudioStreamPlayer.new()
	add_child(player)

	var stream = AudioStreamGenerator.new()
	stream.mix_rate     = 22050.0
	stream.buffer_length = 0.6
	player.stream    = stream
	player.volume_db = -8.0
	player.play()

	var playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return

	var sample_rate  = 22050.0
	var notes        = [523.0, 659.0, 784.0, 1047.0]
	var note_duration = 0.1

	for note_freq in notes:
		var n_samples = int(sample_rate * note_duration)
		for i in n_samples:
			var t        = float(i) / sample_rate
			var envelope = 1.0 - float(i) / float(n_samples)
			var sample   = sin(TAU * note_freq * t) * 0.25 * envelope
			playback.push_frame(Vector2(sample, sample))

	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(player): player.queue_free()

# ── Gemmes ───────────────────────────────────────────────────────
func _spawn_gem(lane: int, pos: Vector2, xp_val: int):
	var g = gem_scene.instantiate()
	g.lane     = lane
	g.xp_value = xp_val
	g.position = pos
	# Couleur de gemme selon la valeur d'XP
	var diamond = g.get_node("Diamond")
	if xp_val >= 100:
		diamond.color = Color(1.0, 0.35, 0.35)   # rouge
	elif xp_val >= 50:
		diamond.color = Color(0.35, 0.55, 1.0)   # bleue
	# sinon cyan par défaut (vert)
	bg.add_child(g)
	active_gems.append({"node": g, "lane": lane})

	# X verrouillé sur la file d'origine dès le début — on ne tweene que Y
	var fixed_x = GRID_X + lane * LANE_W + LANE_W * 0.5
	g.position.x = fixed_x
	var dist     = abs((PLAYER_Y - 10) - g.position.y)
	var duration = dist / 380.0  # 380 px/s — vitesse constante
	var tw = create_tween()
	tw.tween_property(g, "position:y", PLAYER_Y - 10, duration)
	await tw.finished
	if not is_instance_valid(g): return
	g.position.x = fixed_x  # sécurité : re-snap au cas où
	if lane == player_lane:
		_collect_gem(g)
	else:
		var tw2 = create_tween()
		tw2.tween_property(g, "modulate", Color(1,1,1,0), 0.3)
		await tw2.finished
		if is_instance_valid(g): g.queue_free()
	active_gems = active_gems.filter(func(e): return is_instance_valid(e.node))

func _collect_gem(g: Node2D):
	var xp_val = g.xp_value
	g.visible = false  # cacher immédiatement, avant l'await du flash
	_add_xp(xp_val)
	var flash = Label.new()
	flash.text = "+%d XP" % xp_val
	flash.position = g.position + Vector2(-28, -55)
	flash.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
	bg.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "position", flash.position + Vector2(0, -55), 0.8)
	tw.parallel().tween_property(flash, "modulate", Color(1,1,1,0), 0.8)
	await tw.finished
	if is_instance_valid(flash): flash.queue_free()
	if is_instance_valid(g): g.queue_free()

# ── XP & Niveau ──────────────────────────────────────────────────
func _add_xp(amount: int):
	xp += amount
	if xp >= xp_needed:
		xp -= xp_needed
		xp_needed = int(xp_needed * 1.55)
		hero_level += 1
		hud.update_xp(xp, xp_needed, hero_level)
		_trigger_level_up()
	else:
		hud.update_xp(xp, xp_needed, hero_level)

func _trigger_level_up():
	leveling_up = true
	var choices = _generate_choices()
	hud.show_level_up(choices)

func _generate_choices() -> Array:
	var pool = []
	for w in active_weapons:
		pool.append({"type": "upgrade", "weapon_id": w.id, "current_level": w.level})
	if active_weapons.size() < 4:
		var unowned = _get_unowned_weapons()
		unowned.shuffle()
		for wid in unowned:
			pool.append({"type": "new", "weapon_id": wid})
	pool.shuffle()
	return pool.slice(0, min(3, pool.size()))

func _get_unowned_weapons() -> Array:
	var owned = active_weapons.map(func(w): return w.id)
	return WEAPON_DEFS.keys().filter(func(wid): return not owned.has(wid))

func apply_level_up_choice(choice: Dictionary):
	if choice.type == "new":
		active_weapons.append({"id": choice.weapon_id, "level": 1, "acc": 0.0})
	else:
		for w in active_weapons:
			if w.id == choice.weapon_id:
				w.level += 1
				break
	hud.update_weapons(active_weapons)
	hud.hide_level_up()
	leveling_up = false

# ── Joueur blessé ────────────────────────────────────────────────
func _hit_player(dmg: int):
	print("[HIT] Joueur touché -%d PV — remaining: %d" % [dmg, monsters_remaining])
	player_hp = max(0, player_hp - dmg)
	hud.update_health(player_hp, player_max)
	player_node.modulate = Color(1, 0.25, 0.25)
	await get_tree().create_timer(0.2).timeout
	player_node.modulate = Color.WHITE
	if player_hp <= 0:
		game_over = true
		hud.show_game_over(score, room_num)

# ── Input ────────────────────────────────────────────────────────
func _input(event: InputEvent):
	if game_over: return
	if leveling_up: return
	if event.is_action_pressed("lane_left"):
		_move_player(-1)
	elif event.is_action_pressed("lane_right"):
		_move_player(1)
	elif event.is_action_pressed("next_room") and room_clear:
		_start_room(room_num + 1)

# ── Visuels d'attaque ────────────────────────────────────────────
func _shoot_arrow(lane: int, target_row: int, duration: float,
				  col: Color = Color(0.95, 0.85, 0.3), w: float = 3.0):
	var arrow = Node2D.new()
	var shaft = Line2D.new()
	shaft.add_point(Vector2(0, 0)); shaft.add_point(Vector2(0, -28))
	shaft.width = w; shaft.default_color = col
	arrow.add_child(shaft)
	var tip = ColorRect.new()
	tip.size = Vector2(7, 9); tip.position = Vector2(-3.5, -37)
	tip.color = col.lightened(0.2); arrow.add_child(tip)
	var feather = ColorRect.new()
	feather.size = Vector2(12, 4); feather.position = Vector2(-6, -4)
	feather.color = Color(0.9, 0.88, 0.78); arrow.add_child(feather)
	arrow.position = Vector2(GRID_X + lane * LANE_W + LANE_W * 0.5, PLAYER_Y - 35)
	bg.add_child(arrow)
	var tw = create_tween()
	tw.tween_property(arrow, "position", grid_pos(target_row, lane), duration)
	await tw.finished
	if is_instance_valid(arrow): arrow.queue_free()

func _show_slash(lane: int, row: int):
	var slash = Line2D.new()
	slash.add_point(Vector2(-22, -18)); slash.add_point(Vector2(22, 18))
	slash.width = 4.0; slash.default_color = Color(1.0, 0.9, 0.4, 0.85)
	slash.position = grid_pos(row, lane); bg.add_child(slash)
	await get_tree().create_timer(0.09).timeout
	if is_instance_valid(slash): slash.queue_free()

func _show_explosion(lane: int, row: int):
	var exp = ColorRect.new()
	exp.size = Vector2(LANE_W - 4, ROW_H - 4)
	exp.position = Vector2(GRID_X + lane * LANE_W + 2, GRID_Y + row * ROW_H + 2)
	exp.color = Color(1.0, 0.55, 0.1, 0.70); bg.add_child(exp)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(exp): exp.queue_free()

func _show_lightning(lane: int, row: int):
	var bolt = Line2D.new()
	var sx = GRID_X + lane * LANE_W + LANE_W * 0.5
	bolt.add_point(Vector2(sx, PLAYER_Y))
	bolt.add_point(Vector2(sx + randf_range(-12, 12), grid_pos(row, lane).y))
	bolt.width = 4.0; bolt.default_color = Color(0.6, 0.6, 1.0, 0.9)
	bg.add_child(bolt)
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(bolt): bolt.queue_free()

func _show_whirlwind():
	var rect = ColorRect.new()
	rect.size = Vector2(LANES * LANE_W, ROW_H)
	rect.position = Vector2(GRID_X, GRID_Y + (ROWS - 1) * ROW_H)
	rect.color = Color(0.8, 0.5, 1.0, 0.35); bg.add_child(rect)
	await get_tree().create_timer(0.18).timeout
	if is_instance_valid(rect): rect.queue_free()

func _show_quake():
	var rect = ColorRect.new()
	rect.size = Vector2(LANES * LANE_W, ROW_H * 2)
	rect.position = Vector2(GRID_X, GRID_Y + (ROWS - 2) * ROW_H)
	rect.color = Color(0.9, 0.65, 0.2, 0.40); bg.add_child(rect)
	var cam = get_viewport().get_camera_2d()
	if cam:
		var tw = create_tween()
		tw.tween_property(cam, "offset", Vector2(6, 0), 0.05)
		tw.tween_property(cam, "offset", Vector2(-6, 0), 0.05)
		tw.tween_property(cam, "offset", Vector2(0, 0), 0.05)
	await get_tree().create_timer(0.20).timeout
	if is_instance_valid(rect): rect.queue_free()

# ── Animations de mort ───────────────────────────────────────────
func _play_death_anim(pos: Vector2, type: String, is_boss: bool):
	if is_boss:
		_death_anim_boss(pos)
		return
	match type:
		"g": _death_anim_green(pos)
		"b": _death_anim_blue(pos)
		"r": _death_anim_red(pos)

func _death_anim_green(pos: Vector2):
	var count = randi_range(6, 8)
	for i in count:
		var sq = ColorRect.new()
		sq.size = Vector2(7, 7)
		sq.color = Color(0.2, 0.85, 0.25)
		sq.position = pos - Vector2(3.5, 3.5)
		bg.add_child(sq)
		var angle = (float(i) / count) * TAU + randf_range(-0.15, 0.15)
		var dist  = randf_range(22.0, 46.0)
		var target = pos + Vector2(cos(angle), sin(angle)) * dist - Vector2(3.5, 3.5)
		var tw = create_tween()
		tw.tween_property(sq, "position", target, 0.3)
		tw.parallel().tween_property(sq, "modulate", Color(1, 1, 1, 0), 0.3)
		tw.tween_callback(sq.queue_free)

func _death_anim_blue(pos: Vector2):
	# Clignotement blanc/bleu 3 fois
	var flash = ColorRect.new()
	flash.size = Vector2(32, 32)
	flash.position = pos - Vector2(16, 16)
	flash.color = Color(1.0, 1.0, 1.0, 0.9)
	bg.add_child(flash)
	var tw = create_tween()
	for _i in 3:
		tw.tween_property(flash, "color", Color(1.0, 1.0, 1.0, 0.9), 0.04)
		tw.tween_property(flash, "color", Color(0.3, 0.5, 1.0, 0.7), 0.04)
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.05)
	tw.tween_callback(flash.queue_free)

	# Éclats décalés
	await get_tree().create_timer(0.10).timeout
	var shard_count = 6
	for i in shard_count:
		var shard = Line2D.new()
		var angle = (float(i) / shard_count) * TAU
		var length = randf_range(12.0, 28.0)
		var dir = Vector2(cos(angle), sin(angle))
		shard.add_point(Vector2(0, 0))
		shard.add_point(dir * length)
		shard.width = 2.5
		shard.default_color = Color(0.4, 0.6, 1.0)
		shard.position = pos
		bg.add_child(shard)
		var tw2 = create_tween()
		tw2.tween_property(shard, "position", pos + dir * 20.0, 0.15)
		tw2.parallel().tween_property(shard, "modulate", Color(1, 1, 1, 0), 0.15)
		tw2.tween_callback(shard.queue_free)

func _death_anim_red(pos: Vector2):
	# Flash rouge intense
	var flash = ColorRect.new()
	flash.size = Vector2(42, 42)
	flash.position = pos - Vector2(21, 21)
	flash.color = Color(1.0, 0.1, 0.1, 0.85)
	bg.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.2)
	tw.tween_callback(flash.queue_free)

	# Shockwave circulaire (Line2D en cercle qui s'élargit)
	var ring = Line2D.new()
	ring.width = 3.0
	ring.default_color = Color(1.0, 0.2, 0.2, 0.85)
	var pts = 16
	for i in pts + 1:
		var angle = (float(i) / pts) * TAU
		ring.add_point(Vector2(cos(angle), sin(angle)) * 8.0)
	ring.position = pos
	bg.add_child(ring)
	var tw2 = create_tween()
	tw2.tween_property(ring, "scale", Vector2(4.5, 4.5), 0.35)
	tw2.parallel().tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.35)
	tw2.tween_callback(ring.queue_free)

func _death_anim_boss(pos: Vector2):
	# Grand flash doré
	var flash = ColorRect.new()
	flash.size = Vector2(70, 70)
	flash.position = pos - Vector2(35, 35)
	flash.color = Color(1.0, 0.85, 0.1, 0.9)
	bg.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.35)
	tw.tween_callback(flash.queue_free)

	# Gros éclats
	var shard_count = 10
	for i in shard_count:
		var shard = Line2D.new()
		var angle = (float(i) / shard_count) * TAU
		var length = randf_range(20.0, 45.0)
		var dir = Vector2(cos(angle), sin(angle))
		shard.add_point(Vector2(0, 0))
		shard.add_point(dir * length)
		shard.width = 3.5
		shard.default_color = Color(1.0, 0.75, 0.1)
		shard.position = pos
		bg.add_child(shard)
		var tw2 = create_tween()
		tw2.tween_property(shard, "position", pos + dir * 30.0, 0.5)
		tw2.parallel().tween_property(shard, "modulate", Color(1, 1, 1, 0), 0.5)
		tw2.tween_callback(shard.queue_free)

	# Double shockwave décalée
	for wave_i in 2:
		var ring = Line2D.new()
		ring.width = 4.0 - wave_i * 1.5
		ring.default_color = Color(1.0, 0.5, 0.1, 0.75 - wave_i * 0.25)
		var pts = 20
		for i in pts + 1:
			var angle = (float(i) / pts) * TAU
			ring.add_point(Vector2(cos(angle), sin(angle)) * 8.0)
		ring.position = pos
		bg.add_child(ring)
		var ring_tw = create_tween()
		ring_tw.tween_interval(wave_i * 0.15)
		ring_tw.tween_property(ring, "scale", Vector2(6.0 + wave_i * 2.0, 6.0 + wave_i * 2.0), 0.55)
		ring_tw.parallel().tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.55)
		ring_tw.tween_callback(ring.queue_free)

	# Screen shake
	var cam = get_viewport().get_camera_2d()
	if cam:
		var shake_tw = create_tween()
		shake_tw.tween_property(cam, "offset", Vector2(8, 4), 0.07)
		shake_tw.tween_property(cam, "offset", Vector2(-8, -4), 0.07)
		shake_tw.tween_property(cam, "offset", Vector2(5, -3), 0.06)
		shake_tw.tween_property(cam, "offset", Vector2(-5, 3), 0.06)
		shake_tw.tween_property(cam, "offset", Vector2(0, 0), 0.05)
