## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends Node3D

var activar_out := "activar_codo_in"   # nombre de la acción en el Input Map
var activar_in := "activar_codo_out"   # nombre de la acción en el Input Map

@export var rotation_speed_elbow_deg := 60.0    # grados por segundo


func _process(delta : float):
	# Rota sobre el eje Z del padre 
	var v :=  Vector3(0,0,1)
	var ang := deg_to_rad(rotation_speed_elbow_deg*delta)

	if Input.is_action_pressed(activar_in):
		transform = Transform3D().rotated(v,ang) * transform
	if Input.is_action_pressed(activar_out):
		transform = Transform3D().rotated(v,-ang) * transform	
