class_name GameData

# Simulation fixe — 1 seconde de gameplay = 12 ticks logiques
const TICKS_PER_SECOND : int = 12
# Conversions de référence : 6 ticks = 0,5 s ; 12 ticks = 1 s ; 24 ticks = 2 s

# ── Composition des salles ───────────────────────────────────────
const ROOM_WAVES = {
	1:  ["g","g","g"],
	2:  ["g","g","g","g"],
	3:  ["g","g","g","b"],
	4:  ["g","g","b","b"],
	5:  ["g","b","b","b","b"],
	6:  ["g","g","b","b","b"],
	7:  ["g","b","b","b","b","b"],
	8:  ["b","b","b","b","r","r"],
	9:  ["b","b","b","r","r","r","r"],
	10: ["b","b","r","r","r","r","r"],
}

# ── Lore inter-salles ────────────────────────────────────────────
const LORE_TEXTS = {
	1:  "L'air est humide. Mes bottes résonnent dans le silence. Je descends.",
	2:  "Ces créatures... elles étaient plus nombreuses que prévu. Je continue quand même.",
	3:  "Quelque chose remonte des profondeurs. Une odeur. Ancienne.",
	4:  "Mes mains tremblent légèrement. Je les ignore. La porte m'attend.",
	5:  "Ce monstre... il gardait cette porte. Pourquoi garder une porte ?",
	6:  "Plus bas. Toujours plus bas. La lumière du jour n'existe plus ici.",
	7:  "Je repense aux histoires qu'on racontait sur ce donjon. Je regrette de ne pas avoir écouté.",
	8:  "Ils se multiplient. Comme si le donjon lui-même voulait me repousser.",
	9:  "Je ne sais plus depuis combien de temps je descends. Le temps est différent ici.",
	10: "Ce gardien était plus fort. Beaucoup plus fort. Ce qui suit sera pire.",
	11: "Mes flèches s'épuisent. Heureusement quelque chose dans ce donjon me réapprovisionne. Je préfère ne pas savoir quoi.",
	12: "J'ai entendu une voix. Très loin en dessous. Elle semblait... m'attendre.",
	13: "Le sol vibre légèrement sous mes pieds. Quelque chose de gigantesque se déplace là-dessous.",
	14: "Je pourrais faire demi-tour. Cette pensée me traverse l'esprit à chaque salle. Je ne le ferai pas.",
	15: "Ce gardien rouge... ses yeux étaient intelligents. Il savait qui j'étais. Comment est-ce possible ?",
}

# ── Définitions des ennemis standards ───────────────────────────
const MONSTER_DEFS = {
	"g": {
		"name":               "Gobelin vert",
		"scene":              "res://scenes/monster_base.tscn",
		"behavior":           "standard",
		"hp":                 30,
		"damage":             12,
		"move_speed":         1,
		"xp_value":           25,
		"is_boss":            false,
		"tags":               [],
		"sprite_path":        "res://assets/characters/goblin_green.svg",
		# Comportement simple : attend quand bloqué, ne contourne pas
		"obstacle_behaviors": [ObstacleBehavior.WAIT],
		"palette": {
			"main": Color(0.25, 0.52, 0.14),
			"dark": Color(0.22, 0.48, 0.12),
			"nose": Color(0.18, 0.40, 0.10),
			"eye":  Color(0.85, 0.70, 0.05),
		},
	},
	"b": {
		"name":               "Gobelin bleu",
		"scene":              "res://scenes/monster_base.tscn",
		"behavior":           "standard",
		"hp":                 55,
		"damage":             20,
		"move_speed":         1,
		"xp_value":           50,
		"is_boss":            false,
		"tags":               [],
		"sprite_path":        "res://assets/characters/goblin_blue.svg",
		# Comportement rusé : essaie de contourner gauche puis droite avant d'attendre
		"obstacle_behaviors": [ObstacleBehavior.SIDESTEP_LEFT, ObstacleBehavior.SIDESTEP_RIGHT, ObstacleBehavior.WAIT],
		"palette": {
			"main": Color(0.18, 0.30, 0.78),
			"dark": Color(0.15, 0.25, 0.70),
			"nose": Color(0.12, 0.22, 0.60),
			"eye":  Color(0.90, 0.90, 0.10),
		},
	},
	"r": {
		"name":               "Gobelin rouge",
		"scene":              "res://scenes/monster_base.tscn",
		"behavior":           "standard",
		"hp":                 90,
		"damage":             30,
		"move_speed":         2,
		"xp_value":           100,
		"is_boss":            false,
		"tags":               [],
		"sprite_path":        "res://assets/characters/goblin_red.svg",
		# Comportement agressif : contourne aléatoirement, saute si impossible, sinon attend
		"obstacle_behaviors": [ObstacleBehavior.SIDESTEP_RANDOM, ObstacleBehavior.JUMP_OBSTACLE, ObstacleBehavior.WAIT],
		"palette": {
			"main": Color(0.80, 0.12, 0.08),
			"dark": Color(0.72, 0.10, 0.08),
			"nose": Color(0.60, 0.08, 0.06),
			"eye":  Color(1.00, 0.55, 0.05),
		},
	},
	# ── Boss (monster_type = type de base pour couleur/records) ─────
	# Les stats des salles >15 sont scalées à l'instantiation dans game_enemies.gd
	"boss_g": {
		"name":               "Boss Gobelin vert",
		"scene":              "res://scenes/monster_boss.tscn",
		"behavior":           "boss",
		"hp":                 300,
		"damage":             25,
		"move_speed":         1,
		"xp_value":           500,
		"is_boss":            true,
		"monster_type":       "g",
		"tags":               ["boss"],
		"sprite_path":        "res://assets/characters/boss_green.svg",
		# Les boss tiennent leur lane, ne se déplacent pas latéralement
		"obstacle_behaviors": [ObstacleBehavior.WAIT],
		"palette": {
			"main": Color(0.25, 0.52, 0.14),
			"dark": Color(0.22, 0.48, 0.12),
			"nose": Color(0.18, 0.40, 0.10),
			"eye":  Color(0.85, 0.70, 0.05),
		},
	},
	"boss_b": {
		"name":               "Boss Gobelin bleu",
		"scene":              "res://scenes/monster_boss.tscn",
		"behavior":           "boss",
		"hp":                 600,
		"damage":             40,
		"move_speed":         1,
		"xp_value":           1000,
		"is_boss":            true,
		"monster_type":       "b",
		"tags":               ["boss"],
		"sprite_path":        "res://assets/characters/boss_blue.svg",
		"obstacle_behaviors": [ObstacleBehavior.WAIT],
		"palette": {
			"main": Color(0.22, 0.35, 0.75),
			"dark": Color(0.18, 0.30, 0.68),
			"nose": Color(0.15, 0.25, 0.60),
			"eye":  Color(0.90, 0.90, 0.10),
		},
	},
	"boss_r": {
		"name":               "Boss Gobelin rouge",
		"scene":              "res://scenes/monster_boss.tscn",
		"behavior":           "boss",
		"hp":                 1000,
		"damage":             60,
		"move_speed":         2,
		"xp_value":           2000,
		"is_boss":            true,
		"monster_type":       "r",
		"tags":               ["boss"],
		"sprite_path":        "res://assets/characters/boss_red.svg",
		"obstacle_behaviors": [ObstacleBehavior.WAIT],
		"palette": {
			"main": Color(0.75, 0.18, 0.12),
			"dark": Color(0.68, 0.15, 0.10),
			"nose": Color(0.58, 0.12, 0.08),
			"eye":  Color(1.00, 0.55, 0.05),
		},
	},
}

# ── Définitions des armes ────────────────────────────────────────
const WEAPON_DEFS = {
	"arc":        {"name": "Arc",        "base_dmg": 25, "cd": 1.0,  "desc": "1 ennemi dans la file active",       "icon": "🏹", "icon_path": "res://assets/weapons/arc.png"},
	"arbalete":   {"name": "Arbalète",   "base_dmg": 55, "cd": 2.0,  "desc": "Perce 2 ennemis dans la file",       "icon": "🎯", "icon_path": "res://assets/weapons/arbalete.png"},
	"dague":      {"name": "Dague",      "base_dmg": 10, "cd": 0.35, "desc": "Très rapide, file active",           "icon": "🗡️", "icon_path": "res://assets/weapons/dague.png"},
	"bombe":      {"name": "Bombe",      "base_dmg": 20, "cd": 2.5,  "desc": "Explose sur 3 files voisines",       "icon": "💣", "icon_path": "res://assets/weapons/bombe.png"},
	"eclair":     {"name": "Eclair",     "base_dmg": 16, "cd": 1.5,  "desc": "Frappe tous les ennemis de la file", "icon": "⚡", "icon_path": "res://assets/weapons/eclair.png"},
	"tourbillon": {"name": "Tourbillon", "base_dmg": 12, "cd": 2.0,  "desc": "1ère rangée de chaque file",         "icon": "🌀", "icon_path": "res://assets/weapons/tourbillon.png"},
	"givre":      {"name": "Givre",      "base_dmg": 8,  "cd": 1.5,  "desc": "Ralentit l'ennemi 2s + dégâts",      "icon": "❄️", "icon_path": "res://assets/weapons/givre.png"},
	"sismique":   {"name": "Sismique",   "base_dmg": 9,  "cd": 3.0,  "desc": "2 dernières rangées, toutes files",  "icon": "🪨", "icon_path": "res://assets/weapons/sismique.png"},
}
