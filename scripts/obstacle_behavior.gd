class_name ObstacleBehavior

# Identifiants de comportement d'obstacle (utilisés dans MONSTER_DEFS["obstacle_behaviors"])
const WAIT             = "wait"
const SIDESTEP_LEFT    = "sidestep_left"
const SIDESTEP_RIGHT   = "sidestep_right"
const SIDESTEP_RANDOM  = "sidestep_random"
const JUMP_OBSTACLE    = "jump_obstacle"
const DESTROY_OBSTACLE = "destroy_obstacle" # Réservé — requiert obstacle destructible actif

# Résout l'action à prendre quand la cellule cible directe est bloquée.
# L'avancée directe est supposée déjà vérifiée et échouée par l'appelant.
#
# Deux modes de sélection selon la valeur de weights :
#   - weights vide ({})   → sélection ordonnée : premier comportement valide retenu
#   - weights non vide    → tirage pondéré parmi les comportements valides
#
# Comportements sans clé dans weights → poids par défaut = 1.
#
# rng_seed : entier déterministe (ex: row * COLS + lane) pour sidestep_random et tirage pondéré.
#
# Retourne :
#   {"action": "wait"}                            — aucun mouvement ce tick
#   {"action": "move", "row": r, "lane": l}       — déplacement latéral
#   {"action": "jump_start", "row": r, "lane": l} — initiation de saut multi-ticks
static func resolve(
	behaviors: Array,
	row: int,
	lane: int,
	board_state: BoardState,
	rng_seed: int = 0,
	weights: Dictionary = {}
) -> Dictionary:
	if weights.is_empty():
		# Mode ordonné (backward-compatible) : premier comportement valide retenu
		return _resolve_ordered(behaviors, row, lane, board_state, rng_seed)

	# Mode pondéré : collecte des comportements valides puis tirage pondéré
	var valid = _collect_valid(behaviors, row, lane, board_state, rng_seed)
	if valid.is_empty():
		return {"action": "wait"}
	if valid.size() == 1:
		return valid[0]["result"]
	var table = build_weight_table(valid, weights)
	var selected = select_from_weight_table(table, rng_seed)
	return selected["result"]

# Construit la table de tirage pondéré depuis une liste de comportements valides.
# Chaque entrée de valid_entries doit avoir un champ "behavior" (String).
# Poids manquant dans weights → défaut 1. Poids négatif traité comme 0.
# Retourne Array de {cumulative: int, entry: Dictionary} trié par seuil croissant.
static func build_weight_table(valid_entries: Array, weights: Dictionary) -> Array:
	var table = []
	var cumulative = 0
	for entry in valid_entries:
		var w = max(0, weights.get(entry["behavior"], 1))
		cumulative += w
		table.append({"cumulative": cumulative, "entry": entry})
	return table

# Sélectionne une entrée dans une table pondérée de manière déterministe.
# Si total == 0 (tous poids nuls), retourne la première entrée en fallback.
static func select_from_weight_table(table: Array, rng_seed: int) -> Dictionary:
	if table.is_empty():
		return {}
	var total = table[-1]["cumulative"]
	if total <= 0:
		return table[0]["entry"]
	var pick = rng_seed % total
	for t in table:
		if pick < t["cumulative"]:
			return t["entry"]
	return table[-1]["entry"]

# Revalidation finale d'un atterrissage de saut.
# Appelée au tick de résolution (tick 3) : retourne true si le saut peut s'appliquer.
static func validate_jump_landing(row: int, lane: int, board_state: BoardState) -> bool:
	if not BoardGeometry.is_valid_cell(row, lane):
		return false
	return board_state.is_cell_free(row, lane) and not board_state.is_cell_blocked(row, lane)

# ── Implémentations privées ──────────────────────────────────────────

# Mode ordonné : itère behaviors dans l'ordre et retourne le premier résultat valide.
static func _resolve_ordered(
	behaviors: Array,
	row: int,
	lane: int,
	board_state: BoardState,
	rng_seed: int
) -> Dictionary:
	for b in behaviors:
		var result = _try_behavior(b, row, lane, board_state, rng_seed)
		if result != null:
			return result
	return {"action": "wait"}

# Collecte tous les comportements valides avec leur action pré-calculée.
static func _collect_valid(
	behaviors: Array,
	row: int,
	lane: int,
	board_state: BoardState,
	rng_seed: int
) -> Array:
	var valid = []
	for b in behaviors:
		var result = _try_behavior(b, row, lane, board_state, rng_seed)
		if result != null:
			valid.append({"behavior": b, "result": result})
	return valid

# Évalue un comportement et retourne son action si valide, null sinon.
static func _try_behavior(
	b: String,
	row: int,
	lane: int,
	board_state: BoardState,
	rng_seed: int
) -> Variant:
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
			var try_left_first = (rng_seed % 2 == 0)
			var dir_a = lane - 1 if try_left_first else lane + 1
			var dir_b = lane + 1 if try_left_first else lane - 1
			if _sidestep_valid(row, dir_a, board_state):
				return {"action": "move", "row": row, "lane": dir_a}
			if _sidestep_valid(row, dir_b, board_state):
				return {"action": "move", "row": row, "lane": dir_b}
		JUMP_OBSTACLE:
			var target_row = row + 2
			if target_row < BoardGeometry.GRID_ROWS:
				return {"action": "jump_start", "row": target_row, "lane": lane}
		# DESTROY_OBSTACLE : non implémenté, ignoré silencieusement
	return null

# Vérifie qu'une cellule latérale est dans les bornes, libre et non bloquée.
static func _sidestep_valid(row: int, lane: int, board_state: BoardState) -> bool:
	if lane < 0 or lane >= BoardGeometry.GRID_COLUMNS:
		return false
	return board_state.is_cell_free(row, lane) and not board_state.is_cell_blocked(row, lane)
