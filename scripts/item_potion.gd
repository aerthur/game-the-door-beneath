extends Area2D

@export var heal_amount: int = 30

func _ready():
    add_to_group("items")
    body_entered.connect(_on_body_entered)

func _on_body_entered(body):
    if body.is_in_group("player"):
        body.heal(heal_amount)
        queue_free()
