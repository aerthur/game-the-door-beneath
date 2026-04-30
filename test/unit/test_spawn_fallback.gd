extends GutTest

# Tests de non-régression : logique de spawn (find_spawn_lane, _resolve_spawn_ctx)
# et politique de respawn avec retry prioritaire (issue #70).
# Couvre : mapping entry_side → coordonnées grille, retry sur file d'origine (12 ticks),
#          fallback adjacent après expiration, abandon si aucune lane, cas limites.

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
	var lane := _enemies.find_spawn_lane(2)
	assert_eq(lane, 2, "lane préférée libre → retourne la lane préférée")

func test_find_spawn_lane_preferred_occupied_tries_plus1() -> void:
	_state.set_cell_occupied(0, 2, "m")
	var lane := _enemies.find_spawn_lane(2)
	assert_eq(lane, 3, "lane 2 occupée → premier offset +1 → lane 3")

func test_find_spawn_lane_preferred_and_plus1_occupied_tries_minus1() -> void:
	_state.set_cell_occupied(0, 2, "m")
	_state.set_cell_occupied(0, 3, "m")
	var lane := _enemies.find_spawn_lane(2)
	assert_eq(lane, 1, "lanes 2 et 3 occupées → offset -1 → lane 1")

func test_find_spawn_lane_all_occupied_returns_minus_one() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_cell_occupied(0, c, "m")
	var lane := _enemies.find_spawn_lane(2)
	assert_eq(lane, -1, "toutes les lanes occupées → retourne -1")

func test_find_spawn_lane_preferred_blocked_by_obstacle() -> void:
	_state.set_obstacle(0, 2, ObstacleData.make_wall())
	var lane := _enemies.find_spawn_lane(2)
	assert_ne(lane, 2, "lane bloquée par obstacle exclue du résultat")
	assert_true(lane >= 0, "une lane de fallback existe")

func test_find_spawn_lane_all_blocked_returns_minus_one() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_obstacle(0, c, ObstacleData.make_wall())
	var lane := _enemies.find_spawn_lane(0)
	assert_eq(lane, -1, "toutes les lanes bloquées → retourne -1")

func test_find_spawn_lane_boundary_lane0_occupied() -> void:
	_state.set_cell_occupied(0, 0, "m")
	var lane := _enemies.find_spawn_lane(0)
	assert_ne(lane, -1, "lane 0 occupée mais fallbacks disponibles → pas de -1")
	assert_true(lane >= 0 and lane < BoardGeometry.GRID_COLUMNS, "lane de fallback dans les bornes")

func test_find_spawn_lane_boundary_lane4_occupied() -> void:
	_state.set_cell_occupied(0, 4, "m")
	var lane := _enemies.find_spawn_lane(4)
	assert_ne(lane, -1, "lane 4 occupée mais fallbacks disponibles → pas de -1")
	assert_true(lane >= 0 and lane < BoardGeometry.GRID_COLUMNS, "lane de fallback dans les bornes")

func test_find_spawn_lane_returns_valid_lane_index() -> void:
	var lane := _enemies.find_spawn_lane(1)
	assert_true(lane >= 0 and lane < BoardGeometry.GRID_COLUMNS,
		"lane retournée dans l'intervalle [0, GRID_COLUMNS[")

func test_find_spawn_lane_four_occupied_still_finds_one() -> void:
	for c in [0, 1, 2, 3]:
		_state.set_cell_occupied(0, c, "m")
	var lane := _enemies.find_spawn_lane(0)
	assert_eq(lane, 4, "4 lanes occupées depuis 0 → fallback sur la dernière lane libre (4)")

# ── Politique de retry/fallback — issue #70 ──────────────────────
# resolve_pending_respawn_lane est une fonction pure (pas de side-effect).
# Valeurs de retour : lane >= 0 → spawner là ; -1 → rester en attente ; -2 → abandonner.

func test_request_respawn_queues_when_lane_occupied() -> void:
	_state.set_cell_occupied(0, 2, "m")
	var spawned := _enemies.request_respawn("g", 2)
	assert_false(spawned, "Lane occupée → request_respawn retourne false (en attente)")
	assert_eq(_enemies.pending_respawns.size(), 1, "Un respawn en attente créé")
	assert_eq(_enemies.pending_respawns[0]["lane"], 2, "Lane d'origine mémorisée")
	assert_eq(_enemies.pending_respawns[0]["ticks_waited"], 0, "Compteur initialisé à 0")

func test_resolve_pending_stays_minus1_within_window() -> void:
	_state.set_cell_occupied(0, 2, "m")
	var req := { "monster_id": "g", "lane": 2, "ticks_waited": 0 }
	for i in range(GameData.TICKS_PER_SECOND - 1):
		req["ticks_waited"] = i + 1
		var result := _enemies.resolve_pending_respawn_lane(req)
		assert_eq(result, -1, "Tick %d < %d : lane occupée → reste en attente" % [i+1, GameData.TICKS_PER_SECOND])

func test_resolve_pending_returns_origin_when_freed_within_window() -> void:
	# Reproduit le bug corrigé : sans le retry, un fallback immédiat était déclenché
	# même si la lane d'origine allait se libérer dans la fenêtre de 12 ticks.
	_state.set_cell_occupied(0, 2, "m")
	var req := { "monster_id": "g", "lane": 2, "ticks_waited": 5 }
	_state.clear_cell(0, 2)  # la cellule se libère au tick 5
	var result := _enemies.resolve_pending_respawn_lane(req)
	assert_eq(result, 2, "Lane d'origine libérée à t=5 (< 12) → retourne lane 2, sans fallback adjacent")

func test_resolve_pending_falls_back_after_timeout() -> void:
	_state.set_cell_occupied(0, 2, "m")
	# lanes 1 et 3 libres, fenêtre expirée
	var req := { "monster_id": "g", "lane": 2, "ticks_waited": GameData.TICKS_PER_SECOND }
	var result := _enemies.resolve_pending_respawn_lane(req)
	assert_ne(result, -1, "Fenêtre expirée → ne reste plus en attente")
	assert_ne(result, -2, "Lane adjacente disponible → pas d'abandon")
	assert_ne(result, 2, "Lane d'origine toujours occupée → pas la lane 2")
	assert_true(result >= 0 and result < BoardGeometry.GRID_COLUMNS, "Fallback dans les bornes valides")

func test_resolve_pending_abandons_when_all_blocked_after_timeout() -> void:
	for c in BoardGeometry.GRID_COLUMNS:
		_state.set_cell_occupied(0, c, "m")
	var req := { "monster_id": "g", "lane": 2, "ticks_waited": GameData.TICKS_PER_SECOND }
	var result := _enemies.resolve_pending_respawn_lane(req)
	assert_eq(result, -2, "Toutes les lanes bloquées + fenêtre expirée → abandon (-2)")

func test_pending_respawns_cleared_between_tests() -> void:
	_state.set_cell_occupied(0, 0, "m")
	_enemies.request_respawn("g", 0)
	_enemies.clear_pending_respawns()
	assert_eq(_enemies.pending_respawns.size(), 0, "clear_pending_respawns vide la file")
