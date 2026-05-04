class_name BoardGeometry

# ── Géométrie canonique de la grille 5×8 ─────────────────────────
const GRID_COLUMNS  = 5
const GRID_ROWS     = 8
const CELL_WIDTH    = 180
const CELL_HEIGHT   = 56
const GRID_ORIGIN_X = (1280 - GRID_COLUMNS * CELL_WIDTH) / 2   # 140
const GRID_ORIGIN_Y = 115
const PLAYER_Y      = GRID_ORIGIN_Y + GRID_ROWS * CELL_HEIGHT + 40  # 603

# ── Helpers grille ↔ monde ────────────────────────────────────────

static func get_cell_center(row: int, col: int) -> Vector2:
	return Vector2(
		GRID_ORIGIN_X + col * CELL_WIDTH  + CELL_WIDTH  * 0.5,
		GRID_ORIGIN_Y + row * CELL_HEIGHT + CELL_HEIGHT * 0.5
	)

static func cell_to_world(row: int, col: int) -> Vector2:
	return get_cell_center(row, col)

static func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(
		int((pos.y - GRID_ORIGIN_Y) / CELL_HEIGHT),
		int((pos.x - GRID_ORIGIN_X) / CELL_WIDTH)
	)

static func is_valid_cell(row: int, col: int) -> bool:
	return row >= 0 and row < GRID_ROWS and col >= 0 and col < GRID_COLUMNS
