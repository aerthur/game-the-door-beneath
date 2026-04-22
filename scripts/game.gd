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
	"arc":        {"name": "Arc",        "base_dmg": 25, "cd": 1.0,  "desc": "1 ennemi dans la file active"},
	"arbalete":   {"name": "Arbalète",   "base_dmg": 55, "cd": 2.0,  "desc": "Perce 2 ennemis dans la file"},
	"dague":      {"name": "Dague",      "base_dmg": 10, "cd": 0.35, "desc": "Très rapide, file active"},
	"bombe":      {"name": "Bombe",      "base_dmg": 20, "cd": 2.5,  "desc": "Explose sur 3 files voisines"},
	"eclair":     {"name": "Eclair",     "base_dmg": 16, "cd": 1.5,  "desc": "Frappe tous les ennemis de la file"},
	"tourbillon": {"name": "Tourbillon", "base_dmg": 12, "cd": 2.0,  "desc": "1ère rangée de chaque file"},
	"givre":      {"name": "Givre",      "base_dmg": 8,  "cd": 1.5,  "desc": "Ralentit l'ennemi 2 ticks"},
	"sismique":   {"name": "Sismique",   "base_dmg": 9,  "cd": 3.0,  "desc": "2 dernières rangées, toutes files"},
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
	room_clear = true
	hud.show_door()

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
	var tw = create_tween()
	tw.tween_property(g, "position:y", PLAYER_Y - 10, 1.2)
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
	_add_xp(xp_val)
	var flash = Label.new()
	flash.text = "+%d XP" % xp_val
	flash.position = g.position + Vector2(-22, -20)
	flash.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
	bg.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "position", flash.position + Vector2(0, -35), 0.7)
	tw.parallel().tween_property(flash, "modulate", Color(1,1,1,0), 0.7)
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
	if active_weapons.size() < 3:
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
