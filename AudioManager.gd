extends Node

# Sound & Music Library
var sfx_library: Dictionary = {}
var player_pool: Array[AudioStreamPlayer2D] = []
var music_player: AudioStreamPlayer = null
const POOL_SIZE: int = 18

const SETTINGS_FILE = "user://audio_settings.cfg"

# Default Volume Values (0.0 to 1.0 Linear)
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.85

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_load_audio_settings()
	_generate_sound_effects()
	_generate_soundtrack()
	_create_audio_pool()
	_create_music_player()
	
	# Start soundtrack on Music bus
	play_music(true)

# ------------------------------------------------------------------------------
# 1. AUDIO BUS CONFIGURATION & VOLUME CONTROL
# ------------------------------------------------------------------------------

func _setup_audio_buses():
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var music_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_idx, "Music")
		AudioServer.set_bus_send(music_idx, "Master")

	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var sfx_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_send(sfx_idx, "Master")

func set_master_volume(linear_val: float):
	master_volume = clampf(linear_val, 0.0, 1.0)
	var bus_idx = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(master_volume) if master_volume > 0.001 else -80.0)
	AudioServer.set_bus_mute(bus_idx, master_volume <= 0.001)
	_save_audio_settings()

func set_music_volume(linear_val: float):
	music_volume = clampf(linear_val, 0.0, 1.0)
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(music_volume) if music_volume > 0.001 else -80.0)
		AudioServer.set_bus_mute(bus_idx, music_volume <= 0.001)
	_save_audio_settings()

func set_sfx_volume(linear_val: float):
	sfx_volume = clampf(linear_val, 0.0, 1.0)
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(sfx_volume) if sfx_volume > 0.001 else -80.0)
		AudioServer.set_bus_mute(bus_idx, sfx_volume <= 0.001)
	_save_audio_settings()

func _save_audio_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.save(SETTINGS_FILE)

func _load_audio_settings():
	var config = ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		master_volume = config.get_value("audio", "master", 0.8)
		music_volume = config.get_value("audio", "music", 0.6)
		sfx_volume = config.get_value("audio", "sfx", 0.85)

	set_master_volume(master_volume)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)

# ------------------------------------------------------------------------------
# 2. PROCEDURAL SOUNDTRACK SYNTHESIZER
# ------------------------------------------------------------------------------

func _generate_soundtrack():
	var sample_rate = 22050
	var bpm = 85.0
	var beat_duration = 60.0 / bpm
	var total_beats = 32
	var total_duration = total_beats * beat_duration
	var total_samples = int(sample_rate * total_duration)

	var mix_buffer = PackedFloat32Array()
	mix_buffer.resize(total_samples)
	mix_buffer.fill(0.0)

	var chord_roots = [73.42, 87.31, 58.27, 55.0]
	var arpeggio_notes = [
		146.83, 174.61, 220.0, 293.66, 261.63, 220.0, 174.61, 164.81,
		174.61, 220.0, 261.63, 349.23, 329.63, 261.63, 220.0, 196.00,
		116.54, 146.83, 174.61, 233.08, 220.0, 174.61, 146.83, 130.81,
		110.00, 138.59, 164.81, 220.00, 246.94, 220.00, 164.81, 138.59
	]

	var organ_phase = [0.0, 0.0, 0.0]
	var arp_phase = 0.0

	for i in range(total_samples):
		var time = float(i) / float(sample_rate)
		var current_beat = time / beat_duration
		var bar_index = int(current_beat / 4.0) % 4
		var beat_in_bar = fmod(current_beat, 4.0)
		var sixteenth_index = int(current_beat * 4.0) % arpeggio_notes.size()

		# Pipe Organ
		var root_freq = chord_roots[bar_index]
		organ_phase[0] += (root_freq * TAU) / sample_rate
		organ_phase[1] += (root_freq * 2.0 * TAU) / sample_rate
		organ_phase[2] += (root_freq * 3.0 * TAU) / sample_rate
		var organ_mix = (sin(organ_phase[0]) * 0.45 + sin(organ_phase[1]) * 0.22 + sin(organ_phase[2]) * 0.10) * 0.4

		# Industrial Drums
		var drum_mix = 0.0
		var kick_trigger = fmod(beat_in_bar, 2.0)
		if kick_trigger < 0.25:
			var kt = kick_trigger / 0.25
			drum_mix += sin(lerpf(85.0, 30.0, kt) * TAU * kick_trigger * beat_duration) * pow(1.0 - kt, 2.5) * 0.55

		if (beat_in_bar >= 1.0 and beat_in_bar < 1.35) or (beat_in_bar >= 3.0 and beat_in_bar < 3.35):
			var st = fmod(beat_in_bar, 2.0) - 1.0
			if st >= 0.0 and st < 0.35:
				var s_env = pow(1.0 - (st / 0.35), 2.0)
				drum_mix += (sin(440.0 * TAU * st * beat_duration) * 0.3 + randf_range(-1.0, 1.0) * 0.7) * s_env * 0.35

		var hat_t = fmod(current_beat * 4.0, 1.0)
		if hat_t < 0.15:
			drum_mix += randf_range(-0.3, 0.3) * (1.0 - (hat_t / 0.15)) * 0.12

		# Synth Arpeggio
		arp_phase += (arpeggio_notes[sixteenth_index] * TAU) / sample_rate
		var arp_mix = (1.0 if sin(arp_phase) > 0.0 else -1.0) * pow(1.0 - fmod(current_beat * 4.0, 1.0), 1.8) * 0.14

		mix_buffer[i] = clampf(organ_mix + drum_mix + arp_mix, -1.0, 1.0)

	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)
	for i in range(total_samples):
		var int16_val = int(clampf(mix_buffer[i] * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = total_samples

	sfx_library["soundtrack"] = stream

func _create_music_player():
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = "Music"
	add_child(music_player)

func play_music(loop: bool = true):
	if music_player and sfx_library.has("soundtrack"):
		music_player.stream = sfx_library["soundtrack"]
		music_player.play()

func stop_music():
	if music_player: music_player.stop()

# ------------------------------------------------------------------------------
# 3. GRIMDARK PROCEDURAL SFX GENERATOR
# ------------------------------------------------------------------------------

func _generate_sound_effects():
	# Kinetic & Heavy Weapons
	sfx_library["radium_shot"] = _synth_heavy_bolter_shot(0.18)
	sfx_library["laser"] = _synth_autocannon_thud(0.14) # Base Turret rapid kinetic thump
	sfx_library["autocannon"] = _synth_autocannon_thud(0.14)
	
	# High-Tech Omnissian Energy Weapons
	sfx_library["volkite_beam"] = _synth_volkite_ray(0.32)
	sfx_library["arc_lightning"] = _synth_arc_lightning(0.24)
	
	# Melee & Impact
	sfx_library["axe_swing"] = _synth_heavy_cleave(0.20)
	sfx_library["hit"] = _synth_heavy_impact(0.14)
	sfx_library["orbital_strike"] = _synth_cataclysmic_explosion(1.5)
	
	# Mechanical Fortifications & Environment
	sfx_library["building_place"] = _synth_pneumatic_clamp(0.24)
	sfx_library["gate_toggle"] = _synth_blast_gate(0.22)
	sfx_library["scrap_pickup"] = _synth_brass_cog_clink(0.16)
	sfx_library["klaxon_alert"] = _synth_vox_klaxon(0.75)

# --- 1. HEAVY KINETIC BOLTER / RADIUM SHOT ---
func _synth_heavy_bolter_shot(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase_sub = 0.0
	var phase_body = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Layer 1: High-velocity transient crack (Noise + Pitch drop)
		var noise = randf_range(-1.0, 1.0) * pow(1.0 - t, 6.0) * 0.85
		
		# Layer 2: Heavy 55Hz sub-bass thump
		var sub_freq = lerpf(180.0, 48.0, pow(t, 0.4))
		phase_sub += (sub_freq * TAU) / sample_rate
		var sub_body = sin(phase_sub) * pow(1.0 - t, 2.2) * 0.95
		
		# Layer 3: Mechanical chamber punch & radioactive rasp
		phase_body += (lerpf(360.0, 90.0, t) * TAU) / sample_rate
		var mech_punch = (1.0 if sin(phase_body) > 0.0 else -1.0) * pow(1.0 - t, 3.5) * 0.35
		
		# Analog saturation (Warm tube overdrive clipping)
		var raw_mix = (noise * 0.7 + sub_body * 0.8 + mech_punch * 0.4) * 1.5
		var sample_val = clampf(raw_mix - (raw_mix * raw_mix * raw_mix) * 0.15, -1.0, 1.0)

		var int16_val = int(sample_val * 32767.0)
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 2. RAPID AUTOCANNON / TURRET KINETIC THUD ---
func _synth_autocannon_thud(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Heavy thud pitch drop (240Hz -> 60Hz)
		var freq = lerpf(260.0, 58.0, pow(t, 0.5))
		phase += (freq * TAU) / sample_rate
		var tone = sin(phase) * 0.85
		
		# Sharp metallic breach slap
		var snap = randf_range(-0.6, 0.6) * (1.0 - t * 5.0 if t < 0.2 else 0.0)
		var env = pow(1.0 - t, 2.8)
		
		var sample_val = clampf((tone + snap) * env * 1.3, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 3. VOLKITE SEARING THERMAL RAY ---
func _synth_volkite_ray(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var fm_mod_phase = 0.0
	var carrier_phase = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Ominous 55Hz carrier modulated by 165Hz harmonic
		fm_mod_phase += (165.0 * TAU) / sample_rate
		var mod = sin(fm_mod_phase) * 60.0
		
		carrier_phase += ((75.0 + mod) * TAU) / sample_rate
		var drone = sin(carrier_phase) * 0.65
		
		# Incinerating thermal hiss
		var frying_hiss = randf_range(-0.45, 0.45) * sin(t * PI)
		var env = sin(t * PI) * (1.0 - t * 0.3)
		
		var raw = (drone + frying_hiss) * env * 1.4
		var sample_val = clampf(raw, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 4. HEAVY ARC LIGHTNING DISCHARGE ---
func _synth_arc_lightning(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase1 = 0.0
	var phase2 = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Detuned saw breakdown
		phase1 += (lerpf(420.0, 80.0, t) * TAU) / sample_rate
		phase2 += (lerpf(395.0, 85.0, t) * TAU) / sample_rate
		var saw = (fmod(phase1, TAU) / PI - 1.0) * 0.4 + (fmod(phase2, TAU) / PI - 1.0) * 0.4
		
		# Aggressive plasma crackle
		var crackle = randf_range(-0.8, 0.8) * (1.0 - t)
		var env = pow(1.0 - t, 1.6)
		
		var sample_val = clampf((saw * 0.6 + crackle * 0.7) * env * 1.5, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 5. HEAVY SERVO POWER-AXE CLEAVE ---
func _synth_heavy_cleave(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var servo_phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Pitch-rising hydraulic servo whine
		servo_phase += (lerpf(110.0, 340.0, t) * TAU) / sample_rate
		var servo = sin(servo_phase) * 0.35 * sin(t * PI)
		
		# Heavy blade wind displacement
		var whoosh = randf_range(-0.7, 0.7) * sin(t * PI) * 0.75
		
		var sample_val = clampf((servo + whoosh) * 1.3, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 6. CRUNCHY KINETIC IMPACT ---
func _synth_heavy_impact(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Low bone/metal thud (140Hz -> 38Hz drop)
		phase += (lerpf(160.0, 38.0, pow(t, 0.3)) * TAU) / sample_rate
		var thud = sin(phase) * 0.9
		var crunch = randf_range(-0.6, 0.6) * (1.0 - t * 3.5 if t < 0.28 else 0.0)
		var env = pow(1.0 - t, 2.0)
		
		var sample_val = clampf((thud + crunch) * env * 1.5, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 7. CATACLYSMIC ORBITAL / STIKKBOMB EXPLOSION ---
func _synth_cataclysmic_explosion(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var sub_phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Devastating sub-bass drop (85Hz -> 24Hz)
		sub_phase += (lerpf(88.0, 24.0, pow(t, 0.3)) * TAU) / sample_rate
		var sub_bass = sin(sub_phase) * 0.95
		
		# Distorted blast shockwave noise
		var rumble = randf_range(-1.0, 1.0) * pow(1.0 - t, 1.3) * 0.7
		var initial_crack = randf_range(-1.0, 1.0) * (1.0 - t * 10.0 if t < 0.10 else 0.0)
		
		var env = pow(1.0 - t, 1.2)
		var raw = (sub_bass + rumble + initial_crack) * env * 1.6
		var sample_val = clampf(raw - (raw * raw * raw) * 0.12, -1.0, 1.0)
		
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 8. PNEUMATIC CONSTRUCTION CLAMP ---
func _synth_pneumatic_clamp(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Hydraulic locking ring tone
		phase += (140.0 * TAU) / sample_rate
		var tone = sin(phase) * 0.5 * pow(1.0 - t, 3.0)
		var hiss = randf_range(-0.55, 0.55) * (1.0 - t) * (1.0 - t)
		
		var sample_val = clampf((tone + hiss) * 1.3, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 9. MOTORIZED BLAST GATE ---
func _synth_blast_gate(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		phase += (lerpf(220.0, 90.0, t) * TAU) / sample_rate
		var motor = (1.0 if sin(phase) > 0.0 else -1.0) * 0.4
		var air_release = randf_range(-0.4, 0.4) * (1.0 - t)
		
		var sample_val = clampf((motor + air_release) * (1.0 - t * 0.5), -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 10. SOLID BRASS COG CLINK ---
func _synth_brass_cog_clink(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var p1 = 0.0; var p2 = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Dual high-frequency resonant gear chime (1480Hz & 2240Hz)
		p1 += (1480.0 * TAU) / sample_rate
		p2 += (2240.0 * TAU) / sample_rate
		var ring = (sin(p1) * 0.5 + sin(p2) * 0.5) * pow(1.0 - t, 2.5)
		var mechanical_click = randf_range(-0.4, 0.4) * (1.0 - t * 8.0 if t < 0.12 else 0.0)
		
		var sample_val = clampf((ring + mechanical_click) * 1.2, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- 11. AUSPEX THREAT WAR-HORN KLAXON ---
func _synth_vox_klaxon(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var p1 = 0.0; var p2 = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Dissonant dual brass horn tones (110Hz & 117Hz) creating menacing warble
		p1 += (110.0 * TAU) / sample_rate
		p2 += (117.0 * TAU) / sample_rate
		var horn = ((1.0 if sin(p1) > 0.0 else -1.0) * 0.45 + (1.0 if sin(p2) > 0.0 else -1.0) * 0.45)
		var env = sin(t * PI) * (0.8 + sin(t * TAU * 4.0) * 0.2)
		
		var sample_val = clampf(horn * env * 1.3, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _create_stream_from_bytes(bytes: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

# ------------------------------------------------------------------------------
# 4. SPATIAL SFX POOL (Routed to "SFX" Bus)
# ------------------------------------------------------------------------------

func _create_audio_pool():
	for i in range(POOL_SIZE):
		var p = AudioStreamPlayer2D.new()
		p.name = "AudioPoolPlayer_" + str(i)
		p.bus = "SFX"
		p.max_distance = 1400.0
		add_child(p)
		player_pool.append(p)

func play_sfx(sfx_name: String, world_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0, pitch_scale: float = 1.0):
	if not sfx_library.has(sfx_name): return

	for p in player_pool:
		if not p.playing:
			p.stream = sfx_library[sfx_name]
			p.global_position = world_pos
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale * randf_range(0.95, 1.05)
			p.play()
			return
