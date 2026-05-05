class_name ObstacleBehavior

# Identifiants de comportement d'obstacle (utilisés dans MONSTER_DEFS["obstacle_behaviors"])
const WAIT             = "wait"
const SIDESTEP_LEFT    = "sidestep_left"
const SIDESTEP_RIGHT   = "sidestep_right"
const SIDESTEP_RANDOM  = "sidestep_random"
const JUMP_OBSTACLE    = "jump_obstacle"    # Réservé — logique multi-ticks à concevoir
const DESTROY_OBSTACLE = "destroy_obstacle" # Réservé — requiert obstacle destructible actif

# Résout l'action à prendre quand la cellule cible directe est bloquée.
# L'avancée directe est supposée déjà vérifiée et échouée par l'appelant.
#
# Retourne :
#   {"action": "wait"}                       — aucun mouvement ce tick
#   {"action": "move", "row": r, "lane": l}  — déplacement latéral (même rangée, lane adjacente)
#
# rng_seed : entier déterministe (ex: row * COLS + lane) pour sidestep_random.
# La sélection respecte l'ordre de la liste behaviors ; le premier comportement
# dont la cellule cible est valide est retenu.
static func resolve(
	behaviors: Array,
	row: int,
	lane: int,
	board_state: BoardState,
	rng_seed: int = 0
) -> Dictionary:
	for b in behaviors:
		match b:
			WAIT:
				return {"action": "wait"}
			SIDESTEP_LEFT:
				if _sidestep_valid(row, lane - 1, board_state):
					return {"action": "move", "row": row, "lane": lane - 1}
			SIDESTEP_RIGHT:
				if _sidestep_valid(row, lane + 1, board_state):
					return {"action": "move", "row": row, "lane": lane + 1}
			SIDESTEP_RANDOM:
				# Déterministe : parité de rng_seed décide de la direction prioritaire
				var try_left_first = (rng_seed % 2 == 0)
				var dir_a = lane - 1 if try_left_first else lane + 1
				var dir_b = lane + 1 if try_left_first else lane - 1
				if _sidestep_valid(row, dir_a, board_state):
					return {"action": "move", "row": row, "lane": dir_a}
				if _sidestep_valid(row, dir_b, board_state):
					return {"action": "move", "row": row, "lane": dir_b}
			JUMP_OBSTACLE:
				# Franchit la cellule bloquante (row+1) pour atterrir en row+2.
				# Ne réserve pas la cellule cible ; revalidation à la résolution finale.
				var target_row = row + 2
				if target_row < BoardGeometry.GRID_ROWS:
					return {"action": "jump_start", "row": target_row, "lane": lane}
			# DESTROY_OBSTACLE : non implémenté, passé silencieusement
	# Aucun comportement autorisé n'a produit un mouvement valide → attente
	return {"action": "wait"}

# Revalidation finale d'un atterrissage de saut.
# Appelée au tick de résolution (tick 3) : retourne true si le saut peut s'appliquer.
static func validate_jump_landing(row: int, lane: int, board_state: BoardState) -> bool:
	if not BoardGeometry.is_valid_cell(row, lane):
		return false
	return board_state.is_cell_free(row, lane) and not board_state.is_cell_blocked(row, lane)

# Vérifie qu'une cellule latérale est dans les bornes de la grille,
# libre d'occupant et non bloquée par obstacle.
static func _sidestep_valid(row: int, lane: int, board_state: BoardState) -> bool:
	if lane < 0 or lane >= BoardGeometry.GRID_COLUMNS:
		return false
	return board_state.is_cell_free(row, lane) and not board_state.is_cell_blocked(row, lane)
