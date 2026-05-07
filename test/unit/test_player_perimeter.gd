extends GutTest
# Tests unitaires pour la position périphérique du joueur (issue #77).
# Vérifie : positions monde, index max, transitions de bord, cas neutres.
#
# Les tests de déplacement utilisent un dictionnaire d'état {side, index, lane}
# et des helpers purs pour éviter les dépendances à la scène.

# ── Helpers purs ──────────────────────────────────────────────────

func _calc_lane(side: String, index: int) -> int:
	match side:
		"bottom", "top": return index
		"left":          return 0
		"right":         return BoardGeometry.GRID_COLUMNS - 1
	return 0

func _make(side: String, index: int) -> Dictionary:
	return {"side": side, "index": index, "lane": _calc_lane(side, index)}

# Miroir de move_perimeter() sans tween ni HUD — retourne true si déplacement.
func _move(st: Dictionary, action: String) -> bool:
	var max_idx   : int    = BoardGeometry.get_perimeter_max_index(st.side)
	var new_side  : String = st.side
	var new_index : int    = st.index

	match st.side:
		"bottom":
			match action:
				"left":
					if st.index <= 0:         return false
					new_index = st.index - 1
				"right":
					if st.index >= max_idx:   return false
					new_index = st.index + 1
				"up":
					if st.index == 0:
						new_side  = "left"
						new_index = BoardGeometry.GRID_ROWS - 1
					else:
						return false
				_:
					return false

		"left":
			match action:
				"up":
					if st.index <= 0:         return false
					new_index = st.index - 1
				"down":
					if st.index >= max_idx:   return false
					new_index = st.index + 1
				"right":
					if st.index == 0:
						new_side  = "top"
						new_index = 0
					else:
						return false
				_:
					return false

		"top":
			match action:
				"left":
					if st.index <= 0:         return false
					new_index = st.index - 1
				"right":
					if st.index >= max_idx:   return false
					new_index = st.index + 1
				"down":
					if st.index == max_idx:
						new_side  = "right"
						new_index = 0
					else:
						return false
				_:
					return false

		"right":
			match action:
				"up":
					if st.index <= 0:         return false
					new_index = st.index - 1
				"down":
					if st.index >= max_idx:   return false
					new_index = st.index + 1
				"left":
					if st.index == max_idx:
						new_side  = "bottom"
						new_index = BoardGeometry.GRID_COLUMNS - 1
					else:
						return false
				_:
					return false

	st.side  = new_side
	st.index = new_index
	st.lane  = _calc_lane(new_side, new_index)
	return true

# ── BoardGeometry.get_perimeter_max_index ────────────────────────

func test_perimeter_max_index_column_sides():
	assert_eq(BoardGeometry.get_perimeter_max_index("bottom"), BoardGeometry.GRID_COLUMNS - 1)
	assert_eq(BoardGeometry.get_perimeter_max_index("top"),    BoardGeometry.GRID_COLUMNS - 1)

func test_perimeter_max_index_row_sides():
	assert_eq(BoardGeometry.get_perimeter_max_index("left"),  BoardGeometry.GRID_ROWS - 1)
	assert_eq(BoardGeometry.get_perimeter_max_index("right"), BoardGeometry.GRID_ROWS - 1)

# ── BoardGeometry.get_player_perimeter_pos ───────────────────────

func test_perimeter_pos_bottom():
	var pos = BoardGeometry.get_player_perimeter_pos("bottom", 2)
	var ex  = BoardGeometry.GRID_ORIGIN_X + 2 * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH * 0.5
	assert_eq(pos.x, ex,                    "bottom x = centre colonne")
	assert_eq(pos.y, BoardGeometry.PLAYER_Y, "bottom y = PLAYER_Y")

func test_perimeter_pos_top():
	var pos = BoardGeometry.get_player_perimeter_pos("top", 0)
	var ex  = BoardGeometry.GRID_ORIGIN_X + BoardGeometry.CELL_WIDTH * 0.5
	var ey  = BoardGeometry.GRID_ORIGIN_Y - BoardGeometry.PLAYER_MARGIN
	assert_eq(pos.x, ex, "top x = centre colonne 0")
	assert_eq(pos.y, ey, "top y = au-dessus de la grille")

func test_perimeter_pos_left():
	var pos = BoardGeometry.get_player_perimeter_pos("left", 3)
	var ex  = BoardGeometry.GRID_ORIGIN_X - BoardGeometry.PLAYER_MARGIN
	var ey  = BoardGeometry.GRID_ORIGIN_Y + 3 * BoardGeometry.CELL_HEIGHT + BoardGeometry.CELL_HEIGHT * 0.5
	assert_eq(pos.x, ex, "left x = à gauche de la grille")
	assert_eq(pos.y, ey, "left y = centre rangée 3")

func test_perimeter_pos_right():
	var pos = BoardGeometry.get_player_perimeter_pos("right", 0)
	var ex  = BoardGeometry.GRID_ORIGIN_X + BoardGeometry.GRID_COLUMNS * BoardGeometry.CELL_WIDTH + BoardGeometry.PLAYER_MARGIN
	var ey  = BoardGeometry.GRID_ORIGIN_Y + BoardGeometry.CELL_HEIGHT * 0.5
	assert_eq(pos.x, ex, "right x = à droite de la grille")
	assert_eq(pos.y, ey, "right y = centre rangée 0")

func test_perimeter_pos_bottom_columns_ordered():
	var p0 = BoardGeometry.get_player_perimeter_pos("bottom", 0)
	var p4 = BoardGeometry.get_player_perimeter_pos("bottom", 4)
	assert_true(p0.x < p4.x, "colonne 0 est à gauche de la colonne 4")

func test_perimeter_pos_left_rows_ordered():
	var p0 = BoardGeometry.get_player_perimeter_pos("left", 0)
	var p7 = BoardGeometry.get_player_perimeter_pos("left", 7)
	assert_true(p0.y < p7.y, "rangée 0 est au-dessus de la rangée 7")

# ── Déplacement sur le bord bas ───────────────────────────────────

func test_bottom_move_right():
	var s = _make("bottom", 2)
	assert_true(_move(s, "right"))
	assert_eq(s.side, "bottom")
	assert_eq(s.index, 3)
	assert_eq(s.lane, 3)

func test_bottom_move_left():
	var s = _make("bottom", 2)
	assert_true(_move(s, "left"))
	assert_eq(s.index, 1)

func test_bottom_right_at_max_neutral():
	var s = _make("bottom", BoardGeometry.GRID_COLUMNS - 1)
	assert_false(_move(s, "right"), "neutre au bord droit")
	assert_eq(s.index, BoardGeometry.GRID_COLUMNS - 1)

func test_bottom_left_at_zero_neutral():
	var s = _make("bottom", 0)
	assert_false(_move(s, "left"), "neutre au bord gauche")
	assert_eq(s.index, 0)

func test_bottom_down_neutral():
	var s = _make("bottom", 2)
	assert_false(_move(s, "down"), "down sur bottom = neutre")

func test_bottom_up_at_nonzero_neutral():
	var s = _make("bottom", 2)
	assert_false(_move(s, "up"), "up sur bottom hors coin = neutre")

# ── Transition coin bas-gauche → côté gauche ──────────────────────

func test_transition_bottom_left_to_left_side():
	var s = _make("bottom", 0)
	assert_true(_move(s, "up"), "transition corner bas-gauche")
	assert_eq(s.side,  "left",                       "côté gauche")
	assert_eq(s.index, BoardGeometry.GRID_ROWS - 1,  "entrée en bas du côté gauche")
	assert_eq(s.lane,  0,                            "player_lane = 0 côté gauche")

# ── Déplacement sur le bord gauche ───────────────────────────────

func test_left_move_up():
	var s = _make("left", 4)
	assert_true(_move(s, "up"))
	assert_eq(s.index, 3)
	assert_eq(s.lane, 0)

func test_left_move_down():
	var s = _make("left", 4)
	assert_true(_move(s, "down"))
	assert_eq(s.index, 5)

func test_left_up_at_zero_neutral():
	var s = _make("left", 0)
	assert_false(_move(s, "up"))

func test_left_down_at_max_neutral():
	var s = _make("left", BoardGeometry.GRID_ROWS - 1)
	assert_false(_move(s, "down"))

func test_left_left_neutral():
	var s = _make("left", 3)
	assert_false(_move(s, "left"), "left sur côté gauche = neutre")

func test_left_right_non_corner_neutral():
	var s = _make("left", 3)
	assert_false(_move(s, "right"), "right hors coin = neutre sur côté gauche")

# ── Transition coin haut-gauche → côté haut ───────────────────────

func test_transition_top_left_to_top_side():
	var s = _make("left", 0)
	assert_true(_move(s, "right"), "transition corner haut-gauche")
	assert_eq(s.side,  "top", "côté haut")
	assert_eq(s.index, 0,    "entrée colonne gauche du côté haut")
	assert_eq(s.lane,  0)

# ── Déplacement sur le bord haut ─────────────────────────────────

func test_top_move_left():
	var s = _make("top", 2)
	assert_true(_move(s, "left"))
	assert_eq(s.index, 1)
	assert_eq(s.lane, 1)

func test_top_move_right():
	var s = _make("top", 2)
	assert_true(_move(s, "right"))
	assert_eq(s.index, 3)

func test_top_left_at_zero_neutral():
	var s = _make("top", 0)
	assert_false(_move(s, "left"))

func test_top_right_at_max_neutral():
	var s = _make("top", BoardGeometry.GRID_COLUMNS - 1)
	assert_false(_move(s, "right"))

func test_top_up_neutral():
	var s = _make("top", 2)
	assert_false(_move(s, "up"), "up sur top = neutre")

func test_top_down_non_corner_neutral():
	var s = _make("top", 2)
	assert_false(_move(s, "down"), "down hors coin sur top = neutre")

# ── Transition coin haut-droit → côté droit ───────────────────────

func test_transition_top_right_to_right_side():
	var s = _make("top", BoardGeometry.GRID_COLUMNS - 1)
	assert_true(_move(s, "down"), "transition corner haut-droit")
	assert_eq(s.side,  "right",                       "côté droit")
	assert_eq(s.index, 0,                             "entrée en haut du côté droit")
	assert_eq(s.lane,  BoardGeometry.GRID_COLUMNS - 1)

# ── Déplacement sur le bord droit ────────────────────────────────

func test_right_move_up():
	var s = _make("right", 3)
	assert_true(_move(s, "up"))
	assert_eq(s.index, 2)
	assert_eq(s.lane, BoardGeometry.GRID_COLUMNS - 1)

func test_right_move_down():
	var s = _make("right", 3)
	assert_true(_move(s, "down"))
	assert_eq(s.index, 4)

func test_right_up_at_zero_neutral():
	var s = _make("right", 0)
	assert_false(_move(s, "up"))

func test_right_down_at_max_neutral():
	var s = _make("right", BoardGeometry.GRID_ROWS - 1)
	assert_false(_move(s, "down"))

func test_right_right_neutral():
	var s = _make("right", 3)
	assert_false(_move(s, "right"), "right sur côté droit = neutre")

func test_right_left_non_corner_neutral():
	var s = _make("right", 3)
	assert_false(_move(s, "left"), "left hors coin = neutre sur côté droit")

# ── Transition coin bas-droit → côté bas ──────────────────────────

func test_transition_bottom_right_to_bottom_side():
	var s = _make("right", BoardGeometry.GRID_ROWS - 1)
	assert_true(_move(s, "left"), "transition corner bas-droit")
	assert_eq(s.side,  "bottom",                       "côté bas")
	assert_eq(s.index, BoardGeometry.GRID_COLUMNS - 1, "entrée colonne droite du côté bas")
	assert_eq(s.lane,  BoardGeometry.GRID_COLUMNS - 1)

# ── Tour complet dans le sens horaire ─────────────────────────────

func test_full_clockwise_loop():
	var s = _make("bottom", 0)

	# bottom → left (coin bas-gauche + up)
	_move(s, "up")
	assert_eq(s.side, "left")
	assert_eq(s.index, BoardGeometry.GRID_ROWS - 1)

	# remonter jusqu'à index 0
	for _i in (BoardGeometry.GRID_ROWS - 1):
		_move(s, "up")
	assert_eq(s.index, 0)

	# left → top (coin haut-gauche + right)
	_move(s, "right")
	assert_eq(s.side, "top")
	assert_eq(s.index, 0)

	# avancer jusqu'au coin haut-droit
	for _i in (BoardGeometry.GRID_COLUMNS - 1):
		_move(s, "right")
	assert_eq(s.index, BoardGeometry.GRID_COLUMNS - 1)

	# top → right (coin haut-droit + down)
	_move(s, "down")
	assert_eq(s.side, "right")
	assert_eq(s.index, 0)

	# descendre jusqu'au coin bas-droit
	for _i in (BoardGeometry.GRID_ROWS - 1):
		_move(s, "down")
	assert_eq(s.index, BoardGeometry.GRID_ROWS - 1)

	# right → bottom (coin bas-droit + left)
	_move(s, "left")
	assert_eq(s.side, "bottom")
	assert_eq(s.index, BoardGeometry.GRID_COLUMNS - 1)

# ── player_lane selon le côté ─────────────────────────────────────

func test_player_lane_on_bottom():
	var s = _make("bottom", 3)
	assert_eq(s.lane, 3)

func test_player_lane_on_top():
	var s = _make("top", 1)
	assert_eq(s.lane, 1)

func test_player_lane_on_left():
	var s = _make("left", 5)
	assert_eq(s.lane, 0, "left → player_lane = 0")

func test_player_lane_on_right():
	var s = _make("right", 2)
	assert_eq(s.lane, BoardGeometry.GRID_COLUMNS - 1, "right → player_lane = GRID_COLUMNS - 1")

func test_player_lane_updated_after_corner_transition():
	# Depuis bottom col 0, up → left
	var s = _make("bottom", 0)
	_move(s, "up")
	assert_eq(s.lane, 0, "après transition bottom→left, lane=0")

func test_player_lane_updated_after_bottom_right_transition():
	# Depuis right bas, left → bottom col max
	var s = _make("right", BoardGeometry.GRID_ROWS - 1)
	_move(s, "left")
	assert_eq(s.lane, BoardGeometry.GRID_COLUMNS - 1,
			"après transition right→bottom, lane = GRID_COLUMNS - 1")
