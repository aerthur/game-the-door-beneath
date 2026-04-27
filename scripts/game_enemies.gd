extends Node2D
# ── GameEnemies ──────────────────────────────────────────────────
# Spawn, placement et retraite des ennemis.
# Doit être ajouté comme enfant du nœud Game dans main.tscn.
# game.gd définit dans _ready() :
#   enemies.monsters_node = monsters_node
#   enemies.grid          = grid          ← même référence Array

var monsters_node : Node2D
var grid          : Array   # référence partagée avec game.gd

var _scene_cache  : Dictionary = {}  # scene_path → PackedScene

func _get_scene(scene_path: String) -> PackedScene:
	if not _scene_cache.has(scene_path):
		_scene_cache[scene_path] = load(scene_path)
	return _scene_cache[scene_path]

# ── Helper position grille ───────────────────────────────────────
func grid_pos(row: int, lane: int) -> Vector2:
	return BoardGeometry.get_cell_center(row, lane)

# ── Composition de la salle ──────────────────────────────────────
func get_composition(room: int) -> Array:
	if GameData.ROOM_WAVES.has(room):
		return GameData.ROOM_WAVES[room].duplicate()
	# Au-delà de la salle 10 : que des rouges, de plus en plus
	var extra = room - 10
	var reds  = min(BoardGeometry.GRID_COLUMNS + extra, BoardGeometry.GRID_COLUMNS * 2)
	var result = []
	for _i in reds: result.append("r")
	return result

# ── Boss ─────────────────────────────────────────────────────────
# Retourne le nombre de boss spawné (toujours 1, pour monsters_remaining)
func spawn_boss(room_num: int) -> int:
	var boss_id : String
	if room_num >= 15:
		boss_id = "boss_r"
	elif room_num >= 10:
		boss_id = "boss_b"
	else:
		boss_id = "boss_g"

	var def = GameData.MONSTER_DEFS[boss_id].duplicate()

	# Scaling exponentiel pour les salles au-delà de la salle 15
	if room_num > 15:
		var extra_tranches = (room_num - 15) / 5
		var mult = pow(1.5, extra_tranches)
		def["hp"]       = int(def["hp"]       * mult)
		def["damage"]   = int(def["damage"]   * mult)
		def["xp_value"] = int(def["xp_value"] * mult)

	var boss = _get_scene(def["scene"]).instantiate()
	boss.setup_from_def(boss_id, def)
	monsters_node.add_child(boss)
	boss.position  = grid_pos(0, 2)
	boss.grid_row  = 0
	boss.grid_lane = 2
	grid[0][2]     = boss
	print("[BOSS] Salle %d — %s hp=%d dmg=%d" % [room_num, def["name"], def["hp"], def["damage"]])
	return 1

# ── Résolution du contexte de spawn ─────────────────────────────
# spawn_ctx = { "entry_side": String, "entry_index": int }
# entry_side  : "top" | "bottom" | "left" | "right"
# entry_index : numéro de lane (top/bottom) ou de rangée (left/right)
# Retourne { "row": int, "lane": int } en coordonnées grille.
func _resolve_spawn_ctx(ctx: Dictionary) -> Dictionary:
	var side  : String = ctx.get("entry_side",  "top")
	var index : int    = ctx.get("entry_index", 0)
	match side:
		"bottom": return { "row": BoardGeometry.GRID_ROWS - 1, "lane": index }
		"left":   return { "row": index, "lane": 0 }
		"right":  return { "row": index, "lane": BoardGeometry.GRID_COLUMNS - 1 }
		_:        return { "row": 0, "lane": index }  # "top" par défaut

# ── Vague de monstres ────────────────────────────────────────────
func spawn_wave(composition: Array):
	var lanes_list = range(BoardGeometry.GRID_COLUMNS)
	lanes_list.shuffle()
	for i in composition.size():
		var lane = lanes_list[i % BoardGeometry.GRID_COLUMNS]
		var ctx  = { "entry_side": "top", "entry_index": lane }
		spawn_monster(composition[i], ctx)

# spawn_monster — data-driven et contextuel
# monster_id : clé dans GameData.MONSTER_DEFS
# spawn_ctx  : { "entry_side": String, "entry_index": int }
func spawn_monster(monster_id: String, spawn_ctx: Dictionary) -> bool:
	if not GameData.MONSTER_DEFS.has(monster_id):
		push_error("[Enemies] monster_id inconnu : " + monster_id)
		return false

	var def      : Dictionary = GameData.MONSTER_DEFS[monster_id]
	var resolved : Dictionary = _resolve_spawn_ctx(spawn_ctx)

	var target_lane = find_spawn_lane(resolved["lane"])
	if target_lane == -1: return false   # toutes colonnes pleines

	var r : int = resolved["row"]
	while r < BoardGeometry.GRID_ROWS and grid[r][target_lane] != null:
		r += 1
	if r >= BoardGeometry.GRID_ROWS: return false

	var m = _get_scene(def["scene"]).instantiate()
	m.setup_from_def(monster_id, def)
	monsters_node.add_child(m)
	m.position           = grid_pos(r, target_lane)
	m.grid_row           = r
	m.grid_lane          = target_lane
	grid[r][target_lane] = m
	return true

func find_spawn_lane(preferred: int) -> int:
	if grid[0][preferred] == null:
		return preferred
	for offset in [1, -1, 2, -2, 3, -3, 4, -4]:
		var l = preferred + offset
		if l >= 0 and l < BoardGeometry.GRID_COLUMNS and grid[0][l] == null:
			return l
	return -1

# ── Retraite du boss ─────────────────────────────────────────────
func boss_retreat(boss: Node2D, lane: int):
	var heal_amount = int(boss.hp_max * 0.3)
	boss.hp = min(boss.hp_max, boss.hp + heal_amount)
	boss.update_health_bar()
	boss.grid_row  = 0
	boss.grid_lane = lane
	grid[0][lane]  = boss
	boss.position  = grid_pos(0, lane)
	print("[BOSS] Remontée file %d — soigné +%d → %d/%d" % [lane + 1, heal_amount, boss.hp, boss.hp_max])
