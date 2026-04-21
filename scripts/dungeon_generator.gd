extends Node2D

const TILE  = 32
const ROOM_MIN = 5
const ROOM_MAX = 10
const MAX_ROOMS = 12
const MAP_W = 64
const MAP_H = 64

const TILE_FLOOR = 0
const TILE_WALL  = 1

# Couleurs du donjon
const COLOR_FLOOR     = Color(0.18, 0.15, 0.12)   # brun très sombre
const COLOR_WALL      = Color(0.38, 0.33, 0.28)   # pierre beige
const COLOR_WALL_TOP  = Color(0.48, 0.43, 0.36)   # liseret clair sur le bord haut des murs

var rooms: Array[Rect2i] = []
var _map: Array = []

func generate(floor_num: int) -> Array[Rect2i]:
	rooms.clear()
	_map.clear()

	# Remplir de murs
	for y in MAP_H:
		_map.append([])
		for x in MAP_W:
			_map[y].append(TILE_WALL)

	var num_rooms = clampi(4 + floor_num, 4, MAX_ROOMS)
	for _i in num_rooms * 5:
		if rooms.size() >= num_rooms:
			break
		_try_place_room()

	for i in range(rooms.size() - 1):
		_corridor(rooms[i], rooms[i + 1])

	_draw_dungeon()
	return rooms

func _try_place_room():
	var w = randi_range(ROOM_MIN, ROOM_MAX)
	var h = randi_range(ROOM_MIN, ROOM_MAX)
	var x = randi_range(1, MAP_W - w - 1)
	var y = randi_range(1, MAP_H - h - 1)
	var r = Rect2i(x, y, w, h)
	for other in rooms:
		if r.intersects(other.grow(1)):
			return
	rooms.append(r)
	for ry in range(y, y + h):
		for rx in range(x, x + w):
			_map[ry][rx] = TILE_FLOOR

func _corridor(a: Rect2i, b: Rect2i):
	var s = a.get_center()
	var e = b.get_center()
	var cx = s.x; var cy = s.y
	while cx != e.x:
		_map[cy][cx] = TILE_FLOOR
		cx += 1 if e.x > cx else -1
	while cy != e.y:
		_map[cy][cx] = TILE_FLOOR
		cy += 1 if e.y > cy else -1

func _draw_dungeon():
	# Supprimer les anciens visuels
	for child in get_children():
		child.queue_free()

	for y in MAP_H:
		for x in MAP_W:
			var rect = ColorRect.new()
			rect.position = Vector2(x * TILE, y * TILE)
			rect.size     = Vector2(TILE, TILE)

			if _map[y][x] == TILE_FLOOR:
				rect.color = COLOR_FLOOR
				# Légère variation pour donner du relief
				if (x + y) % 7 == 0:
					rect.color = COLOR_FLOOR.lightened(0.06)
			else:
				# Mur : liseret clair si la case en dessous est un sol (bord visible)
				var has_floor_below = y + 1 < MAP_H and _map[y + 1][x] == TILE_FLOOR
				rect.color = COLOR_WALL_TOP if has_floor_below else COLOR_WALL

			add_child(rect)

func room_center(idx: int) -> Vector2:
	if idx >= rooms.size():
		idx = rooms.size() - 1
	var c = rooms[idx].get_center()
	return Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)

func random_floor_pos() -> Vector2:
	var cells: Array[Vector2i] = []
	for y in MAP_H:
		for x in MAP_W:
			if _map[y][x] == TILE_FLOOR:
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return Vector2.ZERO
	var c = cells[randi() % cells.size()]
	return Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE / 2.0)
