extends GutTest

# Tests de non-régression : logique de spawn (find_spawn_lane, _resolve_spawn_ctx)
# Couvre : mapping entry_side → coordonnées grille, retry prioritaire, fallback de lane,
#          cas limites (all occupied, all blocked, lanes de bord)

var _state: BoardState
var _enemies: Node

func before_each() -> void:
	_state = BoardState.new()
	_state.clear_all()
	_enemies = preload("res://scripts/game_enemies.gd").new()
	_enemies.board_state = _state
	add_child_autofree(_enemies)

# ── _resolve_spawn_ctx : mapping entry_side → coordonnées ────────

func test_resolve_ctx_top_maps_to_row0() -> void:
	var result: Dictionary = _enemies._resolve_spawn_ctx({"entry_side": "top", "entry_index": 2})
	assert_eq(result["row"],  0, "entry_side 'top' → row 0")
	assert_eq(result["lane"], 2, "entry_side 'top' → lane = entry_index")

func test_resolve_ctx_bottom_maps_to_last_row() -> void:
	var result: Dictionary = _enemies._resolve_spawn_ctx({"entry_side": "bottom", "entry_index": 3})
	assert_eq(result["row"],  BoardGeometry.GRID_ROWS - 1, "entry_side 'bottom' → dernière row")
	assert_eq(result["lane"], 3, "entry_side 'bottom' → lane = entry_index")

func test_resolve_ctx_left_maps_to_lane0() -> void:
	var result: Dictionary = _enemies._resolve_spawn_ctx({"entry_side": "left", "entry_index": 4})
	assert_eq(result["row"],  4, "entry_side 'left' → row = entry_index")
	assert_eq(result["lane"], 0, "entry_side 'left' → lane 0")

func test_resolve_ctx_right_maps_to_last_lane() -> void:
	var result: Dictionary = _enemies._resolve_spawn_ctx({"entry_side": "right", "entry_index": 1})
	assert_eq(result["row"],  1, "entry_side 'right' → row = entry_index")
	assert_eq(result["lane"], BoardGeometry.GRID_COLUMNS - 1, "entry_side 'right' → dernière lane")

func test_resolve_ctx_missing_side_defaults_to_top() -> void:
	var result: Dictionary = _enemies._resolve_spawn_ctx({"entry_index": 0})
	assert_eq(result["row"],  0, "entry_side absent → top → row 0")
	assert_eq(result["lane"], 0, "entry_side absent → top → lane = index")

func test_resolve_ctx_unknown_side_defaults_to_top() -> void:
	var result: Dictionary = _enemies._resolve_spawn_ctx({"entry_side": "diagonal", "entry_index": 2})
	assert_eq(result["row"], 0, "entry_side inconnu → top → row 0")

# ── find_spawn_lane : retry et fallback ──────────────────────────

func test_find_spawn_lane_preferred_free_returns_it() -> void:
	var lane: int = _enemies.find_spawn_lane(2)
	assert_eq(lane, 2, "lane préférée libre → retourne la lane préférée")

func test_find_spawn_lane_preferred_occupied_tries_plus1() -> void:
	_state.set_cell_occupied(0, 2, "m")
	var lane: int = _enemies.find_spawn_lane(2)
	assert_eq(lane, 3, "lane 2 occupée → premier offset +1 → lane 3")

func test_find_spawn_lane_preferred_and_plus1_occupied_tries_minus1() -> void:
	_state.set_cell_occupied(0, 2, "m")
	_state.set_cell_occupied(0, 3, "m")
	var lane: int = _enemies.find_spawn_lane(2)
	assert_eq(lane, 1, "lanes 2 et 3 occupées → offset -1 → lane 1")

func test_find_spawn_lane_all_occupied_returns_minus_one() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_cell_occupied(0, c, "m")
	var lane: int = _enemies.find_spawn_lane(2)
	assert_eq(lane, -1, "toutes les lanes occupées → retourne -1")

func test_find_spawn_lane_preferred_blocked_by_obstacle() -> void:
	_state.set_obstacle(0, 2, ObstacleData.make_wall())
	var lane: int = _enemies.find_spawn_lane(2)
	assert_ne(lane, 2, "lane bloquée par obstacle exclue du résultat")
	assert_true(lane >= 0, "une lane de fallback existe")

func test_find_spawn_lane_all_blocked_returns_minus_one() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_obstacle(0, c, ObstacleData.make_wall())
	var lane: int = _enemies.find_spawn_lane(0)
	assert_eq(lane, -1, "toutes les lanes bloquées → retourne -1")

func test_find_spawn_lane_boundary_lane0_occupied() -> void:
	_state.set_cell_occupied(0, 0, "m")
	var lane: int = _enemies.find_spawn_lane(0)
	assert_ne(lane, -1, "lane 0 occupée mais fallbacks disponibles → pas de -1")
	assert_true(lane >= 0 and lane < BoardGeometry.GRID_COLUMNS, "lane de fallback dans les bornes")

func test_find_spawn_lane_boundary_lane4_occupied() -> void:
	_state.set_cell_occupied(0, 4, "m")
	var lane: int = _enemies.find_spawn_lane(4)
	assert_ne(lane, -1, "lane 4 occupée mais fallbacks disponibles → pas de -1")
	assert_true(lane >= 0 and lane < BoardGeometry.GRID_COLUMNS, "lane de fallback dans les bornes")

func test_find_spawn_lane_returns_valid_lane_index() -> void:
	var lane: int = _enemies.find_spawn_lane(1)
	assert_true(lane >= 0 and lane < BoardGeometry.GRID_COLUMNS,
		"lane retournée dans l'intervalle [0, GRID_COLUMNS[")

func test_find_spawn_lane_four_occupied_still_finds_one() -> void:
	for c in [0, 1, 2, 3]:
		_state.set_cell_occupied(0, c, "m")
	var lane: int = _enemies.find_spawn_lane(0)
	assert_eq(lane, 4, "4 lanes occupées depuis 0 → fallback sur la dernière lane libre (4)")

# ── get_respawn_lane : politique de retry prioritaire (issue #70) ─

func test_respawn_no_fallback_when_preferred_occupied_in_window() -> void:
	# Bug reproduit : l'ancienne logique (find_spawn_lane) basculait immédiatement vers lane 3.
	# La nouvelle logique (get_respawn_lane) reste en attente dans la fenêtre de 12 ticks.
	_state.set_cell_occupied(0, 2, "m")
	var old_result: int = _enemies.find_spawn_lane(2)
	assert_eq(old_result, 3, "ancienne logique find_spawn_lane : fallback immédiat vers lane 3")
	var new_result: int = _enemies.get_respawn_lane(2, 0, 12)
	assert_eq(new_result, _enemies.RESPAWN_KEEP_WAITING,
		"nouvelle logique : reste en attente (pas de fallback immédiat)")

func test_respawn_keep_waiting_throughout_window() -> void:
	_state.set_cell_occupied(0, 2, "m")
	for tick in range(0, 12):
		var r: int = _enemies.get_respawn_lane(2, tick, 12)
		assert_eq(r, _enemies.RESPAWN_KEEP_WAITING,
			"tick %d : file occupée dans la fenêtre → keep waiting" % tick)

func test_respawn_retry_succeeds_on_preferred_lane_within_window() -> void:
	# Retry réussi : file occupée à t=0, se libère à t=6, spawn sur file d'origine
	_state.set_cell_occupied(0, 2, "m")
	var r0: int = _enemies.get_respawn_lane(2, 0, 12)
	assert_eq(r0, _enemies.RESPAWN_KEEP_WAITING, "t0 occupée → keep waiting")
	var r5: int = _enemies.get_respawn_lane(2, 5, 12)
	assert_eq(r5, _enemies.RESPAWN_KEEP_WAITING, "t5 encore occupée → keep waiting")
	_state.clear_cell(0, 2)
	var r6: int = _enemies.get_respawn_lane(2, 6, 12)
	assert_eq(r6, 2, "t6 libérée → spawn sur file d'origine (lane 2)")
	assert_ne(r6, 3, "pas de fallback sur lane adjacente")

func test_respawn_fallback_after_12_ticks() -> void:
	# Fallback après timeout : file d'origine occupée pendant 12 ticks → fallback vers lane 3
	_state.set_cell_occupied(0, 2, "m")
	var r11: int = _enemies.get_respawn_lane(2, 11, 12)
	assert_eq(r11, _enemies.RESPAWN_KEEP_WAITING, "tick 11 → encore dans la fenêtre")
	var r12: int = _enemies.get_respawn_lane(2, 12, 12)
	assert_eq(r12, 3, "tick 12 → fenêtre expirée, fallback vers lane 3 (offset +1)")

func test_respawn_fallback_deterministic_order() -> void:
	# Ordre déterministe du fallback : offsets [+1, -1, +2, -2, ...]
	_state.set_cell_occupied(0, 2, "m")
	_state.set_cell_occupied(0, 3, "m")  # +1 occupé
	var r: int = _enemies.get_respawn_lane(2, 12, 12)
	assert_eq(r, 1, "lane 3 (offset +1) occupée → fallback vers lane 1 (offset -1)")

func test_respawn_give_up_when_all_lanes_blocked_after_timeout() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_cell_occupied(0, c, "m")
	var r: int = _enemies.get_respawn_lane(2, 12, 12)
	assert_eq(r, _enemies.RESPAWN_GIVE_UP, "toutes les lanes bloquées après timeout → GIVE_UP")

func test_respawn_preferred_free_returns_immediately() -> void:
	# File d'origine libre → retourne immédiatement même à ticks_waited = 0
	var r: int = _enemies.get_respawn_lane(2, 0, 12)
	assert_eq(r, 2, "file d'origine libre → retourne lane 2 sans attente")

# ── tick_pending_respawns : intégration file d'attente ───────────

func test_tick_pending_stay_waiting_when_occupied() -> void:
	_state.set_cell_occupied(0, 2, "m")
	_enemies.queue_respawn(2, "g")
	var results: Array = _enemies.tick_pending_respawns()
	assert_eq(results.size(), 0, "file occupée dans la fenêtre → pas d'action retournée")
	assert_eq(_enemies._pending_respawns.size(), 1, "respawn toujours en attente")
	assert_eq(_enemies._pending_respawns[0]["ticks_waited"], 1, "ticks_waited incrémenté à 1")

func test_tick_pending_spawn_on_preferred_when_free() -> void:
	# File libre dès le premier tick → action spawn retournée
	_enemies.queue_respawn(2, "g")
	var results: Array = _enemies.tick_pending_respawns()
	assert_eq(results.size(), 1, "file libre → une action retournée")
	assert_eq(results[0]["action"], "spawn", "action = spawn")
	assert_eq(results[0]["lane"], 2, "spawn sur la file d'origine (lane 2)")
	assert_eq(results[0]["status"], "success", "status = success (file d'origine)")
	assert_eq(_enemies._pending_respawns.size(), 0, "plus en attente après résolution")

func test_tick_pending_fallback_after_12_ticks_integrated() -> void:
	# Simulation de 12 ticks avec file occupée → fallback vers lane 3
	_state.set_cell_occupied(0, 2, "m")
	_enemies.queue_respawn(2, "g")
	var results_before: Array = []
	for _i in range(11):
		results_before = _enemies.tick_pending_respawns()
		assert_eq(results_before.size(), 0, "dans la fenêtre → pas d'action")
	# 12ème tick → fallback
	var results: Array = _enemies.tick_pending_respawns()
	assert_eq(results.size(), 1, "après 12 ticks → action retournée")
	assert_eq(results[0]["action"], "spawn", "action = spawn (fallback)")
	assert_eq(results[0]["lane"], 3, "fallback vers lane 3 (offset +1)")
	assert_eq(results[0]["status"], "fallback", "status = fallback")

func test_tick_pending_abandoned_if_all_lanes_occupied_after_timeout() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_cell_occupied(0, c, "m")
	_enemies.queue_respawn(2, "g")
	for _i in range(12):
		_enemies.tick_pending_respawns()
	var results: Array = _enemies.tick_pending_respawns()
	assert_eq(results.size(), 1, "après timeout toutes lanes occupées → action retournée")
	assert_eq(results[0]["action"], "abandon", "action = abandon")

func test_clear_pending_respawns() -> void:
	_enemies.queue_respawn(1, "g")
	_enemies.queue_respawn(3, "b")
	_enemies.clear_pending_respawns()
	assert_eq(_enemies._pending_respawns.size(), 0, "clear_pending_respawns vide la file")
