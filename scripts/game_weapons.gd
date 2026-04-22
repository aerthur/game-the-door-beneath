extends Node2D
# ── GameWeapons ──────────────────────────────────────────────────
# Logique de tir des 8 armes.
# Doit être ajouté comme enfant du nœud Game dans main.tscn.
# game.gd définit dans _ready() :
#   weapons.grid        = grid          ← même référence Array
#   weapons.visuals     = visuals
#   weapons.deal_fn     = _deal_and_check  ← Callable

var grid             : Array
var visuals          : Node2D
var deal_fn          : Callable  # func(m, row, lane, dmg)
var player_lane      : int = 2   # mis à jour par game.gd à chaque déplacement
var active_weapon_id : String = ""  # arme actuellement en cours de tir (pour stats)

# ── Dégâts ───────────────────────────────────────────────────────
func get_dmg(w: Dictionary) -> int:
	return int(GameData.WEAPON_DEFS[w.id].base_dmg * (1.0 + (w.level - 1) * 0.5))

# ── Dispatch ─────────────────────────────────────────────────────
func fire(w: Dictionary):
	active_weapon_id = w.id
	match w.id:
		"arc":        _w_arc(w)
		"arbalete":   _w_arbalete(w)
		"dague":      _w_dague(w)
		"bombe":      _w_bombe(w)
		"eclair":     _w_eclair(w)
		"tourbillon": _w_tourbillon(w)
		"givre":      _w_givre(w)
		"sismique":   _w_sismique(w)

# ── 8 armes ──────────────────────────────────────────────────────
func _w_arc(w: Dictionary):
	for r in range(GameData.ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			var t = 0.15 + r * 0.02
			visuals.shoot_arrow(player_lane, r, t, Color(0.95, 0.85, 0.3))
			await get_tree().create_timer(t).timeout
			if is_instance_valid(m): deal_fn.call(m, r, player_lane, get_dmg(w))
			return

func _w_arbalete(w: Dictionary):
	var hit = 0
	for r in range(GameData.ROWS - 1, -1, -1):
		if hit >= 2: break
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			visuals.shoot_arrow(player_lane, r, 0.18 + r * 0.015, Color(0.6, 0.6, 1.0), 5.0)
			await get_tree().create_timer(0.18 + r * 0.015).timeout
			if is_instance_valid(m): deal_fn.call(m, r, player_lane, get_dmg(w))
			hit += 1

func _w_dague(w: Dictionary):
	for r in range(GameData.ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			visuals.show_slash(player_lane, r)
			deal_fn.call(grid[r][player_lane], r, player_lane, get_dmg(w))
			return

func _w_bombe(w: Dictionary):
	for l in [player_lane - 1, player_lane, player_lane + 1]:
		if l < 0 or l >= GameData.LANES: continue
		for r in range(GameData.ROWS - 1, -1, -1):
			if grid[r][l] != null:
				visuals.show_explosion(l, r)
				await get_tree().create_timer(0.1).timeout
				if grid[r][l] != null: deal_fn.call(grid[r][l], r, l, get_dmg(w))
				break

func _w_eclair(w: Dictionary):
	for r in range(GameData.ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			visuals.show_lightning(player_lane, r)
			deal_fn.call(grid[r][player_lane], r, player_lane, get_dmg(w))

func _w_tourbillon(w: Dictionary):
	visuals.show_whirlwind()
	for l in GameData.LANES:
		for r in range(GameData.ROWS - 1, -1, -1):
			if grid[r][l] != null:
				deal_fn.call(grid[r][l], r, l, get_dmg(w))
				break

func _w_givre(w: Dictionary):
	for r in range(GameData.ROWS - 1, -1, -1):
		if grid[r][player_lane] != null:
			var m = grid[r][player_lane]
			visuals.shoot_arrow(player_lane, r, 0.2, Color(0.4, 0.85, 1.0), 3.0)
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(m):
				m.freeze(2)
				deal_fn.call(m, r, player_lane, get_dmg(w))
			return

func _w_sismique(w: Dictionary):
	visuals.show_quake()
	for r in [GameData.ROWS - 1, GameData.ROWS - 2]:
		for l in GameData.LANES:
			if r >= 0 and grid[r][l] != null:
				deal_fn.call(grid[r][l], r, l, get_dmg(w))
