extends CharacterBody3D


const BULLET_VELOCITY: float = 20.0

var time_alive: float = 5.0
var hit: bool = false

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var omni_light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_physics_process(false)
		collision_shape.disabled = true


func _physics_process(delta: float) -> void:
	if hit:
		return
	time_alive -= delta
	if time_alive < 0.0:
		hit = true
		explode()
		return
	var displacement: Vector3 = -delta * BULLET_VELOCITY * transform.basis.z
	var col: KinematicCollision3D = move_and_collide(displacement)
	if col:
		var collider: Node3D = col.get_collider() as Node3D
		if collider and collider.has_method(&"hit"):
			# Call hit directly for guaranteed damage in local play and web
			collider.hit()
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				collider.hit.rpc()
		collision_shape.disabled = true
		hit = true
		explode()


@rpc("call_local")
func explode() -> void:
	if animation_player and animation_player.has_animation(&"explode"):
		animation_player.play(&"explode")
	else:
		destroy()


func destroy() -> void:
	queue_free()
