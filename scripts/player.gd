extends CharacterBody2D

signal health_changed(new_health, max_health)
signal player_died

@export var speed: float = 200.0
@export var max_health: int = 100
@export var attack_damage: int = 25
@export var attack_range: float = 64.0
@export var attack_cooldown: float = 0.5

var health: int
var can_attack: bool = true
var facing_direction: Vector2 = Vector2.RIGHT

func _ready():
    health = max_health
    add_to_group("player")
    health_changed.emit(health, max_health)
    $AttackArea.body_entered.connect(_on_attack_area_body_entered)

func _physics_process(_delta):
    var direction = Vector2.ZERO
    if Input.is_action_pressed("move_right"): direction.x += 1
    if Input.is_action_pressed("move_left"):  direction.x -= 1
    if Input.is_action_pressed("move_down"):  direction.y += 1
    if Input.is_action_pressed("move_up"):    direction.y -= 1

    if direction != Vector2.ZERO:
        facing_direction = direction.normalized()
        direction = direction.normalized()

    velocity = direction * speed
    move_and_slide()

func _input(event):
    if event.is_action_pressed("attack") and can_attack:
        _perform_attack()

func _perform_attack():
    can_attack = false
    $AttackArea/CollisionShape2D.disabled = false
    $AttackArea.position = facing_direction * 36.0

    # Feedback visuel
    $AttackSprite.visible = true
    $AttackSprite.position = facing_direction * 36.0

    await get_tree().create_timer(0.15).timeout
    $AttackArea/CollisionShape2D.disabled = true
    $AttackSprite.visible = false

    await get_tree().create_timer(attack_cooldown).timeout
    can_attack = true

func take_damage(amount: int):
    health = max(0, health - amount)
    health_changed.emit(health, max_health)
    modulate = Color(1.0, 0.3, 0.3)
    await get_tree().create_timer(0.15).timeout
    modulate = Color.WHITE
    if health <= 0:
        player_died.emit()
        queue_free()

func heal(amount: int):
    health = min(max_health, health + amount)
    health_changed.emit(health, max_health)

func _on_attack_area_body_entered(body):
    if body.is_in_group("enemies"):
        body.take_damage(attack_damage)
