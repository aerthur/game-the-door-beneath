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

var tick_acc : float = 0.0
var tick_interval : float = 1.0

@onready var monsters_node : Node2D      = $Monsters
@onready var player_node   : Node2D      = $Player
@onready var hud           : CanvasLayer = $HUD
@onready var bg            : Node2D      = $Background
@onready var visuals     : Node2D      = $Visuals

var blob_scene  = preload("res://scenes/monster_blob.tscn")
var blue_scene  = preload("res://scenes/monster_blue.tscn")
var red_scene   = preload("res://scenes/monster_red.tscn")
var boss_scene  = preload("res://scenes/monster_boss.tscn")
var gem_scene   = preload("res://scenes/gem.tscn")

# ═════════════════════════════════════════════════════════════════
func _ready():
	add_to_group("game")
	visuals.bg = bg
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

	if room_num % 5 == 0:
		_spawn_boss()
	else:
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

func _spawn_boss(escort: Array = []):
	var boss_type  : String = "g"
	var boss_hp    : int    = 300
	var boss_dmg   : int    = 25
	var boss_speed : int    = 1
	var boss_xp    : int    = 500

	if room_num >= 15:
		boss_type  = "r"
		boss_hp    = 1000
		boss_dmg   = 60
		boss_speed = 2
		boss_xp    = 2000
		if room_num > 15:
			var extra_tranches = (room_num - 15) / 5
			var mult = pow(1.5, extra_tranches)
			boss_hp  = int(boss_hp  * mult)
			boss_dmg = int(boss_dmg * mult)
			boss_xp  = int(boss_xp  * mult)
	elif room_num >= 10:
		boss_type  = "b"
		boss_hp    = 600
		boss_dmg   = 40
		boss_speed = 1
		boss_xp    = 1000

	var boss = boss_scene.instantiate()
	boss.hp           = boss_hp
	boss.hp_max       = boss_hp
	boss.damage       = boss_dmg
	boss.move_speed   = boss_speed
	boss.xp_value     = boss_xp
	boss.monster_type = boss_type
	monsters_node.add_child(boss)
	boss.position  = grid_pos(0, 2)
	boss.grid_row  = 0
	boss.grid_lane = 2
	grid[0][2]     = boss
	monsters_remaining = 1
	print("[BOSS] Salle %d — type=%s hp=%d dmg=%d" % [room_num, boss_type, boss_hp, boss_dmg])

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
				if m.is_boss:
					# Boss: inflige dégâts sur sa file ± 1, remonte soigné sans se dupliquer
					# TODO: adapter l'axe selon enemy_direction quand ce système sera implémenté
					var hit_lanes : Dictionary = {}
					for dl in [-1, 0, 1]:
						hit_lanes[clamp(l + dl, 0, LANES - 1)] = true
					for tl in hit_lanes:
						if tl == player_lane:
							_hit_player(dmg)
					_boss_retreat(m, l)
				else:
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

func _boss_retreat(boss: Node2D, lane: int):
	var heal_amount = int(boss.hp_max * 0.3)
	boss.hp = min(boss.hp_max, boss.hp + heal_amount)
	boss.update_health_bar()
	boss.grid_row  = 0
	boss.grid_lane = lane
	grid[0][lane]  = boss
	boss.position  = grid_pos(0, lane)
	print("[BOSS] Remontée file %d — soigné +%d → %d/%d" % [lane + 1, heal_amount, boss.hp, boss.hp_max])

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
			visuals.shoot_arrow(player_lane, r, t, Color(0.95, 0.85, 0.3))
			await get_tree().create_timer(t).timeout
			if is_instance_valid(m): _deal_and_check(m, r, player_lane, _get_dmg(w))
			return

func _w_arbalete(w: Dictionary):
	var hit = 0
	for r in range(ROWS - 1, -1, -1):
		if hit >= 2: break
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			visuals.shoot_arrow(player_lane, r, 0.18 + r * 0.015, Color(0.6, 0.6, 1.0), 5.0)
			await get_tree().create_timer(0.18 + r * 0.015).timeout
			if is_instance_valid(m): _deal_and_check(m, r, player_lane, _get_dmg(w))
			hit += 1

func _w_dague(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			visuals.show_slash(player_lane, r)
			_deal_and_check(grid[r][player_lane], r, player_lane, _get_dmg(w))
			return

func _w_bombe(w: Dictionary):
	for l in [player_lane - 1, player_lane, player_lane + 1]:
		if l < 0 or l >= LANES: continue
		for r in range(ROWS - 1, -1, -1):
			if grid[r][l] != null:
				visuals.show_explosion(l, r)
				await get_tree().create_timer(0.1).timeout
				if grid[r][l] != null: _deal_and_check(grid[r][l], r, l, _get_dmg(w))
				break

func _w_eclair(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			visuals.show_lightning(player_lane, r)
			_deal_and_check(grid[r][player_lane], r, player_lane, _get_dmg(w))

func _w_tourbillon(w: Dictionary):
	visuals.show_whirlwind()
	for l in LANES:
		for r in range(ROWS - 1, -1, -1):
			if grid[r][l] != null:
				_deal_and_check(grid[r][l], r, l, _get_dmg(w))
				break

func _w_givre(w: Dictionary):
	for r in range(ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			visuals.shoot_arrow(player_lane, r, 0.2, Color(0.4, 0.85, 1.0), 3.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(m):
				m.freeze(2)
				_deal_and_check(m, r, player_lane, _get_dmg(w))
			return

func _w_sismique(w: Dictionary):
	visuals.show_quake()
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
		visuals.play_death_anim(pos, mtype, false)
		_on_monster_killed(lane, pos, xp_val, mtype)

func _on_monster_killed(lane: int, kill_pos: Vector2, xp_val: int, mtype: String):
	var gold_table = {"g": 5, "b": 12, "r": 25}
	_add_gold(gold_table.get(mtype, 0))
	monsters_remaining -= 1
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
	for r in ROWS:
		for l in LANES:
			if grid[r][l] != null: return false
	return true

func _room_cleared():
	await visuals.play_door_animation(room_num, player_lane, _add_gold)
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
		hud.show_game_over(gold_total_earned, room_num)

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
