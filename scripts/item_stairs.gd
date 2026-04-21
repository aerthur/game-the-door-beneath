extends Area2D

signal next_floor_reached

func _ready():
    add_to_group("items")
    body_entered.connect(_on_body_entered)

func _on_body_entered(body):
    if body.is_in_group("player"):
        next_floor_reached.emit()
