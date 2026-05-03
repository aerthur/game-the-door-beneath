extends Control
# ── DoorDrawing ───────────────────────────────────────────────────
# Reproduit la porte gothique du Design System Claude (slide 02).
# Coordonnées converties depuis le SVG viewBox (-8,-6 176×254).
# Contenu utile : x=4→156 (152px), y=8→245 (237px).
# Affiché à 90×130 px par défaut (custom_minimum_size dans la scène).

const C_GOLD     := Color(0.722, 0.604, 0.306)         # #b89a4e
const C_GOLD_DIM := Color(0.420, 0.353, 0.157)         # #6b5a28
const C_GOLD_LN  := Color(0.784, 0.627, 0.251, 0.40)  # #c8a040 @40%
const C_DARK     := Color(0.102, 0.075, 0.031)         # #1a1308
const C_WHITE_DM := Color(1.000, 0.973, 0.878, 0.20)  # #fff8e0 @20%
const C_KEYHOLE  := Color(0.784, 0.627, 0.251, 0.90)  # #c8a040 @90%

# Bezier quadratique : retourne n+1 points (inclus p0 et p2)
static func _qb(p0: Vector2, p1: Vector2, p2: Vector2, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var u := 1.0 - t
		pts.append(u * u * p0 + 2.0 * u * t * p1 + t * t * p2)
	return pts

# SVG coords → écran 90×130
func _s(x: float, y: float) -> Vector2:
	return Vector2((x - 4.0) * 90.0 / 152.0, (y - 8.0) * 130.0 / 237.0)

func _draw() -> void:
	# Centrer dans le Control si plus grand que 90×130
	var ox := (size.x - 90.0) * 0.5
	var oy := (size.y - 130.0) * 0.5
	draw_set_transform(Vector2(ox, oy))

	# ── Arche extérieure ─────────────────────────────────────────
	# M4,245 L4,96 Q4,8 80,8 Q156,8 156,96 L156,245
	var arch := PackedVector2Array()
	arch.append(_s(4, 245))
	arch.append(_s(4, 96))
	var a1 := _qb(_s(4, 96), _s(4, 8), _s(80, 8))
	a1.remove_at(0)
	arch.append_array(a1)
	var a2 := _qb(_s(80, 8), _s(156, 8), _s(156, 96))
	a2.remove_at(0)
	arch.append_array(a2)
	arch.append(_s(156, 245))
	draw_polyline(arch, C_GOLD_DIM, 2.5)

	# ── Panneau gauche (remplissage sombre) ──────────────────────
	var lp := PackedVector2Array()
	lp.append(_s(14, 245))
	lp.append(_s(14, 100))
	var lc := _qb(_s(14, 100), _s(20, 22), _s(80, 20))
	lc.remove_at(0)
	lp.append_array(lc)
	lp.append(_s(74, 245))
	draw_colored_polygon(lp, C_DARK)

	# ── Panneau droit (remplissage sombre) ───────────────────────
	var rp := PackedVector2Array()
	rp.append(_s(86, 245))
	rp.append(_s(80, 20))
	var rc := _qb(_s(80, 20), _s(140, 22), _s(146, 100))
	rc.remove_at(0)
	rp.append_array(rc)
	rp.append(_s(146, 245))
	draw_colored_polygon(rp, C_DARK)

	# ── Encadrements de panneau (rectangles décoratifs) ──────────
	var _r := func(pts: Array) -> void:
		var pa := PackedVector2Array()
		for v in pts: pa.append(v)
		pa.append(pts[0])  # fermer le rectangle
		draw_polyline(pa, C_GOLD_DIM, 0.8)

	# Gauche haut
	_r.call([_s(20,40), _s(68,38), _s(66,130), _s(20,132)])
	# Gauche bas
	_r.call([_s(20,142), _s(68,140), _s(66,210), _s(20,212)])
	# Droite haut
	_r.call([_s(92,38), _s(140,40), _s(140,132), _s(92,130)])
	# Droite bas
	_r.call([_s(92,140), _s(140,142), _s(140,212), _s(92,210)])

	# ── Lignes centrales (fente de porte) ────────────────────────
	draw_line(_s(69, 20), _s(75, 245), C_GOLD_LN, 2.0)   # gauche
	draw_line(_s(84, 20), _s(85, 245), C_GOLD_LN, 2.0)   # droite
	draw_line(_s(80, 18), _s(80, 245), C_WHITE_DM, 1.5)   # lumière centrale

	# ── Poignées ─────────────────────────────────────────────────
	for cx in [62.0, 98.0]:
		var hc := _s(cx, 155)
		draw_arc(hc, 2.7, 0.0, TAU, 32, C_GOLD, 1.2)
		draw_circle(hc, 1.1, C_GOLD)

	# ── Serrure centrale ─────────────────────────────────────────
	draw_circle(_s(80, 138), 1.8, C_KEYHOLE)

	draw_set_transform(Vector2.ZERO)
