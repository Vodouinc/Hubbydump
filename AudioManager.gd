extends Node

# Sound & Music Library
var sfx_library: Dictionary = {}
var player_pool: Array[AudioStreamPlayer2D] = []
var music_player: AudioStreamPlayer = null
const POOL_SIZE: int = 16

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
	# Ensure "Music" and "SFX" buses exist
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
	music_player.bus = "Music" # Routed to Music bus!
	add_child(music_player)

func play_music(loop: bool = true):
	if music_player and sfx_library.has("soundtrack"):
		music_player.stream = sfx_library["soundtrack"]
		music_player.play()

func stop_music():
	if music_player: music_player.stop()

# ------------------------------------------------------------------------------
# 3. PROCEDURAL SFX GENERATOR
# ------------------------------------------------------------------------------

func _generate_sound_effects():
	sfx_library["laser"] = _synth_pitch_sweep(880.0, 220.0, 0.18, "sine")
	sfx_library["radium_shot"] = _synth_gunshot(0.12)
	sfx_library["axe_swing"] = _synth_whoosh(0.18)
	sfx_library["building_place"] = _synth_pneumatic_clank(0.22)
	sfx_library["hit"] = _synth_impact(0.10)
	sfx_library["orbital_strike"] = _synth_heavy_explosion(1.4)
	sfx_library["scrap_pickup"] = _synth_chime([587.33, 880.0], 0.14)
	sfx_library["gate_toggle"] = _synth_pitch_sweep(320.0, 640.0, 0.15, "square")

func _synth_pitch_sweep(start_freq: float, end_freq: float, duration: float, wave_type: String = "sine") -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase += (lerpf(start_freq, end_freq, pow(t, 0.5)) * TAU) / sample_rate
		var sample_val = sin(phase) if wave_type == "sine" else (1.0 if sin(phase) > 0.0 else -1.0)
		var envelope = (1.0 - t) * (1.0 - t)
		var int16_val = int(clampf(sample_val * envelope * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_gunshot(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase += (lerpf(600.0, 120.0, t) * TAU) / sample_rate
		var noise = randf_range(-1.0, 1.0)
		var square = 1.0 if sin(phase) > 0.0 else -1.0
		var sample_val = lerpf(square, noise, 0.4)
		var envelope = pow(1.0 - t, 3.0)
		var int16_val = int(clampf(sample_val * envelope * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_whoosh(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var noise = randf_range(-1.0, 1.0)
		var envelope = sin(t * PI) * 0.8
		var int16_val = int(clampf(noise * envelope * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_pneumatic_clank(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase += (180.0 * TAU) / sample_rate
		var tone = sin(phase) * 0.6
		var hiss = randf_range(-0.5, 0.5) * (1.0 - t)
		var sample_val = (tone + hiss) * (1.0 - t)
		var int16_val = int(clampf(sample_val * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_heavy_explosion(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var sub_phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		sub_phase += (lerpf(90.0, 25.0, t) * TAU) / sample_rate
		var sub_bass = sin(sub_phase) * 0.75
		var rumble_noise = randf_range(-1.0, 1.0) * 0.5
		var envelope = pow(1.0 - t, 1.5)
		var sample_val = (sub_bass + rumble_noise) * envelope
		var int16_val = int(clampf(sample_val * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_impact(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase += (lerpf(280.0, 60.0, t) * TAU) / sample_rate
		var thud = sin(phase) * 0.8
		var click = randf_range(-0.4, 0.4) * (1.0 - t * 4.0 if t < 0.25 else 0.0)
		var sample_val = (thud + click) * (1.0 - t)
		var int16_val = int(clampf(sample_val * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_chime(frequencies: Array, duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var sample_val = 0.0
		for freq in frequencies:
			sample_val += sin((freq * TAU * float(i)) / sample_rate)
		sample_val = (sample_val / float(frequencies.size())) * (1.0 - t)
		var int16_val = int(clampf(sample_val * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

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
		p.bus = "SFX" # Routed to SFX bus!
		p.max_distance = 1200.0
		add_child(p)
		player_pool.append(p)

func play_sfx(sfx_name: String, world_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0, pitch_scale: float = 1.0):
	if not sfx_library.has(sfx_name): return

	for p in player_pool:
		if not p.playing:
			p.stream = sfx_library[sfx_name]
			p.global_position = world_pos
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale * randf_range(0.94, 1.06)
			p.play()
			return
