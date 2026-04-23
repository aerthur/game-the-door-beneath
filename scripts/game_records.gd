extends Node2D
# ── GameRecords ───────────────────────────────────────────────────
# Persistance des records et statistiques de run.
# Doit être ajouté comme enfant du nœud Main dans main.tscn.
# game.gd définit dans _ready() :
#   records_ctrl.hud = hud          ← pour afficher les records en game over
# API publique :
#   records_ctrl.load_records()
#   records_ctrl.init_run_stats()
#   records_ctrl.on_kill(mtype, wid)
#   records_ctrl.on_game_over(room, gold_earned, hero_level)

const SAVE_PATH = "user://records.json"

var hud : CanvasLayer  # défini par game.gd

var records   : Dictionary = {}  # bests persistants (chargés depuis disque)
var run_stats : Dictionary = {}  # stats de la run en cours (reset à chaque salle 1)
var _run_start_ms : int = 0

# ── Chargement / Sauvegarde ───────────────────────────────────────
func load_records():
	if not FileAccess.file_exists(SAVE_PATH):
		records = {}
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		records = {}
		return
	var json = JSON.new()
	if json.parse(f.get_as_text()) == OK:
		records = json.get_data()
	f.close()

func save_records():
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[Records] Impossible d'écrire : " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(records, "\t"))
	f.close()

# ── Init run ─────────────────────────────────────────────────────
func init_run_stats():
	_run_start_ms = Time.get_ticks_msec()
	run_stats = {
		"kills":        {"g": 0, "b": 0, "r": 0},
		"weapon_kills": {},
		"rooms_cleared": 0,
	}

# ── Kill ─────────────────────────────────────────────────────────
func on_kill(mtype: String, wid: String):
	if not run_stats.has("kills"): return
	run_stats.kills[mtype] = run_stats.kills.get(mtype, 0) + 1
	if wid != "":
		run_stats.weapon_kills[wid] = run_stats.weapon_kills.get(wid, 0) + 1

# ── Fin de run ────────────────────────────────────────────────────
func on_game_over(room: int, gold_earned: int, hero_level: int):
	var run_secs = (Time.get_ticks_msec() - _run_start_ms) / 1000
	run_stats.rooms_cleared = max(0, room - 1)

	var is_best_room  = not records.has("best_room")  or room       > records.best_room
	var is_best_gold  = not records.has("best_gold")  or gold_earned > records.best_gold
	var is_best_level = not records.has("best_level") or hero_level  > records.best_level

	if is_best_room:  records["best_room"]  = room
	if is_best_gold:  records["best_gold"]  = gold_earned
	if is_best_level: records["best_level"] = hero_level
	records["best_time"] = records.get("best_time", 0)
	if run_secs > records.best_time:
		records["best_time"] = run_secs
	records["total_runs"] = records.get("total_runs", 0) + 1

	# Kills cumulatifs par type
	for mtype in ["g", "b", "r"]:
		var key = "total_kills_" + mtype
		records[key] = records.get(key, 0) + run_stats.kills.get(mtype, 0)

	# Kills cumulatifs par arme → arme préférée
	for wid in run_stats.weapon_kills:
		var key = "weapon_kills_" + wid
		records[key] = records.get(key, 0) + run_stats.weapon_kills[wid]
	var best_wid = ""
	var best_count = 0
	for wid in GameData.WEAPON_DEFS.keys():
		var count = int(records.get("weapon_kills_" + wid, 0))
		if count > best_count:
			best_count = count
			best_wid = wid
	if best_wid != "":
		records["fav_weapon"] = best_wid

	save_records()

	print("[RECORDS] Salle:%d Or:%d Lvl:%d — best_room:%d best_gold:%d" % [
		room, gold_earned, hero_level, records.best_room, records.best_gold])
