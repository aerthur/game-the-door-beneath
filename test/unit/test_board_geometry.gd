extends GutTest

# Template : tests unitaires pour BoardGeometry
# Nommage : test_<ce_qui_est_testé>
# Chaque test est une méthode publique préfixée "test_"

func test_grid_dimensions() -> void:
	assert_eq(BoardGeometry.GRID_COLUMNS, 5, "5 lanes")
	assert_eq(BoardGeometry.GRID_ROWS, 8, "8 rows")

func test_cell_center_origin() -> void:
	var center := BoardGeometry.get_cell_center(0, 0)
	var expected_x := BoardGeometry.GRID_ORIGIN_X + BoardGeometry.CELL_WIDTH / 2
	var expected_y := BoardGeometry.GRID_ORIGIN_Y + BoardGeometry.CELL_HEIGHT / 2
	assert_eq(center.x, float(expected_x), "cell (0,0) center x")
	assert_eq(center.y, float(expected_y), "cell (0,0) center y")

func test_is_valid_cell_boundaries() -> void:
	assert_true(BoardGeometry.is_valid_cell(0, 0), "coin haut-gauche valide")
	assert_true(BoardGeometry.is_valid_cell(7, 4), "coin bas-droit valide")
	assert_false(BoardGeometry.is_valid_cell(-1, 0), "row négative invalide")
	assert_false(BoardGeometry.is_valid_cell(0, -1), "col négative invalide")
	assert_false(BoardGeometry.is_valid_cell(8, 0), "row >= GRID_ROWS invalide")
	assert_false(BoardGeometry.is_valid_cell(0, 5), "col >= GRID_COLUMNS invalide")

func test_world_to_cell_round_trip() -> void:
	for row in range(BoardGeometry.GRID_ROWS):
		for col in range(BoardGeometry.GRID_COLUMNS):
			var world := BoardGeometry.get_cell_center(row, col)
			var cell := BoardGeometry.world_to_cell(world)
			assert_eq(cell.x, row, "round-trip row (%d,%d)" % [row, col])
			assert_eq(cell.y, col, "round-trip col (%d,%d)" % [row, col])
