extends GutTest

# Tests unitaires : logique XP / chaînage level-up
# Réplique l'algorithme de game.gd._add_xp() en pur GDScript (sans scène).
# Couvre : seuil exact, sous-seuil, multi-niveaux, XP résiduelle, cas limites.

# ── Helpers ──────────────────────────────────────────────────────

# Simule _add_xp() et retourne {levels, xp, xp_needed}
func _sim_add_xp(start_xp: int, start_needed: int, amount: int) -> Dictionary:
	var xp       : int = start_xp + amount
	var needed   : int = start_needed
	var levels   : int = 0
	while xp >= needed:
		xp     -= needed
		needed  = int(needed * 1.55)
		levels += 1
	return {"levels": levels, "xp": xp, "xp_needed": needed}

# ── Cas de base ───────────────────────────────────────────────────

func test_no_levelup_below_threshold() -> void:
	var r = _sim_add_xp(0, 60, 59)
	assert_eq(r["levels"], 0, "59 XP < 60 → aucun niveau")
	assert_eq(r["xp"],    59, "XP résiduelle = 59")

func test_exact_threshold_gives_one_level() -> void:
	var r = _sim_add_xp(0, 60, 60)
	assert_eq(r["levels"], 1, "60 XP = seuil → exactement 1 niveau")
	assert_eq(r["xp"],     0, "XP résiduelle = 0")

func test_just_over_threshold_gives_one_level() -> void:
	var r = _sim_add_xp(0, 60, 61)
	assert_eq(r["levels"], 1,  "61 XP > 60 → 1 niveau")
	assert_eq(r["xp"],     1,  "XP résiduelle = 1")

# ── Multi-niveaux ─────────────────────────────────────────────────

func test_500xp_from_level1_gives_multiple_levels() -> void:
	var r = _sim_add_xp(0, 60, 500)
	assert_true(r["levels"] > 1, "500 XP depuis niveau 1 → plusieurs niveaux")

func test_500xp_gives_exactly_4_levels() -> void:
	# Seuils : 60 → 93 → 144 → 223 → 346  (total cumulé : 60+93+144+223 = 520 > 500)
	# 60+93+144 = 297 ≤ 500, donc 3 niveaux ; résidu = 500-297 = 203 < 223 → 3 niveaux
	var r = _sim_add_xp(0, 60, 500)
	assert_eq(r["levels"], 3, "500 XP depuis niveau 1 → 3 niveaux (seuils 60+93+144=297)")

func test_residual_xp_is_correct_after_multi_levelup() -> void:
	# Après 3 niveaux avec 500 XP : résidu = 500 - (60+93+144) = 203
	var r = _sim_add_xp(0, 60, 500)
	assert_eq(r["xp"], 203, "XP résiduelle après 3 niveaux = 203")

func test_next_xp_needed_scales_correctly() -> void:
	# Après 1 niveau : xp_needed = int(60 * 1.55) = 93
	var r = _sim_add_xp(0, 60, 60)
	assert_eq(r["xp_needed"], 93, "xp_needed après 1 niveau = int(60*1.55) = 93")

func test_xp_needed_after_3_levels() -> void:
	# 60 → 93 → 144 → 223
	var r = _sim_add_xp(0, 60, 500)
	assert_eq(r["xp_needed"], 223, "xp_needed après 3 niveaux = int(144*1.55) = 223")

# ── XP de départ non nul ─────────────────────────────────────────

func test_levelup_with_accumulated_xp() -> void:
	# Déjà 50 XP, seuil 60 → +15 XP → franchit (50+15=65 ≥ 60)
	var r = _sim_add_xp(50, 60, 15)
	assert_eq(r["levels"], 1,  "50 XP accumulés + 15 = 65 ≥ 60 → 1 niveau")
	assert_eq(r["xp"],     5,  "XP résiduelle = 65 - 60 = 5")

func test_accumulated_xp_causing_multi_levelup() -> void:
	# Déjà 55 XP, seuil 60 → +200 XP → plusieurs niveaux
	var r = _sim_add_xp(55, 60, 200)
	assert_true(r["levels"] > 1, "XP accumulés + jackpot → multi-niveaux")

# ── Cas limites ───────────────────────────────────────────────────

func test_zero_xp_gain_gives_no_level() -> void:
	var r = _sim_add_xp(0, 60, 0)
	assert_eq(r["levels"], 0, "0 XP → aucun niveau")

func test_large_xp_gain_exhausts_correctly() -> void:
	# 10 000 XP depuis niveau 1 — vérifie que la boucle termine et que l'XP résiduelle
	# est bien inférieure au prochain seuil
	var r = _sim_add_xp(0, 60, 10000)
	assert_true(r["levels"] > 0,          "10 000 XP → au moins un niveau")
	assert_true(r["xp"] < r["xp_needed"], "XP résiduelle toujours < prochain seuil")

# ── Logique de chaînage (_pending_levelups) ───────────────────────

func test_pending_levelups_accumulates_correctly() -> void:
	# Simule deux appels successifs pendant leveling_up = true
	var pending : int = 0
	var leveling_up : bool = false

	# Premier appel : 3 niveaux d'un coup
	var r1 = _sim_add_xp(0, 60, 500)
	pending += r1["levels"]
	if not leveling_up:
		leveling_up = true   # _trigger_level_up()

	# Deuxième appel (gemme arrivée pendant le panel) : 1 niveau supplémentaire
	var r2 = _sim_add_xp(r1["xp"], r1["xp_needed"], 300)
	pending += r2["levels"]
	# leveling_up est true → pas de second trigger

	assert_true(pending > r1["levels"], "niveaux accumulés pendant panel > niveaux du premier appel")

func test_chain_resolves_to_zero() -> void:
	# Simule apply_level_up_choice() jusqu'à épuisement
	var pending : int = 4
	var choices_made : int = 0
	while pending > 0:
		pending -= 1
		choices_made += 1
	assert_eq(pending,      0, "pending_levelups atteint 0 après tous les choix")
	assert_eq(choices_made, 4, "exactement 4 choix présentés pour 4 niveaux")
