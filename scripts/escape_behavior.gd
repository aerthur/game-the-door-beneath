class_name EscapeBehavior

# ── Politique de fin de file (issue #109) ────────────────────────
# Résolveur statique pur pour les comportements de fin de file.
# Aucune dépendance scène — testable sans Godot.
#
# Structure escape_behavior attendue dans MONSTER_DEFS :
#   {
#     "return_self": {
#       "enabled":        bool,
#       "preserve_state": bool,   # true = conserve HP courant, false = repart pleine vie
#       "heal_mode":      String, # "none" | "flat" | "percent_max" | "full"
#       "heal_value":     variant, # int (flat) ou float (percent_max)
#     },
#     "spawn_on_escape": {
#       "enabled":     bool,
#       "count":       int,
#       "spawn_types": Array[String],
#       "mode":        "ordered",
#     }
#   }

# Calcule le HP de retour pour un monstre qui revient après avoir atteint le bout de sa file.
# preserve_state=false → base = hp_max (repart plein) ; true → base = current_hp.
# heal_mode appliqué sur la base, résultat borné à [1, hp_max].
static func calc_return_hp(current_hp: int, hp_max: int, return_cfg: Dictionary) -> int:
	var base_hp := current_hp if return_cfg.get("preserve_state", false) else hp_max
	match return_cfg.get("heal_mode", "none"):
		"flat":
			base_hp = min(hp_max, base_hp + int(return_cfg.get("heal_value", 0)))
		"percent_max":
			var ratio := float(return_cfg.get("heal_value", 0.0))
			base_hp = min(hp_max, base_hp + int(float(hp_max) * ratio))
		"full":
			base_hp = hp_max
	return max(1, base_hp)

# Retourne le spawn_type à utiliser pour l'index i dans spawn_on_escape.
# Règle : si spawn_types a moins d'entrées que count, la dernière entrée est réutilisée.
# Si spawn_types est vide, retourne fallback (le type du monstre sortant).
static func get_spawn_type_at(spawn_types: Array, index: int, fallback: String) -> String:
	if spawn_types.is_empty():
		return fallback
	return spawn_types[min(index, spawn_types.size() - 1)]
