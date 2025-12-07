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

@export var tolerance := 0.04        # en metros, por ejemplo
@export var step_max_deg := 10    # damping por paso (luego se usará en step)


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
	j_offset_local.append( wrist_roll.to_local(wrist_pitch.global_position) )   # wrist_roll → wrist_pitch (mismo punto)
	
	# (no necesitamos offset para el último)

	# 5) Tip offsets (desde el último joint físico = wrist_pitch)
	tip_mouth_local = wrist_pitch.to_local(mouth_end.global_position)
	tip_fire_local  = wrist_pitch.to_local(fire_end.global_position)
	
	# Ponemos provisionalmente current_tip_local como tip_mouth_local, es decir
	# que el efector sea el filtro del cigarro
	current_tip_local = tip_mouth_local


	# 6) Límites por joint (en rad). Ajusta a tus rangos reales:
	j_min = [deg_to_rad(-180), deg_to_rad(0),   deg_to_rad(-130), deg_to_rad(-60)]
	j_max = [deg_to_rad(+0), deg_to_rad(+90), deg_to_rad(-40), deg_to_rad(+60)]

	# Sanidad de las longitudes
	assert(j_nodes.size() == j_axis_idx.size())
	assert(j_nodes.size() - 1 == j_offset_local.size())
	assert(j_nodes.size() == j_min.size() && j_nodes.size() == j_max.size())


	# 7) Rellenar cache leyendo el ángulo actual de cada eje
	cache = _read_angles_from_scene()
	test_fk_consistency()
	_debug_chain(cache)
	
#--DD#DEGUB FUNCTIONS
func debug_draw_vectors(origin: Vector3, v_cur: Vector3, v_tgt: Vector3, axis: Vector3):
	# Dibuja línea ROJA hacia donde está el efector ahora
	DebugDraw3D.draw_line(origin, origin + v_cur, Color.RED) 
	# Dibuja línea VERDE hacia donde quieres ir
	DebugDraw3D.draw_line(origin, origin + v_tgt, Color.GREEN)
	# Dibuja línea AZUL para el eje de rotación
	DebugDraw3D.draw_line(origin, origin + axis * 0.2, Color.BLUE)
func print_deg(arr_ang: Array[float]) -> void:
	var arr_c : Array[float]
	for i in arr_ang.size():
		arr_c.append(arr_ang[i]*360/(2*PI))
	print(arr_c)
# Me comprueba que en el estado inicial la posición del efector calculada sea
# la posición real del efector
func test_fk_consistency() -> void:
	fill_cache()             # lee los ángulos REALES de la escena
	var out := cache.duplicate()
	var pred_end := get_cached_end_position3d(out)   # FK con esos mismos ángulos
	var real_end := (get_node(mouth_end_path) as Node3D).global_transform.origin
	print("FK error = ", pred_end.distance_to(real_end))

func debug_compare_basis(joint_idx: int, fk_transform: Transform3D):
	var real_node = j_nodes[joint_idx]
	var real_basis = real_node.global_transform.basis
	var fk_basis = fk_transform.basis
	
	print("\n--- DEBUG JOINT ", joint_idx, " ---")
	print("Real Euler (deg): ", _v3_to_deg(real_basis.get_euler()))
	print("FK   Euler (deg): ", _v3_to_deg(fk_basis.get_euler()))
	
	# Producto punto de los vectores base para ver alineación
	# Si da 1.0 están alineados, -1.0 opuestos, 0.0 perpendiculares
	var x_align = real_basis.x.dot(fk_basis.x)
	var y_align = real_basis.y.dot(fk_basis.y)
	var z_align = real_basis.z.dot(fk_basis.z)
	
	print("Alineación X: ", x_align)
	print("Alineación Y: ", y_align)
	print("Alineación Z: ", z_align)

	if x_align < 0.99 or y_align < 0.99 or z_align < 0.99:
		print("¡DESVIACIÓN DETECTADA! La orientación no coincide.")

func _v3_to_deg(v: Vector3) -> Vector3:
	return Vector3(rad_to_deg(v.x), rad_to_deg(v.y), rad_to_deg(v.z))
func _base_of_chain() -> Transform3D:
	var root := j_nodes[0]
	var parent := root.get_parent()
	if parent is Node3D:
		return parent.global_transform
	return Transform3D() # identidad si no hay padre Node3D

func _debug_chain(out_angles: Array[float]) -> void:
	var T := _base_of_chain()                 # marco del padre del hombro
	print("\n== CADENA DEBUG ==")
	for i in j_nodes.size():
		var transform = get_cached_transform3d(out_angles, i)
		debug_compare_basis(i, transform)
		var fk_pos := get_cached_transform3d(out_angles,i).origin
		
		var real_pos := j_nodes[i].global_transform.origin
		var delta := fk_pos.distance_to(real_pos)
		
		print("joint ", i, "  Δpos = ", str(delta).pad_decimals(4),
			  "   fk=", fk_pos, "   real=", real_pos)


# ---ENDDEBUG
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
	goal_position = get_node(mouth_target_path).global_transform.origin
	set_pose(solve())

# TODO clean up draw solve from solve
func solve() -> Array[float]:
	var iterations : int = 0
	while (not cache_goal_reached() and iterations < 50): 
		cache = step()
		iterations += 1
	
	return cache


func draw_step() -> void:
	fill_cache()

	var mouth_target := get_node(mouth_target_path) as Node3D
	goal_position = mouth_target.global_transform.origin

	var out := step()                                # 1 paso (PREDICCIÓN)
	var pred_end := get_cached_end_position3d(out)
	var pred_dist := pred_end.distance_to(goal_position)

	set_pose(out)                                    # aplicamos la POSE
	# (opcional) espera un frame si quieres asegurarte de la propagación
	# await get_tree().process_frame

	var mouth_end := get_node(mouth_end_path) as Node3D
	var real_end := mouth_end.global_transform.origin
	var real_dist := real_end.distance_to(goal_position)

	print("pred_dist=", pred_dist, "  real_dist=", real_dist)
	print("goal=", goal_position, "  pred_end=", pred_end, "  real_end=", real_end)




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
	# --- INICIO DEBUG VISUAL ---
	## 1. Dibuja el EJE de rotación actual (AZUL)
	##    Si este eje no es perpendicular al movimiento que esperas, algo falla en axis_local.
	#var anim_time : float = 5
	#DebugDraw3D.draw_arrow(joint_pos, joint_pos + axis_world * 0.5, Color.BLUE, 0.1,false,anim_time)
#
	## 2. Dibuja el "Brazo actual" desde este joint hasta el efector (ROJO)
	#DebugDraw3D.draw_arrow(joint_pos, joint_pos + v_cur, Color.RED, 0.1,false,anim_time)
#
	## 3. Dibuja el vector "Ideal" hacia el objetivo (VERDE)
	#DebugDraw3D.draw_arrow(joint_pos, joint_pos + v_tgt, Color.GREEN, 0.1, false,anim_time)
#
	## 4. Etiqueta para saber qué joint está trabajando
	#DebugDraw3D.draw_text((joint_pos+Vector3(-1,0,0)), "J: " + str(i), 32,Color.WHITE,anim_time)
	## --- FIN DEBUG VISUAL ---
	
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
	
	print("i=", i, " dist=", get_cached_end_position3d(output).distance_to(goal_position))
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

#
#func count_cached_distance(cache : Array[float], i : int) -> float:
	#var endpoint = get_cached_end_position(cache, segments.size() - 1)
	#var position = get_cached_transform(cache, i).origin
	#return abs(position.distance_to(goal_position) - position.distance_to(endpoint))






























# asdsdgas
