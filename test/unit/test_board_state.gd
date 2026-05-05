extends GutTest

# Tests de non-régression : BoardState
# Couvre : occupation de cellules, gestion des obstacles, is_grid_empty, is_cell_blocked

var _state: BoardState

func before_each() -> void:
	_state = BoardState.new()
	_state.clear_all()

func test_all_cells_free_initially() -> void:
	for r in BoardGeometry.GRID_ROWS:
		for c in BoardGeometry.GRID_COLUMNS:
			assert_true(_state.is_cell_free(r, c), "cellule (%d,%d) libre après clear_all" % [r, c])

func test_set_cell_marks_occupied() -> void:
	_state.set_cell_occupied(0, 0, "occupant")
	assert_true(_state.is_cell_occupied(0, 0), "cellule occupée après set")
	assert_false(_state.is_cell_free(0, 0), "cellule non libre après set")

func test_get_cell_occupant_returns_stored_value() -> void:
	var sentinel := {"tag": "test"}
	_state.set_cell_occupied(3, 2, sentinel)
	assert_eq(_state.get_cell_occupant(3, 2), sentinel, "occupant retourné correctement")

func test_clear_cell_frees_it() -> void:
	_state.set_cell_occupied(0, 0, "x")
	_state.clear_cell(0, 0)
	assert_true(_state.is_cell_free(0, 0), "cellule libre après clear_cell")
	assert_null(_state.get_cell_occupant(0, 0), "occupant null après clear_cell")

func test_is_grid_empty_initially() -> void:
	assert_true(_state.is_grid_empty(), "grille vide après clear_all")

func test_is_grid_not_empty_after_set() -> void:
	_state.set_cell_occupied(4, 2, "m")
	assert_false(_state.is_grid_empty(), "grille non vide après spawn")

func test_is_grid_empty_after_removing_only_occupant() -> void:
	_state.set_cell_occupied(1, 1, "m")
	_state.clear_cell(1, 1)
	assert_true(_state.is_grid_empty(), "grille vide après retrait du seul occupant")

func test_no_obstacle_by_default() -> void:
	assert_false(_state.has_obstacle(0, 0), "pas d'obstacle par défaut")

func test_set_and_has_obstacle() -> void:
	_state.set_obstacle(2, 1, ObstacleData.make_wall())
	assert_true(_state.has_obstacle(2, 1), "obstacle présent après set_obstacle")

func test_is_cell_blocked_by_wall() -> void:
	_state.set_obstacle(2, 1, ObstacleData.make_wall())
	assert_true(_state.is_cell_blocked(2, 1), "cellule bloquée par mur indestructible")

func test_is_cell_blocked_false_without_obstacle() -> void:
	assert_false(_state.is_cell_blocked(0, 0), "cellule non bloquée sans obstacle")

func test_clear_obstacle_unblocks_cell() -> void:
	_state.set_obstacle(0, 0, ObstacleData.make_wall())
	_state.clear_obstacle(0, 0)
	assert_false(_state.has_obstacle(0, 0), "obstacle absent après clear_obstacle")
	assert_false(_state.is_cell_blocked(0, 0), "cellule non bloquée après effacement")

func test_clear_obstacles_does_not_affect_occupants() -> void:
	_state.set_cell_occupied(1, 1, "m")
	_state.set_obstacle(1, 1, ObstacleData.make_wall())
	_state.clear_obstacles()
	assert_false(_state.has_obstacle(1, 1), "obstacles effacés par clear_obstacles")
	assert_true(_state.is_cell_occupied(1, 1), "occupants non affectés par clear_obstacles")

func test_obstacle_blocking_movement_only() -> void:
	var obs := ObstacleData.new()
	obs.blocks_movement  = true
	obs.blocks_occupancy = false
	_state.set_obstacle(0, 0, obs)
	assert_true(_state.is_cell_blocked(0, 0), "obstacle bloquant mouvement → is_cell_blocked = true")

func test_obstacle_blocking_occupancy_only() -> void:
	var obs := ObstacleData.new()
	obs.blocks_movement  = false
	obs.blocks_occupancy = true
	_state.set_obstacle(0, 0, obs)
	assert_true(_state.is_cell_blocked(0, 0), "obstacle bloquant occupation → is_cell_blocked = true")

func test_obstacle_blocking_nothing_not_blocked() -> void:
	var obs := ObstacleData.new()
	obs.blocks_movement  = false
	obs.blocks_occupancy = false
	_state.set_obstacle(0, 0, obs)
	assert_false(_state.is_cell_blocked(0, 0), "obstacle sans blocage → is_cell_blocked = false")

# ── Tests destruction d'obstacles (issue #74) ─────────────────────────
func test_destructible_obstacle_is_blocked_before_destruction() -> void:
	_state.set_obstacle(1, 1, ObstacleData.make_destructible_wall(30))
	assert_true(_state.is_cell_blocked(1, 1), "obstacle destructible bloque avant destruction")

func test_is_obstacle_destructible_true() -> void:
	_state.set_obstacle(1, 1, ObstacleData.make_destructible_wall(30))
	assert_true(_state.is_obstacle_destructible(1, 1), "obstacle destructible reconnu")

func test_is_obstacle_destructible_false_for_wall() -> void:
	_state.set_obstacle(1, 1, ObstacleData.make_wall())
	assert_false(_state.is_obstacle_destructible(1, 1), "mur indestructible non destructible")

func test_is_obstacle_destructible_false_without_obstacle() -> void:
	assert_false(_state.is_obstacle_destructible(0, 0), "pas d'obstacle = pas destructible")

func test_is_obstacle_destroyed_false_before_damage() -> void:
	_state.set_obstacle(2, 2, ObstacleData.make_destructible_wall(30))
	assert_false(_state.is_obstacle_destroyed(2, 2), "obstacle pas détruit avant dégâts")

func test_is_obstacle_destroyed_false_without_obstacle() -> void:
	assert_false(_state.is_obstacle_destroyed(0, 0), "pas d'obstacle = pas détruit")

func test_damage_obstacle_reduces_hp() -> void:
	_state.set_obstacle(2, 2, ObstacleData.make_destructible_wall(30))
	_state.damage_obstacle(2, 2, 10)
	assert_eq(_state.get_obstacle(2, 2).hp, 20, "hp réduit à 20 après 10 dégâts")
	assert_true(_state.is_cell_blocked(2, 2), "encore bloqué à 20 hp")
	assert_false(_state.is_obstacle_destroyed(2, 2), "pas encore détruit")

func test_damage_obstacle_destroys_at_zero_hp() -> void:
	_state.set_obstacle(3, 3, ObstacleData.make_destructible_wall(30))
	_state.damage_obstacle(3, 3, 30)
	assert_false(_state.is_cell_blocked(3, 3), "cellule non bloquée après destruction")
	assert_true(_state.is_obstacle_destroyed(3, 3), "obstacle marqué détruit")
	assert_true(_state.has_obstacle(3, 3), "obstacle toujours présent (état non bloquant)")

func test_damage_obstacle_overkill() -> void:
	_state.set_obstacle(0, 0, ObstacleData.make_destructible_wall(10))
	_state.damage_obstacle(0, 0, 999)
	assert_false(_state.is_cell_blocked(0, 0), "cellule non bloquée après overkill")
	assert_true(_state.is_obstacle_destroyed(0, 0), "obstacle détruit par overkill")
	assert_true(_state.get_obstacle(0, 0).hp <= 0, "hp négatif (overkill ok)")

func test_damage_obstacle_indestructible_ignored() -> void:
	_state.set_obstacle(1, 0, ObstacleData.make_wall())
	_state.damage_obstacle(1, 0, 1000)
	assert_true(_state.is_cell_blocked(1, 0), "mur indestructible reste bloqué")
	assert_false(_state.is_obstacle_destroyed(1, 0), "mur indestructible non détruit")

func test_damage_obstacle_no_obstacle_no_error() -> void:
	_state.damage_obstacle(0, 0, 10)
	assert_false(_state.has_obstacle(0, 0), "cellule vide reste vide après damage")

func test_partial_damage_keeps_blocking() -> void:
	_state.set_obstacle(4, 4, ObstacleData.make_destructible_wall(50))
	_state.damage_obstacle(4, 4, 25)
	assert_true(_state.is_cell_blocked(4, 4), "bloqué à mi-chemin")
	assert_false(_state.is_obstacle_destroyed(4, 4), "pas encore détruit")
