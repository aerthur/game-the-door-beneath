extends GutTest

# Tests de non-régression : ObstacleBehavior.resolve()
# Couvre : avancée directe libre (hors scope du résolveur), wait, sidestep_left/right/random,
#          priorité des comportements, cas limites (bord de grille, cellule occupée/bloquée),
#          liste vide, comportements réservés, déterminisme avec rng_seed.

var _state: BoardState

func before_each() -> void:
	_state = BoardState.new()
	_state.clear_all()

# ── wait ─────────────────────────────────────────────────────────

func test_wait_returns_wait_action() -> void:
	var result = ObstacleBehavior.resolve([ObstacleBehavior.WAIT], 4, 2, _state)
	assert_eq(result["action"], "wait", "comportement wait → action wait")

func test_empty_behaviors_returns_wait() -> void:
	var result = ObstacleBehavior.resolve([], 4, 2, _state)
	assert_eq(result["action"], "wait", "liste vide → action wait par défaut")

# ── sidestep_left ─────────────────────────────────────────────────

func test_sidestep_left_free_returns_move_left() -> void:
	# Lane 2 → sidestep vers lane 1 (libre)
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_LEFT], 4, 2, _state)
	assert_eq(result["action"], "move",  "sidestep_left lane libre → action move")
	assert_eq(result["lane"],   1,       "cible = lane 1 (lane - 1)")
	assert_eq(result["row"],    4,       "même rangée (sidestep latéral)")

func test_sidestep_left_occupied_returns_wait() -> void:
	_state.set_cell_occupied(4, 1, "blocker")
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_LEFT], 4, 2, _state)
	assert_eq(result["action"], "wait", "lane gauche occupée → sidestep invalide → wait")

func test_sidestep_left_blocked_by_obstacle_returns_wait() -> void:
	_state.set_obstacle(4, 1, ObstacleData.make_wall())
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_LEFT], 4, 2, _state)
	assert_eq(result["action"], "wait", "lane gauche obstacle → sidestep invalide → wait")

func test_sidestep_left_at_lane0_returns_wait() -> void:
	# Impossible de se décaler davantage vers la gauche depuis lane 0
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_LEFT], 4, 0, _state)
	assert_eq(result["action"], "wait", "lane 0 → hors bornes gauche → wait")

# ── sidestep_right ────────────────────────────────────────────────

func test_sidestep_right_free_returns_move_right() -> void:
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RIGHT], 4, 2, _state)
	assert_eq(result["action"], "move",  "sidestep_right lane libre → action move")
	assert_eq(result["lane"],   3,       "cible = lane 3 (lane + 1)")
	assert_eq(result["row"],    4,       "même rangée (sidestep latéral)")

func test_sidestep_right_occupied_returns_wait() -> void:
	_state.set_cell_occupied(4, 3, "blocker")
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RIGHT], 4, 2, _state)
	assert_eq(result["action"], "wait", "lane droite occupée → sidestep invalide → wait")

func test_sidestep_right_at_last_lane_returns_wait() -> void:
	var last = BoardGeometry.GRID_COLUMNS - 1
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RIGHT], 4, last, _state)
	assert_eq(result["action"], "wait", "dernière lane → hors bornes droite → wait")

# ── sidestep_random ───────────────────────────────────────────────

func test_sidestep_random_seed0_tries_left_first() -> void:
	# seed 0 → parité paire → essaie gauche en premier
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 4, 2, _state, 0)
	assert_eq(result["action"], "move", "sidestep_random seed=0 → action move")
	assert_eq(result["lane"],   1,      "seed 0 (paire) → gauche prioritaire → lane 1")

func test_sidestep_random_seed1_tries_right_first() -> void:
	# seed 1 → parité impaire → essaie droite en premier
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 4, 2, _state, 1)
	assert_eq(result["action"], "move", "sidestep_random seed=1 → action move")
	assert_eq(result["lane"],   3,      "seed 1 (impaire) → droite prioritaire → lane 3")

func test_sidestep_random_first_dir_blocked_tries_other() -> void:
	# seed 0 → gauche en premier, mais gauche occupée → essaie droite
	_state.set_cell_occupied(4, 1, "blocker")
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 4, 2, _state, 0)
	assert_eq(result["action"], "move", "première direction bloquée → essaie l'autre")
	assert_eq(result["lane"],   3,      "gauche bloquée, seed 0 → droite en fallback → lane 3")

func test_sidestep_random_both_blocked_returns_wait() -> void:
	_state.set_cell_occupied(4, 1, "blocker")
	_state.set_cell_occupied(4, 3, "blocker")
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 4, 2, _state)
	assert_eq(result["action"], "wait", "les deux côtés bloqués → wait")

# ── priorité et ordre ────────────────────────────────────────────

func test_priority_sidestep_left_before_wait() -> void:
	# [sidestep_left, wait] avec gauche libre → doit sidestep, pas wait
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.WAIT], 4, 2, _state)
	assert_eq(result["action"], "move", "sidestep_left disponible avant wait → move prioritaire")
	assert_eq(result["lane"],   1,      "sidestep_left → lane 1")

func test_priority_sidestep_left_invalid_falls_to_wait() -> void:
	# [sidestep_left, wait] avec gauche occupée → wait
	_state.set_cell_occupied(4, 1, "blocker")
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.WAIT], 4, 2, _state)
	assert_eq(result["action"], "wait", "sidestep_left invalide → tombe sur wait")

func test_priority_sidestep_right_before_left_in_list() -> void:
	# [sidestep_right, sidestep_left] avec les deux libres → droite en premier
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.SIDESTEP_LEFT], 4, 2, _state)
	assert_eq(result["lane"], 3, "sidestep_right avant sidestep_left dans la liste → lane 3")

func test_priority_first_valid_wins() -> void:
	# [sidestep_right, sidestep_left] avec droite bloquée → gauche retournée
	_state.set_cell_occupied(4, 3, "blocker")
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.SIDESTEP_LEFT], 4, 2, _state)
	assert_eq(result["lane"], 1, "droite bloquée → premier valide = gauche → lane 1")

# ── comportements réservés (non implémentés) ─────────────────────

func test_jump_obstacle_placeholder_skipped() -> void:
	# jump_obstacle non implémenté → ignoré, tombe sur wait
	var result = ObstacleBehavior.resolve([ObstacleBehavior.JUMP_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "wait", "jump_obstacle (réservé) → ignoré → wait")

func test_destroy_obstacle_placeholder_skipped() -> void:
	var result = ObstacleBehavior.resolve([ObstacleBehavior.DESTROY_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "wait", "destroy_obstacle (réservé) → ignoré → wait")

func test_reserved_then_wait_falls_to_wait() -> void:
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.JUMP_OBSTACLE, ObstacleBehavior.WAIT], 4, 2, _state)
	assert_eq(result["action"], "wait", "réservé puis wait → action wait")

# ── déterminisme simulation 12 tps ───────────────────────────────

func test_same_inputs_always_same_output() -> void:
	# Le résolveur est pur (pas d'état global) → même entrée = même sortie
	var r1 = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 3, 2, _state, 42)
	var r2 = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 3, 2, _state, 42)
	assert_eq(r1["action"], r2["action"], "déterministe : mêmes entrées → même action")
	assert_eq(r1["lane"],   r2["lane"],   "déterministe : mêmes entrées → même lane")

func test_different_seeds_can_differ() -> void:
	# seed paire et impaire sur lane centrale → directions opposées
	var r_even = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 3, 2, _state, 0)
	var r_odd  = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RANDOM], 3, 2, _state, 1)
	assert_ne(r_even["lane"], r_odd["lane"],
		"seed paire vs impaire → directions opposées (gauche vs droite)")

# ── intégration avec MONSTER_DEFS ────────────────────────────────

func test_all_monster_defs_have_obstacle_behaviors() -> void:
	for monster_id in GameData.MONSTER_DEFS:
		var def = GameData.MONSTER_DEFS[monster_id]
		assert_true(def.has("obstacle_behaviors"),
			"MONSTER_DEFS['%s'] doit avoir le champ obstacle_behaviors" % monster_id)
		assert_true(def["obstacle_behaviors"] is Array,
			"obstacle_behaviors de '%s' doit être un Array" % monster_id)
		assert_true(def["obstacle_behaviors"].size() > 0,
			"obstacle_behaviors de '%s' ne doit pas être vide" % monster_id)

func test_green_goblin_only_waits() -> void:
	var behaviors = GameData.MONSTER_DEFS["g"]["obstacle_behaviors"]
	assert_eq(behaviors.size(), 1, "gobelin vert : un seul comportement")
	assert_eq(behaviors[0], ObstacleBehavior.WAIT, "gobelin vert : comportement = wait")

func test_blue_goblin_tries_sidestep() -> void:
	var behaviors = GameData.MONSTER_DEFS["b"]["obstacle_behaviors"]
	assert_true(behaviors.has(ObstacleBehavior.SIDESTEP_LEFT),  "gobelin bleu : sidestep_left autorisé")
	assert_true(behaviors.has(ObstacleBehavior.SIDESTEP_RIGHT), "gobelin bleu : sidestep_right autorisé")
	assert_true(behaviors.has(ObstacleBehavior.WAIT),           "gobelin bleu : wait en fallback")

func test_red_goblin_uses_random_sidestep() -> void:
	var behaviors = GameData.MONSTER_DEFS["r"]["obstacle_behaviors"]
	assert_true(behaviors.has(ObstacleBehavior.SIDESTEP_RANDOM), "gobelin rouge : sidestep_random autorisé")
	assert_true(behaviors.has(ObstacleBehavior.WAIT),            "gobelin rouge : wait en fallback")

func test_bosses_only_wait() -> void:
	for boss_id in ["boss_g", "boss_b", "boss_r"]:
		var behaviors = GameData.MONSTER_DEFS[boss_id]["obstacle_behaviors"]
		assert_eq(behaviors.size(), 1,
			"boss '%s' : un seul comportement" % boss_id)
		assert_eq(behaviors[0], ObstacleBehavior.WAIT,
			"boss '%s' : comportement = wait (tient sa lane)" % boss_id)

# ── cas limites grille ────────────────────────────────────────────

func test_sidestep_left_valid_from_lane1() -> void:
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_LEFT], 4, 1, _state)
	assert_eq(result["action"], "move", "lane 1 → sidestep_left vers lane 0 possible")
	assert_eq(result["lane"],   0,      "cible = lane 0")

func test_sidestep_right_valid_from_lane3() -> void:
	var last = BoardGeometry.GRID_COLUMNS - 1  # 4
	var result = ObstacleBehavior.resolve([ObstacleBehavior.SIDESTEP_RIGHT], 4, last - 1, _state)
	assert_eq(result["action"], "move",  "avant-dernière lane → sidestep_right vers dernière possible")
	assert_eq(result["lane"],   last,    "cible = dernière lane")
