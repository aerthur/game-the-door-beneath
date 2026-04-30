extends GutTest
# Tests unitaires pour BoardState (occupation de la grille) et ObstacleData.

var state: BoardState

func before_each() -> void:
	state = BoardState.new()
	state.clear_all()

# ── État initial ────────────────────────────────────────────────────────────────

func test_fresh_state_is_empty() -> void:
	assert_true(state.is_grid_empty())

func test_all_cells_free_after_clear() -> void:
	for row in range(BoardGeometry.GRID_ROWS):
		for col in range(BoardGeometry.GRID_COLUMNS):
			assert_true(state.is_cell_free(row, col))

func test_no_obstacles_after_clear() -> void:
	for row in range(BoardGeometry.GRID_ROWS):
		for col in range(BoardGeometry.GRID_COLUMNS):
			assert_false(state.has_obstacle(row, col))

# ── Occupation des cellules ─────────────────────────────────────────────────────

func test_set_cell_occupied() -> void:
	var dummy := Node2D.new()
	state.set_cell_occupied(0, 0, dummy)
	assert_true(state.is_cell_occupied(0, 0))
	assert_false(state.is_cell_free(0, 0))
	dummy.free()

func test_get_cell_occupant_returns_node() -> void:
	var dummy := Node2D.new()
	state.set_cell_occupied(2, 3, dummy)
	assert_eq(state.get_cell_occupant(2, 3), dummy)
	dummy.free()

func test_get_cell_occupant_returns_null_when_free() -> void:
	assert_null(state.get_cell_occupant(0, 0))

func test_clear_cell_frees_it() -> void:
	var dummy := Node2D.new()
	state.set_cell_occupied(1, 1, dummy)
	state.clear_cell(1, 1)
	assert_true(state.is_cell_free(1, 1))
	assert_null(state.get_cell_occupant(1, 1))
	dummy.free()

func test_grid_not_empty_when_occupied() -> void:
	var dummy := Node2D.new()
	state.set_cell_occupied(4, 4, dummy)
	assert_false(state.is_grid_empty())
	dummy.free()

func test_grid_empty_after_clearing_occupant() -> void:
	var dummy := Node2D.new()
	state.set_cell_occupied(0, 0, dummy)
	state.clear_cell(0, 0)
	assert_true(state.is_grid_empty())
	dummy.free()

# ── ObstacleData.make_wall ──────────────────────────────────────────────────────

func test_make_wall_kind() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	assert_eq(wall.kind, "wall")

func test_make_wall_blocks_movement() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	assert_true(wall.blocks_movement)

func test_make_wall_blocks_occupancy() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	assert_true(wall.blocks_occupancy)

func test_make_wall_blocks_los() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	assert_true(wall.blocks_los)

func test_make_wall_is_indestructible() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	assert_eq(wall.destructibility, "indestructible")

func test_make_wall_hp_is_minus_one() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	assert_eq(wall.hp, -1)

# ── Gestion des obstacles dans BoardState ───────────────────────────────────────

func test_set_obstacle_marks_cell() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	state.set_obstacle(3, 2, wall)
	assert_true(state.has_obstacle(3, 2))

func test_get_obstacle_returns_data() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	state.set_obstacle(3, 2, wall)
	assert_eq(state.get_obstacle(3, 2), wall)

func test_is_cell_blocked_with_wall() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	state.set_obstacle(1, 1, wall)
	assert_true(state.is_cell_blocked(1, 1))

func test_is_cell_blocked_without_obstacle() -> void:
	assert_false(state.is_cell_blocked(0, 0))

func test_clear_obstacle_removes_it() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	state.set_obstacle(2, 2, wall)
	state.clear_obstacle(2, 2)
	assert_false(state.has_obstacle(2, 2))
	assert_false(state.is_cell_blocked(2, 2))

func test_clear_obstacles_removes_all() -> void:
	var wall: ObstacleData = ObstacleData.make_wall()
	state.set_obstacle(0, 0, wall)
	state.set_obstacle(7, 4, wall)
	state.clear_obstacles()
	assert_false(state.has_obstacle(0, 0))
	assert_false(state.has_obstacle(7, 4))

func test_obstacle_does_not_affect_occupancy_check() -> void:
	# is_cell_free vérifie les occupants, pas les obstacles
	var wall: ObstacleData = ObstacleData.make_wall()
	state.set_obstacle(0, 0, wall)
	assert_true(state.is_cell_free(0, 0))

func test_passable_obstacle_not_blocked() -> void:
	var passable := ObstacleData.new()
	passable.blocks_movement = false
	passable.blocks_occupancy = false
	state.set_obstacle(0, 0, passable)
	assert_false(state.is_cell_blocked(0, 0))
