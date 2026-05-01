extends Node
# Dernière mise à jour : 2026-04-22

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
var board_state : BoardState = BoardState.new()
var active_gems : Array = []

var tick_acc      : float = 0.0
var tick_interval : float = 1.0 / 12.0  # simulation fixe à 12 ticks/s (GameData.TICKS_PER_SECOND)

@onready var monsters_node  : Node2D      = $Monsters
@onready var player_node    : Node2D      = $Player
@onready var hud            : CanvasLayer = $HUD
@onready var bg             : Node2D      = $Background
@onready var visuals        : Node2D      = $Visuals
@onready var enemies        : Node2D      = $Enemies
@onready var weapons        : Node2D      = $Weapons
@onready var player_ctrl    : Node2D      = $PlayerCtrl
@onready var records_ctrl   : Node2D      = $Records

var gem_scene = preload("res://scenes/gem.tscn")

# ═════════════════════════════════════════════════════════════════
func _ready():
	add_to_group("game")
	records_ctrl.hud = hud
	records_ctrl.load_records()
	visuals.bg = bg
	enemies.monsters_node = monsters_node
	enemies.board_state = board_state
	weapons.board_state = board_state
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
	board_state.clear_all()
	_setup_test_obstacles()

# Obstacles de test — à retirer ou adapter quand les salles seront data-driven.
func _setup_test_obstacles():
	var wall = ObstacleData.make_wall()
	board_state.set_obstacle(3, 1, wall)
	board_state.set_obstacle(3, 3, wall)

func grid_pos(row: int, lane: int) -> Vector2:
	return BoardGeometry.get_cell_center(row, lane)

# ── Fond ─────────────────────────────────────────────────────────
func _draw_background():
	var floor_rect = ColorRect.new()
	floor_rect.color = Color(0.07, 0.05, 0.04)
	floor_rect.size  = Vector2(1280, 720)
	bg.add_child(floor_rect)
	for r in BoardGeometry.GRID_ROWS:
		for l in BoardGeometry.GRID_COLUMNS:
			var cell = ColorRect.new()
			cell.position = Vector2(BoardGeometry.GRID_ORIGIN_X + l * BoardGeometry.CELL_WIDTH, BoardGeometry.GRID_ORIGIN_Y + r * BoardGeometry.CELL_HEIGHT)
			cell.size     = Vector2(BoardGeometry.CELL_WIDTH - 2, BoardGeometry.CELL_HEIGHT - 2)
			cell.color    = Color(0.13, 0.10, 0.08) if (r + l) % 2 == 0 else Color(0.11, 0.09, 0.07)
			bg.add_child(cell)
	for l in BoardGeometry.GRID_COLUMNS:
		var lbl = Label.new()
		lbl.text = "F%d" % (l + 1)
		lbl.position = Vector2(BoardGeometry.GRID_ORIGIN_X + l * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH * 0.5 - 10,
							   BoardGeometry.GRID_ORIGIN_Y + BoardGeometry.GRID_ROWS * BoardGeometry.CELL_HEIGHT + 4)
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		bg.add_child(lbl)
	_draw_obstacles()

# Dessine les obstacles de test comme overlays sur les cellules concernées.
func _draw_obstacles():
	var test_cells = [[3, 1], [3, 3]]
	for coord in test_cells:
		var r : int = coord[0]
		var l : int = coord[1]
		var rect = ColorRect.new()
		rect.position = Vector2(
			BoardGeometry.GRID_ORIGIN_X + l * BoardGeometry.CELL_WIDTH + 1,
			BoardGeometry.GRID_ORIGIN_Y + r * BoardGeometry.CELL_HEIGHT + 1)
		rect.size  = Vector2(BoardGeometry.CELL_WIDTH - 3, BoardGeometry.CELL_HEIGHT - 3)
		rect.color = Color(0.28, 0.22, 0.12, 0.92)
		bg.add_child(rect)
		var lbl = Label.new()
		lbl.text = "▪"
		lbl.position = rect.position + Vector2(BoardGeometry.CELL_WIDTH * 0.5 - 8, BoardGeometry.CELL_HEIGHT * 0.5 - 10)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.45, 0.30))
		bg.add_child(lbl)

# ── Salle ────────────────────────────────────────────────────────
func _start_room(num: int):
	if num == 1:
		records_ctrl.init_run_stats()
	room_num         = num
	room_clear       = false
	spawns_in_flight = 0
	for child in monsters_node.get_children(): child.queue_free()
	for g in active_gems:
		if is_instance_valid(g.node): g.node.queue_free()
	active_gems.clear()
	_init_grid()
	hud.update_room(room_num)
	hud.hide_door()

	enemies.clear_pending_respawns()
	if room_num % 5 == 0:
		monsters_remaining = enemies.spawn_boss(room_num)
	else:
		var composition = enemies.get_composition(num)
		monsters_remaining = composition.size()
		print("[SALLE %d] Démarrage — %d monstres — composition: %s" % [num, monsters_remaining, composition])
		enemies.spawn_wave(composition)

# ── Boucle ───────────────────────────────────────────────────────
func _process(delta: float):
	if game_over or leveling_up: return
	if room_clear: return

	tick_acc += delta
	while tick_acc >= tick_interval:
		tick_acc -= tick_interval
		_do_tick()

	for w in active_weapons:
		var def = GameData.WEAPON_DEFS[w.id]
		w.acc += delta
		if w.acc >= def.cd:
			w.acc = 0.0
			weapons.fire(w)

# ── Tick ─────────────────────────────────────────────────────────
func _do_tick():
	for r in range(BoardGeometry.GRID_ROWS - 1, -1, -1):
		for l in range(BoardGeometry.GRID_COLUMNS):
			var m = board_state.get_cell_occupant(r, l)
			if m == null: continue
			m.tick_freeze()
			if m.frozen_ticks > 0: continue
			m.move_countdown_ticks -= 1
			if m.move_countdown_ticks > 0: continue
			m.move_countdown_ticks = m.move_period_ticks

			var new_row = r + 1
			if new_row >= BoardGeometry.GRID_ROWS:
				var dmg   = m.damage
				var mtype = m.monster_type
				board_state.clear_cell(r, l)
				if m.is_boss:
					var hit_lanes : Dictionary = {}
					for dl in [-1, 0, 1]:
						hit_lanes[clamp(l + dl, 0, BoardGeometry.GRID_COLUMNS - 1)] = true
					for tl in hit_lanes:
						if tl == player_ctrl.player_lane:
							player_ctrl.hit(dmg)
					enemies.boss_retreat(m, l)
				else:
					m.queue_free()
					if l == player_ctrl.player_lane:
						player_ctrl.hit(dmg)
					_on_monster_escaped(l, mtype)
			else:
				if board_state.is_cell_free(new_row, l) and not board_state.is_cell_blocked(new_row, l):
					board_state.set_cell_occupied(new_row, l, m)
					board_state.clear_cell(r, l)
					m.grid_row  = new_row
					m.grid_lane = l
					var tw = create_tween()
					tw.tween_property(m, "position", grid_pos(new_row, l), 0.25)
	# Traitement des respawns en attente après les déplacements
	_execute_respawn_results(enemies.tick_pending_respawns())

func _on_monster_escaped(lane: int, mtype: String) -> void:
	spawns_in_flight   += 1
	monsters_remaining += 1
	# Tentative immédiate sur la file d'origine uniquement (pas de fallback immédiat)
	if enemies.try_spawn_preferred(mtype, lane):
		spawns_in_flight -= 1
		print("[ESCAPE] File %d type=%s — spawn immédiat — remaining: %d" % [lane+1, mtype, monsters_remaining])
	else:
		# File occupée : retry prioritaire pendant 12 ticks avant fallback adjacent
		enemies.queue_respawn(lane, mtype)
		print("[ESCAPE] File %d type=%s — spawn différé (retry %d ticks) — remaining: %d" % [lane+1, mtype, GameData.TICKS_PER_SECOND, monsters_remaining])

# Exécute les actions retournées par enemies.tick_pending_respawns().
func _execute_respawn_results(results: Array) -> void:
	for r in results:
		spawns_in_flight -= 1
		if r["action"] == "spawn":
			var ok := enemies.spawn_at(r["mtype"], 0, r["lane"])
			if not ok:
				monsters_remaining -= 1
				print("[RESPAWN] File %d type=%s → spawn échoué — remaining: %d" % [r["preferred_lane"]+1, r["mtype"], monsters_remaining])
			else:
				print("[RESPAWN] File %d type=%s → %s lane %d — remaining: %d" % [r["preferred_lane"]+1, r["mtype"], r["status"], r["lane"]+1, monsters_remaining])
		else:  # abandon
			monsters_remaining -= 1
			print("[RESPAWN] File %d type=%s → abandonné — remaining: %d" % [r["preferred_lane"]+1, r["mtype"], monsters_remaining])
		_check_room_clear()

# ── Combat ───────────────────────────────────────────────────────
func _deal_and_check(m: Node2D, _row: int, _lane: int, dmg: int):
	if not is_instance_valid(m): return
	var xp_val = m.xp_value
	m.take_damage(dmg)
	if m.hp <= 0:
		var row   = m.grid_row
		var lane  = m.grid_lane
		var mtype = m.monster_type
		board_state.clear_cell(row, lane)
		var pos = m.position
		m.queue_free()
		visuals.play_death_anim(pos, mtype, false)
		_on_monster_killed(lane, pos, xp_val, mtype)

func _on_monster_killed(lane: int, kill_pos: Vector2, xp_val: int, mtype: String):
	var gold_table = {"g": 5, "b": 12, "r": 25}
	_add_gold(gold_table.get(mtype, 0))
	monsters_remaining -= 1
	records_ctrl.on_kill(mtype, weapons.active_weapon_id)
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
	if _grid_empty() and spawns_in_flight == 0:
		if monsters_remaining != 0:
			print("[CLEAR] Correction compteur dérivé: remaining %d → 0" % monsters_remaining)
			monsters_remaining = 0
		print("[CLEAR] Salle vidée → _room_cleared()")
		_room_cleared()

func _grid_empty() -> bool:
	return board_state.is_grid_empty()

func _room_cleared():
	await visuals.play_door_animation(room_num, player_ctrl.player_lane, _add_gold)
	room_clear = true
	_start_room(room_num + 1)

# ── Gemmes ───────────────────────────────────────────────────────
func _spawn_gem(lane: int, pos: Vector2, xp_val: int):
	var g = gem_scene.instantiate()
	g.lane     = lane
	g.xp_value = xp_val
	g.position = pos
	var diamond = g.get_node("Diamond")
	if xp_val >= 100:
		diamond.color = Color(1.0, 0.35, 0.35)
	elif xp_val >= 50:
		diamond.color = Color(0.35, 0.55, 1.0)
	bg.add_child(g)
	active_gems.append({"node": g, "lane": lane})

	var fixed_x = BoardGeometry.GRID_ORIGIN_X + lane * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH * 0.5
	g.position.x = fixed_x
	var dist     = abs((BoardGeometry.PLAYER_Y - 10) - g.position.y)
	var duration = dist / 380.0
	var tw = create_tween()
	tw.tween_property(g, "position:y", BoardGeometry.PLAYER_Y - 10, duration)
	await tw.finished
	if not is_instance_valid(g): return
	g.position.x = fixed_x
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
	g.visible = false
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
	hud.show_level_up(_generate_choices())

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

# ── Game Over ────────────────────────────────────────────────────
func _on_player_game_over():
	game_over = true
	records_ctrl.on_game_over(room_num, gold_total_earned, hero_level)
	hud.show_game_over(gold_total_earned, room_num)

# ── Input (délégué à player_ctrl) ────────────────────────────────
func _input(event: InputEvent):
	player_ctrl.handle_input(event, game_over, leveling_up, room_clear)
