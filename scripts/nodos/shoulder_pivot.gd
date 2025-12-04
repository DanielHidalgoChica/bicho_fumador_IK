## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends Node3D

var activar_up := "activate_shoulder_up"   # nombre de la acción en el Input Map
var activar_down := "activate_shoulder_down"   # nombre de la acción en el Input Map

@export var rotation_speed_deg := 60.0    # grados por segundo

func _process(delta):
	# activar / desactivar con la tecla que pongas en el Input Map
	if Input.is_action_pressed(activar_up):
		rotation.x -= deg_to_rad(rotation_speed_deg * delta)
	if Input.is_action_pressed(activar_down):
		rotation.x += deg_to_rad(rotation_speed_deg * delta)	
