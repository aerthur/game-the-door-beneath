extends GutTest
# Tests unitaires pour BoardGeometry (géométrie canonique de la grille 5×8).
# Template de référence pour les futurs tests GUT du projet.

# ── Constantes ─────────────────────────────────────────────────────────────────

func test_grid_has_five_columns() -> void:
	assert_eq(BoardGeometry.GRID_COLUMNS, 5)

func test_grid_has_eight_rows() -> void:
	assert_eq(BoardGeometry.GRID_ROWS, 8)

func test_cell_width_is_180() -> void:
	assert_eq(BoardGeometry.CELL_WIDTH, 180)

func test_cell_height_is_68() -> void:
	assert_eq(BoardGeometry.CELL_HEIGHT, 68)

func test_grid_origin_x_is_centered() -> void:
	# (1280 - 5×180) / 2 = 140
	assert_eq(BoardGeometry.GRID_ORIGIN_X, 140)

func test_grid_origin_y_is_30() -> void:
	assert_eq(BoardGeometry.GRID_ORIGIN_Y, 30)

func test_player_y_is_below_grid() -> void:
	# 30 + 8×68 + 24 = 598
	assert_eq(BoardGeometry.PLAYER_Y, 598)

# ── get_cell_center ─────────────────────────────────────────────────────────────

func test_cell_center_origin_x() -> void:
	var center: Vector2 = BoardGeometry.get_cell_center(0, 0)
	# GRID_ORIGIN_X + 0×CELL_WIDTH + CELL_WIDTH/2 = 140 + 90 = 230
	assert_eq(center.x, 230.0)

func test_cell_center_origin_y() -> void:
	var center: Vector2 = BoardGeometry.get_cell_center(0, 0)
	# GRID_ORIGIN_Y + 0×CELL_HEIGHT + CELL_HEIGHT/2 = 30 + 34 = 64
	assert_eq(center.y, 64.0)

func test_cell_center_col_offset() -> void:
	var c0: Vector2 = BoardGeometry.get_cell_center(0, 0)
	var c1: Vector2 = BoardGeometry.get_cell_center(0, 1)
	assert_eq(c1.x - c0.x, float(BoardGeometry.CELL_WIDTH))

func test_cell_center_row_offset() -> void:
	var r0: Vector2 = BoardGeometry.get_cell_center(0, 0)
	var r1: Vector2 = BoardGeometry.get_cell_center(1, 0)
	assert_eq(r1.y - r0.y, float(BoardGeometry.CELL_HEIGHT))

func test_cell_to_world_matches_get_cell_center() -> void:
	for row in range(BoardGeometry.GRID_ROWS):
		for col in range(BoardGeometry.GRID_COLUMNS):
			assert_eq(
				BoardGeometry.cell_to_world(row, col),
				BoardGeometry.get_cell_center(row, col)
			)

# ── is_valid_cell ───────────────────────────────────────────────────────────────

func test_valid_cell_top_left() -> void:
	assert_true(BoardGeometry.is_valid_cell(0, 0))

func test_valid_cell_bottom_right() -> void:
	assert_true(BoardGeometry.is_valid_cell(7, 4))

func test_valid_cell_center() -> void:
	assert_true(BoardGeometry.is_valid_cell(3, 2))

func test_invalid_cell_negative_row() -> void:
	assert_false(BoardGeometry.is_valid_cell(-1, 0))

func test_invalid_cell_negative_col() -> void:
	assert_false(BoardGeometry.is_valid_cell(0, -1))

func test_invalid_cell_row_overflow() -> void:
	assert_false(BoardGeometry.is_valid_cell(8, 0))

func test_invalid_cell_col_overflow() -> void:
	assert_false(BoardGeometry.is_valid_cell(0, 5))

# ── world_to_cell ───────────────────────────────────────────────────────────────

func test_world_to_cell_roundtrip_origin() -> void:
	var center: Vector2 = BoardGeometry.get_cell_center(0, 0)
	var cell: Vector2i = BoardGeometry.world_to_cell(center)
	assert_eq(cell.x, 0)
	assert_eq(cell.y, 0)

func test_world_to_cell_roundtrip_center() -> void:
	var center: Vector2 = BoardGeometry.get_cell_center(3, 2)
	var cell: Vector2i = BoardGeometry.world_to_cell(center)
	assert_eq(cell.x, 3)
	assert_eq(cell.y, 2)

func test_world_to_cell_roundtrip_bottom_right() -> void:
	var center: Vector2 = BoardGeometry.get_cell_center(7, 4)
	var cell: Vector2i = BoardGeometry.world_to_cell(center)
	assert_eq(cell.x, 7)
	assert_eq(cell.y, 4)
