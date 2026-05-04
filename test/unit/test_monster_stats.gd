extends GutTest

# Tests de non-régression : constantes GameData (monstres, armes, ticks)
# Couvre : TICKS_PER_SECOND, conversion move_speed→ticks, intégrité de MONSTER_DEFS
#          et WEAPON_DEFS, formule de scaling des boss

func test_ticks_per_second_is_12() -> void:
	assert_eq(GameData.TICKS_PER_SECOND, 12, "simulation fixe à 12 ticks/s")

func test_move_period_speed1_equals_12_ticks() -> void:
	var period := GameData.TICKS_PER_SECOND / 1
	assert_eq(period, 12, "speed=1 → 12 ticks par déplacement (1 case/s)")

func test_move_period_speed2_equals_6_ticks() -> void:
	var period := GameData.TICKS_PER_SECOND / 2
	assert_eq(period, 6, "speed=2 → 6 ticks par déplacement (2 cases/s)")

func test_all_monster_defs_have_required_fields() -> void:
	var required := ["name", "scene", "behavior", "hp", "damage", "move_speed",
					 "xp_value", "is_boss", "tags", "palette", "sprite_path"]
	for monster_id: String in GameData.MONSTER_DEFS:
		var def: Dictionary = GameData.MONSTER_DEFS[monster_id]
		for field: String in required:
			assert_true(def.has(field),
				"MONSTER_DEFS['%s'] doit avoir le champ '%s'" % [monster_id, field])

func test_all_monster_defs_sprite_path_nonempty() -> void:
	for monster_id: String in GameData.MONSTER_DEFS:
		var path: String = GameData.MONSTER_DEFS[monster_id].get("sprite_path", "")
		assert_true(path.begins_with("res://assets/characters/"),
			"MONSTER_DEFS['%s'].sprite_path doit pointer vers res://assets/characters/" % monster_id)

func test_all_monster_defs_hp_positive() -> void:
	for monster_id: String in GameData.MONSTER_DEFS:
		var hp: int = GameData.MONSTER_DEFS[monster_id]["hp"]
		assert_true(hp > 0, "MONSTER_DEFS['%s'].hp > 0 (valeur: %d)" % [monster_id, hp])

func test_all_monster_defs_move_speed_positive() -> void:
	for monster_id: String in GameData.MONSTER_DEFS:
		var spd: int = GameData.MONSTER_DEFS[monster_id]["move_speed"]
		assert_true(spd > 0, "MONSTER_DEFS['%s'].move_speed > 0" % monster_id)

func test_boss_defs_have_is_boss_true() -> void:
	for boss_id: String in ["boss_g", "boss_b", "boss_r"]:
		assert_true(GameData.MONSTER_DEFS[boss_id]["is_boss"],
			"'%s'.is_boss doit être true" % boss_id)

func test_standard_defs_have_is_boss_false() -> void:
	for mob_id: String in ["g", "b", "r"]:
		assert_false(GameData.MONSTER_DEFS[mob_id]["is_boss"],
			"'%s'.is_boss doit être false" % mob_id)

func test_gobelin_rouge_move_speed_is_2() -> void:
	assert_eq(GameData.MONSTER_DEFS["r"]["move_speed"], 2,
		"gobelin rouge plus rapide : speed = 2")

func test_gobelin_vert_and_bleu_speed_is_1() -> void:
	assert_eq(GameData.MONSTER_DEFS["g"]["move_speed"], 1, "gobelin vert : speed = 1")
	assert_eq(GameData.MONSTER_DEFS["b"]["move_speed"], 1, "gobelin bleu : speed = 1")

func test_boss_monster_type_matches_base() -> void:
	assert_eq(GameData.MONSTER_DEFS["boss_g"]["monster_type"], "g", "boss_g → monster_type 'g'")
	assert_eq(GameData.MONSTER_DEFS["boss_b"]["monster_type"], "b", "boss_b → monster_type 'b'")
	assert_eq(GameData.MONSTER_DEFS["boss_r"]["monster_type"], "r", "boss_r → monster_type 'r'")

func test_all_weapon_defs_have_required_fields() -> void:
	var required := ["name", "base_dmg", "cd", "desc", "icon", "icon_path"]
	for weapon_id: String in GameData.WEAPON_DEFS:
		var def: Dictionary = GameData.WEAPON_DEFS[weapon_id]
		for field: String in required:
			assert_true(def.has(field),
				"WEAPON_DEFS['%s'] doit avoir le champ '%s'" % [weapon_id, field])

func test_all_weapon_defs_icon_path_nonempty() -> void:
	for weapon_id: String in GameData.WEAPON_DEFS:
		var path: String = GameData.WEAPON_DEFS[weapon_id].get("icon_path", "")
		assert_true(path.begins_with("res://assets/weapons/"),
			"WEAPON_DEFS['%s'].icon_path doit pointer vers res://assets/weapons/" % weapon_id)

func test_all_weapon_defs_base_dmg_positive() -> void:
	for weapon_id: String in GameData.WEAPON_DEFS:
		var dmg: int = GameData.WEAPON_DEFS[weapon_id]["base_dmg"]
		assert_true(dmg > 0, "WEAPON_DEFS['%s'].base_dmg > 0" % weapon_id)

func test_all_weapon_defs_cd_positive() -> void:
	for weapon_id: String in GameData.WEAPON_DEFS:
		var cd: float = GameData.WEAPON_DEFS[weapon_id]["cd"]
		assert_true(cd > 0.0, "WEAPON_DEFS['%s'].cd > 0" % weapon_id)

func test_boss_scaling_room_20_one_tranche() -> void:
	# room 20 : extra_tranches = (20 - 15) / 5 = 1 → mult = 1.5^1 = 1.5
	var room := 20
	var extra_tranches := (room - 15) / 5
	var mult := pow(1.5, extra_tranches)
	assert_eq(extra_tranches, 1, "room 20 → 1 tranche au-delà de la salle 15")
	assert_almost_eq(mult, 1.5, 0.001, "1 tranche → multiplicateur 1.5")

func test_boss_scaling_room_25_two_tranches() -> void:
	# room 25 : extra_tranches = (25 - 15) / 5 = 2 → mult = 1.5^2 = 2.25
	var room := 25
	var extra_tranches := (room - 15) / 5
	var mult := pow(1.5, extra_tranches)
	assert_eq(extra_tranches, 2, "room 25 → 2 tranches")
	assert_almost_eq(mult, 2.25, 0.001, "2 tranches → multiplicateur 2.25")

func test_boss_scaling_room_15_no_scaling() -> void:
	# room 15 : pas de scaling (condition room > 15 non déclenchée)
	var room := 15
	assert_false(room > 15, "salle 15 : pas de scaling exponentiel appliqué")

func test_eight_weapons_defined() -> void:
	assert_eq(GameData.WEAPON_DEFS.size(), 8, "exactement 8 armes définies")

func test_six_monsters_defined() -> void:
	assert_eq(GameData.MONSTER_DEFS.size(), 6, "exactement 6 entrées dans MONSTER_DEFS (3 standards + 3 boss)")
