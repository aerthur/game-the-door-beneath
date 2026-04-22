extends CharacterBody2D

@export var speed: float = 70.0
@export var max_health: int = 40
@export var attack_damage: int = 8
@export var attack_range: float = 28.0
@export var attack_cooldown: float = 1.2
@export var detection_range: float = 220.0
@export var xp_value: int = 10

var health: int
var player: CharacterBody2D = null
var can_attack: bool = true

func _ready():
	health = max_health
	add_to_group("enemies")

func _physics_process(_delta):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
		return

	var dist = global_position.distance_to(player.global_position)
	if dist < detection_range:
		if dist > attack_range:
			var dir = (player.global_position - global_position).normalized()
			velocity = dir * speed
		else:
			velocity = Vector2.ZERO
			if can_attack:
				_attack()
	else:
		velocity = lerp(velocity, Vector2.ZERO, 0.1)
	move_and_slide()

func _attack():
	can_attack = false
	if is_instance_valid(player):
		player.take_damage(attack_damage)
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func take_damage(amount: int):
	health -= amount
	modulate = Color(1.0, 0.3, 0.3)
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	if health <= 0:
		_die()

func _die():
	var gm = get_tree().get_first_node_in_group("game_manager")
	if gm:
		gm.on_enemy_killed(xp_value)
	queue_free()
