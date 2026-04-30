extends Node2D
# ── GameEnemies ──────────────────────────────────────────────────
# Spawn, placement et retraite des ennemis.
# Doit être ajouté comme enfant du nœud Game dans main.tscn.
# game.gd définit dans _ready() :
#   enemies.monsters_node = monsters_node
#   enemies.board_state   = board_state   ← source de vérité partagée

var monsters_node : Node2D
var board_state   : BoardState  # source de vérité partagée avec game.gd

var _scene_cache  : Dictionary = {}  # scene_path → PackedScene

# ── Système de respawn avec retry prioritaire (issue #70) ────────
# Fenêtre de retry = 12 ticks (1 s à 12 tps) avant fallback adjacent.
const RETRY_WINDOW_TICKS : int = GameData.TICKS_PER_SECOND

# File des respawns en attente : { monster_id, lane, ticks_waited }
var pending_respawns : Array = []

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
	board_state.set_cell_occupied(0, 2, boss)
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
	while r < BoardGeometry.GRID_ROWS and (board_state.is_cell_occupied(r, target_lane) or board_state.is_cell_blocked(r, target_lane)):
		r += 1
	if r >= BoardGeometry.GRID_ROWS: return false

	var m = _get_scene(def["scene"]).instantiate()
	m.setup_from_def(monster_id, def)
	monsters_node.add_child(m)
	m.position  = grid_pos(r, target_lane)
	m.grid_row  = r
	m.grid_lane = target_lane
	board_state.set_cell_occupied(r, target_lane, m)
	return true

func find_spawn_lane(preferred: int) -> int:
	if board_state.is_cell_free(0, preferred) and not board_state.is_cell_blocked(0, preferred):
		return preferred
	for offset in [1, -1, 2, -2, 3, -3, 4, -4]:
		var l = preferred + offset
		if l >= 0 and l < BoardGeometry.GRID_COLUMNS and board_state.is_cell_free(0, l) and not board_state.is_cell_blocked(0, l):
			return l
	return -1

# ── Retry prioritaire sur la file d'origine (issue #70) ─────────

# Tente le spawn strictement sur la lane donnée (row 0, col lane).
# Pas de fallback. Retourne true si spawn réussi.
func _try_spawn_in_lane(monster_id: String, lane: int) -> bool:
	if not GameData.MONSTER_DEFS.has(monster_id): return false
	if not board_state.is_cell_free(0, lane) or board_state.is_cell_blocked(0, lane): return false
	var def = GameData.MONSTER_DEFS[monster_id]
	var r : int = 0
	while r < BoardGeometry.GRID_ROWS and (board_state.is_cell_occupied(r, lane) or board_state.is_cell_blocked(r, lane)):
		r += 1
	if r >= BoardGeometry.GRID_ROWS: return false
	var m = _get_scene(def["scene"]).instantiate()
	m.setup_from_def(monster_id, def)
	monsters_node.add_child(m)
	m.position  = grid_pos(r, lane)
	m.grid_row  = r
	m.grid_lane = lane
	board_state.set_cell_occupied(r, lane, m)
	return true

# Tente un spawn sur la file d'origine.
# Si la cellule d'entrée est occupée/bloquée, met en file d'attente.
# Retourne true si spawn immédiat, false si mis en attente.
func request_respawn(monster_id: String, preferred_lane: int) -> bool:
	if _try_spawn_in_lane(monster_id, preferred_lane):
		return true
	pending_respawns.append({
		"monster_id": monster_id,
		"lane": preferred_lane,
		"ticks_waited": 0,
	})
	return false

# Décision pure (sans effet de bord) pour un respawn en attente.
# Retourne : lane >= 0 → spawner là ; -1 → rester en attente ; -2 → abandonner.
func resolve_pending_respawn_lane(req: Dictionary) -> int:
	if board_state.is_cell_free(0, req["lane"]) and not board_state.is_cell_blocked(0, req["lane"]):
		return req["lane"]
	if req["ticks_waited"] >= RETRY_WINDOW_TICKS:
		var fallback = _find_fallback_lane(req["lane"])
		return fallback if fallback >= 0 else -2
	return -1

# Traite tous les respawns en attente à chaque tick (appelé par game.gd._do_tick).
# Retourne { "spawned": int, "abandoned": int } pour mise à jour de monsters_remaining.
func process_pending_respawns() -> Dictionary:
	if pending_respawns.is_empty():
		return { "spawned": 0, "abandoned": 0 }
	var spawned   : int = 0
	var abandoned : int = 0
	var still_pending : Array = []
	for req in pending_respawns:
		req["ticks_waited"] += 1
		var target_lane : int = resolve_pending_respawn_lane(req)
		if target_lane == -1:
			still_pending.append(req)
			continue
		if target_lane == -2:
			abandoned += 1
			print("[RESPAWN] Abandon type=%s file %d — %d ticks expirés, aucune lane disponible" % [req["monster_id"], req["lane"]+1, req["ticks_waited"]])
			continue
		if _try_spawn_in_lane(req["monster_id"], target_lane):
			spawned += 1
			if target_lane == req["lane"]:
				print("[RESPAWN] type=%s file %d — spawn réussi après %d ticks" % [req["monster_id"], req["lane"]+1, req["ticks_waited"]])
			else:
				print("[RESPAWN] type=%s file %d → fallback file %d après %d ticks" % [req["monster_id"], req["lane"]+1, target_lane+1, req["ticks_waited"]])
		else:
			abandoned += 1
			print("[RESPAWN] type=%s file %d — spawn échoué sur file %d, abandon" % [req["monster_id"], req["lane"]+1, target_lane+1])
	pending_respawns = still_pending
	return { "spawned": spawned, "abandoned": abandoned }

func _find_fallback_lane(original_lane: int) -> int:
	for offset in [1, -1, 2, -2, 3, -3, 4, -4]:
		var l = original_lane + offset
		if l >= 0 and l < BoardGeometry.GRID_COLUMNS:
			if board_state.is_cell_free(0, l) and not board_state.is_cell_blocked(0, l):
				return l
	return -1

func clear_pending_respawns() -> void:
	pending_respawns.clear()

# ── Retraite du boss ─────────────────────────────────────────────
func boss_retreat(boss: Node2D, lane: int):
	var heal_amount = int(boss.hp_max * 0.3)
	boss.hp = min(boss.hp_max, boss.hp + heal_amount)
	boss.update_health_bar()
	boss.grid_row  = 0
	boss.grid_lane = lane
	board_state.set_cell_occupied(0, lane, boss)
	boss.position  = grid_pos(0, lane)
	print("[BOSS] Remontée file %d — soigné +%d → %d/%d" % [lane + 1, heal_amount, boss.hp, boss.hp_max])
