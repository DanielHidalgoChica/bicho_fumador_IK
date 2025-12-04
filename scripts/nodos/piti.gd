## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends MeshInstance3D

@export var mouth_path: NodePath        # nodo "Mouth" de la cara
@export var mouth_end_path: NodePath = "MouthEnd"  # punto del piti que toca la boca
@export var fire_end_path: NodePath = "FireEnd"    # el mesh rojo que hemos creado
#@export var ignite_distance := 0.085    # distancia máxima para considerarlo "en la boca"
@export var ignite_distance := 0.045   # distancia máxima para considerarlo "en la boca"

@export var smoke_path: NodePath = "Smoke"   
var smoke: CPUParticles3D

var mouth: Node3D
var mouth_end: Node3D
var fire_end: MeshInstance3D

func _ready():
	mouth = get_node(mouth_path)
	mouth_end = get_node(mouth_end_path)
	fire_end = get_node(fire_end_path)
	fire_end.visible = false   # apagado al inicio
	smoke = get_node(smoke_path)
	smoke.emitting = false
	
func _process(delta):
	# posiciones en el mundo
	var mouth_pos = mouth.global_transform.origin
	var cig_pos = mouth_end.global_transform.origin

	# distancia entre la boca y la punta del piti
	var dist = mouth_pos.distance_to(cig_pos)

	if dist < ignite_distance:
		fire_end.visible = true
		smoke.emitting = true
	else:
		fire_end.visible = false
		smoke.emitting = false
