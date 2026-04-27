class_name ObstacleData
extends RefCounted
# Structure de données d'un obstacle sur une cellule de la grille.
# Extensible : chaque champ permet de distinguer des familles d'obstacles
# sans refactoriser quand de nouvelles catégories sont introduites.

var kind             : String = "wall"          # identifiant sémantique
var blocks_movement  : bool   = true
var blocks_occupancy : bool   = true
var blocks_los       : bool   = false           # non exploité pour le moment
var destructibility  : String = "indestructible" # "indestructible" | "destructible"
var hp               : int    = -1              # -1 = non applicable
var max_hp           : int    = -1

# ── Factories ────────────────────────────────────────────────────────
static func make_wall() -> ObstacleData:
	var o = ObstacleData.new()
	o.kind            = "wall"
	o.blocks_movement = true
	o.blocks_occupancy= true
	o.blocks_los      = true
	o.destructibility = "indestructible"
	return o
