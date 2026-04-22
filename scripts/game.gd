extends Node
# Dernière mise à jour : 2026-04-21


# ── État ─────────────────────────────────────────────────────────
var player_hp   : int  = 100
var player_max  : int  = 100
var room_num    : int  = 1
var gold_current      : int  = 0
var gold_total_earned : int  = 0
var gold_spent        : int  = 0
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

var run_stats   : Dictionary = {}
var records     : Dictionary = {}
var _run_start_ms : int = 0

var tick_acc : float = 0.0
var tick_interval : float = 1.0

@onready var monsters_node : Node2D      = $Monsters
@onready var player_node   : Node2D      = $Player
@onready var hud           : CanvasLayer = $HUD
@onready var bg            : Node2D      = $Background
@onready var visuals     : Node2D      = $Visuals

@onready var enemies : Node2D = $Enemies
@onready var weapons : Node2D = $Weapons
@onready var player_ctrl : Node2D = $PlayerCtrl
var gem_scene   = preload("res://scenes/gem.tscn")

# ═════════════════════════════════════════════════════════════════
func _ready():
	add_to_group("game")
	_load_records()
	visuals.bg = bg
	enemies.monsters_node = monsters_node
	enemies.grid = grid
	weapons.grid    = grid
	weapons.visuals = visuals
	weapons.deal_fn = _deal_and_check
	player_ctrl.player_node = player_node
	player_ctrl.hud         = hud
	player_ctrl.weapons_ref = weapons
	player_ctrl.init_player(2, player_hp, player_max)
	player_ctrl.game_over_triggered.connect(_on_player_game_over)
	player_ctrl.next_room_requested.connect(func(): _start_room(room_num + 1))
	weapons.player_lane = player_ctrl.player_lane
	_init_grid()
	_draw_background()
	_start_room(1)
	hud.update_weapons(active_weapons)
	hud.update_xp(xp, xp_needed, hero_level)

# ── Grille ───────────────────────────────────────────────────────
func _init_grid():
	grid.clear()
	for _r in GameData.ROWS:
		var row = []
		for _l in GameData.LANES: row.append(null)
		grid.append(row)

func grid_pos(row: int, lane: int) -> Vector2:
	return Vector2(GameData.GRID_X + lane * GameData.LANE_W + GameData.LANE_W * 0.5,
				   GameData.GRID_Y + row  * GameData.ROW_H  + GameData.ROW_H  * 0.5)

# ── Fond ─────────────────────────────────────────────────────────
func _draw_background():
	var floor_rect = ColorRect.new()
	floor_rect.color = Color(0.07, 0.05, 0.04)
	floor_rect.size  = Vector2(1280, 720)
	bg.add_child(floor_rect)
	for r in GameData.ROWS:
		for l in GameData.LANES:
			var cell = ColorRect.new()
			cell.position = Vector2(GameData.GRID_X + l * GameData.LANE_W, GameData.GRID_Y + r * GameData.ROW_H)
			cell.size     = Vector2(GameData.LANE_W - 2, GameData.ROW_H - 2)
			cell.color    = Color(0.13, 0.10, 0.08) if (r + l) % 2 == 0 else Color(0.11, 0.09, 0.07)
			bg.add_child(cell)
	for l in GameData.LANES:
		var lbl = Label.new()
		lbl.text = "F%d" % (l + 1)
		lbl.position = Vector2(GameData.GRID_X + l * GameData.LANE_W + GameData.LANE_W * 0.5 - 10, GameData.GRID_Y + GameData.ROWS * GameData.ROW_H + 4)
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		bg.add_child(lbl)

# ── Joueur ───────────────────────────────────────────────────────

func _start_room(num: int):
	if num == 1:
		_init_run_stats()
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

	if room_num % 5 == 0:
		monsters_remaining = enemies.spawn_boss(room_num)
	else:
		var composition = enemies.get_composition(num)
		monsters_remaining = composition.size()
		print("[SALLE %d] Démarrage — %d monstres à tuer — composition: %s" % [num, monsters_remaining, composition])
		enemies.spawn_wave(composition)

# ── Boucle ───────────────────────────────────────────────────────
func _process(delta: float):
	if game_over or leveling_up: return
	if room_clear: return   # attente ESPACE, pas de ticks ni tirs

	tick_acc += delta
	if tick_acc >= tick_interval:
		tick_acc = 0.0
		_do_tick()

	for w in active_weapons:
		var def = GameData.WEAPON_DEFS[w.id]
		w.acc += delta
		if w.acc >= def.cd:
			w.acc = 0.0
			weapons.fire(w)

# ── Tick ─────────────────────────────────────────────────────────
func _do_tick():
	for r in range(GameData.ROWS - 1, -1, -1):
		for l in range(GameData.LANES):
			var m = grid[r][l]
			if m == null: continue
			m.tick_freeze()
			if m.frozen_ticks > 0: continue

			var new_row = r + m.move_speed
			if new_row >= GameData.ROWS:
				var dmg   = m.damage
				var mtype = m.monster_type
				grid[r][l] = null
				if m.is_boss:
					# Boss: inflige dégâts sur sa file ± 1, remonte soigné sans se dupliquer
					# TODO: adapter l'axe selon enemy_direction quand ce système sera implémenté
					var hit_lanes : Dictionary = {}
					for dl in [-1, 0, 1]:
						hit_lanes[clamp(l + dl, 0, GameData.LANES - 1)] = true
					for tl in hit_lanes:
						if tl == player_ctrl.player_lane:
							player_ctrl.hit(dmg)
					enemies.boss_retreat(m, l)
				else:
					m.queue_free()
					if l == player_ctrl.player_lane:
						player_ctrl.hit(dmg)
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

	var s1 = enemies.spawn_monster(0, lane, mtype)
	if not s1:
		monsters_remaining -= 1
		print("[ESCAPE] File %d type=%s — spawn1 RATÉ — remaining: %d→%d" % [lane+1, mtype, before, monsters_remaining])
	else:
		print("[ESCAPE] File %d type=%s — spawn1 ok — remaining: %d→%d" % [lane+1, mtype, before, monsters_remaining])

	await get_tree().create_timer(0.35).timeout

	if not game_over:
		var s2 = enemies.spawn_monster(0, lane, mtype)
		if not s2:
			monsters_remaining -= 1
			print("[ESCAPE] File %d type=%s — spawn2 RATÉ — remaining: %d" % [lane+1, mtype, monsters_remaining])
		else:
			print("[ESCAPE] File %d type=%s — spawn2 ok — remaining: %d" % [lane+1, mtype, monsters_remaining])

	spawns_in_flight -= 1
	_check_room_clear()

# ── 8 ARMES ──────────────────────────────────────────────────────
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
		visuals.play_death_anim(pos, mtype, false)
		_on_monster_killed(lane, pos, xp_val, mtype)

func _on_monster_killed(lane: int, kill_pos: Vector2, xp_val: int, mtype: String):
	var gold_table = {"g": 5, "b": 12, "r": 25}
	_add_gold(gold_table.get(mtype, 0))
	monsters_remaining -= 1
	if run_stats.has("kills"):
		run_stats.kills[mtype] = run_stats.kills.get(mtype, 0) + 1
		var wid = weapons.active_weapon_id
		if wid != "":
			run_stats.weapon_kills[wid] = run_stats.weapon_kills.get(wid, 0) + 1
	print("[KILL] File %d — remaining: %d — grid_empty: %s — in_flight: %d" % [lane+1, monsters_remaining, _grid_empty(), spawns_in_flight])
	visuals.show_gold_float(kill_pos, gold_table.get(mtype, 0))
	_spawn_gem(lane, kill_pos, xp_val)
	_check_room_clear()

func _add_gold(amount: int):
	gold_current      += amount
	gold_total_earned += amount
	hud.update_gold(gold_current)

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
	for r in GameData.ROWS:
		for l in GameData.LANES:
			if grid[r][l] != null: return false
	return true

func _room_cleared():
	await visuals.play_door_animation(room_num, player_ctrl.player_lane, _add_gold)
	room_clear = true
	_start_room(room_num + 1)

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
	var fixed_x = GameData.GRID_X + lane * GameData.LANE_W + GameData.LANE_W * 0.5
	g.position.x = fixed_x
	var dist     = abs((GameData.PLAYER_Y - 10) - g.position.y)
	var duration = dist / 380.0  # 380 px/s — vitesse constante
	var tw = create_tween()
	tw.tween_property(g, "position:y", GameData.PLAYER_Y - 10, duration)
	await tw.finished
	if not is_instance_valid(g): return
	g.position.x = fixed_x  # sécurité : re-snap au cas où
	if lane == player_ctrl.player_lane:
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
	return GameData.WEAPON_DEFS.keys().filter(func(wid): return not owned.has(wid))

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

# ── Input (délégué à player_ctrl) ──────────────────────────────
func _input(event: InputEvent):
	player_ctrl.handle_input(event, game_over, leveling_up, room_clear)

# ── Callback game over joueur ───────────────────────────────────
func _on_player_game_over():
	game_over = true
	_save_records()
	hud.show_game_over(gold_total_earned, room_num)

# ── Records ──────────────────────────────────────────────────────
func _init_run_stats():
	_run_start_ms = Time.get_ticks_msec()
	run_stats = {
		"score":        0,
		"best_room":    1,
		"run_time":     0,
		"kills":        {"g": 0, "b": 0, "r": 0},
		"weapon_kills": {}
	}
	for wid in GameData.WEAPON_DEFS.keys():
		run_stats.weapon_kills[wid] = 0

func _save_records():
	run_stats.score     = gold_total_earned
	run_stats.best_room = room_num
	run_stats.run_time  = int((Time.get_ticks_msec() - _run_start_ms) / 1000)

	var best_score = records.get("best_score", 0)
	var best_room  = records.get("best_room",  0)
	var best_time  = records.get("best_time",  0)

	var total_kills   : Dictionary = records.get("total_kills",   {"g": 0, "b": 0, "r": 0})
	var weapon_kills  : Dictionary = records.get("weapon_kills",  {})

	if run_stats.score    > best_score: best_score = run_stats.score
	if run_stats.best_room > best_room: best_room  = run_stats.best_room
	if run_stats.run_time  > best_time: best_time  = run_stats.run_time

	for t in run_stats.kills:
		total_kills[t] = total_kills.get(t, 0) + run_stats.kills[t]
	for wid in run_stats.weapon_kills:
		weapon_kills[wid] = weapon_kills.get(wid, 0) + run_stats.weapon_kills[wid]

	var fav = ""
	var fav_count = 0
	for wid in weapon_kills:
		if weapon_kills[wid] > fav_count:
			fav_count = weapon_kills[wid]
			fav = wid

	records = {
		"best_score":   best_score,
		"best_room":    best_room,
		"best_time":    best_time,
		"total_kills":  total_kills,
		"weapon_kills": weapon_kills,
		"fav_weapon":   fav
	}

	var cfg = ConfigFile.new()
	cfg.set_value("records", "best_score",  records.best_score)
	cfg.set_value("records", "best_room",   records.best_room)
	cfg.set_value("records", "best_time",   records.best_time)
	cfg.set_value("records", "fav_weapon",  records.fav_weapon)
	for t in records.total_kills:
		cfg.set_value("kills", t, records.total_kills[t])
	for wid in records.weapon_kills:
		cfg.set_value("weapon_kills", wid, records.weapon_kills[wid])
	cfg.save("user://records.cfg")
	print("[RECORDS] Sauvegarde — score: %d  salle: %d  temps: %ds  arme fav: %s" % [best_score, best_room, best_time, fav])

func _load_records():
	var cfg = ConfigFile.new()
	if cfg.load("user://records.cfg") != OK:
		records = {
			"best_score":   0,
			"best_room":    0,
			"best_time":    0,
			"total_kills":  {"g": 0, "b": 0, "r": 0},
			"weapon_kills": {},
			"fav_weapon":   ""
		}
		return

	var total_kills : Dictionary = {"g": 0, "b": 0, "r": 0}
	for t in total_kills.keys():
		total_kills[t] = cfg.get_value("kills", t, 0)

	var weapon_kills : Dictionary = {}
	for wid in GameData.WEAPON_DEFS.keys():
		weapon_kills[wid] = cfg.get_value("weapon_kills", wid, 0)

	records = {
		"best_score":   cfg.get_value("records", "best_score",  0),
		"best_room":    cfg.get_value("records", "best_room",   0),
		"best_time":    cfg.get_value("records", "best_time",   0),
		"total_kills":  total_kills,
		"weapon_kills": weapon_kills,
		"fav_weapon":   cfg.get_value("records", "fav_weapon",  "")
	}
	print("[RECORDS] Chargé — meilleur score: %d  salle: %d" % [records.best_score, records.best_room])
