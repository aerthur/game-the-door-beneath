class_name BoardState
extends RefCounted
# Source de vérité unique pour l'occupation de la grille 5×8.
# Un seul occupant principal par cellule (Node2D ou null).
# Conçu pour ne pas bloquer une évolution future vers plusieurs entités par cellule.
# Couche obstacles séparée : chaque cellule peut contenir un ObstacleData ou null.

var _cells:     Array = []
var _obstacles: Array = []

func clear_all() -> void:
	_cells.clear()
	_obstacles.clear()
	for _r in BoardGeometry.GRID_ROWS:
		var row_cells = []
		var row_obs   = []
		for _l in BoardGeometry.GRID_COLUMNS:
			row_cells.append(null)
			row_obs.append(null)
		_cells.append(row_cells)
		_obstacles.append(row_obs)

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

# ── API Obstacles ────────────────────────────────────────────────────
func has_obstacle(row: int, col: int) -> bool:
	return _obstacles[row][col] != null

func get_obstacle(row: int, col: int) -> ObstacleData:
	return _obstacles[row][col]

func set_obstacle(row: int, col: int, obstacle_data: ObstacleData) -> void:
	_obstacles[row][col] = obstacle_data

func clear_obstacle(row: int, col: int) -> void:
	_obstacles[row][col] = null

func clear_obstacles() -> void:
	for r in BoardGeometry.GRID_ROWS:
		for l in BoardGeometry.GRID_COLUMNS:
			_obstacles[r][l] = null

# Retourne true si la cellule porte un obstacle bloquant le mouvement/l'occupation.
func is_cell_blocked(row: int, col: int) -> bool:
	var obs: ObstacleData = _obstacles[row][col]
	if obs == null:
		return false
	return obs.blocks_movement or obs.blocks_occupancy

# ── API Destruction d'obstacles ──────────────────────────────────────
# Règle d'implémentation : un obstacle détruit reste en grille (has_obstacle = true)
# mais ses champs blocks_movement et blocks_occupancy sont mis à false.
# is_obstacle_destroyed() retourne true, is_cell_blocked() retourne false.
# Les obstacles indestructibles ignorent les dégâts.

func is_obstacle_destructible(row: int, col: int) -> bool:
	var obs: ObstacleData = _obstacles[row][col]
	if obs == null:
		return false
	return obs.destructibility == "destructible"

func is_obstacle_destroyed(row: int, col: int) -> bool:
	var obs: ObstacleData = _obstacles[row][col]
	if obs == null:
		return false
	return obs.destructibility == "destructible" and obs.hp <= 0

func damage_obstacle(row: int, col: int, amount: int) -> void:
	var obs: ObstacleData = _obstacles[row][col]
	if obs == null or obs.destructibility != "destructible":
		return
	obs.hp -= amount
	if obs.hp <= 0:
		obs.blocks_movement  = false
		obs.blocks_occupancy = false
