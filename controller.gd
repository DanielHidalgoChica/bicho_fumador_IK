extends Node
@export var ik_solver : IKSolver3D

@export var camera_path: NodePath
@export var red_dot_path: NodePath
@export var mouth_target_path : NodePath
@export var ik_target_path: NodePath # El nodo vacío que persigue el brazo

@onready var camera = get_node(camera_path)
@onready var red_dot = get_node(red_dot_path)
@onready var ik_target = get_node(ik_target_path)


func _process(delta):
	# Al soltar la tecla, calculamos el NUEVO destino.
	# El solver se encargará de interpolar hacia él en su propio _process.
	if Input.is_action_just_released("tip_mouth"):
		ik_solver.use_cig_mouth = true
	if Input.is_action_just_released("tip_fire"):
		ik_solver.use_cig_mouth = false
		
	if Input.is_action_just_released("ik_solve"):
		ik_target = get_node(mouth_target_path)
		ik_solver.target_node = ik_target
		ik_solver.use_smoothing = true # Activamos suavizado
		ik_solver.smoothing_speed = 4

		ik_solver.draw_solve()         # Calcula y actualiza 'target_angles'

	# Para el "step" (debug paso a paso), normalmente NO queremos suavizado
	# porque queremos ver el algoritmo trabajar matemáticamente.
	if Input.is_action_just_released("ik_step"):
		ik_target = get_node(mouth_target_path)
		ik_solver.target_node = ik_target
		ik_solver.use_smoothing = false # Desactivamos para ver el salto exacto
		ik_solver.draw_step()           
		
	if Input.is_action_just_released("return-default"):
		ik_solver.use_smoothing = true # Desactivamos para ver el salto exacto
		ik_solver.smoothing_speed = 4
		ik_solver.return_to_default_smooth()
		
func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			raycast_from_mouse(event.position)# Tema del ratón
func raycast_from_mouse(mouse_pos: Vector2):
	# 1. Accedemos al estado físico del espacio
	var space_state = get_viewport().get_world_3d().direct_space_state
	
	# 2. Preparamos el rayo desde la cámara
	var origin = camera.project_ray_origin(mouse_pos)
	var normal = camera.project_ray_normal(mouse_pos)
	var end = origin + normal * 1000.0 # Un rayo de 1000 metros
	
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_bodies = true
	# 3. Lanzamos el rayo y obtenemos el resultado
	var result = space_state.intersect_ray(query)
	
	if result:
		# result.position es el punto exacto del impacto en el mundo 3D
		var hit_pos = result["position"]
		var hit_normal = result["normal"]
		
		# --- FILTRO : ¿Hemos dado en la parte de arriba? ---
		# El vector UP es (0, 1, 0). Si la normal se parece a UP, es la superficie superior.
		# Si la normal apunta a los lados, habremos dado en el borde.
		if hit_normal.dot(Vector3.UP) > 0.8:
			# A) Movemos el punto rojo visual
			red_dot.visible = true
			red_dot.global_position = hit_pos
			red_dot.visible = true
			
			# Que el bicho pegue un calo primero
		
			# Para que se espere a que llegue a pose natural antes de ir
			ik_solver.smoothing_speed = 2
			# B) Movemos el objetivo real del IK
			ik_target = get_node(ik_target_path)
			ik_target.global_position = hit_pos
			ik_solver.target_node = ik_target
			
			# C) Activamos el Solver (con la punta del cigarro seleccionada)
			ik_solver.use_cig_mouth = false
			
			# Llamamos a resolver el movimiento
			ik_solver.use_smoothing = true

			ik_solver.draw_solve()     
			
