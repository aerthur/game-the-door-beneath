extends GutTest

# Tests : issue #109 — comportement de fin de file data-driven
# Couvre : EscapeBehavior.calc_return_hp (pur), get_spawn_type_at,
#          intégration MONSTER_DEFS (champ escape_behavior, cas vert/bleu/rouge/boss),
#          Monster.apply_initial_hp, compteurs monsters_remaining / spawns_in_flight.

# ── calc_return_hp : heal_mode "none" ────────────────────────────

func test_calc_return_hp_preserve_false_returns_full() -> void:
	var cfg := {"preserve_state": false, "heal_mode": "none", "heal_value": 0}
	var hp  := EscapeBehavior.calc_return_hp(10, 100, cfg)
	assert_eq(hp, 100, "preserve_state=false → repart pleine vie")

func test_calc_return_hp_preserve_true_none_keeps_current() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "none", "heal_value": 0}
	var hp  := EscapeBehavior.calc_return_hp(30, 100, cfg)
	assert_eq(hp, 30, "preserve_state=true + heal_mode=none → conserve HP courant")

func test_calc_return_hp_default_cfg_returns_full() -> void:
	# Pas de return_self dans la def → dict vide → comportement par défaut = pleine vie
	var hp := EscapeBehavior.calc_return_hp(20, 100, {})
	assert_eq(hp, 100, "cfg vide → preserve_state=false par défaut → pleine vie")

# ── calc_return_hp : heal_mode "flat" ────────────────────────────

func test_calc_return_hp_flat_heal_adds_value() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "flat", "heal_value": 30}
	var hp  := EscapeBehavior.calc_return_hp(40, 100, cfg)
	assert_eq(hp, 70, "HP 40 + heal flat 30 = 70")

func test_calc_return_hp_flat_heal_capped_at_max() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "flat", "heal_value": 80}
	var hp  := EscapeBehavior.calc_return_hp(60, 100, cfg)
	assert_eq(hp, 100, "60 + 80 dépasserait max → borné à 100")

func test_calc_return_hp_flat_heal_on_fresh_base() -> void:
	# preserve_state=false + flat → base = hp_max puis heal (superflu mais autorisé)
	var cfg := {"preserve_state": false, "heal_mode": "flat", "heal_value": 20}
	var hp  := EscapeBehavior.calc_return_hp(10, 100, cfg)
	assert_eq(hp, 100, "preserve_state=false → base 100, +20 → toujours borné à 100")

# ── calc_return_hp : heal_mode "percent_max" ─────────────────────

func test_calc_return_hp_percent_max_boss_case() -> void:
	# Boss : revient avec 30% de HP max (modèle boss existant)
	var cfg := {"preserve_state": true, "heal_mode": "percent_max", "heal_value": 0.3}
	var hp  := EscapeBehavior.calc_return_hp(100, 300, cfg)
	assert_eq(hp, 190, "100 + 30% de 300 = 190")

func test_calc_return_hp_percent_max_capped_at_max() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "percent_max", "heal_value": 0.9}
	var hp  := EscapeBehavior.calc_return_hp(80, 100, cfg)
	assert_eq(hp, 100, "80 + 90% de 100 = 170 → borné à 100")

func test_calc_return_hp_percent_max_zero_heal() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "percent_max", "heal_value": 0.0}
	var hp  := EscapeBehavior.calc_return_hp(55, 100, cfg)
	assert_eq(hp, 55, "heal_value=0 → aucun heal, conserve HP courant")

# ── calc_return_hp : heal_mode "full" ────────────────────────────

func test_calc_return_hp_full_explicit_restores_max() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "full", "heal_value": 0}
	var hp  := EscapeBehavior.calc_return_hp(1, 100, cfg)
	assert_eq(hp, 100, "heal_mode=full → toujours pleine vie, même avec preserve_state=true")

func test_calc_return_hp_full_only_if_explicitly_configured() -> void:
	# Sans "full" explicite, preserve_state=true conserve les blessures
	var cfg_no_full := {"preserve_state": true, "heal_mode": "none"}
	var hp          := EscapeBehavior.calc_return_hp(5, 100, cfg_no_full)
	assert_eq(hp, 5, "pleine vie uniquement si heal_mode=full explicitement configuré")

# ── calc_return_hp : cas limites ─────────────────────────────────

func test_calc_return_hp_never_zero() -> void:
	var cfg := {"preserve_state": true, "heal_mode": "none"}
	var hp  := EscapeBehavior.calc_return_hp(0, 100, cfg)
	assert_eq(hp, 1, "HP ne descend jamais en dessous de 1 (min=1 garanti)")

func test_calc_return_hp_never_exceeds_max() -> void:
	var cfg := {"preserve_state": false, "heal_mode": "full"}
	var hp  := EscapeBehavior.calc_return_hp(200, 100, cfg)
	assert_eq(hp, 100, "HP toujours borné à hp_max")

# ── get_spawn_type_at : règle de réutilisation de la dernière entrée ─

func test_get_spawn_type_at_index_within_range() -> void:
	var spawn_type := EscapeBehavior.get_spawn_type_at(["b", "r"], 0, "g")
	assert_eq(spawn_type, "b", "index 0 dans la liste → premier type")

func test_get_spawn_type_at_index_exceeds_list_reuses_last() -> void:
	var spawn_type := EscapeBehavior.get_spawn_type_at(["b"], 5, "g")
	assert_eq(spawn_type, "b", "index dépasse la liste → dernière entrée réutilisée")

func test_get_spawn_type_at_empty_list_returns_fallback() -> void:
	var spawn_type := EscapeBehavior.get_spawn_type_at([], 0, "r")
	assert_eq(spawn_type, "r", "liste vide → fallback (type du monstre sortant)")

func test_get_spawn_type_at_multi_types_ordered() -> void:
	var types := ["b", "r", "g"]
	assert_eq(EscapeBehavior.get_spawn_type_at(types, 0, "g"), "b", "index 0 → b")
	assert_eq(EscapeBehavior.get_spawn_type_at(types, 1, "g"), "r", "index 1 → r")
	assert_eq(EscapeBehavior.get_spawn_type_at(types, 2, "g"), "g", "index 2 → g")
	assert_eq(EscapeBehavior.get_spawn_type_at(types, 10, "g"), "g", "index 10 → dernière = g")

# ── Monster.apply_initial_hp ──────────────────────────────────────

func test_apply_initial_hp_sets_hp() -> void:
	var m := Monster.new()
	m.hp_max = 100
	m.hp     = 100
	m.apply_initial_hp(40)
	assert_eq(m.hp, 40, "apply_initial_hp(40) → hp = 40")
	m.free()

func test_apply_initial_hp_clamps_to_max() -> void:
	var m := Monster.new()
	m.hp_max = 100
	m.hp     = 100
	m.apply_initial_hp(999)
	assert_eq(m.hp, 100, "apply_initial_hp(999) → borné à hp_max=100")
	m.free()

func test_apply_initial_hp_minimum_is_1() -> void:
	var m := Monster.new()
	m.hp_max = 100
	m.hp     = 100
	m.apply_initial_hp(0)
	assert_eq(m.hp, 1, "apply_initial_hp(0) → borné à 1 minimum")
	m.free()

# ── Monster.monster_id et _def_snapshot ──────────────────────────

func test_setup_from_def_sets_monster_id() -> void:
	var m   := Monster.new()
	var def := GameData.MONSTER_DEFS["g"].duplicate()
	m.setup_from_def("g", def)
	assert_eq(m.monster_id, "g", "setup_from_def stocke le monster_id")
	m.free()

func test_setup_from_def_stores_def_snapshot() -> void:
	var m   := Monster.new()
	var def := GameData.MONSTER_DEFS["r"].duplicate()
	m.setup_from_def("r", def)
	assert_false(m._def_snapshot.is_empty(), "_def_snapshot non vide après setup")
	assert_eq(m._def_snapshot["hp"], def["hp"], "_def_snapshot contient le bon hp")
	m.free()

func test_setup_from_def_boss_stores_monster_id_as_boss_key() -> void:
	var m   := Monster.new()
	var def := GameData.MONSTER_DEFS["boss_g"].duplicate()
	m.setup_from_def("boss_g", def)
	assert_eq(m.monster_id, "boss_g", "boss : monster_id = 'boss_g' (pas 'g')")
	assert_eq(m.monster_type, "g",    "boss : monster_type = 'g' (type de base)")
	m.free()

# ── Intégration MONSTER_DEFS : champ escape_behavior ─────────────

func test_all_monster_defs_have_escape_behavior() -> void:
	for monster_id in GameData.MONSTER_DEFS:
		var def := GameData.MONSTER_DEFS[monster_id]
		assert_true(def.has("escape_behavior"),
			"MONSTER_DEFS['%s'] doit avoir le champ escape_behavior" % monster_id)

func test_all_escape_behaviors_have_return_self() -> void:
	for monster_id in GameData.MONSTER_DEFS:
		var eb := GameData.MONSTER_DEFS[monster_id]["escape_behavior"]
		assert_true(eb.has("return_self"),
			"escape_behavior['%s'] doit avoir return_self" % monster_id)

func test_all_escape_behaviors_have_spawn_on_escape() -> void:
	for monster_id in GameData.MONSTER_DEFS:
		var eb := GameData.MONSTER_DEFS[monster_id]["escape_behavior"]
		assert_true(eb.has("spawn_on_escape"),
			"escape_behavior['%s'] doit avoir spawn_on_escape" % monster_id)

func test_green_goblin_does_not_return() -> void:
	var eb := GameData.MONSTER_DEFS["g"]["escape_behavior"]
	assert_false(eb["return_self"].get("enabled", true),
		"gobelin vert : return_self.enabled = false (sort définitivement)")

func test_green_goblin_no_additional_spawns() -> void:
	var eb := GameData.MONSTER_DEFS["g"]["escape_behavior"]
	assert_false(eb["spawn_on_escape"].get("enabled", true),
		"gobelin vert : spawn_on_escape.enabled = false (aucun spawn additionnel)")

func test_blue_goblin_does_not_return() -> void:
	var eb := GameData.MONSTER_DEFS["b"]["escape_behavior"]
	assert_false(eb["return_self"].get("enabled", true),
		"gobelin bleu : return_self.enabled = false (sort définitivement)")

func test_red_goblin_returns() -> void:
	var eb := GameData.MONSTER_DEFS["r"]["escape_behavior"]
	assert_true(eb["return_self"].get("enabled", false),
		"gobelin rouge : return_self.enabled = true (revient)")

func test_red_goblin_preserves_state() -> void:
	var eb := GameData.MONSTER_DEFS["r"]["escape_behavior"]
	assert_true(eb["return_self"].get("preserve_state", false),
		"gobelin rouge : preserve_state = true (revient blessé)")

func test_red_goblin_no_heal() -> void:
	var eb := GameData.MONSTER_DEFS["r"]["escape_behavior"]
	assert_eq(eb["return_self"].get("heal_mode", ""), "none",
		"gobelin rouge : heal_mode = none (pas de soin au retour)")

func test_red_goblin_spawns_blue() -> void:
	var eb := GameData.MONSTER_DEFS["r"]["escape_behavior"]
	assert_true(eb["spawn_on_escape"].get("enabled", false),
		"gobelin rouge : spawn_on_escape.enabled = true")
	assert_eq(eb["spawn_on_escape"].get("count", 0), 1,
		"gobelin rouge : génère 1 spawn additionnel")
	assert_eq(eb["spawn_on_escape"].get("spawn_types", []), ["b"],
		"gobelin rouge : génère un gobelin bleu")

func test_red_goblin_return_hp_calculation() -> void:
	# Rouge à 30/90 HP, heal_mode=none, preserve_state=true → retour à 30
	var eb      := GameData.MONSTER_DEFS["r"]["escape_behavior"]
	var ret_cfg := eb["return_self"]
	var hp      := EscapeBehavior.calc_return_hp(30, 90, ret_cfg)
	assert_eq(hp, 30, "rouge blessé revient avec ses PV courants (30/90)")

func test_boss_returns_with_heal() -> void:
	for boss_id in ["boss_g", "boss_b", "boss_r"]:
		var eb := GameData.MONSTER_DEFS[boss_id]["escape_behavior"]
		assert_true(eb["return_self"].get("enabled", false),
			"boss '%s' : return_self.enabled = true" % boss_id)
		assert_eq(eb["return_self"].get("heal_mode", ""), "percent_max",
			"boss '%s' : heal_mode = percent_max" % boss_id)
		assert_almost_eq(float(eb["return_self"].get("heal_value", 0.0)), 0.3, 0.001,
			"boss '%s' : heal_value = 0.3 (30%% des PV max)" % boss_id)

func test_boss_no_additional_spawns() -> void:
	for boss_id in ["boss_g", "boss_b", "boss_r"]:
		var eb := GameData.MONSTER_DEFS[boss_id]["escape_behavior"]
		assert_false(eb["spawn_on_escape"].get("enabled", true),
			"boss '%s' : spawn_on_escape.enabled = false" % boss_id)

func test_boss_return_hp_calculation() -> void:
	# Boss vert hp_max=300, en vie à 100, heal 30% → 100 + 90 = 190
	var eb      := GameData.MONSTER_DEFS["boss_g"]["escape_behavior"]
	var ret_cfg := eb["return_self"]
	var hp      := EscapeBehavior.calc_return_hp(100, 300, ret_cfg)
	assert_eq(hp, 190, "boss à 100/300 PV + 30%% = 190 PV")

func test_boss_return_hp_capped_at_max() -> void:
	# Boss presque plein (270/300) + 30% = 270 + 90 = 360 → borné à 300
	var eb      := GameData.MONSTER_DEFS["boss_g"]["escape_behavior"]
	var ret_cfg := eb["return_self"]
	var hp      := EscapeBehavior.calc_return_hp(270, 300, ret_cfg)
	assert_eq(hp, 300, "boss presque plein + heal → borné à hp_max")

# ── Intégration : queue_respawn avec def_snapshot et initial_hp ───

func test_queue_respawn_stores_initial_hp() -> void:
	var state   := BoardState.new()
	var enemies := preload("res://scripts/game_enemies.gd").new()
	enemies.board_state = state
	add_child_autofree(enemies)
	var def := GameData.MONSTER_DEFS["r"].duplicate()
	enemies.queue_respawn(2, "r", def, 45)
	assert_eq(enemies._pending_respawns.size(), 1, "un respawn en attente")
	assert_eq(enemies._pending_respawns[0]["initial_hp"], 45, "initial_hp stocké correctement")

func test_queue_respawn_backward_compat_no_initial_hp() -> void:
	var state   := BoardState.new()
	var enemies := preload("res://scripts/game_enemies.gd").new()
	enemies.board_state = state
	add_child_autofree(enemies)
	enemies.queue_respawn(2, "g")  # appel à 2 args (ancienne syntaxe)
	assert_eq(enemies._pending_respawns[0]["initial_hp"], -1,
		"appel sans initial_hp → défaut -1 (pleine vie)")
	assert_true(enemies._pending_respawns[0]["def_snapshot"].is_empty(),
		"appel sans def_snapshot → dict vide")

func test_tick_pending_respawns_passes_initial_hp_in_result() -> void:
	var state   := BoardState.new()
	state.clear_all()
	var enemies := preload("res://scripts/game_enemies.gd").new()
	enemies.board_state = state
	add_child_autofree(enemies)
	var def := GameData.MONSTER_DEFS["r"].duplicate()
	enemies.queue_respawn(2, "r", def, 42)
	var results := enemies.tick_pending_respawns()
	assert_eq(results.size(), 1, "file libre → résultat retourné")
	assert_eq(results[0]["initial_hp"], 42, "initial_hp propagé dans le résultat")
	assert_false(results[0]["def_snapshot"].is_empty(),
		"def_snapshot propagé dans le résultat")
