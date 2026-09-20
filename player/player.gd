class_name Player
extends CharacterBody3D


enum Animations {
	JUMP_UP,
	JUMP_DOWN,
	STRAFE,
	WALK,
}

const MOTION_INTERPOLATE_SPEED: float = 10.0
const ROTATION_INTERPOLATE_SPEED: float = 10.0

const MIN_AIRBORNE_TIME: float = 0.1
const JUMP_SPEED: float = 6.0
const WALK_SPEED: float = 6.0
const STRAFE_SPEED: float = 4.5

var airborne_time: float = 100.0

var orientation := Transform3D()
var motion := Vector2()
var attack_timer: float = 0.0

@onready var initial_position: Vector3 = transform.origin

@onready var player_input: PlayerInputSynchronizer = $InputSynchronizer
@onready var player_model: Node3D = $PlayerModel
@onready var anim_player: AnimationPlayer = player_model.get_node_or_null(^"AnimationPlayer")
@onready var divine_attack_origin: Node3D = _find_attack_origin()
@onready var shoot_from: Marker3D = divine_attack_origin as Marker3D
@onready var crosshair: TextureRect = $Crosshair
@onready var fire_cooldown: Timer = $FireCooldown

@onready var sound_effects: Node = $SoundEffects
@onready var sound_effect_jump: AudioStreamPlayer = sound_effects.get_node(^"Jump")
@onready var sound_effect_land: AudioStreamPlayer = sound_effects.get_node(^"Land")
@onready var sound_effect_shoot: AudioStreamPlayer = sound_effects.get_node(^"Shoot")

@export var player_id: int = 1:
	set(value):
		player_id = value
		$InputSynchronizer.set_multiplayer_authority(value)

@export var current_animation := Animations.WALK


func _find_attack_origin() -> Node3D:
	var n: Node3D = player_model.find_child("DivineAttackOrigin", true, false)
	if n:
		return n
	n = player_model.find_child("ShootFrom", true, false)
	if n:
		return n
	if has_node(^"DivineAttackOrigin"):
		return get_node(^"DivineAttackOrigin")
	if has_node(^"ShootFrom"):
		return get_node(^"ShootFrom")
	return null


func _ready() -> void:
	# Pre-initialize orientation transform.
	orientation = player_model.global_transform
	orientation.origin = Vector3()

	# Safeguard: Apply dark Ganesha material override if not already set
	var mesh = player_model.find_child("Ganesha_Elephant_Mesh", true, false)
	if mesh and mesh.material_override == null:
		mesh.material_override = preload("res://player/model/ganesh_dark_material.tres")

	# Adjust arm poses on animations to remove T-pose and provide natural stance
	_setup_natural_arm_animations()

	# Immediately play natural standing idle pose on game start so Ganesha is never in T-pose
	if anim_player:
		if anim_player.has_animation(&"Idle_Standing"):
			anim_player.play(&"Idle_Standing")
		elif anim_player.has_animation(&"Idle"):
			anim_player.play(&"Idle")

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		set_process(false)


func _setup_natural_arm_animations() -> void:
	if anim_player == null:
		return
	var q_down_l = Quaternion(Vector3(0, 0, 1), -0.55)
	var q_down_r = Quaternion(Vector3(0, 0, 1), 0.55)
	for anim_name in anim_player.get_animation_list():
		var anim = anim_player.get_animation(anim_name)
		if anim == null:
			continue
		var s_name = str(anim_name).to_lower()
		var is_attack = "trident" in s_name or "strike" in s_name or "bless" in s_name
		for t in range(anim.get_track_count()):
			var path = str(anim.track_get_path(t))
			if "UpperArm.L" in path:
				for k in range(anim.track_get_key_count(t)):
					var val = anim.track_get_key_value(t, k)
					if val is Quaternion:
						anim.track_set_key_value(t, k, q_down_l * val)
			elif "UpperArm.R" in path and not is_attack:
				# Keep right arm free for forward divine casting!
				for k in range(anim.track_get_key_count(t)):
					var val = anim.track_get_key_value(t, k)
					if val is Quaternion:
						anim.track_set_key_value(t, k, q_down_r * val)


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		apply_input(delta)
	else:
		animate(current_animation, delta)


func animate(anim: int, delta: float) -> void:
	current_animation = anim as Animations
	if anim_player == null:
		return

	# Priority 1: Divine Attack animation
	if attack_timer > 0.0:
		if anim_player.has_animation(&"Trident_Strike"):
			if anim_player.current_animation != &"Trident_Strike":
				anim_player.play(&"Trident_Strike", 0.1)
			anim_player.speed_scale = 1.3
			return
		elif anim_player.has_animation(&"Blessing_Gesture"):
			if anim_player.current_animation != &"Blessing_Gesture":
				anim_player.play(&"Blessing_Gesture", 0.1)
			anim_player.speed_scale = 1.3
			return

	# Priority 2: In-Air / Jump
	if anim == Animations.JUMP_UP or anim == Animations.JUMP_DOWN:
		if anim_player.has_animation(&"Race_Depart"):
			if anim_player.current_animation != &"Race_Depart":
				anim_player.play(&"Race_Depart", 0.15)
			anim_player.speed_scale = 1.0
		return

	# Priority 3: Aiming / Strafing
	if anim == Animations.STRAFE:
		if motion.length() > 0.05:
			var move_anim: StringName = &"Walk_Crawl" if anim_player.has_animation(&"Walk_Crawl") else &"Race_Depart"
			if anim_player.current_animation != move_anim:
				anim_player.play(move_anim, 0.2)
			anim_player.speed_scale = clampf(motion.length(), 0.8, 1.2)
		elif anim_player.has_animation(&"Guard_Stance"):
			if anim_player.current_animation != &"Guard_Stance":
				anim_player.play(&"Guard_Stance", 0.2)
			anim_player.speed_scale = 1.0
		elif anim_player.has_animation(&"Idle_Standing"):
			if anim_player.current_animation != &"Idle_Standing":
				anim_player.play(&"Idle_Standing", 0.2)
			anim_player.speed_scale = 1.0
		return

	# Priority 4: Standard Locomotion (Walk/Run/Idle)
	if motion.length() > 0.75:
		# Sprint / Fast Run
		var run_anim: StringName = &"Race_Depart" if anim_player.has_animation(&"Race_Depart") else &"Walk_Crawl"
		if anim_player.current_animation != run_anim:
			anim_player.play(run_anim, 0.2)
		anim_player.speed_scale = clampf(motion.length() * 1.1, 0.9, 1.4)
	elif motion.length() > 0.05:
		# Natural Walk Cycle
		var walk_anim: StringName = &"Walk_Crawl" if anim_player.has_animation(&"Walk_Crawl") else &"Race_Depart"
		if anim_player.current_animation != walk_anim:
			anim_player.play(walk_anim, 0.2)
		anim_player.speed_scale = clampf(motion.length() * 1.2, 0.8, 1.25)
	else:
		# Natural Idle Standing with Breathing
		var idle_anim: StringName = &"Idle_Standing" if anim_player.has_animation(&"Idle_Standing") else &"Idle"
		if anim_player.current_animation != idle_anim:
			anim_player.play(idle_anim, 0.25)
		anim_player.speed_scale = 1.0


func apply_input(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta

	motion = motion.lerp(player_input.motion, MOTION_INTERPOLATE_SPEED * delta)

	var camera_basis: Basis = player_input.get_camera_rotation_basis()
	var camera_z: Vector3 = camera_basis.z
	var camera_x: Vector3 = camera_basis.x

	camera_z.y = 0
	camera_z = camera_z.normalized()
	camera_x.y = 0
	camera_x = camera_x.normalized()

	# Jump/in-air logic.
	airborne_time += delta
	if is_on_floor():
		if airborne_time > 0.5:
			land()
			if multiplayer.has_multiplayer_peer():
				land.rpc()
		airborne_time = 0

	var on_air: bool = airborne_time > MIN_AIRBORNE_TIME

	if not on_air and player_input.jumping:
		velocity.y = JUMP_SPEED
		on_air = true
		airborne_time = MIN_AIRBORNE_TIME
		jump()
		if multiplayer.has_multiplayer_peer():
			jump.rpc()

	player_input.jumping = false

	var target_vel := Vector3.ZERO

	if on_air:
		if velocity.y > 0:
			animate(Animations.JUMP_UP, delta)
		else:
			animate(Animations.JUMP_DOWN, delta)
		target_vel = (camera_x * motion.x + camera_z * motion.y) * WALK_SPEED

	elif player_input.aiming:
		# Rotate towards camera direction while aiming.
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = player_input.get_camera_base_quaternion()
		orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))

		animate(Animations.STRAFE, delta)
		target_vel = (camera_x * motion.x + camera_z * motion.y) * STRAFE_SPEED

	else: # Walking / Idle
		var target_dir: Vector3 = camera_x * motion.x + camera_z * motion.y
		if target_dir.length() > 0.001:
			var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
			var q_to: Quaternion = Basis.looking_at(target_dir).get_rotation_quaternion()
			orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED))
			target_vel = target_dir * WALK_SPEED

		animate(Animations.WALK, delta)

	# Handle Divine Attack in ANY state (Aiming or Normal Third-Person)
	if player_input.shooting and fire_cooldown.time_left == 0:
		_perform_divine_attack(delta)

	# Smooth horizontal velocity
	velocity.x = move_toward(velocity.x, target_vel.x, 25.0 * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, 25.0 * delta)
	velocity += get_gravity() * delta

	set_velocity(velocity)
	set_up_direction(Vector3.UP)
	move_and_slide()

	# Keep model orientation normalized
	orientation = orientation.orthonormalized()
	player_model.global_transform.basis = orientation.basis

	# Respawn if fallen out of map
	if transform.origin.y < -40.0:
		transform.origin = initial_position


func _perform_divine_attack(delta: float) -> void:
	var origin_node: Node3D = divine_attack_origin if divine_attack_origin else shoot_from
	var shoot_origin: Vector3 = origin_node.global_transform.origin if origin_node else (global_transform.origin + Vector3.UP * 1.2)
	
	var target_pos: Vector3 = player_input.shoot_target
	var shoot_dir: Vector3 = (target_pos - shoot_origin).normalized()
	if shoot_dir.length_squared() < 0.001:
		shoot_dir = -player_input.get_camera_rotation_basis().z.normalized()

	# Turn Ganesha toward the attack direction for clear aim feedback
	var aim_dir_flat := Vector3(shoot_dir.x, 0, shoot_dir.z).normalized()
	if aim_dir_flat.length() > 0.01:
		var q_from: Quaternion = orientation.basis.get_rotation_quaternion()
		var q_to: Quaternion = Basis.looking_at(aim_dir_flat).get_rotation_quaternion()
		orientation.basis = Basis(q_from.slerp(q_to, delta * ROTATION_INTERPOLATE_SPEED * 3.0))

	# Launch visible divine energy projectile
	var bullet: CharacterBody3D = preload("res://player/bullet/bullet.tscn").instantiate()
	get_parent().add_child(bullet, true)
	bullet.global_transform.origin = shoot_origin
	bullet.look_at(shoot_origin + shoot_dir)
	bullet.add_collision_exception_with(self)

	attack_timer = 0.45
	fire_cooldown.start()
	shoot()
	if multiplayer.has_multiplayer_peer():
		shoot.rpc()


@rpc("call_local")
func jump() -> void:
	animate(Animations.JUMP_UP, 0.0)
	sound_effect_jump.play()


@rpc("call_local")
func land() -> void:
	animate(Animations.JUMP_DOWN, 0.0)
	sound_effect_land.play()


@rpc("call_local")
func shoot() -> void:
	var origin_node: Node3D = divine_attack_origin if divine_attack_origin else shoot_from
	if origin_node:
		var shoot_particle = origin_node.get_node_or_null(^"ShootParticle")
		if shoot_particle:
			shoot_particle.restart()
			shoot_particle.emitting = true
		var muzzle_particle = origin_node.get_node_or_null(^"MuzzleFlash")
		if muzzle_particle:
			muzzle_particle.restart()
			muzzle_particle.emitting = true
	fire_cooldown.start()
	sound_effect_shoot.play()
	add_camera_shake_trauma(0.25)


@rpc("call_local")
func hit() -> void:
	add_camera_shake_trauma(0.75)
	if anim_player and anim_player.has_animation(&"Grieving"):
		anim_player.play(&"Grieving", 0.1)


@rpc("call_local")
func add_camera_shake_trauma(amount: float) -> void:
	if player_input and player_input.camera_camera:
		player_input.camera_camera.add_trauma(amount)

