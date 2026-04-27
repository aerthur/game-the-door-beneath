# The Door Beneath — Contexte pour agents Claude Code

## Présentation du projet
Jeu roguelite en lanes développé avec **Godot 4.6** et **GDScript 2.0**.
- Moteur : Godot 4.6 (standard, pas .NET)
- Résolution : 1280×720
- Language : GDScript 2.0

Archer en bas, 5 files verticales, monstres qui descendent tick par tick.
Scène de démarrage : `title_screen.tscn` → lance `main.tscn` au clic "Nouvelle partie".

---

## Structure des fichiers

```
game-the-door-beneath/
├── project.godot
├── CLAUDE.md
├── scenes/
│   ├── title_screen.tscn       ← scène principale au démarrage (menu + meilleurs scores)
│   ├── main.tscn               ← scène de jeu (lancée depuis title_screen)
│   ├── player.tscn             ← archer joueur (Node2D + polygones)
│   ├── monster_base.tscn       ← scène réutilisable pour tous les gobelins (palette appliquée au runtime)
│   ├── monster_boss.tscn       ← boss (2× visuel, couronne, barre de vie)
│   ├── gem.tscn                ← gemme XP (Polygon2D diamond)
│   └── ui/
│       └── hud.tscn            ← CanvasLayer UI (HP, XP, armes, level-up, game over)
└── scripts/
    ├── obstacle_data.gd        ← class_name ObstacleData (structure de données obstacles)
    ├── title_screen.gd         ← menu principal + affichage meilleurs scores
    ├── game.gd                 ← coordinateur principal (état, tick, room)
    ├── game_constants.gd       ← class_name GameData (ROOM_WAVES, WEAPON_DEFS, MONSTER_DEFS, LORE_TEXTS)
    ├── board_geometry.gd       ← class_name BoardGeometry (géométrie grille 5×8, helpers statiques)
    ├── board_state.gd          ← class_name BoardState (occupation de la grille, source de vérité)
    ├── monster.gd              ← class_name Monster (classe de base de tous les monstres)
    ├── game_enemies.gd         ← spawn, placement, retraite des ennemis ($Enemies)
    ├── game_player.gd          ← état/input joueur ($PlayerCtrl)
    ├── game_weapons.gd         ← logique de tir des 8 armes ($Weapons)
    ├── game_visuals.gd         ← animations et effets ($Visuals)
    ├── game_records.gd         ← records persistants JSON ($Records)
    ├── hud.gd                  ← logique HUD
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
enemies.board_state = board_state
weapons.board_state = board_state
weapons.visuals = visuals
weapons.deal_fn = _deal_and_check
player_ctrl.weapons_ref = weapons
records_ctrl.hud = hud
```

### GameData — constantes partagées

`game_constants.gd` déclare `class_name GameData`. Accessible via `GameData.X` depuis n'importe quel script :

```gdscript
GameData.ROOM_WAVES    # Dict salle → liste types monstres
GameData.WEAPON_DEFS   # Dict id → {name, base_dmg, cd, desc, icon}
GameData.MONSTER_DEFS  # Dict id → def complète (hp, damage, scene, palette, …)
GameData.LORE_TEXTS    # Dict salle → texte lore (salles 1–15)
```

> ⚠️ Les constantes de géométrie (`LANES`, `ROWS`, `LANE_W`, etc.) ont été **migrées dans `BoardGeometry`**. Ne plus les chercher dans `GameData`.

### BoardState — occupation de la grille

`board_state.gd` déclare `class_name BoardState` (extends RefCounted). Source de vérité unique pour l'occupation des cellules 5×8. Instanciée dans `game.gd` et partagée avec `game_enemies.gd` et `game_weapons.gd` via `board_state`.

Deux couches indépendantes : occupants (`_cells`) et obstacles (`_obstacles`). Un seul occupant principal par cellule (Node2D ou null).

```gdscript
# Occupants
board_state.clear_all()                          # réinitialise occupants ET obstacles
board_state.is_cell_free(row, col) -> bool
board_state.is_cell_occupied(row, col) -> bool
board_state.set_cell_occupied(row, col, occupant)
board_state.clear_cell(row, col)
board_state.get_cell_occupant(row, col)          # retourne Node2D ou null
board_state.is_grid_empty() -> bool

# Obstacles
board_state.has_obstacle(row, col) -> bool
board_state.get_obstacle(row, col) -> ObstacleData
board_state.set_obstacle(row, col, obstacle_data)
board_state.clear_obstacle(row, col)
board_state.clear_obstacles()
board_state.is_cell_blocked(row, col) -> bool    # true si obstacle bloque mouvement/occupation
```

> Toute modification d'occupation (spawn, déplacement, mort, retraite boss) doit passer par `board_state`. Ne jamais modifier directement `_cells` ou `_obstacles`.
> Toujours mettre à jour `board_state` ET `m.grid_row` / `m.grid_lane` ensemble lors d'un déplacement.
> Le code de déplacement (`_do_tick`) et de spawn (`game_enemies`) vérifie `is_cell_blocked()` en plus de `is_cell_free()`.

### ObstacleData — structure de données d'obstacle

`obstacle_data.gd` déclare `class_name ObstacleData` (extends RefCounted). Décrit un obstacle sur une cellule. Conçu pour distinguer plusieurs familles sans se limiter à un booléen.

| Champ | Type | Valeur par défaut | Rôle |
|---|---|---|---|
| `kind` | String | `"wall"` | Identifiant sémantique de l'obstacle |
| `blocks_movement` | bool | `true` | Empêche un monstre de traverser la cellule |
| `blocks_occupancy` | bool | `true` | Empêche tout spawn/placement sur la cellule |
| `blocks_los` | bool | `false` | Bloque la ligne de vue (non exploité pour le moment) |
| `destructibility` | String | `"indestructible"` | `"indestructible"` ou `"destructible"` |
| `hp` / `max_hp` | int | `-1` | Points de vie si destructible (-1 = non applicable) |

Factory disponible : `ObstacleData.make_wall()` → mur indestructible bloquant tout.

**Obstacles de test** : `game.gd._setup_test_obstacles()` place deux murs en (row=3, col=1) et (row=3, col=3). Rendu visuel dans `_draw_obstacles()` (overlay ColorRect sur le `$Background`).

### BoardGeometry — géométrie de la grille

`board_geometry.gd` déclare `class_name BoardGeometry`. Constantes et helpers statiques pour la grille 5×8 :

```gdscript
BoardGeometry.GRID_COLUMNS   # 5
BoardGeometry.GRID_ROWS      # 8
BoardGeometry.CELL_WIDTH     # 180
BoardGeometry.CELL_HEIGHT    # 68
BoardGeometry.GRID_ORIGIN_X  # 140  — (1280 - 5*180) / 2
BoardGeometry.GRID_ORIGIN_Y  # 30
BoardGeometry.PLAYER_Y       # 598  — bas de grille + 24

BoardGeometry.get_cell_center(row, col) -> Vector2
BoardGeometry.cell_to_world(row, col)   -> Vector2
BoardGeometry.world_to_cell(pos)        -> Vector2i
BoardGeometry.is_valid_cell(row, col)   -> bool
```

### Monster — classe de base

`monster.gd` déclare `class_name Monster` (extends Node2D). Tous les monstres en héritent.

Variables exposées : `hp`, `hp_max`, `damage`, `move_speed`, `frozen_ticks`, `xp_value`, `monster_type`, `is_boss`, `grid_row`, `grid_lane`, `behavior`, `palette`, `tags`.

API publique :
```gdscript
monster.setup_from_def(monster_id, def)  # initialise depuis MONSTER_DEFS
monster.take_damage(amount)              # réduit hp + flash rouge
monster.freeze(ticks)                    # gel + teinte bleue
monster.tick_freeze()                    # appelé à chaque tick (décrémente)
monster.on_tick()                        # hook comportement (override dans sous-classes)
monster.apply_palette(palette)           # applique les couleurs sur les Polygon2D
```

### Variables d'état (game.gd)

```gdscript
var player_hp          : int   # PV joueur courants
var player_max         : int   # PV joueur maximum (100 par défaut)
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
var active_weapons     : Array      # [{"id": "arc", "level": 1, "acc": 0.0}, ...]
var board_state        : BoardState # source de vérité pour l'occupation de la grille
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

L'occupation de la grille est gérée exclusivement par `board_state` (instance de `BoardState`).
- row 0 = haut de l'écran, row 7 = bas
- lane 0 = gauche, lane 4 = droite
- Toujours appeler `board_state.set_cell_occupied/clear_cell` ET mettre à jour `m.grid_row` / `m.grid_lane` ensemble

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

Tous les monstres standards utilisent `monster_base.tscn` + `class Monster`. Les stats et couleurs viennent de `GameData.MONSTER_DEFS`.

| id | Nom | HP | Dmg | Speed | XP |
|---|---|---|---|---|---|
| "g" | Gobelin vert | 30 | 12 | 1 | 25 |
| "b" | Gobelin bleu | 55 | 20 | 1 | 50 |
| "r" | Gobelin rouge | 90 | 30 | 2 | 100 |

`move_speed` = nombre de rangées parcourues par tick.

## Boss (toutes les 5 salles)

Les boss sont **data-driven** via `GameData.MONSTER_DEFS` (`boss_g`, `boss_b`, `boss_r`). `game_enemies.spawn_boss(room_num)` sélectionne l'id selon les seuils :

| Seuil | id | Nom | HP | Dmg | Speed | XP |
|---|---|---|---|---|---|---|
| room < 10 | "boss_g" | Boss Gobelin vert | 300 | 25 | 1 | 500 |
| room >= 10 | "boss_b" | Boss Gobelin bleu | 600 | 40 | 1 | 1000 |
| room >= 15 | "boss_r" | Boss Gobelin rouge | 1000 | 60 | 2 | 2000 |
| room > 15 | "boss_r" | (scalé) | ×1.5 / 5 salles | idem | 2 | ×1.5 / 5 salles |

Scaling : `pow(1.5, (room - 15) / 5)` appliqué à hp, damage, xp_value au moment du spawn (def dupliquée, MONSTER_DEFS inchangé).

- Spawne en lane 2 (index 2), row 0 — `monsters_remaining = 1`
- `monster_boss.gd` extends `Monster` — surcharge `setup_from_def()` (appel super) et `_on_damage_taken()` (update barre de vie)
- Retraite : soigné +30% HP max, remonte row 0 dans sa lane via `enemies.boss_retreat()`

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

## Architecture des archétypes et variantes (issue #54)

### Champs normalisés de MONSTER_DEFS

Chaque entrée de `GameData.MONSTER_DEFS` doit contenir :

| Champ | Type | Rôle |
|---|---|---|
| `name` | String | Nom affiché |
| `scene` | String (res://) | Scène instanciée par `game_enemies.gd` |
| `behavior` | String | Identifiant comportement ("standard", "boss", …) |
| `hp` | int | Points de vie |
| `damage` | int | Dégâts infligés |
| `move_speed` | int | Rangées par tick |
| `xp_value` | int | XP accordée au kill |
| `is_boss` | bool | Boss = true (spawner contextuel + retraite) |
| `tags` | Array[String] | Flags optionnels (ex: ["boss", "armored"]) |
| `palette` | Dictionary | Couleurs `main/dark/nose/eye` (appliquées par `monster.gd`) |
| `monster_type` | String (optionnel) | Type de base pour records (boss uniquement ; ex: boss_g → "g") |

Le spawn est **entièrement data-driven** : `game_enemies._get_scene(def["scene"])` charge et cache la scène automatiquement — aucun preload à ajouter dans `game_enemies.gd`.

### Point d'extension comportement

`Monster.on_tick()` est appelé à chaque tick de mouvement. Les comportements spéciaux surchargent cette méthode dans leur script GDScript.

```gdscript
# Dans scripts/monster_charge.gd (exemple futur)
extends Monster
func on_tick() -> void:
    move_speed += 1  # accélère chaque tick
```

`game.gd` devra appeler `m.on_tick()` dans `_do_tick()` pour activer le dispatch. Actuellement le hook existe mais n'est pas encore appelé — à brancher lors de l'implémentation du premier comportement spécial.

### Spawn contextuel (pensé pour le futur mode "en face du joueur")

`game_enemies.spawn_monster(monster_id, spawn_ctx)` accepte un contexte :

```gdscript
spawn_ctx = {
    "entry_side":  "top" | "bottom" | "left" | "right",
    "entry_index": int  # numéro de lane (top/bottom) ou rangée (left/right)
}
```

Ce système est conçu pour supporter un futur mode où les ennemis spawneraient en face du joueur ou depuis plusieurs bords simultanément, sans modifier l'API publique de spawn.

---

## Comment ajouter une feature typique

### Nouvelle arme (Mode Lanes)
1. Ajouter dans `GameData.WEAPON_DEFS` dans `game_constants.gd` (icon emoji + stats)
2. Ajouter un `case` dans `game_weapons.gd` → `fire()`
3. Implémenter `_w_nomArme(w: Dictionary)` dans `game_weapons.gd`
4. L'arme sera automatiquement proposable au level-up

### Ennemi standard (nouvelle couleur / stats)
1. Ajouter une entrée dans `GameData.MONSTER_DEFS` (`game_constants.gd`) avec les champs normalisés
2. Pointer `"scene"` vers `"res://scenes/monster_base.tscn"` (scène réutilisable)
3. Définir la `"palette"` (main/dark/nose/eye) pour la couleur
4. Ajouter la clé dans `GameData.ROOM_WAVES` pour les salles concernées
5. Aucune modification de code dans `game_enemies.gd`

### Nouvelle variante visuelle (nouvelle scène)
1. Créer `scenes/monster_XXX.tscn` avec un script héritant `Monster` (ou `monster_boss.gd`)
2. Le script n'a besoin de surcharger que ce qui diffère (ex: `_ready` pour ajouter des nœuds visuels)
3. Pointer `"scene": "res://scenes/monster_XXX.tscn"` dans `MONSTER_DEFS`
4. `game_enemies._get_scene()` chargera et cachera la scène automatiquement

### Nouveau boss
1. Ajouter une entrée `"boss_XXX"` dans `MONSTER_DEFS` avec `"is_boss": true`, `"tags": ["boss"]`, `"scene": "res://scenes/monster_boss.tscn"`, `"monster_type": "X"` et une `"palette"` (la couleur de la barre de vie est `palette["main"]`)
2. Mettre à jour les seuils dans `game_enemies.spawn_boss()` pour inclure le nouveau boss
3. La barre de vie et la couronne sont créées automatiquement par `monster_boss.gd` (extends Monster) via la palette — aucun code supplémentaire

### Comportement spécial futur
1. Créer `scripts/monster_behavior_XXX.gd` (extends Monster)
2. Surcharger `on_tick()` avec la logique spéciale
3. Créer une scène `scenes/monster_XXX.tscn` utilisant ce script
4. Brancher `m.on_tick()` dans `game.gd._do_tick()` si ce n'est pas encore fait
5. Pointer `"behavior": "XXX"` dans `MONSTER_DEFS` (informatif, le dispatch est par héritage)

### Nouvelle mécanique de jeu
- Logique de tick/état → `game.gd`
- Spawn/placement ennemis → `game_enemies.gd`
- Input/état joueur → `game_player.gd`
- Armes → `game_weapons.gd`
- Visuels → `game_visuals.gd`
- Records → `game_records.gd`
- Constantes → `game_constants.gd` (GameData)
