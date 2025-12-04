## Nombre: Daniel Apellidos: Hidalgo Chica Titulación: GIM
## email: danielhc@correo.ugr.es DNI: 21037568C 
extends Node3D

func _ready():
	# Número de puntas
	var n := 6
	var mesh_est = ArrayMeshEstrellaZ(n)
	
	var inst_estrella = MeshInstance3D.new()
	inst_estrella.mesh = mesh_est

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # sin iluminación
	inst_estrella.material_override = mat
	
	add_child(inst_estrella)
	
	var mesh_cono := generar_mesh_cono()
	var mat_cono := StandardMaterial3D.new()
	mat_cono.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_cono.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_cono.albedo_color = Color(0.9, 0.9, 0.9)
	
	# Parámetros geométricos (los mismos que usaste en ArrayMeshEstrellaZ)
	var r_outer := 0.5              # radio de las puntas de la estrella
	var altura_cono := 0.15         # altura del cono (coincide con generar_mesh_cono)
	var angle_step_tip := 2.0 * PI / float(n)  # ángulo entre puntas (2π/n)
	var centro := Vector3(0, 0, 0)  # centro de la estrella

	for k in range(n):
		# Dirección del radio hacia la punta k-ésima
		var angle := -float(k) * angle_step_tip
		var dir := Vector3(cos(angle), sin(angle), 0.0).normalized()

		# Posición de la punta (coincide con la de la estrella)
		var punta := centro + dir * (r_outer + altura_cono)

		# Queremos que el eje del cono:
		# - tenga la misma dirección que 'dir'
		# - tenga longitud = altura_cono
		# - vaya desde la base hasta el ápice
		# Colocamos el ápice exactamente en la punta y la base hacia dentro:
		var base_center := punta - dir * altura_cono

		# Crear instancia del cono que COMPARTIRÁ la misma malla y material
		var inst_cono := MeshInstance3D.new()
		inst_cono.mesh = mesh_cono
		inst_cono.material_override = mat_cono

		# Rotación: alinear el eje local +Y del cono con 'dir'
		var rot := Transform3D().rotated(Vector3(0,0,1),-PI/2+angle)
		var tras := Transform3D().translated(base_center)

		# Transform del cono: primero rotación, luego traslación
		# (el origen de la malla del cono está en el centro de la base en (0,0,0),
		#  y el ápice en (0,altura_cono,0) antes de transformar).
		inst_cono.transform = tras * rot

		add_child(inst_cono)
		
	## Corregimos la orientación de la estrella para que esté ocomo el 
	## en el guión
	transform = Transform3D().rotated(Vector3(0,1,0),PI/2)

var rotar : bool = true
func _process(delta: float) -> void:
	var activar_x := "activate_rotation_x"   # nombre de la acción en el Input Map

	var rotation_speed_deg := 360 * 2.5   # grados por segundo (son 2.5 vueltas por sec

	# activar / desactivar con la tecla que pongas en el Input Map
	if Input.is_action_just_pressed(activar_x):
		if (rotar):
			rotar = false
		else:
			rotar = true
	
	if (rotar): 
		rotation.z -= deg_to_rad(rotation_speed_deg * delta)

# Devuelve la malla indexada con la estrella en el plano Z=0,
# centro en (0, 0) y colores de vértices según coordenadas.
func ArrayMeshEstrellaZ(n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var c := Vector3(0, 0, 0.0)  # centro
	var arrVer: PackedVector3Array = []  
	arrVer.append(c)

	var r_outer := 0.5   # radio de las puntas 
	var r_inner := 0.25  # radio de los valles 
	var angle_step := PI / n   

	# Generamos 2n vértices alternando radio grande / pequeño
	# k = 0..2n-1 → arrVer[1]..arrVer[2n]
	for k in range(2 * n):
		var angle := -float(k) * angle_step
		var r := r_outer if (k % 2 == 0) else r_inner

		var x := c.x + r * cos(angle)
		var y := c.y + r * sin(angle)
		var vertex := Vector3(x, y, 0.0)
		arrVer.append(vertex)

	# Triángulos (centro, v_j, v_{j+1}) para j = 1..2n-1
	for j in range(1, 2 * n):
		# centro
		st.set_color(Color(1, 1, 1))
		st.add_vertex(c)

		# vértice j
		var vj := arrVer[j]
		st.set_color(Color(vj.x, vj.y, vj.z))
		st.add_vertex(vj)

		# vértice j+1
		var vnext := arrVer[j + 1]
		st.set_color(Color(vnext.x, vnext.y, vnext.z))
		st.add_vertex(vnext)

	# Último triángulo: (centro, v_{2n}, v_1)
	var v_last := arrVer[2 * n]
	var v_first := arrVer[1]

	st.set_color(Color(1, 1, 1))
	st.add_vertex(c)

	st.set_color(Color(v_last.x, v_last.y, v_last.z))
	st.add_vertex(v_last)

	st.set_color(Color(v_first.x, v_first.y, v_first.z))
	st.add_vertex(v_first)

	# Convertimos a malla indexada
	st.index()
	return st.commit()

func rotar_eje_y(seccion_en_XY : PackedVector2Array, num_copias: int, vertices : PackedVector3Array, triangulos :PackedInt32Array) -> void:
	## Necesito imponer que haya más de un vértice en la sección en XY para
	## que haya al menos una cara lateral
	assert(seccion_en_XY.size() > 1)

	## Defino el ángulo por el que roto para dibujar cada sección de la revolución
	var angle : float = 2*PI/num_copias

	var num_vertices_por_seccion : int = seccion_en_XY.size()

	## Guardo los vértices originales en 3D

	var vertices_originales : PackedVector3Array

	for i in num_vertices_por_seccion:
		## Extiendo cada vértice en 2D al espacio 3D y lo meto
		## en salida
		var original_vertex_3D : Vector3
		original_vertex_3D.x = seccion_en_XY[i].x
		original_vertex_3D.y = seccion_en_XY[i].y
		original_vertex_3D.z = 0
		vertices_originales.push_back(original_vertex_3D)


	## Tomo los originales y los roto primero 0*angle, 1*angle
	## luego, 2*angle, luego 3*angle hasta (num_copias-1)*angle
	for i in num_copias:
		for nv in num_vertices_por_seccion:
			## = rotar el original nv-ésimo i*angle sobre el eje Y
			## Creo matriz identidad
			var Id : = Transform3D()
			## Matriz de rotación sobre el eje Y de ángulo i*angle
			## (lo pongo negativo porque ha sido como lo he pensado
			## y he puesto los vértices en sentido horario más adelante asumiendo
			## esto)
			var R := Id.rotated(Vector3(0,1,0),(-i*angle))
			var vertice_rotado : Vector3 = R * vertices_originales[nv]
			vertices.push_back(vertice_rotado)
	## Indexamos los triángulos
	## Empezamos desde la segunda capa desde arriba
	## porque construimos triángulos usando la superior
	## El loop es hasta num_copias+1 por el funcionamiento de range
	for j in range(0,num_copias):
		## La anterior es la anterior, a menos que sea la anterior a la primera,
		## en cuyo caso es la última
		var copia_anterior := j-1 if (j != 0) else num_copias-1
		for n in range(1,num_vertices_por_seccion):
			## Primer triángulo (arriba)
			var ind_abajo_anterior := (n + copia_anterior*num_vertices_por_seccion)
			var ind_abajo_siguiente := (n + j*num_vertices_por_seccion)
			var ind_arriba_anterior := ((n-1) + copia_anterior*num_vertices_por_seccion)
			var ind_arriba_siguiente := ((n-1) + j*num_vertices_por_seccion)


			triangulos.append_array(PackedInt32Array([
				ind_abajo_anterior,
				ind_arriba_siguiente,
				ind_arriba_anterior,
				]))

			## Segundo (abajo)
			triangulos.append_array(PackedInt32Array([
				ind_abajo_anterior,
				ind_abajo_siguiente,
				ind_arriba_siguiente,
				]))

func generar_mesh_cono(base : float = 0.14, altura : float = 0.15) -> ArrayMesh:
	var seccion_XY := PackedVector2Array([
		Vector2(0,altura),   # arriba
		Vector2(base,0)
	])

	var vertices := PackedVector3Array([])
	var triangulos := PackedInt32Array([])

	var num_copias := 20
	
	rotar_eje_y(seccion_XY,num_copias, vertices, triangulos)
	var normales := Utilidades.calcNormales( vertices, triangulos )

	var tablas : Array = []   ## tabla vacía incialmente
	tablas.resize( Mesh.ARRAY_MAX ) ## redimensionar al tamaño adecuado
	tablas[ Mesh.ARRAY_VERTEX ] = vertices
	tablas[ Mesh.ARRAY_INDEX  ] = triangulos
	tablas[ Mesh.ARRAY_NORMAL ] = normales

	## crear e inicialzar el objeto 'mesh' de este nodo
	var mesh = ArrayMesh.new() ## crea malla en modo diferido, vacía
	mesh.add_surface_from_arrays( Mesh.PRIMITIVE_TRIANGLES, tablas )
	
	return mesh
