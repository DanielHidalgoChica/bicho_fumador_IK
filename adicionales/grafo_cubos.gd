## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends Node3D

var cubitos: Array[MeshInstance3D] = []

var rotar : bool = true
func _process(delta: float) -> void:
	var activar_rotation_cube := "activate_rotation_cube"   # nombre de la acción en el Input Map

	var rotation_speed_deg := 360   # grados por segundo

	# activar / desactivar con la tecla que pongas en el Input Map
	if Input.is_action_just_pressed(activar_rotation_cube):
		if (rotar):
			rotar = false
		else:
			rotar = true
	
	if (rotar):
		var dtheta := rotation_speed_deg * delta 
		for c in cubitos:	
			var centro := c.global_transform.origin
			var eje_mundo := (Vector3.ZERO - centro).normalized()
			var rot := Basis(eje_mundo, dtheta)
			
			var g := c.global_transform
			g.basis = rot * g.basis
			c.global_transform = g



func _ready() -> void:
	# ---------- 3) CUBO CENTRAL DE REJILLAS ----------
	var m := 10
	var n := 10

	var mesh_rejilla := ArrayMeshRejilla(m, n)

	var mat_rejilla := StandardMaterial3D.new()
	mat_rejilla.vertex_color_use_as_albedo = true
	mat_rejilla.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Nodo contenedor con centro en el origen
	var cubo_central := Node3D.new()
	add_child(cubo_central)

	# Caras superior e inferior 
	# Rotamos convenientemente para tener buen culling
	var cara_abajo  = _crear_cara_cubo(cubo_central, mesh_rejilla, mat_rejilla, 
		Basis().rotated(Vector3.BACK,PI), Vector3(0,-0.5,0))  # y = -0.5
	var cara_arriba  = _crear_cara_cubo(cubo_central, mesh_rejilla, mat_rejilla,
		Basis(), Vector3(0,0.5,0))  # y = -0.5
	
	var cara_frente = _crear_cara_cubo(cubo_central, mesh_rejilla, mat_rejilla,
		Basis().rotated(Vector3.RIGHT,PI/2), Vector3(0,0,0.5))
	var cara_atras = _crear_cara_cubo(cubo_central, mesh_rejilla, mat_rejilla,
		Basis().rotated(Vector3.RIGHT,-PI/2), Vector3(0,0,-0.5))

	var cara_derecha = _crear_cara_cubo(cubo_central, mesh_rejilla, mat_rejilla,
		Basis().rotated(Vector3.BACK,-PI/2), Vector3(0.5,0,0))
	var cara_izquierda = _crear_cara_cubo(cubo_central, mesh_rejilla, mat_rejilla,
		Basis().rotated(Vector3.BACK,+PI/2), Vector3(-0.5,0,0))

	var mesh_cubo := ArrayMeshCubo24()

	var mat_cubo := StandardMaterial3D.new()
	mat_cubo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_cubo.albedo_color = Color(1, 1, 1)

	var base_scale := 0.25    # tamaño base del cubito
	var elongacion := 3     # cuánto se alarga hacia el origen

	# Todas las caras del cubo grande
	var caras := [
		cara_arriba,
		cara_abajo,
		cara_frente,
		cara_atras,
		cara_derecha,
		cara_izquierda,
	]

	for cara in caras:
		var cubito := MeshInstance3D.new()
		cubito.mesh = mesh_cubo
		cubito.material_override = mat_cubo

		# Escala anisotrópica
		var scale_y := base_scale * elongacion
		# Como antes el lado medía 1, ahora mide exactamente scale_y
		cubito.scale = Vector3(base_scale, scale_y, base_scale)

		# Desplazar el centro del cubito hacia fuera de la cara
		var half_height := 0.5 * scale_y
		cubito.position = Vector3(0, half_height, 0)
		# Si alguna cara te queda hacia dentro, para esa cara usarías -half_height
		cara.add_child(cubito)	
		cubitos.append(cubito)


# ---------- FUNCIONES AUXILIARES ----------

func _crear_cara_cubo(
	parent: Node3D,
	mesh_rejilla: ArrayMesh,
	mat_rejilla: StandardMaterial3D,
	basis: Basis,
	origin: Vector3
) -> MeshInstance3D:
	var cara := MeshInstance3D.new()
	cara.mesh = mesh_rejilla
	cara.material_override = mat_rejilla
	cara.transform = Transform3D(basis, origin)
	parent.add_child(cara)
	return cara


func ArrayMeshRejilla(m: int, n: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colores  := PackedColorArray()
	var indices  := PackedInt32Array()
	var normales := PackedVector3Array()

	for i in range(m):
		var x := float(i) / float(m - 1)
		for j in range(n):
			var z := float(j) / float(n - 1)
			# Corrijo para que la rotación aquí sea
			# más fácil
			var v := Vector3(x-0.5, 0.0, z-0.5)
			vertices.append(v)
			colores.append(Color(v.x, v.y, v.z, 1.0))
			normales.append(Vector3.DOWN)

	for i in range(m - 1):
		for j in range(n - 1):
			var v00 := i * n + j
			var v10 := (i + 1) * n + j
			var v01 := i * n + (j + 1)
			var v11 := (i + 1) * n + (j + 1)

			indices.append_array([v00, v10, v11])
			indices.append_array([v00, v11, v01])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR]  = colores
	arrays[Mesh.ARRAY_INDEX]  = indices
	arrays[Mesh.ARRAY_NORMAL] = normales

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func ArrayMeshCubo24() -> ArrayMesh:
	var vertices := PackedVector3Array([])
	var triangulos := PackedInt32Array([])

	for h in 3:
		for i in 2:
			for j in 2:
				for k in 2:
					vertices.push_back(Vector3(i-0.5, j-0.5, k-0.5))

	triangulos.append_array(PackedInt32Array([
		## Frente (normal en −Z)
		1, 7, 5,
		1, 3, 7,

		## Atrás (normal en +Z)
		8, 4, 2,
		4, 6, 2,

		## Izquierda (normal en −X)
		1+8, 2+8, 3+8,
		1+8, 8,   2+8,

		## Derecha (normal en +X)
		5+8, 7+8, 6+8,
		5+8, 6+8, 4+8,

		## Arriba (normal en +Y)
		2+16, 6+16, 3+16,
		3+16, 6+16, 7+16,

		## Abajo (normal en −Y)
		1+16, 5+16, 4+16,
		1+16, 4+16, 16,
	]))
	var normales := Utilidades.calcNormales(vertices, triangulos)

	var tablas : Array = []
	tablas.resize(Mesh.ARRAY_MAX)
	tablas[Mesh.ARRAY_VERTEX] = vertices
	tablas[Mesh.ARRAY_INDEX]  = triangulos
	tablas[Mesh.ARRAY_NORMAL] = normales

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tablas)
	return mesh
