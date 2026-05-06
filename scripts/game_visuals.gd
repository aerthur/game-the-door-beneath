extends Node2D
# ── GameVisuals ──────────────────────────────────────────────────
# Toutes les animations et effets visuels du jeu.
# Doit être ajouté comme enfant du nœud Game dans main.tscn.
# game.gd définit :  visuals.bg = bg   dans son _ready().

var bg: Node2D  # défini par game.gd

# ── Helper position grille ───────────────────────────────────────
func grid_pos(row: int, lane: int) -> Vector2:
	return BoardGeometry.get_cell_center(row, lane)

# ── Visuels d'attaque ────────────────────────────────────────────
func shoot_arrow(lane: int, target_row: int, duration: float,
				 col: Color = Color(0.95, 0.85, 0.3), w: float = 3.0):
	var arrow = Node2D.new()
	var shaft = Line2D.new()
	shaft.add_point(Vector2(0, 0)); shaft.add_point(Vector2(0, -28))
	shaft.width = w; shaft.default_color = col
	arrow.add_child(shaft)
	var tip = ColorRect.new()
	tip.size = Vector2(7, 9); tip.position = Vector2(-3.5, -37)
	tip.color = col.lightened(0.2); arrow.add_child(tip)
	var feather = ColorRect.new()
	feather.size = Vector2(12, 4); feather.position = Vector2(-6, -4)
	feather.color = Color(0.9, 0.88, 0.78); arrow.add_child(feather)
	arrow.position = Vector2(BoardGeometry.GRID_ORIGIN_X + lane * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH * 0.5, BoardGeometry.PLAYER_Y - 35)
	bg.add_child(arrow)
	var tw = create_tween()
	tw.tween_property(arrow, "position", grid_pos(target_row, lane), duration)
	await tw.finished
	if is_instance_valid(arrow): arrow.queue_free()

func show_slash(lane: int, row: int):
	var slash = Line2D.new()
	slash.add_point(Vector2(-22, -18)); slash.add_point(Vector2(22, 18))
	slash.width = 4.0; slash.default_color = Color(1.0, 0.9, 0.4, 0.85)
	slash.position = grid_pos(row, lane); bg.add_child(slash)
	await get_tree().create_timer(0.09).timeout
	if is_instance_valid(slash): slash.queue_free()

func show_explosion(lane: int, row: int):
	var exp = ColorRect.new()
	exp.size = Vector2(BoardGeometry.CELL_WIDTH - 4, BoardGeometry.CELL_HEIGHT - 4)
	exp.position = Vector2(BoardGeometry.GRID_ORIGIN_X + lane * BoardGeometry.CELL_WIDTH + 2, BoardGeometry.GRID_ORIGIN_Y + row * BoardGeometry.CELL_HEIGHT + 2)
	exp.color = Color(1.0, 0.55, 0.1, 0.70); bg.add_child(exp)
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(exp): exp.queue_free()

func show_lightning(lane: int, row: int):
	var bolt = Line2D.new()
	var sx = BoardGeometry.GRID_ORIGIN_X + lane * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH * 0.5
	bolt.add_point(Vector2(sx, BoardGeometry.PLAYER_Y))
	bolt.add_point(Vector2(sx + randf_range(-12, 12), grid_pos(row, lane).y))
	bolt.width = 4.0; bolt.default_color = Color(0.6, 0.6, 1.0, 0.9)
	bg.add_child(bolt)
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(bolt): bolt.queue_free()

func show_whirlwind():
	var rect = ColorRect.new()
	rect.size = Vector2(BoardGeometry.GRID_COLUMNS * BoardGeometry.CELL_WIDTH, BoardGeometry.CELL_HEIGHT)
	rect.position = Vector2(BoardGeometry.GRID_ORIGIN_X, BoardGeometry.GRID_ORIGIN_Y + (BoardGeometry.GRID_ROWS - 1) * BoardGeometry.CELL_HEIGHT)
	rect.color = Color(0.8, 0.5, 1.0, 0.35); bg.add_child(rect)
	await get_tree().create_timer(0.18).timeout
	if is_instance_valid(rect): rect.queue_free()

func show_quake():
	var rect = ColorRect.new()
	rect.size = Vector2(BoardGeometry.GRID_COLUMNS * BoardGeometry.CELL_WIDTH, BoardGeometry.CELL_HEIGHT * 2)
	rect.position = Vector2(BoardGeometry.GRID_ORIGIN_X, BoardGeometry.GRID_ORIGIN_Y + (BoardGeometry.GRID_ROWS - 2) * BoardGeometry.CELL_HEIGHT)
	rect.color = Color(0.9, 0.65, 0.2, 0.40); bg.add_child(rect)
	var cam = get_viewport().get_camera_2d()
	if cam:
		var tw = create_tween()
		tw.tween_property(cam, "offset", Vector2(6, 0), 0.05)
		tw.tween_property(cam, "offset", Vector2(-6, 0), 0.05)
		tw.tween_property(cam, "offset", Vector2(0, 0), 0.05)
	await get_tree().create_timer(0.20).timeout
	if is_instance_valid(rect): rect.queue_free()

# ── Animations de mort ───────────────────────────────────────────
func play_death_anim(pos: Vector2, type: String, is_boss: bool):
	if is_boss:
		death_anim_boss(pos)
		return
	match type:
		"g": death_anim_green(pos)
		"b": death_anim_blue(pos)
		"r": death_anim_red(pos)

func death_anim_green(pos: Vector2):
	var count = randi_range(6, 8)
	for i in count:
		var sq = ColorRect.new()
		sq.size = Vector2(7, 7)
		sq.color = Color(0.2, 0.85, 0.25)
		sq.position = pos - Vector2(3.5, 3.5)
		bg.add_child(sq)
		var angle = (float(i) / count) * TAU + randf_range(-0.15, 0.15)
		var dist  = randf_range(22.0, 46.0)
		var target = pos + Vector2(cos(angle), sin(angle)) * dist - Vector2(3.5, 3.5)
		var tw = create_tween()
		tw.tween_property(sq, "position", target, 0.3)
		tw.parallel().tween_property(sq, "modulate", Color(1, 1, 1, 0), 0.3)
		tw.tween_callback(sq.queue_free)

func death_anim_blue(pos: Vector2):
	var flash = ColorRect.new()
	flash.size = Vector2(32, 32)
	flash.position = pos - Vector2(16, 16)
	flash.color = Color(1.0, 1.0, 1.0, 0.9)
	bg.add_child(flash)
	var tw = create_tween()
	for _i in 3:
		tw.tween_property(flash, "color", Color(1.0, 1.0, 1.0, 0.9), 0.04)
		tw.tween_property(flash, "color", Color(0.3, 0.5, 1.0, 0.7), 0.04)
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.05)
	tw.tween_callback(flash.queue_free)
	await get_tree().create_timer(0.10).timeout
	var shard_count = 6
	for i in shard_count:
		var shard = Line2D.new()
		var angle = (float(i) / shard_count) * TAU
		var length = randf_range(12.0, 28.0)
		var dir = Vector2(cos(angle), sin(angle))
		shard.add_point(Vector2(0, 0))
		shard.add_point(dir * length)
		shard.width = 2.5
		shard.default_color = Color(0.4, 0.6, 1.0)
		shard.position = pos
		bg.add_child(shard)
		var tw2 = create_tween()
		tw2.tween_property(shard, "position", pos + dir * 20.0, 0.15)
		tw2.parallel().tween_property(shard, "modulate", Color(1, 1, 1, 0), 0.15)
		tw2.tween_callback(shard.queue_free)

func death_anim_red(pos: Vector2):
	var flash = ColorRect.new()
	flash.size = Vector2(42, 42)
	flash.position = pos - Vector2(21, 21)
	flash.color = Color(1.0, 0.1, 0.1, 0.85)
	bg.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.2)
	tw.tween_callback(flash.queue_free)
	var ring = Line2D.new()
	ring.width = 3.0
	ring.default_color = Color(1.0, 0.2, 0.2, 0.85)
	var pts = 16
	for i in pts + 1:
		var angle = (float(i) / pts) * TAU
		ring.add_point(Vector2(cos(angle), sin(angle)) * 8.0)
	ring.position = pos
	bg.add_child(ring)
	var tw2 = create_tween()
	tw2.tween_property(ring, "scale", Vector2(4.5, 4.5), 0.35)
	tw2.parallel().tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.35)
	tw2.tween_callback(ring.queue_free)

func death_anim_boss(pos: Vector2):
	var flash = ColorRect.new()
	flash.size = Vector2(70, 70)
	flash.position = pos - Vector2(35, 35)
	flash.color = Color(1.0, 0.85, 0.1, 0.9)
	bg.add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash, "modulate", Color(1, 1, 1, 0), 0.35)
	tw.tween_callback(flash.queue_free)
	var shard_count = 10
	for i in shard_count:
		var shard = Line2D.new()
		var angle = (float(i) / shard_count) * TAU
		var length = randf_range(20.0, 45.0)
		var dir = Vector2(cos(angle), sin(angle))
		shard.add_point(Vector2(0, 0))
		shard.add_point(dir * length)
		shard.width = 3.5
		shard.default_color = Color(1.0, 0.75, 0.1)
		shard.position = pos
		bg.add_child(shard)
		var tw2 = create_tween()
		tw2.tween_property(shard, "position", pos + dir * 30.0, 0.5)
		tw2.parallel().tween_property(shard, "modulate", Color(1, 1, 1, 0), 0.5)
		tw2.tween_callback(shard.queue_free)
	for wave_i in 2:
		var ring = Line2D.new()
		ring.width = 4.0 - wave_i * 1.5
		ring.default_color = Color(1.0, 0.5, 0.1, 0.75 - wave_i * 0.25)
		var pts = 20
		for i in pts + 1:
			var angle = (float(i) / pts) * TAU
			ring.add_point(Vector2(cos(angle), sin(angle)) * 8.0)
		ring.position = pos
		bg.add_child(ring)
		var ring_tw = create_tween()
		ring_tw.tween_interval(wave_i * 0.15)
		ring_tw.tween_property(ring, "scale", Vector2(6.0 + wave_i * 2.0, 6.0 + wave_i * 2.0), 0.55)
		ring_tw.parallel().tween_property(ring, "modulate", Color(1, 1, 1, 0), 0.55)
		ring_tw.tween_callback(ring.queue_free)
	var cam = get_viewport().get_camera_2d()
	if cam:
		var shake_tw = create_tween()
		shake_tw.tween_property(cam, "offset", Vector2(8, 4), 0.07)
		shake_tw.tween_property(cam, "offset", Vector2(-8, -4), 0.07)
		shake_tw.tween_property(cam, "offset", Vector2(5, -3), 0.06)
		shake_tw.tween_property(cam, "offset", Vector2(-5, 3), 0.06)
		shake_tw.tween_property(cam, "offset", Vector2(0, 0), 0.05)

# ── Animation de dégâts d'évasion ───────────────────────────────
# Appelée pour chaque lane touchée quand un monstre atteint le bas de sa file.
# hit_color : couleur palette du monstre (palette["main"]).
# Fire-and-forget : pas d'await, les tweens tournent en arrière-plan.
func show_escape_hit(lane: int, hit_color: Color):
	var lane_cx     := float(BoardGeometry.GRID_ORIGIN_X + lane * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH / 2)
	var grid_bottom := float(BoardGeometry.GRID_ORIGIN_Y + BoardGeometry.GRID_ROWS * BoardGeometry.CELL_HEIGHT)
	var player_y    := float(BoardGeometry.PLAYER_Y)

	# Trait coloré vertical (couleur monstre → rouge en bas)
	var beam := Line2D.new()
	beam.add_point(Vector2(lane_cx, grid_bottom))
	beam.add_point(Vector2(lane_cx, player_y + 10.0))
	beam.width = 7.0
	beam.default_color = hit_color.lerp(Color(1.0, 0.15, 0.10), 0.35)
	beam.default_color.a = 0.88
	bg.add_child(beam)
	var tw_beam := create_tween()
	tw_beam.tween_property(beam, "modulate:a", 0.0, 0.20)
	tw_beam.tween_callback(beam.queue_free)

	# Flash rouge sur la zone joueur dans cette lane
	var flash := ColorRect.new()
	flash.size     = Vector2(BoardGeometry.CELL_WIDTH - 8, 40)
	flash.position = Vector2(BoardGeometry.GRID_ORIGIN_X + lane * BoardGeometry.CELL_WIDTH + 4, player_y - 22.0)
	flash.color    = Color(1.0, 0.12, 0.08, 0.80)
	bg.add_child(flash)
	var tw_flash := create_tween()
	tw_flash.tween_property(flash, "modulate:a", 0.0, 0.22)
	tw_flash.tween_callback(flash.queue_free)

	# Anneau rouge expansif centré sur la position joueur
	var ring := Line2D.new()
	ring.width         = 3.5
	ring.default_color = Color(1.0, 0.20, 0.10, 0.88)
	var pts := 18
	for i in pts + 1:
		var angle := (float(i) / pts) * TAU
		ring.add_point(Vector2(cos(angle), sin(angle)) * 10.0)
	ring.position = Vector2(lane_cx, player_y)
	bg.add_child(ring)
	var tw_ring := create_tween()
	tw_ring.tween_property(ring, "scale",     Vector2(3.8, 3.8), 0.30)
	tw_ring.parallel().tween_property(ring, "modulate:a", 0.0,   0.30)
	tw_ring.tween_callback(ring.queue_free)

	# Caméra shake léger
	var cam := get_viewport().get_camera_2d()
	if cam:
		var shake := create_tween()
		shake.tween_property(cam, "offset", Vector2( 5.0,  3.0), 0.05)
		shake.tween_property(cam, "offset", Vector2(-5.0, -2.0), 0.05)
		shake.tween_property(cam, "offset", Vector2( 3.0, -1.0), 0.04)
		shake.tween_property(cam, "offset", Vector2( 0.0,  0.0), 0.04)

# ── Float d'or ───────────────────────────────────────────────────
func show_gold_float(pos: Vector2, amount: int):
	var lbl = Label.new()
	lbl.text = "+%d 💰" % amount
	lbl.position = pos + Vector2(-28, -30)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	bg.add_child(lbl)
	var tw = create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -50), 0.7)
	tw.parallel().tween_property(lbl, "modulate", Color(1, 1, 1, 0), 0.7)
	tw.tween_callback(lbl.queue_free)

# ── Texte de lore ────────────────────────────────────────────────
func show_lore_text(rnum: int):
	var text = GameData.LORE_TEXTS.get(rnum, "")
	if text.is_empty():
		return

	var panel_w = 800
	var panel_h = 68
	var panel_x = 640.0 - panel_w / 2.0
	var panel_y = 498.0

	var panel = ColorRect.new()
	panel.color    = Color(0.0, 0.0, 0.0, 0.60)
	panel.size     = Vector2(panel_w, panel_h)
	panel.position = Vector2(panel_x, panel_y)
	panel.modulate.a = 0.0
	bg.add_child(panel)

	var lbl = RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content    = true
	lbl.scroll_active  = false
	lbl.text           = "[center][i]" + text + "[/i][/center]"
	lbl.size           = Vector2(panel_w - 24, panel_h)
	lbl.position       = Vector2(panel_x + 12, panel_y + 10)
	lbl.add_theme_font_size_override("normal_font_size", 17)
	lbl.add_theme_color_override("default_color", Color(0.9, 0.88, 0.8))
	lbl.modulate.a = 0.0
	bg.add_child(lbl)

	var tw = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.3)
	await tw.finished

	await get_tree().create_timer(2.5).timeout

	var tw2 = create_tween()
	tw2.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw2.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3)
	await tw2.finished

	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(lbl): lbl.queue_free()

# ── Son de victoire ──────────────────────────────────────────────
func play_jackpot_sound():
	var player = AudioStreamPlayer.new()
	add_child(player)

	var stream = AudioStreamGenerator.new()
	stream.mix_rate      = 22050.0
	stream.buffer_length = 0.6
	player.stream    = stream
	player.volume_db = -8.0
	player.play()

	var playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		player.queue_free()
		return

	var sample_rate   = 22050.0
	var notes         = [523.0, 659.0, 784.0, 1047.0]
	var note_duration = 0.1

	for note_freq in notes:
		var n_samples = int(sample_rate * note_duration)
		for i in n_samples:
			var t        = float(i) / sample_rate
			var envelope = 1.0 - float(i) / float(n_samples)
			var sample   = sin(TAU * note_freq * t) * 0.25 * envelope
			playback.push_frame(Vector2(sample, sample))

	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(player): player.queue_free()

# ── Animation porte de salle ─────────────────────────────────────
# add_gold_fn : Callable — appelé avec (amount: int) par game.gd, ex: _add_gold
func play_door_animation(room_num: int, player_lane: int, add_gold_fn: Callable):
	var door_w  = 200
	var door_h  = 280
	var cx      = 640
	var cy      = 340
	var door_x  = cx - door_w / 2
	var door_y  = cy - door_h / 2

	var stone = ColorRect.new()
	stone.size     = Vector2(door_w + 20, door_h + 20)
	stone.position = Vector2(door_x - 10, door_y - 10)
	stone.color    = Color(0.45, 0.42, 0.40)
	bg.add_child(stone)

	var glow = ColorRect.new()
	glow.size     = Vector2(door_w, door_h)
	glow.position = Vector2(door_x, door_y)
	glow.color    = Color(1.0, 0.85, 0.2, 0.0)
	bg.add_child(glow)

	var left_panel = ColorRect.new()
	left_panel.size     = Vector2(door_w / 2, door_h)
	left_panel.position = Vector2(door_x, door_y)
	left_panel.color    = Color(0.35, 0.2, 0.1)
	bg.add_child(left_panel)

	var right_panel = ColorRect.new()
	right_panel.size     = Vector2(door_w / 2, door_h)
	right_panel.position = Vector2(cx, door_y)
	right_panel.color    = Color(0.35, 0.2, 0.1)
	bg.add_child(right_panel)

	play_jackpot_sound()

	var t0 = Time.get_ticks_msec() / 1000.0
	var has_lore = GameData.LORE_TEXTS.has(room_num)
	if has_lore:
		show_lore_text(room_num)

	var tw = create_tween()
	tw.tween_property(left_panel,  "position:x", float(door_x - door_w / 2), 0.8)
	tw.parallel().tween_property(right_panel, "position:x", float(cx + door_w / 2), 0.8)
	tw.parallel().tween_property(glow, "color", Color(1.0, 0.85, 0.2, 0.6), 0.4)
	await tw.finished

	# +Or au-dessus du joueur
	var gold_bonus = _get_room_gold_bonus(room_num)
	add_gold_fn.call(gold_bonus)
	var pcx = BoardGeometry.GRID_ORIGIN_X + player_lane * BoardGeometry.CELL_WIDTH + BoardGeometry.CELL_WIDTH * 0.5
	var py  = float(BoardGeometry.PLAYER_Y) - 80.0
	var gold_lbl = Label.new()
	gold_lbl.text = "+%d 💰" % gold_bonus
	gold_lbl.custom_minimum_size = Vector2(200, 0)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lbl.position = Vector2(pcx - 100.0, py)
	gold_lbl.add_theme_font_size_override("font_size", 52)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	bg.add_child(gold_lbl)
	var tw2 = create_tween()
	tw2.tween_property(gold_lbl, "position:y", py - 110.0, 1.1)
	tw2.parallel().tween_property(gold_lbl, "modulate", Color(1, 1, 1, 0), 1.1)
	await tw2.finished
	if is_instance_valid(gold_lbl): gold_lbl.queue_free()

	var tw3 = create_tween()
	tw3.tween_property(stone,       "modulate", Color(1, 1, 1, 0), 0.4)
	tw3.parallel().tween_property(glow,        "modulate", Color(1, 1, 1, 0), 0.4)
	tw3.parallel().tween_property(left_panel,  "modulate", Color(1, 1, 1, 0), 0.4)
	tw3.parallel().tween_property(right_panel, "modulate", Color(1, 1, 1, 0), 0.4)
	await tw3.finished

	for n in [stone, glow, left_panel, right_panel]:
		if is_instance_valid(n): n.queue_free()

	if has_lore:
		var lore_total = 0.3 + 2.5 + 0.3
		var elapsed = Time.get_ticks_msec() / 1000.0 - t0
		var remain = lore_total - elapsed
		if remain > 0.0:
			await get_tree().create_timer(remain).timeout

# ── Bonus or par salle ───────────────────────────────────────────
func _get_room_gold_bonus(room: int) -> int:
	var table = {1: 20, 2: 40, 3: 70, 4: 110, 5: 150, 6: 200, 7: 260, 8: 330, 9: 410}
	if table.has(room):
		return table[room]
	return 410 + (room - 10) * 60
