## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends Node3D

# rotación en la Z
var activate_hand_in := "activate_hand_in"   # nombre de la acción en el Input Map

var activate_hand_out := "activate_hand_out"   # nombre de la acción en el Input Map


@export var rotation_speed_deg_1 := 60

func _process(delta):
	# eje Z
	if Input.is_action_pressed(activate_hand_in):
		rotation.z += deg_to_rad(rotation_speed_deg_1 * delta)
	if Input.is_action_pressed(activate_hand_out):
		rotation.z -= deg_to_rad(rotation_speed_deg_1 * delta)
