extends Node
class_name IKSolver3D

# --- Conecta estos paths en el editor ---
@export var shoulder_pivot_path: NodePath
@export var elbow_pivot_path: NodePath
@export var wrist_roll_pivot_path: NodePath      # Y (roll)
@export var wrist_pitch_pivot_path: NodePath     # Z (pitch)

@export var mouth_target_path: NodePath

@export var mouth_end_path: NodePath
@export var fire_end_path: NodePath

@export var tolerance := 0.02        # en metros, por ejemplo
@export var step_max_deg := 180.0     # damping por paso (luego se usará en step)
@export var limits_min_deg := PackedFloat32Array() # opcional: o pon por-joint abajo
@export var limits_max_deg := PackedFloat32Array()

# --- Arrays “lógicos” del solver ---
var j_nodes: Array[Node3D] = []          # pivotes en orden hombro→codo→muñeca(roll)→muñeca(pitch)
var j_axis_idx: Array[int] = []    # ejes locales de cada joint (X/Y/Z)
var j_offset_local: Array[Vector3] = []  # offset local i→i+1 (último no se usa); roll→pitch = Vector3.ZERO
var j_min: Array[float] = []             # límites (rad)
var j_max: Array[float] = []

# efectores (desde el ÚLTIMO joint físico: wrist_pitch)
var tip_mouth_local := Vector3.ZERO
var tip_fire_local := Vector3.ZERO

var current_tip_local := Vector3.ZERO	# usa tip_mouth_local o tip_fire_local según el caso
var goal_position := Vector3.ZERO

# cache de ángulos (uno por joint)
var cache: Array[float] = []

func _ready() -> void:
	# 1) Resolver nodos de la escena
	var shoulder: Node3D     = get_node(shoulder_pivot_path)
	var elbow: Node3D        = get_node(elbow_pivot_path)
	var wrist_roll: Node3D   = get_node(wrist_roll_pivot_path)
	var wrist_pitch: Node3D  = get_node(wrist_pitch_pivot_path)
		
	var mouth_end: Node3D    = get_node(mouth_end_path)
	var fire_end: Node3D     = get_node(fire_end_path)
	


	
	# 2) Cadena lógica de joints (nodos en orden)
	j_nodes = [shoulder, elbow, wrist_roll, wrist_pitch]

	# 3) Ejes locales por joint
	#   Shoulder → X ; Elbow → Z ; Wrist roll → Y ; Wrist pitch → Z
	j_axis_idx = [Vector3.AXIS_X, Vector3.AXIS_Z, Vector3.AXIS_Y, Vector3.AXIS_Z]
	
	# 4) Offsets locales i→i+1 (precomputados UNA vez)
	j_offset_local.clear()
	j_offset_local.append( shoulder.to_local(elbow.global_position) )
	j_offset_local.append( elbow.to_local(wrist_roll.global_position) )
	j_offset_local.append( Vector3.ZERO )   # wrist_roll → wrist_pitch (mismo punto)
	# (no necesitamos offset para el último)

	# 5) Tip offsets (desde el último joint físico = wrist_pitch)
	tip_mouth_local = wrist_pitch.to_local(mouth_end.global_position)
	tip_fire_local  = wrist_pitch.to_local(fire_end.global_position)

	# 6) Límites por joint (en rad). Ajusta a tus rangos reales:
	j_min = [deg_to_rad(-180), deg_to_rad(-180),   deg_to_rad(-180), deg_to_rad(-180)]
	j_max = [deg_to_rad(+180), deg_to_rad(+180), deg_to_rad(+180), deg_to_rad(+180)]

	# Sanidad de las longitudes
	assert(j_nodes.size() == j_axis_idx.size())
	assert(j_nodes.size() - 1 == j_offset_local.size())
	assert(j_nodes.size() == j_min.size() && j_nodes.size() == j_max.size())


	# 7) Rellenar cache leyendo el ángulo actual de cada eje
	cache = _read_angles_from_scene()

func _read_angles_from_scene() -> Array[float]:
	var out: Array[float] = []
	for i in j_nodes.size():
		var e := j_nodes[i].rotation   # Euler local (rad) XYZ
		var a: float
		match j_axis_idx[i]:
			Vector3.AXIS_X:
				a = e.x
			Vector3.AXIS_Y:
				a = e.y
			Vector3.AXIS_Z:
				a = e.z
		out.append(a)
	return out





func draw_solve():
	fill_cache()
	current_tip_local = tip_mouth_local
	goal_position = get_node(mouth_target_path).global_transform.origin
	set_pose(solve())

# TODO clean up draw solve from solve
func solve() -> Array[float]:
	var iterations : int = 0
	while (not cache_goal_reached() and iterations < 50): 
		cache = step()
		iterations += 1
	
	return cache


func draw_step():
	fill_cache()
	current_tip_local = tip_mouth_local
	goal_position = get_node(mouth_target_path).global_transform.origin
	set_pose(step())

# Escribe el ángulo correspondiente a cada articulación
# con lo que hay en el array que se le pase
func set_pose(angles: Array[float]) -> void:
	for i in j_nodes.size():
		var e := j_nodes[i].rotation
		var a := angles[i]
		match j_axis_idx[i]:
			Vector3.AXIS_X:
				e.x = a
			Vector3.AXIS_Y:
				e.y = a
			Vector3.AXIS_Z:
				e.z = a
		j_nodes[i].rotation = e


#helper
func _axis_local(i: int) -> Vector3:
	return AXIS_UNIT[j_axis_idx[i]]
	
var last_touched_joint : int = 0

func step() -> Array[float]:
	
	
	var output := cache.duplicate()
		# 1) elegir joint (distal -> proximal)
	last_touched_joint -= 1
	if last_touched_joint < 0:
		last_touched_joint = j_nodes.size() - 1
	var i := last_touched_joint
	
	# 2) FK parcial: pose del joint i
	var Ti := get_cached_transform3d(output, i)
	var joint_pos := Ti.origin
	var axis_world := (Ti.basis * _axis_local(i)).normalized()

	
	# 3) vectores desde el joint
	var end_pos := get_cached_end_position3d(output)
	var v_cur := end_pos - joint_pos
	var v_tgt := goal_position - joint_pos
	
	# 4) proyectar al plano perpendicular al eje
	var v_cur_proj := v_cur - axis_world * (axis_world.dot(v_cur))
	var v_tgt_proj := v_tgt - axis_world * (axis_world.dot(v_tgt))
	# aquí en principio a ese if nunca llega porque
	# el vector v_cur debe estar contenido en el plano
	# ortogonal al eje, entonces el producto escalar es 0
	var len_cur := v_cur_proj.length()
	var len_tgt := v_tgt_proj.length()
	if len_cur < 1e-6 or len_tgt < 1e-6:
		return output	# este joint no puede ayudar en este paso
	v_cur_proj /= len_cur
	v_tgt_proj /= len_tgt
	
	# 5) ángulo con signo entre las proyecciones current y target alrededor de axis_world
	# como los vectores están normalizados, la norma del producto vectorial es el seno
	# el producto escalar con el eje es para controlar el signo
	var sin_signed := axis_world.dot(v_cur_proj.cross(v_tgt_proj))
	var cosv := v_cur_proj.dot(v_tgt_proj)
	var correction := atan2(sin_signed, cosv)
	
	var step_max := deg_to_rad(step_max_deg)
	var delta : float = clamp(correction, -step_max, step_max)

	var new_angle : float = output[i] + delta
	new_angle = clamp(new_angle, j_min[i], j_max[i])
	output[i] = new_angle
	
	return output



func fill_cache() -> void:
	cache.clear()
	for i in j_nodes.size():
		var e := j_nodes[i].rotation	# Euler local (rad)
		match j_axis_idx[i]:
			Vector3.AXIS_X:
				cache.append(e.x)
			Vector3.AXIS_Y:
				cache.append(e.y)
			Vector3.AXIS_Z:
				cache.append(e.z)




# if our "imagined" angles configuration returns a valuable solution for IK chain
# TODO unreachable
func cache_goal_reached() -> bool:
	var end_pos := get_cached_end_position3d(cache)
	return end_pos.distance_to(goal_position) < tolerance



const AXIS_UNIT := [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]

func get_cached_transform3d(output: Array[float], upto_idx: int) -> Transform3D:
	# base: colocamos el origen en el primer joint (posición y orientación actuales del hombro)
	var T := j_nodes[0].global_transform

	for i in range(0, upto_idx + 1):
		# 1) rotación local del joint i (alrededor de su eje X/Y/Z)
		var axis_local : Vector3 = AXIS_UNIT[j_axis_idx[i]]
		var angle := output[i]
		var R_local := Basis(Quaternion(axis_local, angle))

		# 2) si aún no hemos llegado al joint pedido, añadimos el offset i→i+1
		var off := Vector3.ZERO
		if i < upto_idx and i < j_offset_local.size():
			off = j_offset_local[i]

		# 3) concatenamos en local (como en 2D: T = T * TransformLocal(i))
		T = T * Transform3D(R_local, off)

	return T


# Tenemos en cuenta que usa current_tip_local, no podemos
# olvidar setear la variable antes de llamar al solver
func get_cached_end_position3d(output: Array[float]) -> Vector3:
	var last := j_nodes.size() - 1
	var T := get_cached_transform3d(output, last)
	return T.origin + T.basis * current_tip_local

#
#func count_cached_distance(cache : Array[float], i : int) -> float:
	#var endpoint = get_cached_end_position(cache, segments.size() - 1)
	#var position = get_cached_transform(cache, i).origin
	#return abs(position.distance_to(goal_position) - position.distance_to(endpoint))






























# asdsdgas
