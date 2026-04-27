extends Node2D
# ── GameEnemies ──────────────────────────────────────────────────
# Spawn, placement et retraite des ennemis.
# Doit être ajouté comme enfant du nœud Game dans main.tscn.
# game.gd définit dans _ready() :
#   enemies.monsters_node = monsters_node
#   enemies.grid          = grid          ← même référence Array

var monsters_node : Node2D
var grid          : Array   # référence partagée avec game.gd

# Registre des scènes indexé par monster_id (data-driven)
var MONSTER_SCENES : Dictionary = {
	"g": preload("res://scenes/monster_blob.tscn"),
	"b": preload("res://scenes/monster_blue.tscn"),
	"r": preload("res://scenes/monster_red.tscn"),
}
var boss_scene = preload("res://scenes/monster_boss.tscn")

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
	var boss_type  : String = "g"
	var boss_hp    : int    = 300
	var boss_dmg   : int    = 25
	var boss_speed : int    = 1
	var boss_xp    : int    = 500

	if room_num >= 15:
		boss_type  = "r"
		boss_hp    = 1000
		boss_dmg   = 60
		boss_speed = 2
		boss_xp    = 2000
		if room_num > 15:
			var extra_tranches = (room_num - 15) / 5
			var mult = pow(1.5, extra_tranches)
			boss_hp  = int(boss_hp  * mult)
			boss_dmg = int(boss_dmg * mult)
			boss_xp  = int(boss_xp  * mult)
	elif room_num >= 10:
		boss_type  = "b"
		boss_hp    = 600
		boss_dmg   = 40
		boss_speed = 1
		boss_xp    = 1000

	var boss = boss_scene.instantiate()
	boss.hp           = boss_hp
	boss.hp_max       = boss_hp
	boss.damage       = boss_dmg
	boss.move_speed   = boss_speed
	boss.xp_value     = boss_xp
	boss.monster_type = boss_type
	monsters_node.add_child(boss)
	boss.position  = grid_pos(0, 2)
	boss.grid_row  = 0
	boss.grid_lane = 2
	grid[0][2]     = boss
	print("[BOSS] Salle %d — type=%s hp=%d dmg=%d" % [room_num, boss_type, boss_hp, boss_dmg])
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

	var scene = MONSTER_SCENES.get(monster_id, MONSTER_SCENES["g"])
	var m = scene.instantiate()
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
