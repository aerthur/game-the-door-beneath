class_name BoardState
extends RefCounted
# Source de vérité unique pour l'occupation de la grille 5×8.
# Un seul occupant principal par cellule (Node2D ou null).
# Conçu pour ne pas bloquer une évolution future vers plusieurs entités par cellule.

var _cells: Array = []

func clear_all() -> void:
	_cells.clear()
	for _r in BoardGeometry.GRID_ROWS:
		var row = []
		for _l in BoardGeometry.GRID_COLUMNS:
			row.append(null)
		_cells.append(row)

func is_cell_free(row: int, col: int) -> bool:
	return _cells[row][col] == null

func is_cell_occupied(row: int, col: int) -> bool:
	return _cells[row][col] != null

func set_cell_occupied(row: int, col: int, occupant) -> void:
	_cells[row][col] = occupant

func clear_cell(row: int, col: int) -> void:
	_cells[row][col] = null

func get_cell_occupant(row: int, col: int):
	return _cells[row][col]

func is_grid_empty() -> bool:
	for r in BoardGeometry.GRID_ROWS:
		for l in BoardGeometry.GRID_COLUMNS:
			if _cells[r][l] != null:
				return false
	return true
