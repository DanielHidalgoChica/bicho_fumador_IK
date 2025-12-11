extends Node
@export var ik_solver : IKSolver3D

func _process(delta):
	# Al soltar la tecla, calculamos el NUEVO destino.
	# El solver se encargará de interpolar hacia él en su propio _process.
	if Input.is_action_just_released("tip_mouth"):
		ik_solver.use_cig_mouth = true
		ik_solver.use_cig_tip = false
	if Input.is_action_just_released("tip_fire"):
		ik_solver.use_cig_mouth = false
		ik_solver.use_cig_tip = true
		
	if Input.is_action_just_released("ik_solve"):
		ik_solver.use_smoothing = true # Activamos suavizado
		ik_solver.draw_solve()         # Calcula y actualiza 'target_angles'

	# Para el "step" (debug paso a paso), normalmente NO queremos suavizado
	# porque queremos ver el algoritmo trabajar matemáticamente.
	if Input.is_action_just_released("ik_step"):
		ik_solver.use_smoothing = false # Desactivamos para ver el salto exacto
		ik_solver.draw_step()           # Tu función original que usa set_pose directo
