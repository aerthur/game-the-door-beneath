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

# ── Périmètre joueur ─────────────────────────────────────────────

# Distance en pixels entre le bord de la grille et le centre du joueur sur chaque côté.
const PLAYER_MARGIN = 40

# Y du joueur sur le bord bas (inchangé pour la compatibilité).
# PLAYER_Y = GRID_ORIGIN_Y + GRID_ROWS * CELL_HEIGHT + PLAYER_MARGIN = 603

# Retourne la position monde du joueur positionné sur le périmètre extérieur.
# side  : "bottom" | "top" | "left" | "right"
# index : colonne (bottom/top) ou rangée (left/right)
static func get_player_perimeter_pos(side: String, index: int) -> Vector2:
	match side:
		"bottom":
			return Vector2(GRID_ORIGIN_X + index * CELL_WIDTH + CELL_WIDTH * 0.5, PLAYER_Y)
		"top":
			return Vector2(GRID_ORIGIN_X + index * CELL_WIDTH + CELL_WIDTH * 0.5,
					GRID_ORIGIN_Y - PLAYER_MARGIN)
		"left":
			return Vector2(GRID_ORIGIN_X - PLAYER_MARGIN,
					GRID_ORIGIN_Y + index * CELL_HEIGHT + CELL_HEIGHT * 0.5)
		"right":
			return Vector2(GRID_ORIGIN_X + GRID_COLUMNS * CELL_WIDTH + PLAYER_MARGIN,
					GRID_ORIGIN_Y + index * CELL_HEIGHT + CELL_HEIGHT * 0.5)
	return Vector2.ZERO

# Retourne l'index maximum valide pour un côté donné.
static func get_perimeter_max_index(side: String) -> int:
	if side == "left" or side == "right":
		return GRID_ROWS - 1
	return GRID_COLUMNS - 1
