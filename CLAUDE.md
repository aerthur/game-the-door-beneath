# The Door Beneath — Contexte pour agents Claude Code

## Présentation du projet
Jeu roguelite en lanes développé avec **Godot 4.6** et **GDScript 2.0**.
- Moteur : Godot 4.6 (standard, pas .NET)
- Résolution : 1280×720
- Language : GDScript 2.0

## Concept de jeu
- 5 files verticales (lanes), 8 rangées par file
- Le joueur est un archer en bas, il change de file avec ←→
- Les monstres descendent du haut vers le bas, tick par tick (1 tick/sec)
- Si un monstre atteint le bas : touche le joueur s'il est dans sa file, puis se duplique (2 nouveaux apparaissent en haut)
- 10 salles de difficulté croissante — ESPACE pour passer à la salle suivante quand elle est vidée
- 3 types de monstres, 8 armes débloquables, système XP/niveau

## Structure des fichiers
```
roguelite_medieval/
├── project.godot
├── CLAUDE.md                   ← ce fichier
├── scenes/
│   ├── game.tscn               ← scène principale (instancie tout)
│   ├── player.tscn             ← archer joueur (Node2D + polygones)
│   ├── monster_blob.tscn       ← gobelin vert
│   ├── monster_blue.tscn       ← gobelin bleu
│   ├── monster_red.tscn        ← gobelin rouge
│   ├── gem.tscn                ← gemme XP (Polygon2D diamond)
│   └── ui/
│       └── hud.tscn            ← CanvasLayer UI (HP, XP, armes, level-up)
└── scripts/
    ├── game.gd                 ← contrôleur principal (TOUT passe par là)
    ├── hud.gd                  ← logique HUD
    ├── monster_blob.gd         ← stats gobelin vert (hp=30, dmg=12, spd=1, xp=25)
    ├── monster_blue.gd         ← stats gobelin bleu (hp=55, dmg=20, spd=1, xp=50)
    └── monster_red.gd          ← stats gobelin rouge (hp=90, dmg=30, spd=2, xp=100)
```

## Architecture game.gd (fichier central)

### Constantes importantes
```gdscript
const LANES  = 5      # files horizontales
const ROWS   = 8      # rangées verticales
const LANE_W = 180    # largeur d'une file en pixels
const ROW_H  = 68     # hauteur d'une rangée en pixels
const GRID_X = (1280 - LANES * LANE_W) / 2   # offset X de la grille
const GRID_Y = 30                              # offset Y de la grille
```

### Variables d'état clés
```gdscript
var player_lane        : int   # 0–4, file active du joueur
var player_hp          : int   # PV joueur (max 100)
var room_num           : int   # salle actuelle (1–10+)
var monsters_remaining : int   # compteur de kills restants
var spawns_in_flight   : int   # nb de coroutines _on_monster_escaped en cours
var room_clear         : bool  # true = salle vidée, attente ESPACE
var game_over          : bool
var leveling_up        : bool  # true = panel level-up affiché
var active_weapons     : Array # [{"id": "arc", "level": 1, "acc": 0.0}, ...]
var grid               : Array # grid[row][lane] = monstre Node2D ou null
```

### Fonctions importantes
- `_start_room(num)` — démarre une salle, spawne la vague
- `_do_tick()` — déplace tous les monstres d'une rangée vers le bas
- `_on_monster_escaped(lane, mtype)` — monstre arrivé en bas → duplique (async)
- `_on_monster_killed(lane, pos, xp)` — kill confirmé, décrémente compteur
- `_check_room_clear()` — vérifie si grille vide + aucun spawn en vol → clear
- `_deal_and_check(m, row, lane, dmg)` — applique dégâts, vérifie mort
- `_fire_weapon(w)` → dispatch vers `_w_arc`, `_w_arbalete`, etc.
- `apply_level_up_choice(choice)` — appelée par hud.gd quand le joueur choisit

### Grille
`grid[row][lane]` contient le Node2D du monstre ou `null`.
- row 0 = haut de l'écran, row 7 = bas
- lane 0 = file gauche, lane 4 = file droite
- Toujours mettre à jour `grid[row][lane]` ET `m.grid_row` / `m.grid_lane` ensemble

### Système de room clear (important — bug précédemment corrigé)
La salle est terminée quand `_grid_empty() == true AND spawns_in_flight == 0`.
Ne pas se fier uniquement à `monsters_remaining` qui peut dériver à cause des coroutines async concurrentes.

## Les 8 armes
| id | Nom | Dégâts base | CD | Comportement |
|---|---|---|---|---|
| arc | Arc | 25 | 1.0s | 1 ennemi dans la file active |
| arbalete | Arbalète | 55 | 2.0s | Perce 2 ennemis dans la file |
| dague | Dague | 10 | 0.35s | Très rapide, file active |
| bombe | Bombe | 20 | 2.5s | 3 files voisines |
| eclair | Eclair | 16 | 1.5s | Tous les ennemis de la file |
| tourbillon | Tourbillon | 12 | 2.0s | 1ère rangée de chaque file |
| givre | Givre | 8 | 1.5s | Ralentit 2 ticks + dégâts |
| sismique | Sismique | 9 | 3.0s | 2 dernières rangées, toutes files |

Les dégâts scalent avec le niveau : `base_dmg * (1.0 + (level - 1) * 0.5)`

## Monstres
| type | monster_type | hp | dmg | speed | xp |
|---|---|---|---|---|---|
| Gobelin vert | "g" | 30 | 12 | 1 | 25 |
| Gobelin bleu | "b" | 55 | 20 | 1 | 50 |
| Gobelin rouge | "r" | 90 | 30 | 2 | 100 |

`move_speed` = nombre de rangées parcourues par tick.

## Conventions de code
- GDScript 2.0 — utiliser `func name() -> Type:` pour les retours typés
- Toujours vérifier `is_instance_valid(node)` avant d'accéder à un Node après un `await`
- Les visuels (flèches, explosions, éclairs) sont des nodes temporaires ajoutés à `$Background`
- Les monstres sont sous `$Monsters` (Node2D)
- Le HUD est `$HUD` (CanvasLayer) — interagir via `hud.update_*()` et `hud.show_*()`

## Inputs mappés (project.godot)
- `lane_left` → flèche gauche
- `lane_right` → flèche droite
- `next_room` → ESPACE

## Comment ajouter une feature typique

### Nouvelle arme
1. Ajouter dans `WEAPON_DEFS` dans game.gd
2. Ajouter un `case` dans `_fire_weapon()`
3. Implémenter `_w_nomArme(w: Dictionary)`
4. L'arme sera automatiquement proposable au level-up

### Nouveau type de monstre
1. Créer `scripts/monster_XXX.gd` (copier monster_blob.gd, changer stats et monster_type)
2. Créer `scenes/monster_XXX.tscn` (Node2D + script + visuel)
3. Preload dans game.gd, ajouter le case dans `_spawn_monster()`
4. Ajouter dans `ROOM_WAVES` si nécessaire

#### Taille de référence des gobelins (issue #4)
Tous les gobelins partagent la même géométrie de base (monster_blob.tscn). Seule la couleur change.
Référence à respecter pour tout nouveau gobelin :
- Head : offset_left=-18, offset_top=-28, offset_right=18, offset_bottom=2
- Body : offset_left=-14, offset_top=-2, offset_right=14, offset_bottom=22
- Ears : width=10, top=-32, bottom=-16 (gauche: left=-26/right=-16 ; droite: left=16/right=26)
- ArmLeft : offset_left=-26, offset_top=2, offset_right=-14, offset_bottom=16
- ArmRight : offset_left=14, offset_top=2, offset_right=26, offset_bottom=16

### Nouvelle mécanique de jeu
- Toute la logique de jeu passe par game.gd
- Le HUD communique avec game.gd via `get_tree().get_first_node_in_group("game")`
