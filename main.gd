extends Node3D
## Volumi3D (Godot 4): visor y editor 3D básico para móvil.
##
## Controles táctiles:
##   1 dedo en vacío           -> orbitar la cámara
##   1 dedo sobre la selección -> mover el objeto sobre el suelo
##   toque corto               -> seleccionar / deseleccionar
##   2 dedos                   -> pellizcar = zoom, arrastrar = desplazar
## Ratón (escritorio): botón izquierdo igual que 1 dedo, botón derecho desplaza, rueda = zoom.

const ROTATE_SPEED := 0.008
const PAN_SPEED := 0.002
const MIN_DISTANCE := 2.0
const MAX_DISTANCE := 60.0
const TAP_TOLERANCE := 12.0
const GROUND_SIZE := 40.0

var camera: Camera3D
var pivot := Vector3.ZERO
var yaw := 0.6
var pitch := -0.5
var distance := 10.0

var objects: Array[Node3D] = []
var selected: Node3D = null
var info_label: Label
var file_dialog: FileDialog

# Estado de punteros (dedos y ratón). Ratón izquierdo usa el id -1.
var pointers := {}     # id -> Vector2 posición actual
var press_pos := {}    # id -> Vector2 posición al pulsar
var moved := false
var drag_object := false
var grab_offset := Vector3.ZERO
var pinch_dist := 0.0
var mouse_right := false


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ui()
	_select(_add_mesh(BoxMesh.new(), Vector3(0, 0.5, 0)))


func _process(_delta: float) -> void:
	pitch = clampf(pitch, -1.5, -0.05)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		-sin(pitch),
		cos(pitch) * cos(yaw)) * distance
	camera.position = pivot + offset
	camera.look_at(pivot, Vector3.UP)


# ---------------------------------------------------------------- escena

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "Suelo"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.24)
	ground.material_override = mat
	add_child(ground)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.current = true
	add_child(camera)


func _add_mesh(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _random_material()
	mi.create_trimesh_collision()
	add_child(mi)
	objects.append(mi)
	return mi


func _random_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.from_hsv(randf(), 0.5, 0.95)
	return m


func _import_gltf(path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		_show("No se pudo leer: " + path.get_file())
		return
	var root := doc.generate_scene(state) as Node3D
	if root == null:
		_show("El archivo no contiene una escena válida")
		return
	add_child(root)
	_add_collisions(root)
	objects.append(root)
	_select(root)
	_show("Importado: " + path.get_file())


func _add_collisions(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).create_trimesh_collision()
	for child in node.get_children():
		_add_collisions(child)


func _delete_selected() -> void:
	if selected == null:
		_show("No hay nada seleccionado")
		return
	objects.erase(selected)
	selected.queue_free()
	_select(null)


# ---------------------------------------------------------------- interfaz

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Margen superior para no tapar la barra de estado / muesca.
	var top := DisplayServer.get_display_safe_area().position.y
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top += top
	bar.offset_bottom += top
	layer.add_child(bar)

	_add_button(bar, "Importar", _open_file_dialog)
	_add_button(bar, "Cubo", func(): _select(_add_mesh(BoxMesh.new(), pivot)))
	_add_button(bar, "Esfera", func(): _select(_add_mesh(SphereMesh.new(), pivot)))
	_add_button(bar, "Borrar", _delete_selected)

	info_label = Label.new()
	info_label.position = Vector2(12, top + 96)
	layer.add_child(info_label)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)


func _open_file_dialog() -> void:
	if file_dialog == null:
		file_dialog = FileDialog.new()
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.glb, *.gltf ; Modelos 3D"])
		file_dialog.file_selected.connect(_import_gltf)
		add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.9)


func _select(node: Node3D) -> void:
	selected = node
	if node == null:
		_show("Toca un objeto para seleccionarlo")
	else:
		_show("Seleccionado: " + node.name)


func _show(text: String) -> void:
	if info_label != null:
		info_label.text = text


# ---------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index, t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_move(d.index, d.position, d.relative)
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if mouse_right:
			_pan(m.relative)
		elif pointers.has(-1):
			_move(-1, m.position, m.relative)


func _mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press(-1, e.position)
			else:
				_release(-1, e.position)
		MOUSE_BUTTON_RIGHT:
			mouse_right = e.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				distance = clampf(distance * 0.9, MIN_DISTANCE, MAX_DISTANCE)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				distance = clampf(distance * 1.1, MIN_DISTANCE, MAX_DISTANCE)


func _press(id: int, pos: Vector2) -> void:
	pointers[id] = pos
	press_pos[id] = pos
	if pointers.size() == 1:
		moved = false
		var hit := _pick(pos)
		drag_object = hit != null and hit == selected
		if drag_object:
			var g: Variant = _ground_point(pos, selected.position.y)
			if g != null:
				grab_offset = selected.position - (g as Vector3)
	elif pointers.size() == 2:
		# Dos dedos: cancelar cualquier arrastre y empezar pellizco.
		drag_object = false
		moved = true
		pinch_dist = _pinch_distance()


func _move(id: int, pos: Vector2, rel: Vector2) -> void:
	if not pointers.has(id):
		return
	pointers[id] = pos
	if pos.distance_to(press_pos[id]) > TAP_TOLERANCE:
		moved = true

	if pointers.size() == 1:
		if drag_object:
			_drag_selected(pos)
		else:
			_orbit(rel)
	elif pointers.size() == 2:
		var d := _pinch_distance()
		if pinch_dist > 0.0 and d > 0.0:
			distance = clampf(distance * pinch_dist / d, MIN_DISTANCE, MAX_DISTANCE)
		pinch_dist = d
		_pan(rel * 0.5)


func _release(id: int, pos: Vector2) -> void:
	if not pointers.has(id):
		return
	var was_single := pointers.size() == 1
	pointers.erase(id)
	press_pos.erase(id)
	if was_single and not moved:
		_select(_pick(pos))
	if pointers.is_empty():
		drag_object = false


# ---------------------------------------------------------------- acciones

func _orbit(rel: Vector2) -> void:
	yaw -= rel.x * ROTATE_SPEED
	pitch -= rel.y * ROTATE_SPEED


func _pan(rel: Vector2) -> void:
	var b := camera.global_transform.basis
	pivot += (-b.x * rel.x + b.y * rel.y) * distance * PAN_SPEED


func _drag_selected(pos: Vector2) -> void:
	var g: Variant = _ground_point(pos, selected.position.y)
	if g != null:
		selected.position = (g as Vector3) + grab_offset


func _pinch_distance() -> float:
	var v: Array = pointers.values()
	if v.size() < 2:
		return 0.0
	var a: Vector2 = v[0]
	var b: Vector2 = v[1]
	return a.distance_to(b)


# ---------------------------------------------------------------- geometría

func _pick(screen_pos: Vector2) -> Node3D:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return _root_of(hit["collider"])


## Sube por el árbol hasta el hijo directo de esta escena (la raíz del objeto).
func _root_of(node: Node) -> Node3D:
	var n: Node = node
	while n != null and n.get_parent() != self:
		n = n.get_parent()
	if n == null:
		return null
	return n as Node3D


## Punto donde el rayo de la pantalla corta el plano horizontal a la altura dada.
func _ground_point(screen_pos: Vector2, height: float) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := (height - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t
