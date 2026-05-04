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
├── .gutconfig.json             ← configuration GUT CLI (dossiers, options)
├── export_presets.cfg          ← preset d'export Godot (Web/HTML5)
├── .github/
│   └── workflows/
│       ├── gut-tests.yml       ← CI GitHub Actions (GUT sur tous push/PR)
│       └── html5-preview.yml   ← export HTML5 + déploiement preview par PR
├── addons/
│   └── gut/                    ← framework de tests GUT v9.6.0 (versionné dans le repo)
├── test/
│   └── unit/                   ← tests unitaires GUT (prefixe test_, suffixe .gd)
│       ├── test_board_geometry.gd    ← template de test (à dupliquer pour nouvelles features)
│       ├── test_board_state.gd       ← occupation de cellules, obstacles, is_grid_empty
│       ├── test_obstacle_data.gd     ← factory make_wall, obstacles destructibles, blocage
│       ├── test_monster_stats.gd     ← constantes GameData, conversion ticks, scaling boss
│       ├── test_spawn_fallback.gd    ← _resolve_spawn_ctx, find_spawn_lane, retry/fallback
│       └── test_monster_behaviors.gd ← ObstacleBehavior.resolve(), wait/sidestep, priorité, déterminisme
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
    ├── obstacle_behavior.gd    ← class_name ObstacleBehavior (résolveur pur de comportements d'obstacle)
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
GameData.TICKS_PER_SECOND  # 12 — cadence fixe de la simulation
GameData.ROOM_WAVES    # Dict salle → liste types monstres
GameData.WEAPON_DEFS   # Dict id → {name, base_dmg, cd, desc, icon}
GameData.MONSTER_DEFS  # Dict id → def complète (hp, damage, scene, palette, …)
GameData.LORE_TEXTS    # Dict salle → texte lore (salles 1–15)
```

> ⚠️ Les constantes de géométrie (`LANES`, `ROWS`, `LANE_W`, etc.) ont été **migrées dans `BoardGeometry`**. Ne plus les chercher dans `GameData`.

### Système de tick — simulation fixe à 12 tps (issue #68)

La simulation s'exécute à **12 ticks par seconde** (cadence fixe). Toutes les mécaniques temporelles (déplacement, statuts) s'expriment en **ticks**, pas en secondes.

**Cadence et conversions :**

| Durée | Ticks |
|---|---|
| 1 tick ≈ 83 ms | 1 |
| 0,25 s | 3 |
| 0,5 s | 6 |
| 1 s | 12 |
| 2 s | 24 |

`GameData.TICKS_PER_SECOND = 12` est la constante de référence.

**Boucle dans `game.gd._process()`** : accumulation du delta dans `tick_acc`, puis boucle `while` qui décrémente `tick_acc -= tick_interval` et appelle `_do_tick()`. Plusieurs ticks peuvent s'exécuter par frame pour rattraper le temps réel.

**Déplacement des monstres :**

Chaque `Monster` porte deux champs :
- `move_period_ticks` — nombre de ticks entre deux déplacements (calculé depuis `move_speed` via `TICKS_PER_SECOND / move_speed`)
- `move_countdown_ticks` — décompte décrémenté à chaque tick ; quand il atteint 0, le monstre se déplace et le compteur se recharge à `move_period_ticks`

| `move_speed` | `move_period_ticks` | Rythme effectif |
|---|---|---|
| 1 | 12 | 1 case/s |
| 2 | 6 | 2 cases/s |

**Gel (freeze) :**

`frozen_ticks` exprime le gel en ticks (12 ticks = 1 s). `tick_freeze()` est appelé à **chaque tick** (pas seulement sur tentative de déplacement). Exemple : givre → `freeze(24)` = 2 s.

**Règles de priorité :**
- `tick_freeze()` est appelé en premier ; si gelé, le monstre ne bouge pas et `move_countdown_ticks` n'est pas décrémenté.
- L'itération se fait du bas vers le haut (`GRID_ROWS-1` → `0`) pour éviter qu'un monstre qui vient de descendre soit traité deux fois dans le même tick.

**Points d'extension :**

Pour ajouter une nouvelle vitesse (ex. `move_speed = 3` → `move_period_ticks = 4`), il suffit d'ajouter l'entrée dans `MONSTER_DEFS` ; la conversion est automatique dans `Monster.setup_from_def()`. Les futurs cooldowns d'actions, délais de comportement ou durées de statuts doivent tous s'exprimer en ticks en utilisant `GameData.TICKS_PER_SECOND` comme référence.

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

### Comportements de résolution d'obstacle (issue #72)

Quand un monstre tente d'avancer vers `new_row = r + 1` mais que la cellule est bloquée ou occupée, il choisit une action parmi ses **comportements autorisés** définis dans `MONSTER_DEFS["obstacle_behaviors"]`.

**Priorité** : l'avancée directe est toujours tentée en premier. Si elle réussit, aucun comportement d'obstacle n'est consulté.

**Résolveur** : `ObstacleBehavior.resolve(behaviors, row, lane, board_state, rng_seed)` — fonction statique pure, testable sans scène. Retourne `{"action": "wait"}` ou `{"action": "move", "row": r, "lane": l}`.

**Comportements supportés** :

| Identifiant | Constante | Comportement |
|---|---|---|
| `"wait"` | `ObstacleBehavior.WAIT` | Reste en place ce tick |
| `"sidestep_left"` | `ObstacleBehavior.SIDESTEP_LEFT` | Se déplace latéralement vers `lane - 1` (même rangée) |
| `"sidestep_right"` | `ObstacleBehavior.SIDESTEP_RIGHT` | Se déplace latéralement vers `lane + 1` (même rangée) |
| `"sidestep_random"` | `ObstacleBehavior.SIDESTEP_RANDOM` | Choisit gauche ou droite selon `rng_seed % 2` (déterministe) |
| `"jump_obstacle"` | `ObstacleBehavior.JUMP_OBSTACLE` | **Réservé** — logique multi-ticks à concevoir |
| `"destroy_obstacle"` | `ObstacleBehavior.DESTROY_OBSTACLE` | **Réservé** — requiert obstacle destructible actif |

**Règles de sélection** : le premier comportement de la liste dont la cellule cible est valide est retenu. Si aucun comportement n'est valide (ou si la liste est vide), l'action est `"wait"`.

**Règle d'échec** : si la cible d'un sidestep est occupée ou bloquée au moment du test, le comportement est invalide pour ce tick. Le monstre réévaluera au tick suivant.

**Anti-double-mouvement** : `game.gd._do_tick()` maintient un dictionnaire `moved_this_tick` qui empêche un monstre ayant sidestepped (vers une lane non encore traitée) d'être traité une deuxième fois dans le même tick.

**rng_seed déterministe** : calculé comme `row * GRID_COLUMNS + lane` — un monstre à la même position produit toujours le même choix, compatible simulation 12 tps.

**Profils par monstre dans MONSTER_DEFS** :

| Monstre | `obstacle_behaviors` | Raisonnement |
|---|---|---|
| Gobelin vert (`"g"`) | `[WAIT]` | Simple, reste bloqué |
| Gobelin bleu (`"b"`) | `[SIDESTEP_LEFT, SIDESTEP_RIGHT, WAIT]` | Rusé, essaie les deux côtés |
| Gobelin rouge (`"r"`) | `[SIDESTEP_RANDOM, WAIT]` | Agressif, contourne aléatoirement |
| Boss (`"boss_*"`) | `[WAIT]` | Tient sa lane, ne se déplace pas latéralement |

**Fichiers concernés** :
- `scripts/obstacle_behavior.gd` — résolveur pur (`class_name ObstacleBehavior`)
- `scripts/game_constants.gd` — champ `obstacle_behaviors` dans chaque entrée de `MONSTER_DEFS`
- `scripts/monster.gd` — variable `obstacle_behaviors`, chargée dans `setup_from_def()`
- `scripts/game.gd` — intégration dans `_do_tick()` + `moved_this_tick`
- `test/unit/test_monster_behaviors.gd` — tests unitaires GUT

### Politique de respawn prioritaire (issue #70)

Quand un monstre quitte la grille par le bas, `game.gd._on_monster_escaped()` tente de le respawn sur sa **file d'origine** (lane d'où il est sorti). Si la cellule d'entrée (row 0) est temporairement occupée ou bloquée, le système ne bascule **pas** immédiatement vers une file adjacente.

**Cycle de retry :**
1. Tentative immédiate sur la file d'origine uniquement (`enemies.try_spawn_preferred`)
2. Si échec → création d'un **respawn en attente** (`enemies.queue_respawn`)
3. À chaque tick suivant : retry automatique via `enemies.tick_pending_respawns()`
4. Dès que la cellule d'entrée devient libre dans la fenêtre → spawn sur la file d'origine
5. Après **12 ticks** (1 seconde à 12 tps) sans succès → fallback vers les files adjacentes (ordre déterministe : offsets `[+1, -1, +2, -2, ...]`)
6. Si aucune file adjacente valide → abandon (décrémentation de `monsters_remaining`)

**Décision via `get_respawn_lane(preferred, ticks_waited, max_ticks)`** — méthode pure, testable sans scène. Retourne `lane >= 0`, `RESPAWN_KEEP_WAITING (-1)`, ou `RESPAWN_GIVE_UP (-2)`.

`tick_pending_respawns()` retourne des **actions** (`{action, mtype, lane?, preferred_lane}`) sans spawner de scène — `game.gd._execute_respawn_results()` les exécute. Cela maintient la séparation logique/visuel et permet les tests unitaires.

**`spawns_in_flight`** reste incrémenté pendant toute la durée d'un respawn en attente, empêchant un room-clear prématuré.

Tests : `test/unit/test_spawn_fallback.gd` — sections `get_respawn_lane` et `tick_pending_respawns`.

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

## Support mobile / web (issue #91)

Le jeu supporte une expérience tactile sur navigateur mobile en **orientation paysage uniquement**.

### Orientation
- `project.godot` force `window/handheld/orientation = "landscape"` sur mobile.
- En portrait, `hud.gd` détecte automatiquement via `get_viewport().size_changed` et affiche un overlay plein écran invitant à tourner l'appareil. Aucune expérience de jeu n'est proposée en portrait.

### Contrôles tactiles
Trois boutons sont intégrés en bas de l'écran dans `hud.tscn` (`TouchButtons`), au-dessus de la zone XP :
- **BtnLeft** (bas-gauche, 160×120 px) — déplacement à gauche
- **BtnRight** (bas-droit, 160×120 px) — déplacement à droite
- **BtnNextRoom** (centre-bas, 300×74 px) — passage à la salle suivante (visible uniquement quand la salle est vidée)

### Architecture d'input unifiée
Les boutons tactiles réutilisent les **actions Godot canoniques** (`lane_left`, `lane_right`, `next_room`) via `Input.parse_input_event(InputEventAction)`. Le flux est identique au clavier : les événements transitent par `game.gd._input()` → `game_player.handle_input()`. Il n'existe qu'un seul chemin de contrôle.

### Fichiers concernés
- `project.godot` — orientation paysage forcée
- `scenes/ui/hud.tscn` — nœuds `TouchButtons` et `PortraitWarning`
- `scripts/hud.gd` — `_check_orientation()`, `_on_touch_left/right/next_room()`

## Export HTML5 et preview par PR (issue #93)

### Export HTML5

Le projet dispose d'un preset d'export Web dans `export_presets.cfg` (preset nommé `"Web"`).

Commande d'export en ligne de commande :
```bash
Godot_v4.6-stable_linux.x86_64 --headless --export-release "Web" build/web/index.html
```

Les templates d'export doivent être installés dans `~/.local/share/godot/export_templates/4.6.stable/` avant l'export.

### Workflow CI dédié (`.github/workflows/html5-preview.yml`)

Déclenché sur `pull_request` (opened, synchronize, reopened). Séparé du workflow GUT pour garder des responsabilités distinctes :

| Workflow | Fichier | Rôle |
|---|---|---|
| Tests GUT | `gut-tests.yml` | Validation logique, tous push + PR |
| Preview HTML5 | `html5-preview.yml` | Export web + publication preview, PR uniquement |

### Preview par PR

Chaque PR reçoit une preview publiée sur GitHub Pages à l'URL :
```
https://<owner>.github.io/<repo>/previews/pr-<numero>/
```

- Un nouveau commit sur la PR **remplace** la preview existante au même chemin (`keep_files: true`).
- La PR reçoit un commentaire automatique (créé ou mis à jour) avec le lien de preview.
- La branche `gh-pages` héberge toutes les previews sous `previews/`.
- La preview reflète l'export HTML5 complet (HTML + JS + WASM + PCK).

### Nettoyage

Le nettoyage des previews de PR fermées n'est pas automatisé dans la v1. Les dossiers `previews/pr-<numero>/` restent sur la branche `gh-pages` après fermeture de la PR.

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

### Nouveau test unitaire GUT (issue #83)
1. Créer `test/unit/test_<nom_module>.gd` (prefixe `test_` obligatoire)
2. Hériter de `GutTest` : `extends GutTest`
3. Chaque test = méthode publique `func test_<ce_que_ca_teste>() -> void:`
4. Utiliser les assertions GUT : `assert_eq`, `assert_true`, `assert_false`, `assert_ne`, etc.
5. Voir `test/unit/test_board_geometry.gd` comme template de référence

---

## Tests unitaires — GUT (issue #83)

### Framework

**GUT v9.6.0** est intégré dans `addons/gut/` et versionné dans le dépôt (aucun téléchargement nécessaire). Le plugin est activé dans `project.godot`.

### Arborescence

```
test/
└── unit/                           ← tests unitaires
    ├── test_board_geometry.gd      ← template + géométrie grille (issue #83)
    ├── test_board_state.gd         ← occupation de cellules, obstacles (issue #84)
    ├── test_obstacle_data.gd       ← factory, destructibles, blocage (issue #84)
    ├── test_monster_stats.gd       ← constantes, ticks, scaling boss (issue #84)
    └── test_spawn_fallback.gd      ← resolve_spawn_ctx, find_spawn_lane (issue #84)
```

Prévoir plus tard : `test/integration/` pour les tests de scènes complètes.

### Lancer les tests en ligne de commande

**Tous les tests unitaires :**
```bash
godot --headless --script addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
```

**Un fichier de test précis :**
```bash
godot --headless --script addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit/ \
  -ginclude_subdirs \
  -gtest=res://test/unit/test_board_geometry.gd \
  -gexit
```

**Un test ciblé dans un fichier :**
```bash
godot --headless --script addons/gut/gut_cmdln.gd \
  -gdir=res://test/unit/ \
  -gtest=res://test/unit/test_board_geometry.gd \
  -gunit_test_name=test_grid_dimensions \
  -gexit
```

Le code de retour est exploitable : `0` = succès, `1` = au moins un test échoue.

### Configuration `.gutconfig.json`

```json
{
  "dirs": ["res://test/unit/"],
  "include_subdirs": true,
  "prefix": "test_",
  "suffix": ".gd",
  "log_level": 1,
  "should_exit": true,
  "should_exit_on_success": true
}
```

### GitHub Actions

`.github/workflows/gut-tests.yml` — déclenché sur **tous les push et pull_request** de toutes les branches. Installe Godot 4.6, puis exécute la commande GUT CLI avec l'addon embarqué (aucun téléchargement de GUT dans le workflow).

### Conventions de nommage

| Élément | Convention |
|---|---|
| Fichier de test | `test_<module>.gd` |
| Classe | `extends GutTest` (pas de `class_name`) |
| Méthode de test | `func test_<description>() -> void:` |
| Assertion | `assert_eq(valeur, attendu, "message")` |
| Setup | `func before_each() -> void:` / `func before_all() -> void:` |

**Règle** : toute nouvelle logique gameplay cœur (géométrie, état de grille, calculs de stats) devrait idéalement s'accompagner d'un test GUT dans `res://test/unit/`, en suivant le modèle de `test_board_geometry.gd`.

---

## Pack de tests critiques de non-régression (issue #84)

### Objectif et principe

Ce pack fournit un **filet de sécurité minimal** avant le refacto structurel prévu (issue #82). Il protège les règles gameplay les plus structurantes, stables et exposées au risque de régression. Il ne vise pas une couverture exhaustive.

### Ce que couvre ce pack

| Fichier | Systèmes couverts |
|---|---|
| `test_board_state.gd` | Occupation de cellules, obstacles (set/get/clear), `is_grid_empty`, `is_cell_blocked` avec tous les cas de blocage |
| `test_obstacle_data.gd` | Factory `make_wall()`, propriétés d'un mur indestructible, création et hp d'un obstacle destructible, cas overkill |
| `test_monster_stats.gd` | `TICKS_PER_SECOND`, conversion `move_speed → move_period_ticks`, intégrité de tous les champs de `MONSTER_DEFS` et `WEAPON_DEFS`, formule de scaling des boss |
| `test_spawn_fallback.gd` | `_resolve_spawn_ctx` (mapping `entry_side` → coordonnées grille pour top/bottom/left/right), `find_spawn_lane` (lane préférée libre, retry offset +1/-1, fallback, all-occupied, all-blocked, lanes de bord) |

### Ce que ce pack ne couvre pas encore

- **Visuels et animations** : effets d'armes, flèches, explosions (dépendants du rendu)
- **Logique de tir des armes** (`game_weapons.gd`) : requiert des nodes visuels (`$Background`, `$Visuals`)
- **Comportement du boss** : retraite, barre de vie (dépend de la scène `monster_boss.tscn`)
- **Tick complet de simulation** : `game.gd._do_tick()` coordonne trop de sous-systèmes
- **HUD et records** : dépendent de scènes et de fichiers persistants
- **Projectile orienté selon le côté actif** : le concept `player_side → forward_dir` n'est pas encore formalisé dans le code (spawner fixé en bas)

### Comment étendre ce pack

Pour de futurs tickets :
1. **Comportements monstres** (`on_tick()` overrides) → étendre `test_monster_behaviors.gd` (issue #72 couvre déjà `ObstacleBehavior.resolve`)
2. **Scaling des armes** (formule `base_dmg * (1 + (level-1) * 0.5)`) → `test_weapon_scaling.gd`
3. **Records et persistance** (mock du filesystem) → `test_game_records.gd`
4. **Spawn contextuel multi-côté** (quand `player_side` sera implémenté) → étendre `test_spawn_fallback.gd`
5. **Obstacles destructibles en jeu** (intégration `BoardState` + `deal_fn`) → `test/integration/`
6. **jump_obstacle** (multi-ticks) → `ObstacleBehavior.JUMP_OBSTACLE` est réservé, à implémenter dans `obstacle_behavior.gd`

### Relancer le pack

Le pack s'intègre sans modification dans l'infrastructure existante :

```bash
# Tous les tests (pack critique inclus)
godot --headless --script addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json

# Un fichier précis du pack
godot --headless --script addons/gut/gut_cmdln.gd \
  -gtest=res://test/unit/test_spawn_fallback.gd -gexit
```

Le workflow GitHub Actions (`.github/workflows/gut-tests.yml`) exécute automatiquement l'ensemble sur chaque push et pull_request.
