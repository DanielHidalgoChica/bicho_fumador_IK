extends Node
class_name IKSolver3D

# --- Conecta estos paths en el editor ---
@export var shoulder_pivot_path: NodePath
@export var elbow_pivot_path: NodePath
@export var wrist_roll_pivot_path: NodePath      # Y (roll)
@export var wrist_pitch_pivot_path: NodePath     # Z (pitch)

@export var mouth_end_path: NodePath
@export var fire_end_path: NodePath

@export var tolerance := 0.02        # en metros, por ejemplo
@export var step_max_deg := 20.0     # damping por paso (luego lo usarás en step)
@export var limits_min_deg := PackedFloat32Array() # opcional: o pon por-joint abajo
@export var limits_max_deg := PackedFloat32Array()

# --- Arrays “lógicos” del solver ---
var j_nodes: Array[Node3D] = []          # pivotes en orden hombro→codo→muñeca(roll)→muñeca(pitch)
var j_axis_local: Array[Vector3] = []    # ejes locales de cada joint (X/Y/Z)
var j_offset_local: Array[Vector3] = []  # offset local i→i+1 (último no se usa); roll→pitch = Vector3.ZERO
var j_min: Array[float] = []             # límites (rad)
var j_max: Array[float] = []

# efectores (desde el ÚLTIMO joint físico: wrist_pitch)
var tip_mouth_local := Vector3.ZERO
var tip_fire_local := Vector3.ZERO

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

	# 3) Ejes locales por joint (ajusta a tu diseño real)
	#   Shoulder → X ; Elbow → Z ; Wrist roll → Y ; Wrist pitch → Z
	j_axis_local = [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, Vector3.FORWARD]

	# 4) Offsets locales i→i+1 (precomputados UNA vez)
	j_offset_local.clear()
	j_offset_local.append( shoulder.to_local(elbow.global_position) )
	j_offset_local.append( elbow.to_local(wrist_roll.global_position) )
	j_offset_local.append( Vector3.ZERO )   # wrist_roll → wrist_pitch (mismo punto)
	# (no necesitas offset para el último)

	# 5) Tip offsets (desde el último joint físico = wrist_pitch)
	tip_mouth_local = wrist_pitch.to_local(mouth_end.global_position)
	tip_fire_local  = wrist_pitch.to_local(fire_end.global_position)

	# 6) Límites por joint (en rad). Ajusta a tus rangos reales:
	j_min = [deg_to_rad(-60), deg_to_rad(0),   deg_to_rad(-90), deg_to_rad(-60)]
	j_max = [deg_to_rad(+60), deg_to_rad(140), deg_to_rad(+90), deg_to_rad(+60)]

	# 7) Rellenar cache leyendo el ángulo actual de cada eje
	cache = _read_angles_from_scene()

func _read_angles_from_scene() -> Array[float]:
	var out: Array[float] = []
	for i in j_nodes.size():
		var e := j_nodes[i].rotation   # Euler local (rad) XYZ
		var axis := j_axis_local[i]
		out.append(
			axis == Vector3.RIGHT   ? e.x :
			axis == Vector3.UP      ? e.y :
									  e.z
		)
	return out

#
#
#func build_chain(segment : ArmSegment):
	#for child in segment.get_children():
		#if child is ArmSegment:
			#segments.append(child)
			#build_chain(child)
#
#
#func draw_solve():
	#fill_cache()
	#goal_position = get_viewport().get_mouse_position()
	#set_pose(solve())
	#redraw_constraints()
#
#
## TODO clean up draw solve from solve
#func solve() -> Array[float]:
	#var start = Time.get_unix_time_from_system()
	#var iterations : int = 0
	#while not cache_goal_reached(): 
		#cache = step()
		#iterations += 1
	#debug_label.text = str(iterations) + " iterations to solve \n"
	#debug_label.text += str((Time.get_unix_time_from_system() - start) * 1000) + " ms spent"
	#return cache
#
#
#func draw_step():
	#fill_cache()
	#goal_position = get_viewport().get_mouse_position()
	#set_pose(step())
	#redraw_constraints()
#
#
#func set_pose(angles : Array[float]):
	#for i in segments.size():
		#segments[i].rotation = angles[i]
#
#
#func step() -> Array[float]:
	#return []
#
#
#func fill_cache():
	#cache.clear()
	#for segment in segments:
		#cache.append(segment.rotation)
#
#
#func redraw_constraints():
	#for segment in segments:
		#segment.redraw_constraints()
#
#
## if our "imagined" angles configuration returns a valuable solution for IK chain
## TODO unreachable
#func cache_goal_reached() -> bool:
	#return get_cached_end_position(cache, segments.size() - 1).distance_to(goal_position) < tolerance
#
#
#func get_cached_transform(output : Array[float], segment : int) -> Transform2D:
	#var transform : Transform2D = Transform2D(output[0], segments[0].global_position)
	#for i in range(1, segment + 1):
		#transform = transform * Transform2D(output[i], segments[i].position)
	#return transform
#
#
#func get_cached_end_position(output : Array[float], segment : int) -> Vector2:
	#var transform : Transform2D = Transform2D(output[0], segments[0].global_position)
	#for i in range(1, segment + 1):
		#transform = transform * Transform2D(output[i], segments[i].position)
	#return transform * Vector2(segments[segment].length, 0)
#
#
#func count_cached_distance(cache : Array[float], i : int) -> float:
	#var endpoint = get_cached_end_position(cache, segments.size() - 1)
	#var position = get_cached_transform(cache, i).origin
	#return abs(position.distance_to(goal_position) - position.distance_to(endpoint))






























# asdsdgas
