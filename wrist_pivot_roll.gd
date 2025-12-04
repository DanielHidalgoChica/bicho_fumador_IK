## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends Node3D

# rotación en la Y
var activate_hand_right := "activate_hand_right"   # nombre de la acción en el Input Map

var activate_hand_left := "activate_hand_left"   # nombre de la acción en el Input Map

@export var rotation_speed_deg_2 := 120

func _process(delta):
	# eje Y
	if Input.is_action_pressed(activate_hand_right):
		rotation.y += deg_to_rad(rotation_speed_deg_2 * delta)
	if Input.is_action_pressed(activate_hand_left):
		rotation.y -= deg_to_rad(rotation_speed_deg_2 * delta)
