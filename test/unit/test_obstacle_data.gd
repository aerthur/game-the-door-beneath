extends GutTest

# Tests de non-régression : ObstacleData
# Couvre : factory make_wall, obstacles destructibles, propriétés de blocage

func test_make_wall_blocks_movement() -> void:
	var wall := ObstacleData.make_wall()
	assert_true(wall.blocks_movement, "mur bloque le mouvement")

func test_make_wall_blocks_occupancy() -> void:
	var wall := ObstacleData.make_wall()
	assert_true(wall.blocks_occupancy, "mur bloque l'occupation")

func test_make_wall_blocks_los() -> void:
	var wall := ObstacleData.make_wall()
	assert_true(wall.blocks_los, "mur bloque la ligne de vue")

func test_make_wall_is_indestructible() -> void:
	var wall := ObstacleData.make_wall()
	assert_eq(wall.destructibility, "indestructible", "mur indestructible par défaut")

func test_make_wall_hp_is_minus_one() -> void:
	var wall := ObstacleData.make_wall()
	assert_eq(wall.hp, -1, "hp = -1 pour obstacle indestructible")

func test_make_wall_kind_is_wall() -> void:
	var wall := ObstacleData.make_wall()
	assert_eq(wall.kind, "wall", "kind = 'wall'")

func test_destructible_obstacle_initial_hp() -> void:
	var obs := ObstacleData.new()
	obs.destructibility = "destructible"
	obs.hp     = 50
	obs.max_hp = 50
	assert_eq(obs.hp, 50, "hp initial correct")
	assert_eq(obs.max_hp, 50, "max_hp correct")

func test_destructible_obstacle_hp_decreases() -> void:
	var obs := ObstacleData.new()
	obs.destructibility = "destructible"
	obs.hp     = 50
	obs.max_hp = 50
	obs.hp -= 20
	assert_eq(obs.hp, 30, "hp diminue après dégâts")
	assert_true(obs.hp > 0, "obstacle toujours vivant à 30 hp")

func test_destructible_obstacle_destroyed_at_zero() -> void:
	var obs := ObstacleData.new()
	obs.destructibility = "destructible"
	obs.hp     = 10
	obs.max_hp = 10
	obs.hp -= 10
	assert_eq(obs.hp, 0, "hp à 0 → obstacle détruit")
	assert_false(obs.hp > 0, "hp <= 0 confirme la destruction")

func test_destructible_obstacle_overkill() -> void:
	var obs := ObstacleData.new()
	obs.destructibility = "destructible"
	obs.hp     = 10
	obs.max_hp = 10
	obs.hp -= 30
	assert_true(obs.hp < 0, "hp négatif possible en cas d'overkill")

func test_obstacle_can_block_movement_only() -> void:
	var obs := ObstacleData.new()
	obs.blocks_movement  = true
	obs.blocks_occupancy = false
	assert_true(obs.blocks_movement, "bloque le mouvement")
	assert_false(obs.blocks_occupancy, "ne bloque pas l'occupation")

func test_obstacle_can_block_occupancy_only() -> void:
	var obs := ObstacleData.new()
	obs.blocks_movement  = false
	obs.blocks_occupancy = true
	assert_false(obs.blocks_movement, "ne bloque pas le mouvement")
	assert_true(obs.blocks_occupancy, "bloque l'occupation")

func test_default_obstacle_blocks_movement_and_occupancy() -> void:
	var obs := ObstacleData.new()
	assert_true(obs.blocks_movement,  "blocks_movement = true par défaut")
	assert_true(obs.blocks_occupancy, "blocks_occupancy = true par défaut")

func test_default_obstacle_does_not_block_los() -> void:
	var obs := ObstacleData.new()
	assert_false(obs.blocks_los, "blocks_los = false par défaut")

# ── Tests make_destructible_wall (issue #74) ──────────────────────────
func test_make_destructible_wall_destructibility() -> void:
	var obs := ObstacleData.make_destructible_wall(30)
	assert_eq(obs.destructibility, "destructible", "factory : obstacle destructible")

func test_make_destructible_wall_hp() -> void:
	var obs := ObstacleData.make_destructible_wall(30)
	assert_eq(obs.hp, 30, "factory : hp = 30")
	assert_eq(obs.max_hp, 30, "factory : max_hp = 30")

func test_make_destructible_wall_blocks_by_default() -> void:
	var obs := ObstacleData.make_destructible_wall(30)
	assert_true(obs.blocks_movement, "factory : bloque le mouvement")
	assert_true(obs.blocks_occupancy, "factory : bloque l'occupation")

func test_indestructible_wall_has_no_hp() -> void:
	var wall := ObstacleData.make_wall()
	assert_eq(wall.hp, -1, "mur indestructible : hp = -1")
	assert_eq(wall.max_hp, -1, "mur indestructible : max_hp = -1")
