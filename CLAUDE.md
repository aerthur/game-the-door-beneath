# The Door Beneath — Contexte pour agents Claude Code

## Présentation du projet
Jeu roguelite en lanes développé avec **Godot 4.6** et **GDScript 2.0**.
- Moteur : Godot 4.6 (standard, pas .NET)
- Résolution : 1280×720
- Language : GDScript 2.0

Archer en bas, 5 files verticales, monstres qui descendent tick par tick.
Scène principale : `main.tscn` (anciennement `game.tscn`).

---

## Structure des fichiers

```
game-the-door-beneath/
├── project.godot
├── CLAUDE.md
├── scenes/
│   ├── main.tscn               ← scène mode Lanes (instancie tout)
│   ├── dungeon.tscn            ← scène mode Donjon
│   ├── player.tscn             ← archer mode Lanes (Node2D)
│   ├── monster_blob.tscn       ← gobelin vert
│   ├── monster_blue.tscn       ← gobelin bleu
│   ├── monster_red.tscn        ← gobelin rouge
│   ├── monster_boss.tscn       ← boss (2× visuel, couronne, barre de vie)
│   ├── gem.tscn                ← gemme XP (Polygon2D diamond)
│   ├── enemy_slime.tscn        ← slime mode Donjon
│   ├── item_potion.tscn        ← potion (soigne 30 HP)
│   ├── item_stairs.tscn        ← escaliers (signal next_floor_reached)
│   └── ui/
│       └── hud.tscn            ← CanvasLayer UI (HP, XP, armes, level-up)
└── scripts/
    ├── game.gd                 ← coordinateur principal (état, tick, room)
    ├── game_constants.gd       ← class_name GameData (constantes, ROOM_WAVES, WEAPON_DEFS, LORE_TEXTS)
    ├── game_enemies.gd         ← spawn, placement, retraite des ennemis ($Enemies)
    ├── game_player.gd          ← état/input joueur ($PlayerCtrl)
    ├── game_weapons.gd         ← logique de tir des 8 armes ($Weapons)
    ├── game_visuals.gd         ← animations et effets ($Visuals)
    ├── game_records.gd         ← records persistants JSON ($Records)
    ├── hud.gd                  ← logique HUD
    ├── monster_blob.gd         ← stats gobelin vert
    ├── monster_blue.gd         ← stats gobelin bleu
    ├── monster_red.gd          ← stats gobelin rouge
    ├── monster_boss.gd         ← boss (is_boss=true, hp_max, barre de vie)
    └── gem.gd                  ← gemme XP
```

---

## Architecture Mode Lanes

### game.gd — coordinateur

`game.gd` est un **nœud coordinateur** (extends Node). Il instancie et câble les sous-systèmes via `@onready` :

```gdscript
@onready var monsters_node  : Node2D      = $Monsters
@onready var player_node    : Node2D      = $Player
@onready var hud            : CanvasLayer = $HUD
@onready var bg             : Node2D      = $Background
@onready var visuals        : Node2D      = $Visuals       # game_visuals.gd
@onready var enemies        : Node2D      = $Enemies       # game_enemies.gd
@onready var weapons        : Node2D      = $Weapons       # game_weapons.gd
@onready var player_ctrl    : Node2D      = $PlayerCtrl    # game_player.gd
@onready var records_ctrl   : Node2D      = $Records       # game_records.gd
```

Dans `_ready()`, game.gd passe ses références aux sous-systèmes :
```gdscript
enemies.grid = grid
weapons.grid = grid
weapons.visuals = visuals
weapons.deal_fn = _deal_and_check
player_ctrl.weapons_ref = weapons
records_ctrl.hud = hud
```

### GameData — constantes partagées

`game_constants.gd` déclare `class_name GameData`. Toutes les constantes sont accessibles via `GameData.X` depuis n'importe quel script :

```gdscript
GameData.LANES    # 5
GameData.ROWS     # 8
GameData.LANE_W   # 180
GameData.ROW_H    # 68
GameData.GRID_X   # (1280 - LANES * LANE_W) / 2
GameData.GRID_Y   # 30
GameData.PLAYER_Y # GRID_Y + ROWS * ROW_H + 24
GameData.ROOM_WAVES    # Dict salle → liste types monstres
GameData.WEAPON_DEFS   # Dict id → {name, base_dmg, cd, desc, icon}
GameData.LORE_TEXTS    # Dict salle → texte lore (salles 1–15)
```

### Variables d'état (game.gd)

```gdscript
var player_hp          : int   # PV joueur (max 100)
var room_num           : int   # salle actuelle (1–10+)
var gold_current       : int   # or disponible (affiché dans HUD)
var gold_total_earned  : int   # or total gagné depuis le début de la run
var gold_spent         : int   # or dépensé
var xp                 : int
var xp_needed          : int   # 60 par défaut
var hero_level         : int
var monsters_remaining : int   # kills restants
var spawns_in_flight   : int   # coroutines _on_monster_escaped en cours
var room_clear         : bool
var game_over          : bool
var leveling_up        : bool
var active_weapons     : Array # [{"id": "arc", "level": 1, "acc": 0.0}, ...]
var grid               : Array # grid[row][lane] = monstre Node2D ou null
```

### Fonctions importantes (game.gd)

- `_start_room(num)` — démarre une salle ; appelle `enemies.spawn_boss()` si room_num % 5 == 0
- `_do_tick()` — déplace tous les monstres d'une rangée vers le bas
- `_on_monster_escaped(lane, mtype)` — monstre arrivé en bas → duplique (async)
- `_on_monster_killed(lane, pos, xp, mtype)` — kill confirmé, ajoute l'or, décrémente compteur
- `_add_gold(amount)` — ajoute de l'or et met à jour le HUD
- `_check_room_clear()` — vérifie si grille vide + aucun spawn en vol → clear
- `_deal_and_check(m, row, lane, dmg)` — applique dégâts, vérifie mort
- `apply_level_up_choice(choice)` — appelée par hud.gd quand le joueur choisit
- `_play_door_animation()` — anime la porte + lore + XP (async)
- `_show_lore_text(rnum)` — affiche la pensée du héros (async, concurrent)

### Grille

`grid[row][lane]` contient le Node2D du monstre ou `null`.
- row 0 = haut de l'écran, row 7 = bas
- lane 0 = gauche, lane 4 = droite
- Toujours mettre à jour `grid[row][lane]` ET `m.grid_row` / `m.grid_lane` ensemble

### Room clear (important — bug précédemment corrigé)

La salle est terminée quand `_grid_empty() == true AND spawns_in_flight == 0`.
Ne pas se fier uniquement à `monsters_remaining` (peut dériver avec les coroutines async).

---

## Systèmes

### Système d'or (issue #29)

Parallèle à l'XP. Variables dans `game.gd` : `gold_current`, `gold_total_earned`, `gold_spent`.
- Ajouté via `_add_gold(amount)` à chaque kill
- Bonus de fin de salle via `_get_room_gold_bonus(room)`
- Affiché dans le HUD

### Système de records (issue #27)

Géré par `game_records.gd` (`$Records`). Sauvegarde en **JSON** (`user://records.json`).

API publique :
```gdscript
records_ctrl.load_records()
records_ctrl.init_run_stats()
records_ctrl.on_kill(mtype, wid)           # appelé à chaque kill
records_ctrl.on_game_over(room, gold, lvl) # appelé au game over
```

Records persistants : `best_room`, `best_gold`, `best_level`, `best_time`, `total_runs`.

### Lore inter-salles (issue #26)

`GameData.LORE_TEXTS` mappe salle → texte (salles 1–15).
Pendant `_play_door_animation()`, `_show_lore_text(room_num)` tourne en coroutine concurrente.
Timing : fade in 0.3s → affiché 2.5s → fade out 0.3s = 3.1s total.
Visuel : `RichTextLabel` BBCode `[center][i]...[/i][/center]`, fond `ColorRect` semi-transparent.

### Icônes armes (issue #9)

Chaque arme dans `GameData.WEAPON_DEFS` a un champ `"icon"` (emoji) et `"icon_path"` (texture).
Affichées dans le panel armes du HUD. L'icône ⚜️ survit aux updates de la liste.

### Animation de porte + XP fin de salle (issue #20)

`_play_door_animation()` anime la porte, affiche le lore, distribue l'XP jackpot.
`room_clear = true` n'est mis à jour qu'après la fin de l'animation.

---

## Les 8 armes (Mode Lanes)

| id | Nom | Dégâts base | CD | Comportement |
|---|---|---|---|---|
| arc | Arc 🏹 | 25 | 1.0s | 1 ennemi dans la file active |
| arbalete | Arbalète 🎯 | 55 | 2.0s | Perce 2 ennemis dans la file |
| dague | Dague 🗡️ | 10 | 0.35s | Très rapide, file active |
| bombe | Bombe 💣 | 20 | 2.5s | 3 files voisines |
| eclair | Eclair ⚡ | 16 | 1.5s | Tous les ennemis de la file |
| tourbillon | Tourbillon 🌀 | 12 | 2.0s | 1ère rangée de chaque file |
| givre | Givre ❄️ | 8 | 1.5s | Ralentit 2 ticks + dégâts |
| sismique | Sismique 🪨 | 9 | 3.0s | 2 dernières rangées, toutes files |

Dégâts scalent : `base_dmg * (1.0 + (level - 1) * 0.5)`
Max 4 armes actives simultanément.

## Monstres (Mode Lanes)

| type | monster_type | hp | dmg | speed | xp |
|---|---|---|---|---|---|
| Gobelin vert | "g" | 30 | 12 | 1 | 25 |
| Gobelin bleu | "b" | 55 | 20 | 1 | 50 |
| Gobelin rouge | "r" | 90 | 30 | 2 | 100 |

`move_speed` = nombre de rangées parcourues par tick.

## Boss (toutes les 5 salles)

| Salle | Type | HP | Dmg | Speed | XP |
|---|---|---|---|---|---|
| 5 | "g" | 300 | 25 | 1 | 500 |
| 10 | "b" | 600 | 40 | 1 | 1000 |
| 15 | "r" | 1000 | 60 | 2 | 2000 |
| 20+ | "r" | ×1.5/tranche | ×1.5/tranche | 2 | ×1.5/tranche |

- Spawne en lane 2, row 0 (`monsters_remaining = 1`)
- Échappement : inflige dmg sur lanes ±1 (clampé), remonte row 0 soigné +30% HP max

---

## Conventions de code

- GDScript 2.0 — utiliser `func name() -> Type:` pour les retours typés
- Toujours vérifier `is_instance_valid(node)` avant d'accéder à un Node après un `await`
- Les visuels (flèches, explosions) sont créés dans `game_visuals.gd`, ajoutés à `$Background`
- Les monstres sont sous `$Monsters` (Node2D)
- Le HUD est `$HUD` (CanvasLayer) — interagir via `hud.update_*()` et `hud.show_*()`
- Les constantes globales passent toujours par `GameData.X` (jamais redéfinies localement)

## Inputs mappés (project.godot)

- `lane_left` → flèche gauche
- `lane_right` → flèche droite
- `next_room` → ESPACE

## Taille de référence des gobelins (issue #4)

Tous les gobelins partagent la même géométrie (monster_blob.tscn). Seule la couleur change.
- Head : offset_left=-18, offset_top=-28, offset_right=18, offset_bottom=2
- Body : offset_left=-14, offset_top=-2, offset_right=14, offset_bottom=22
- Ears : width=10, top=-32, bottom=-16 (gauche: left=-26/right=-16 ; droite: left=16/right=26)
- ArmLeft : offset_left=-26, offset_top=2, offset_right=-14, offset_bottom=16
- ArmRight : offset_left=14, offset_top=2, offset_right=26, offset_bottom=16

---

## Comment ajouter une feature typique

### Nouvelle arme (Mode Lanes)
1. Ajouter dans `GameData.WEAPON_DEFS` dans `game_constants.gd` (icon emoji + stats)
2. Ajouter un `case` dans `game_weapons.gd` → `fire()`
3. Implémenter `_w_nomArme(w: Dictionary)` dans `game_weapons.gd`
4. L'arme sera automatiquement proposable au level-up

### Nouveau type de monstre (Mode Lanes)
1. Créer `scripts/monster_XXX.gd` (copier monster_blob.gd, changer stats et monster_type)
2. Créer `scenes/monster_XXX.tscn` (Node2D + script + visuel)
3. Preload dans `game_enemies.gd`, ajouter le case dans `_spawn_monster()`
4. Ajouter dans `GameData.ROOM_WAVES` si nécessaire

### Nouvelle mécanique de jeu
- Logique de tick/état → `game.gd`
- Spawn/placement ennemis → `game_enemies.gd`
- Input/état joueur → `game_player.gd`
- Armes → `game_weapons.gd`
- Visuels → `game_visuals.gd`
- Records → `game_records.gd`
- Constantes → `game_constants.gd` (GameData)
