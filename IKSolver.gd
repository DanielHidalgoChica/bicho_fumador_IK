extends Node
class_name IKSolver3D

# --- Conecta estos paths en el editor ---
@export var shoulder_pivot_path: NodePath
@export var elbow_pivot_path: NodePath
@export var wrist_roll_pivot_path: NodePath      # Y (roll)
@export var wrist_pitch_pivot_path: NodePath     # Z (pitch)


@export var mouth_end_path: NodePath
@export var fire_end_path: NodePath

@export var tolerance := 0.004       # en metros, por ejemplo
@export var step_max_deg := 10    # damping por paso (luego se usará en step)

# Para los tips
var use_cig_mouth : bool

# --- Arrays “lógicos” del solver ---1
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

# Target
var target_node : Node3D


# cache de ángulos (uno por joint)
var cache: Array[float] = []
var default_pose : Array[float] = []

# Para el movimiento suave y cálculo offline
var target_angles: Array[float] = [] # Aquí guardamos el destino final
@export var smoothing_speed: float = 4.0 # Velocidad de la animación
var use_smoothing: bool = true # Para poder desactivarlo si usas el debug "step"

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
	j_offset_local.append( wrist_roll.to_local(wrist_pitch.global_position) )   # wrist_roll → wrist_pitch (mismo punto)
	
	# (no necesitamos offset para el último)

	# 5) Tip offsets (desde el último joint físico = wrist_pitch)
	tip_mouth_local = wrist_pitch.to_local(mouth_end.global_position)
	tip_fire_local  = wrist_pitch.to_local(fire_end.global_position)
	
	# Por defecto, luego se cambia en el controller y se comprueba en los draws
	use_cig_mouth = true


	# 6) Límites por joint (en rad). Ajusta a tus rangos reales:
	j_min = [deg_to_rad(-180), deg_to_rad(0),   deg_to_rad(-130), deg_to_rad(-60)]
	j_max = [deg_to_rad(+0), deg_to_rad(+90), deg_to_rad(-40), deg_to_rad(+60)]

	# Sanidad de las longitudes
	assert(j_nodes.size() == j_axis_idx.size())
	assert(j_nodes.size() - 1 == j_offset_local.size())
	assert(j_nodes.size() == j_min.size() && j_nodes.size() == j_max.size())


	# 7) Rellenar cache leyendo el ángulo actual de cada eje
	cache = _read_angles_from_scene()
	target_angles = _read_angles_from_scene()
	
	default_pose = cache.duplicate()

func _process(delta: float) -> void:
	# Si tenemos un objetivo válido y el suavizado está activo
	if use_smoothing and target_angles.size() == j_nodes.size():
		_apply_pose_smooth(delta)


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
	#fill_cache()
	cache = default_pose.duplicate()
	if (use_cig_mouth):
		current_tip_local = tip_mouth_local
	else:
		current_tip_local = tip_fire_local
	goal_position = target_node.global_transform.origin
	# Calculamos la solución matemática (instantánea)
	last_touched_joint = 0
	var solution = solve() 
	
	# EN LUGAR DE set_pose(solution), AHORA HACEMOS ESTO:
	target_angles = solution # Guardamos el destino, el _process hará el movimiento
	
func solve() -> Array[float]:
	var iterations : int = 0
	var it_limit : int = 10000
	var debug = false
	while (not cache_goal_reached() and iterations < it_limit): 
		cache = step(debug)
		iterations += 1
	return cache

func return_to_default_smooth() -> void:
	target_angles = default_pose

func draw_step() -> void:
	fill_cache()
	if (use_cig_mouth):
		current_tip_local = tip_mouth_local
	else:
		current_tip_local = tip_fire_local
	goal_position = target_node.global_transform.origin
	
	var debug = true
	var out := step(debug)
	set_pose(out)              

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
		
		
func _apply_pose_smooth(delta: float) -> void:
	for i in j_nodes.size():
		var current_euler := j_nodes[i].rotation
		var goal := target_angles[i]
		var weight = smoothing_speed * delta
		
		match j_axis_idx[i]:
			Vector3.AXIS_X:
				current_euler.x = lerp_angle(current_euler.x, goal, weight)
			Vector3.AXIS_Y:
				current_euler.y = lerp_angle(current_euler.y, goal, weight)
			Vector3.AXIS_Z:
				current_euler.z = lerp_angle(current_euler.z, goal, weight)
		
		j_nodes[i].rotation = current_euler


func _axis_local(i: int) -> Vector3:
	return AXIS_UNIT[j_axis_idx[i]]
	
var last_touched_joint : int = 0

func step(debug) -> Array[float]:
	
	
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
	
	# --- INICIO DEBUG VISUAL ---
	# 1. Dibuja el EJE de rotación actual (AZUL)
	#    Si este eje no es perpendicular al movimiento que esperas, algo falla en axis_local.
	var anim_time : float = 0.1
	if (debug):
		DebugDraw3D.draw_arrow(joint_pos, joint_pos + axis_world * 0.5, Color.BLUE, 0.1,false,anim_time)

		# 2. Dibuja el "Brazo actual" desde este joint hasta el efector (ROJO)
		DebugDraw3D.draw_arrow(joint_pos, joint_pos + v_cur, Color.RED, 0.1,false,anim_time)

		# 3. Dibuja el vector "Ideal" hacia el objetivo (VERDE)
		DebugDraw3D.draw_arrow(joint_pos, joint_pos + v_tgt, Color.GREEN, 0.1, false,anim_time)

		# 4. Etiqueta para saber qué joint está trabajando
		DebugDraw3D.draw_text((joint_pos+Vector3(-1,0,0)), "J: " + str(i), 32,Color.WHITE,anim_time)
		# --- FIN DEBUG VISUAL ---
	
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



const AXIS_UNIT : Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


func get_cached_transform3d(output: Array[float], upto_idx: int) -> Transform3D:
	# marco global del padre del hombro
	var T : Transform3D = j_nodes[0].get_parent().global_transform
	# trasladarse al origen local del hombro
	T.origin += T.basis * j_nodes[0].position

	# ---------- joint 0 --------------
	var axis := AXIS_UNIT[j_axis_idx[0]]
	T.basis = T.basis * Basis(Quaternion(axis, output[0]))   # 1) girar en el hombro
	if upto_idx == 0:                                        #   (sin offset si es el último)
		return T

	T.origin += T.basis * j_offset_local[0]                  # 2) trasladar

	# ---------- joints 1 … upto_idx --------------
	for i in range(1, upto_idx + 1):
		axis = AXIS_UNIT[j_axis_idx[i]]
		T.basis = T.basis * Basis(Quaternion(axis, output[i]))   # 1) girar
		if i < upto_idx and i < j_offset_local.size():           # 2) trasladar
			T.origin += T.basis * j_offset_local[i]

	return T


# Tenemos en cuenta que usa current_tip_local, no podemos
# olvidar setear la variable antes de llamar al solver
func get_cached_end_position3d(output: Array[float]) -> Vector3:
	var last := j_nodes.size() - 1
	var T := get_cached_transform3d(output, last)
	return T * current_tip_local





























# asdsdgas
