extends GutTest

# Tests de non-régression : ObstacleBehavior.resolve()
# Couvre : avancée directe libre (hors scope du résolveur), wait, sidestep_left/right/random,
#          priorité des comportements, cas limites (bord de grille, cellule occupée/bloquée),
#          liste vide, comportements réservés, déterminisme avec rng_seed.
# Couvre aussi : sélection pondérée (behavior_weights), build_weight_table,
#               select_from_weight_table, intégration MONSTER_DEFS.

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

# ── destroy_obstacle ─────────────────────────────────────────────

func test_destroy_obstacle_invalid_when_no_obstacle_in_path() -> void:
	# Aucun obstacle en row+1 → destroy_obstacle invalide → wait
	var result = ObstacleBehavior.resolve([ObstacleBehavior.DESTROY_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "wait", "aucun obstacle en row+1 → destroy_obstacle invalide → wait")

func test_destroy_obstacle_invalid_when_obstacle_indestructible() -> void:
	_state.set_obstacle(5, 2, ObstacleData.make_wall())
	var result = ObstacleBehavior.resolve([ObstacleBehavior.DESTROY_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "wait", "obstacle indestructible en row+1 → destroy_obstacle invalide → wait")

func test_destroy_obstacle_valid_when_destructible_obstacle_blocks() -> void:
	_state.set_obstacle(5, 2, ObstacleData.make_destructible_wall(10))
	var result = ObstacleBehavior.resolve([ObstacleBehavior.DESTROY_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "destroy_obstacle", "obstacle destructible en row+1 → action destroy_obstacle")
	assert_eq(result["row"],    5,                  "cible = row + 1")
	assert_eq(result["lane"],   2,                  "même lane")

func test_destroy_obstacle_invalid_at_last_row() -> void:
	# row 7 → row+1 = 8, hors grille → invalide
	_state.set_obstacle(7, 2, ObstacleData.make_destructible_wall(10))
	var result = ObstacleBehavior.resolve([ObstacleBehavior.DESTROY_OBSTACLE], 7, 2, _state)
	assert_eq(result["action"], "wait", "row+1 hors grille → destroy_obstacle invalide → wait")

func test_destroy_obstacle_in_weighted_selection_can_be_chosen() -> void:
	# Sidesteps bloqués + obstacle destructible → seul destroy_obstacle valide parmi les comportements de mouvement
	_state.set_cell_occupied(4, 1, "blocker")
	_state.set_cell_occupied(4, 3, "blocker")
	_state.set_obstacle(5, 2, ObstacleData.make_destructible_wall(10))
	var behaviors = [ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.DESTROY_OBSTACLE, ObstacleBehavior.WAIT]
	var weights = {
		ObstacleBehavior.SIDESTEP_LEFT:    40,
		ObstacleBehavior.SIDESTEP_RIGHT:   40,
		ObstacleBehavior.DESTROY_OBSTACLE: 20,
		ObstacleBehavior.WAIT:             0,
	}
	var result = ObstacleBehavior.resolve(behaviors, 4, 2, _state, 0, weights)
	assert_eq(result["action"], "destroy_obstacle",
		"sidesteps invalides + wait=0 + obstacle destructible → destroy_obstacle sélectionné")

func test_destroy_obstacle_not_chosen_when_weight_zero() -> void:
	_state.set_obstacle(5, 2, ObstacleData.make_destructible_wall(10))
	var behaviors = [ObstacleBehavior.DESTROY_OBSTACLE, ObstacleBehavior.WAIT]
	var weights = {ObstacleBehavior.DESTROY_OBSTACLE: 0, ObstacleBehavior.WAIT: 10}
	for seed in range(0, 20):
		var result = ObstacleBehavior.resolve(behaviors, 4, 2, _state, seed, weights)
		assert_eq(result["action"], "wait",
			"poids destroy_obstacle=0 → jamais sélectionné (seed=%d)" % seed)

func test_destroy_obstacle_integration_applies_damage() -> void:
	# Flux complet : resolve → damage_obstacle → obstacle endommagé
	_state.set_obstacle(5, 2, ObstacleData.make_destructible_wall(10))
	var result = ObstacleBehavior.resolve([ObstacleBehavior.DESTROY_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "destroy_obstacle")
	# Simule ce que game.gd fait : inflige 8 dégâts (valeur arbitraire de test)
	_state.damage_obstacle(result["row"], result["lane"], 8)
	var obs = _state.get_obstacle(5, 2)
	assert_eq(obs.hp, 2, "10 hp - 8 dégâts = 2 hp restants")
	assert_true(_state.is_cell_blocked(5, 2), "obstacle survivant reste bloquant")

func test_destroy_obstacle_integration_obstacle_destroyed_unblocks_cell() -> void:
	# Flux complet : obstacle destructible → dégâts fatals → cellule débloquée
	_state.set_obstacle(5, 2, ObstacleData.make_destructible_wall(5))
	_state.damage_obstacle(5, 2, 10)  # overkill
	assert_true(_state.is_obstacle_destroyed(5, 2),  "obstacle détruit après overkill")
	assert_false(_state.is_cell_blocked(5, 2),       "cellule débloquée après destruction")
	assert_true(_state.has_obstacle(5, 2),           "obstacle toujours présent en grille (has_obstacle = true)")

# ── jump_obstacle : initiation ────────────────────────────────────

func test_jump_start_returned_when_target_in_bounds() -> void:
	# row 4 → cible row 6 (dans la grille GRID_ROWS=8)
	var result = ObstacleBehavior.resolve([ObstacleBehavior.JUMP_OBSTACLE], 4, 2, _state)
	assert_eq(result["action"], "jump_start", "jump_obstacle disponible → jump_start")
	assert_eq(result["row"],    6,            "cible = row + 2")
	assert_eq(result["lane"],   2,            "même lane (saut vertical)")

func test_jump_not_started_when_target_out_of_bounds() -> void:
	# row 6 → cible row 8 hors grille (GRID_ROWS=8) → tombe sur wait
	var result = ObstacleBehavior.resolve([ObstacleBehavior.JUMP_OBSTACLE], 6, 2, _state)
	assert_eq(result["action"], "wait", "row 6 → cible row 8 hors grille → wait")

func test_jump_then_wait_fallback_on_last_valid_row() -> void:
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.JUMP_OBSTACLE, ObstacleBehavior.WAIT], 6, 2, _state)
	assert_eq(result["action"], "wait", "jump hors grille + wait en fallback → wait")

# ── jump_obstacle : cycle de vie complet ─────────────────────────

func test_jump_ticks_progress_correctly() -> void:
	var m = Monster.new()
	m.start_jump(6, 2)
	assert_eq(m.jump_ticks_remaining, 2, "saut initié : 2 move periods restants")
	m.tick_jump()
	assert_eq(m.jump_ticks_remaining, 1, "après tick 1 : 1 move period restant")
	m.tick_jump()
	assert_eq(m.jump_ticks_remaining, 0, "après tick 2 : résolution (3 move periods consommées)")
	m.free()

func test_is_jumping_flag() -> void:
	var m = Monster.new()
	assert_false(m.is_jumping(), "par défaut : pas en saut")
	m.start_jump(6, 2)
	assert_true(m.is_jumping(), "après start_jump : en saut")
	m.tick_jump()
	assert_true(m.is_jumping(), "après tick 1 : toujours en saut")
	m.tick_jump()
	assert_false(m.is_jumping(), "après tick 2 : résolution — plus en saut")
	m.free()

func test_jump_validate_landing_free_cell() -> void:
	assert_true(ObstacleBehavior.validate_jump_landing(6, 2, _state),
		"cellule libre → atterrissage valide")

func test_jump_validate_landing_blocked_by_obstacle() -> void:
	_state.set_obstacle(6, 2, ObstacleData.make_wall())
	assert_false(ObstacleBehavior.validate_jump_landing(6, 2, _state),
		"cellule avec obstacle → atterrissage invalide")

func test_jump_validate_landing_occupied_by_monster() -> void:
	_state.set_cell_occupied(6, 2, "blocker")
	assert_false(ObstacleBehavior.validate_jump_landing(6, 2, _state),
		"cellule occupée → atterrissage invalide")

func test_jump_validate_landing_out_of_bounds() -> void:
	assert_false(ObstacleBehavior.validate_jump_landing(8, 2, _state),
		"cellule hors grille → atterrissage invalide")

func test_jump_cost_consumed_even_on_failure() -> void:
	# Même si la cellule d'arrivée est bloquée, le coût temporel est entièrement consommé
	_state.set_obstacle(6, 2, ObstacleData.make_wall())
	var m = Monster.new()
	m.start_jump(6, 2)
	m.tick_jump()
	m.tick_jump()
	assert_eq(m.jump_ticks_remaining, 0,
		"coût temporel consommé même si l'atterrissage final échoue")
	m.free()

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
	assert_true(behaviors.has(ObstacleBehavior.SIDESTEP_LEFT),    "gobelin bleu : sidestep_left autorisé")
	assert_true(behaviors.has(ObstacleBehavior.SIDESTEP_RIGHT),   "gobelin bleu : sidestep_right autorisé")
	assert_true(behaviors.has(ObstacleBehavior.DESTROY_OBSTACLE), "gobelin bleu : destroy_obstacle autorisé")
	assert_true(behaviors.has(ObstacleBehavior.WAIT),             "gobelin bleu : wait en fallback")

func test_red_goblin_uses_random_sidestep_jump_and_destroy() -> void:
	var behaviors = GameData.MONSTER_DEFS["r"]["obstacle_behaviors"]
	assert_true(behaviors.has(ObstacleBehavior.SIDESTEP_RANDOM),  "gobelin rouge : sidestep_random autorisé")
	assert_true(behaviors.has(ObstacleBehavior.JUMP_OBSTACLE),    "gobelin rouge : jump_obstacle autorisé")
	assert_true(behaviors.has(ObstacleBehavior.DESTROY_OBSTACLE), "gobelin rouge : destroy_obstacle autorisé")
	assert_true(behaviors.has(ObstacleBehavior.WAIT),             "gobelin rouge : wait en fallback")

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

# ── sélection pondérée : resolve() avec weights ───────────────────

func test_weighted_empty_weights_keeps_ordered_priority() -> void:
	# Sans poids ({}), le mode ordonné est préservé : premier valide gagne
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.WAIT], 4, 2, _state, 0, {})
	assert_eq(result["action"], "move", "weights vide → mode ordonné → sidestep_left gagne")
	assert_eq(result["lane"], 1, "sidestep_left → lane 1")

func test_weighted_single_valid_deterministic_regardless_of_weights() -> void:
	# Gauche bloquée → seul wait valide ; malgré poids élevé sur sidestep_left
	_state.set_cell_occupied(4, 1, "blocker")
	var weights = {ObstacleBehavior.SIDESTEP_LEFT: 9999, ObstacleBehavior.WAIT: 1}
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.WAIT], 4, 2, _state, 0, weights)
	assert_eq(result["action"], "wait", "seul comportement valide → déterministe, pas de tirage")

func test_weighted_invalid_behavior_excluded_from_draw() -> void:
	# sidestep_left bloqué → exclu même avec poids maximal ; seul wait peut sortir
	_state.set_cell_occupied(4, 1, "blocker")
	var weights = {ObstacleBehavior.SIDESTEP_LEFT: 9999, ObstacleBehavior.WAIT: 1}
	for seed in [0, 1, 7, 13, 22, 39, 100, 999]:
		var result = ObstacleBehavior.resolve(
			[ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.WAIT], 4, 2, _state, seed, weights)
		assert_eq(result["action"], "wait",
			"comportement invalide jamais sélectionné (seed=%d)" % seed)

func test_weighted_result_always_within_valid_set() -> void:
	# Les deux directions libres → seules lane 1 et lane 3 peuvent sortir, jamais wait
	var behaviors = [ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.WAIT]
	var weights = {
		ObstacleBehavior.SIDESTEP_LEFT:  50,
		ObstacleBehavior.SIDESTEP_RIGHT: 50,
		ObstacleBehavior.WAIT:           0,
	}
	for seed in range(0, 30):
		var result = ObstacleBehavior.resolve(behaviors, 4, 2, _state, seed, weights)
		assert_eq(result["action"], "move", "poids wait=0 → jamais wait (seed=%d)" % seed)
		assert_true(result["lane"] == 1 or result["lane"] == 3,
			"lane = 1 ou 3 uniquement (seed=%d)" % seed)

func test_weighted_missing_weight_defaults_to_1() -> void:
	# WAIT n'a pas de clé dans weights → poids par défaut = 1
	# sidestep_left bloqué → seul wait reste valid
	_state.set_cell_occupied(4, 1, "blocker")
	var weights = {ObstacleBehavior.SIDESTEP_LEFT: 10}  # WAIT absent → défaut 1
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.WAIT], 4, 2, _state, 0, weights)
	assert_eq(result["action"], "wait", "poids manquant → défaut 1 → wait valide en fallback")

func test_weighted_deterministic_same_inputs() -> void:
	var behaviors = [ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.WAIT]
	var weights = {ObstacleBehavior.SIDESTEP_LEFT: 40, ObstacleBehavior.SIDESTEP_RIGHT: 40, ObstacleBehavior.WAIT: 20}
	var r1 = ObstacleBehavior.resolve(behaviors, 4, 2, _state, 17, weights)
	var r2 = ObstacleBehavior.resolve(behaviors, 4, 2, _state, 17, weights)
	assert_eq(r1["action"], r2["action"], "tirage pondéré déterministe : même seed → même action")
	if r1.has("lane"):
		assert_eq(r1["lane"], r2["lane"], "tirage pondéré déterministe : même seed → même lane")

func test_weighted_direct_advance_not_in_scope_of_resolve() -> void:
	# resolve() n'est appelé que quand l'avancée directe est impossible.
	# Vérification de cohérence : avec un seul comportement valide (wait), result = wait.
	var weights = {ObstacleBehavior.WAIT: 100}
	var result = ObstacleBehavior.resolve([ObstacleBehavior.WAIT], 4, 2, _state, 0, weights)
	assert_eq(result["action"], "wait", "avancée directe hors scope → resolve retourne wait correct")

# ── build_weight_table ────────────────────────────────────────────

func test_build_weight_table_correct_cumulative() -> void:
	var entries = [
		{"behavior": ObstacleBehavior.WAIT, "result": {"action": "wait"}},
		{"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}},
	]
	var weights = {ObstacleBehavior.WAIT: 20, ObstacleBehavior.SIDESTEP_LEFT: 30}
	var table = ObstacleBehavior.build_weight_table(entries, weights)
	assert_eq(table.size(), 2, "table a 2 entrées")
	assert_eq(table[0]["cumulative"], 20, "premier seuil cumulé = 20")
	assert_eq(table[1]["cumulative"], 50, "second seuil cumulé = 50")

func test_build_weight_table_missing_key_defaults_to_1() -> void:
	var entries = [
		{"behavior": ObstacleBehavior.WAIT, "result": {"action": "wait"}},
		{"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}},
	]
	var table = ObstacleBehavior.build_weight_table(entries, {})
	assert_eq(table[0]["cumulative"], 1, "poids manquant → défaut 1, cumulé 1")
	assert_eq(table[1]["cumulative"], 2, "second poids manquant → défaut 1, cumulé 2")

func test_build_weight_table_negative_weight_treated_as_0() -> void:
	var entries = [
		{"behavior": ObstacleBehavior.WAIT, "result": {"action": "wait"}},
		{"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}},
	]
	var weights = {ObstacleBehavior.WAIT: -5, ObstacleBehavior.SIDESTEP_LEFT: 10}
	var table = ObstacleBehavior.build_weight_table(entries, weights)
	assert_eq(table[0]["cumulative"], 0, "poids négatif → traité comme 0, cumulé 0")
	assert_eq(table[1]["cumulative"], 10, "second poids normal, cumulé 10")

# ── select_from_weight_table ──────────────────────────────────────

func test_select_from_table_pick_first_bucket() -> void:
	var wait_entry   = {"behavior": ObstacleBehavior.WAIT,          "result": {"action": "wait"}}
	var move_entry   = {"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}}
	var table = [
		{"cumulative": 20, "entry": wait_entry},
		{"cumulative": 50, "entry": move_entry},
	]
	# seed=0, total=50, pick=0%50=0. 0 < 20 → wait
	var selected = ObstacleBehavior.select_from_weight_table(table, 0)
	assert_eq(selected["behavior"], ObstacleBehavior.WAIT, "pick=0 < seuil 20 → wait sélectionné")

func test_select_from_table_pick_second_bucket() -> void:
	var wait_entry   = {"behavior": ObstacleBehavior.WAIT,          "result": {"action": "wait"}}
	var move_entry   = {"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}}
	var table = [
		{"cumulative": 20, "entry": wait_entry},
		{"cumulative": 50, "entry": move_entry},
	]
	# seed=25, total=50, pick=25%50=25. 25 >= 20, 25 < 50 → move
	var selected = ObstacleBehavior.select_from_weight_table(table, 25)
	assert_eq(selected["behavior"], ObstacleBehavior.SIDESTEP_LEFT, "pick=25 dans [20,50[ → sidestep_left")

func test_select_from_table_deterministic() -> void:
	var wait_entry = {"behavior": ObstacleBehavior.WAIT, "result": {"action": "wait"}}
	var move_entry = {"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}}
	var table = [{"cumulative": 20, "entry": wait_entry}, {"cumulative": 50, "entry": move_entry}]
	var s1 = ObstacleBehavior.select_from_weight_table(table, 7)
	var s2 = ObstacleBehavior.select_from_weight_table(table, 7)
	assert_eq(s1["behavior"], s2["behavior"], "même seed → même résultat (déterministe)")

func test_select_from_table_all_zero_weights_returns_first() -> void:
	var wait_entry = {"behavior": ObstacleBehavior.WAIT, "result": {"action": "wait"}}
	var move_entry = {"behavior": ObstacleBehavior.SIDESTEP_LEFT, "result": {"action": "move", "row": 4, "lane": 1}}
	var table = [{"cumulative": 0, "entry": wait_entry}, {"cumulative": 0, "entry": move_entry}]
	var selected = ObstacleBehavior.select_from_weight_table(table, 42)
	assert_eq(selected["behavior"], ObstacleBehavior.WAIT, "tous poids nuls → fallback = première entrée")

# ── intégration MONSTER_DEFS : behavior_weights ───────────────────

func test_all_monster_defs_have_behavior_weights_field() -> void:
	for monster_id in GameData.MONSTER_DEFS:
		var def = GameData.MONSTER_DEFS[monster_id]
		assert_true(def.has("behavior_weights"),
			"MONSTER_DEFS['%s'] doit avoir le champ behavior_weights" % monster_id)
		assert_true(def["behavior_weights"] is Dictionary,
			"behavior_weights de '%s' doit être un Dictionary" % monster_id)

func test_single_behavior_monsters_have_empty_weights() -> void:
	# Monstres avec un seul comportement → dict vide (mode ordonné trivial)
	for monster_id in ["g", "boss_g", "boss_b", "boss_r"]:
		var weights = GameData.MONSTER_DEFS[monster_id]["behavior_weights"]
		assert_true(weights.is_empty(),
			"'%s' (1 comportement) → behavior_weights vide" % monster_id)

func test_blue_goblin_weights_cover_all_behaviors() -> void:
	var behaviors = GameData.MONSTER_DEFS["b"]["obstacle_behaviors"]
	var weights   = GameData.MONSTER_DEFS["b"]["behavior_weights"]
	for b in behaviors:
		assert_true(weights.has(b),
			"gobelin bleu : poids défini pour comportement '%s'" % b)

func test_red_goblin_weights_cover_all_behaviors() -> void:
	var behaviors = GameData.MONSTER_DEFS["r"]["obstacle_behaviors"]
	var weights   = GameData.MONSTER_DEFS["r"]["behavior_weights"]
	for b in behaviors:
		assert_true(weights.has(b),
			"gobelin rouge : poids défini pour comportement '%s'" % b)

func test_blue_goblin_weights_favor_movement_over_wait() -> void:
	var weights = GameData.MONSTER_DEFS["b"]["behavior_weights"]
	var move_w = weights.get(ObstacleBehavior.SIDESTEP_LEFT, 0) + weights.get(ObstacleBehavior.SIDESTEP_RIGHT, 0)
	var wait_w = weights.get(ObstacleBehavior.WAIT, 0)
	assert_true(move_w > wait_w,
		"gobelin bleu : poids total mouvement > poids attente (profil rusé)")

func test_red_goblin_weights_favor_movement_over_wait() -> void:
	var weights = GameData.MONSTER_DEFS["r"]["behavior_weights"]
	var move_w = weights.get(ObstacleBehavior.SIDESTEP_RANDOM, 0) + weights.get(ObstacleBehavior.JUMP_OBSTACLE, 0)
	var wait_w = weights.get(ObstacleBehavior.WAIT, 0)
	assert_true(move_w > wait_w,
		"gobelin rouge : poids total mouvement > poids attente (profil agressif)")

func test_all_weights_are_non_negative() -> void:
	for monster_id in GameData.MONSTER_DEFS:
		var weights = GameData.MONSTER_DEFS[monster_id]["behavior_weights"]
		for behavior_id in weights:
			assert_true(weights[behavior_id] >= 0,
				"MONSTER_DEFS['%s']['%s'] : poids doit être >= 0" % [monster_id, behavior_id])

# ── cas limites non couverts précédemment ─────────────────────────

func test_build_weight_table_empty_entries_returns_empty() -> void:
	var table = ObstacleBehavior.build_weight_table([], {})
	assert_eq(table.size(), 0, "entrées vides → table vide")

func test_select_from_weight_table_empty_table_returns_empty_dict() -> void:
	var selected = ObstacleBehavior.select_from_weight_table([], 0)
	assert_eq(selected.size(), 0, "table vide → dictionnaire vide (pas de crash)")

func test_weighted_no_wait_all_invalid_returns_wait() -> void:
	# Seul comportement = sidestep_left, bloqué, pas de WAIT dans la liste
	# → _collect_valid vide → resolve retourne wait par défaut
	_state.set_cell_occupied(4, 1, "blocker")
	var weights = {ObstacleBehavior.SIDESTEP_LEFT: 99}
	var result = ObstacleBehavior.resolve(
		[ObstacleBehavior.SIDESTEP_LEFT], 4, 2, _state, 0, weights)
	assert_eq(result["action"], "wait",
		"mode pondéré, tous invalides, pas de WAIT → wait par défaut")

func test_weighted_jump_only_valid_returns_jump_start() -> void:
	# Les deux sidestep bloqués, seul jump_obstacle valide (row 4 → target 6)
	_state.set_cell_occupied(4, 1, "blocker")
	_state.set_cell_occupied(4, 3, "blocker")
	var behaviors = [ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.JUMP_OBSTACLE]
	var weights = {
		ObstacleBehavior.SIDESTEP_LEFT:  40,
		ObstacleBehavior.SIDESTEP_RIGHT: 40,
		ObstacleBehavior.JUMP_OBSTACLE:  20,
	}
	var result = ObstacleBehavior.resolve(behaviors, 4, 2, _state, 0, weights)
	assert_eq(result["action"], "jump_start",
		"seul jump_obstacle valide en mode pondéré → jump_start")
	assert_eq(result["row"],  6, "cible = row + 2")
	assert_eq(result["lane"], 2, "même lane")

func test_weighted_result_never_invalid_action_with_jump_in_mix() -> void:
	# jump_obstacle + sidestep_left disponibles → résultat toujours move ou jump_start
	var behaviors = [ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.JUMP_OBSTACLE]
	var weights = {ObstacleBehavior.SIDESTEP_LEFT: 50, ObstacleBehavior.JUMP_OBSTACLE: 50}
	var valid_actions = ["move", "jump_start"]
	for seed in range(0, 20):
		var result = ObstacleBehavior.resolve(behaviors, 4, 2, _state, seed, weights)
		assert_true(result["action"] in valid_actions,
			"action = move ou jump_start uniquement (seed=%d)" % seed)
