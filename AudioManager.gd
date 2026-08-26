# res://AudioManager.gd
extends Node

# Sound & Music Library
var sfx_library: Dictionary = {}
var player_pool_2d: Array[AudioStreamPlayer2D] = []
var player_pool_ui: Array[AudioStreamPlayer] = []
const POOL_SIZE_2D: int = 24
const POOL_SIZE_UI: int = 6

# Dual Music Players for Smooth Crossfading
var music_player_a: AudioStreamPlayer = null
var music_player_b: AudioStreamPlayer = null
var active_music_player: AudioStreamPlayer = null
var current_track_key: String = ""

# SFX Throttling to prevent volume spikes/clipping
var sfx_cooldowns: Dictionary = {}
const MIN_SFX_INTERVAL: float = 0.045 # 45ms per identical sound

const SETTINGS_FILE = "user://audio_settings.cfg"

# Default Volume Values (0.0 to 1.0 Linear)
var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.85

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_load_audio_settings()
	
	# Generate All Procedural Soundtracks & SFX
	_generate_sound_effects()
	_generate_soundtrack_admech()
	_generate_soundtrack_marshal()
	_generate_soundtrack_sister()
	
	_create_audio_pools()
	_create_music_system()
	
	play_music("soundtrack_admech")

func _process(delta: float) -> void:
	# Tick down SFX cooldown throttles
	for k in sfx_cooldowns.keys():
		sfx_cooldowns[k] -= delta
		if sfx_cooldowns[k] <= 0.0:
			sfx_cooldowns.erase(k)

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
# 2. DUAL-CHANNEL CROSSFADING MUSIC SYSTEM & DUCKING
# ------------------------------------------------------------------------------

func _create_music_system():
	music_player_a = AudioStreamPlayer.new()
	music_player_a.name = "MusicPlayer_A"
	music_player_a.bus = "Music"
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.name = "MusicPlayer_B"
	music_player_b.bus = "Music"
	add_child(music_player_b)

	active_music_player = music_player_a

func play_music(track_key: String, crossfade_time: float = 1.2):
	if not sfx_library.has(track_key): return
	if current_track_key == track_key and active_music_player.playing: return

	current_track_key = track_key
	var incoming_player = music_player_b if active_music_player == music_player_a else music_player_a
	var outgoing_player = active_music_player

	incoming_player.stream = sfx_library[track_key]
	incoming_player.volume_db = -40.0
	incoming_player.play()

	var tween = create_tween().set_parallel(true)
	tween.tween_property(incoming_player, "volume_db", 0.0, crossfade_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(outgoing_player, "volume_db", -40.0, crossfade_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.chain().tween_callback(outgoing_player.stop)
	active_music_player = incoming_player

func duck_music(amount_db: float = -7.0, duration: float = 1.2):
	if not is_instance_valid(active_music_player) or not active_music_player.playing: return
	var tween = create_tween()
	tween.tween_property(active_music_player, "volume_db", amount_db, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(duration * 0.5)
	tween.tween_property(active_music_player, "volume_db", 0.0, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func switch_soundtrack_for_class(chosen_class_id: int):
	match chosen_class_id:
		0: play_music("soundtrack_admech", 1.4)
		1: play_music("soundtrack_marshal", 1.4)
		2: play_music("soundtrack_sister", 1.4)

# ------------------------------------------------------------------------------
# 3. PROCEDURAL SOUNDTRACK GENERATORS
# ------------------------------------------------------------------------------

# --- A. TECH-PRIEST (Gothic Industrial Pipe Organ) ---
func _generate_soundtrack_admech():
	var sample_rate = 22050
	var bpm = 85.0
	var beat_dur = 60.0 / bpm
	var total_beats = 32
	var total_duration = total_beats * beat_dur
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
		var current_beat = time / beat_dur
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
			drum_mix += sin(lerpf(85.0, 30.0, kt) * TAU * kick_trigger * beat_dur) * pow(1.0 - kt, 2.5) * 0.55

		if (beat_in_bar >= 1.0 and beat_in_bar < 1.35) or (beat_in_bar >= 3.0 and beat_in_bar < 3.35):
			var st = fmod(beat_in_bar, 2.0) - 1.0
			if st >= 0.0 and st < 0.35:
				var s_env = pow(1.0 - (st / 0.35), 2.0)
				drum_mix += (sin(440.0 * TAU * st * beat_dur) * 0.3 + randf_range(-1.0, 1.0) * 0.7) * s_env * 0.35

		var hat_t = fmod(current_beat * 4.0, 1.0)
		if hat_t < 0.15:
			drum_mix += randf_range(-0.3, 0.3) * (1.0 - (hat_t / 0.15)) * 0.12

		# Synth Arpeggio
		arp_phase += (arpeggio_notes[sixteenth_index] * TAU) / sample_rate
		var arp_mix = (1.0 if sin(arp_phase) > 0.0 else -1.0) * pow(1.0 - fmod(current_beat * 4.0, 1.0), 1.8) * 0.14

		mix_buffer[i] = tanh((organ_mix + drum_mix + arp_mix) * 1.1) * 0.85

	sfx_library["soundtrack_admech"] = _create_stream_from_buffer(mix_buffer, sample_rate, true)

# --- B. SKITARII MARSHAL (The Binary Military March - 116 BPM) ---
func _generate_soundtrack_marshal():
	var sample_rate = 22050
	var bpm = 116.0
	var beat_dur = 60.0 / bpm
	var total_beats = 32
	var total_duration = total_beats * beat_dur
	var total_samples = int(sample_rate * total_duration)

	var mix_buffer = PackedFloat32Array()
	mix_buffer.resize(total_samples)
	mix_buffer.fill(0.0)

	var march_roots = [55.0, 65.41, 73.42, 49.00] # A, C, D, G cadence
	var bass_phase = 0.0
	var pulse_phase = 0.0
	var telemetry_phase = 0.0

	for i in range(total_samples):
		var time = float(i) / float(sample_rate)
		var current_beat = time / beat_dur
		var bar_idx = int(current_beat / 4.0) % 4
		var beat_in_bar = fmod(current_beat, 4.0)
		var sixteenth_in_bar = int(current_beat * 4.0) % 16
		var sixteenth_t = fmod(current_beat * 4.0, 1.0)

		# 1. Driving Electro-Bass Pulse
		var root_f = march_roots[bar_idx]
		bass_phase = fposmod(bass_phase + (root_f * TAU) / sample_rate, TAU)
		var bass_saw = (fmod(bass_phase, TAU) / PI - 1.0)
		var bass_env = pow(1.0 - sixteenth_t, 1.4)
		var bass_mix = bass_saw * bass_env * 0.42

		# 2. Auspex Telemetry Arpeggios (Chiptune Tactical Telemetry)
		var tele_note = root_f * (4.0 if sixteenth_in_bar % 2 == 0 else 6.0)
		telemetry_phase = fposmod(telemetry_phase + (tele_note * TAU) / sample_rate, TAU)
		var tele_mix = (1.0 if sin(telemetry_phase) > 0.0 else -1.0) * pow(1.0 - sixteenth_t, 2.0) * 0.12

		# 3. Military Marching Cadence (Skitarii Precision Drums)
		var drum_mix = 0.0
		# Snappy Marching Kick on all downbeats
		if sixteenth_in_bar in [0, 4, 8, 12]:
			drum_mix += sin(lerpf(110.0, 38.0, sixteenth_t) * TAU * sixteenth_t * 0.1) * pow(1.0 - sixteenth_t, 2.2) * 0.7

		# Rhythmic Military Snare Roll (Ghost notes on 16ths, accents on 4 and 12)
		var is_snare_hit = sixteenth_in_bar in [4, 7, 10, 12, 14]
		if is_snare_hit:
			var accent = 0.85 if sixteenth_in_bar in [4, 12] else 0.40
			var snare_noise = randf_range(-accent, accent) * pow(1.0 - sixteenth_t, 2.5)
			var snare_snap = sin(280.0 * TAU * sixteenth_t * 0.1) * pow(1.0 - sixteenth_t, 3.0) * accent
			drum_mix += snare_noise + snare_snap

		# Crisp Auspex Beep Hi-Hats
		drum_mix += randf_range(-0.15, 0.15) * (1.0 - sixteenth_t)

		mix_buffer[i] = tanh((bass_mix + tele_mix + drum_mix) * 1.15) * 0.85

	sfx_library["soundtrack_marshal"] = _create_stream_from_buffer(mix_buffer, sample_rate, true)

# --- C. SISTER OF BATTLE (Castlevania-Inspired Gothic Action Hymn - 132 BPM) ---
# ------------------------------------------------------------------------------
# PROCEDURAL SYMPHONIC MEDIEVAL HEAVY METAL BATTLE HYMN (SISTER OF BATTLE)
# ------------------------------------------------------------------------------

func _generate_soundtrack_sister():
	var sample_rate = 22050
	var bpm = 138.0 # Aggressive, driving medieval power-metal tempo
	var beat_dur = 60.0 / bpm
	var total_bars = 8
	var beats_per_bar = 4.0
	var total_beats = total_bars * beats_per_bar
	var total_duration = total_beats * beat_dur
	var total_samples = int(sample_rate * total_duration)

	var mix_buffer = PackedFloat32Array()
	mix_buffer.resize(total_samples)
	mix_buffer.fill(0.0)

	# 8-Bar D-Harmonic Minor Gothic Metal Progression
	# (Dm -> Bb -> Gm -> A7 -> Dm -> F -> Gm -> A7/C# dim)
	var chord_roots = [73.42, 58.27, 49.00, 55.00, 73.42, 87.31, 49.00, 55.00]
	var chord_fifths = [110.00, 87.31, 73.42, 82.41, 110.00, 130.81, 73.42, 82.41]
	var chord_triads = [
		[146.83, 174.61, 220.00], # Dm
		[116.54, 146.83, 174.61], # Bb
		[98.00,  116.54, 146.83], # Gm
		[110.00, 138.59, 164.81], # A Maj
		[146.83, 174.61, 220.00], # Dm
		[174.61, 220.00, 261.63], # F Maj
		[98.00,  116.54, 146.83], # Gm
		[110.00, 138.59, 164.81]  # A Maj (Harmonic Minor Dominant)
	]

	# Neoclassical D-Harmonic Minor Lead (128 notes with C# leading tone sweeps)
	var melody_notes: Array[float] = [
		# Bar 1 (Dm - Medieval Arpeggio Flourish)
		293.66, 349.23, 440.00, 587.33, 554.37, 587.33, 440.00, 349.23, 440.00, 554.37, 587.33, 698.46, 659.25, 587.33, 554.37, 440.00,
		# Bar 2 (Bb - Searing Neoclassical Run)
		466.16, 392.00, 349.23, 293.66, 349.23, 392.00, 466.16, 587.33, 554.37, 466.16, 440.00, 392.00, 349.23, 329.63, 293.66, 329.63,
		# Bar 3 (Gm - Medieval Battle Plunge)
		392.00, 466.16, 587.33, 466.16, 392.00, 349.23, 293.66, 261.63, 293.66, 349.23, 392.00, 466.16, 587.33, 554.37, 466.16, 392.00,
		# Bar 4 (A7 / C# dim - Harmonic Minor Peak)
		554.37, 440.00, 329.63, 277.18, 329.63, 440.00, 554.37, 659.25, 698.46, 659.25, 587.33, 554.37, 440.00, 329.63, 277.18, 220.00,
		# Bar 5 (Dm - High Octave Anthem)
		587.33, 698.46, 880.00, 698.46, 587.33, 440.00, 349.23, 440.00, 587.33, 659.25, 698.46, 880.00, 830.61, 880.00, 698.46, 587.33,
		# Bar 6 (F Maj - Heroic Symphony Surge)
		523.25, 659.25, 783.99, 659.25, 523.25, 440.00, 349.23, 440.00, 523.25, 587.33, 659.25, 783.99, 698.46, 659.25, 587.33, 523.25,
		# Bar 7 (Gm - High Tension)
		587.33, 466.16, 392.00, 349.23, 392.00, 466.16, 587.33, 698.46, 783.99, 698.46, 587.33, 466.16, 392.00, 349.23, 329.63, 349.23,
		# Bar 8 (A7 - Grand Cadence Finale)
		440.00, 554.37, 659.25, 880.00, 830.61, 880.00, 698.46, 659.25, 587.33, 554.37, 440.00, 349.23, 329.63, 277.18, 220.00, 293.66
	]

	# Phase Accumulators
	var lead_phase = 0.0
	var guitar_phase_r = 0.0
	var guitar_phase_5 = 0.0
	var bass_phase = 0.0
	var organ_phases = [0.0, 0.0, 0.0]
	var choir_phase = 0.0
	var bell_phase_low = 0.0
	var bell_phase_high = 0.0

	for i in range(total_samples):
		var time = float(i) / float(sample_rate)
		var current_beat = time / beat_dur
		var bar_idx = int(current_beat / beats_per_bar) % total_bars
		var beat_in_bar = fmod(current_beat, beats_per_bar)
		var sixteenth_in_bar = int(current_beat * 4.0) % 16
		var global_sixteenth = int(current_beat * 4.0) % 128
		var sixteenth_t = fmod(current_beat * 4.0, 1.0)

		# ======================================================================
		# 1. DISTORTED HEAVY METAL RHYTHM GUITAR (Power Chords & High-Gain Chugs)
		# ======================================================================
		var root_f = chord_roots[bar_idx]
		var fifth_f = chord_fifths[bar_idx]
		
		guitar_phase_r = fposmod(guitar_phase_r + (root_f * TAU) / sample_rate, TAU)
		guitar_phase_5 = fposmod(guitar_phase_5 + (fifth_f * TAU) / sample_rate, TAU)

		var saw_r = (fmod(guitar_phase_r, TAU) / PI - 1.0)
		var saw_5 = (fmod(guitar_phase_5, TAU) / PI - 1.0) * 0.75
		var sub_sq = (1.0 if sin(guitar_phase_r * 0.5) > 0.0 else -1.0) * 0.35

		# Palm-muted chug vs open chord accent
		var is_open_stab = (sixteenth_in_bar == 0 or sixteenth_in_bar == 6 or sixteenth_in_bar == 10)
		var chug_env = pow(1.0 - sixteenth_t, 1.8 if not is_open_stab else 0.85)

		var raw_guitar = (saw_r + saw_5 + sub_sq) * chug_env
		# Asymmetrical tube overdrive / high-gain metal saturation
		var metal_guitar = tanh(raw_guitar * 3.4) * 0.38

		# ======================================================================
		# 2. NEOCLASSICAL SYMPHONIC LEAD (Dual Violin & Harpsichord Hybrid)
		# ======================================================================
		var note_freq = melody_notes[global_sixteenth]
		lead_phase = fposmod(lead_phase + (note_freq * TAU) / sample_rate, TAU)
		var lead_saw = (fmod(lead_phase, TAU) / PI - 1.0) * 0.55
		var lead_tri = (abs(fmod(lead_phase, TAU) / PI - 1.0) * 2.0 - 1.0) * 0.45
		
		# Slight choir-like vibrato
		var vibrato = sin(time * 38.0) * 0.05
		var lead_env = pow(1.0 - sixteenth_t, 1.2) * (1.0 + vibrato)
		var lead_mix = (lead_saw + lead_tri) * lead_env * 0.35

		# ======================================================================
		# 3. GALLOPING BASSLINE ENGINE
		# ======================================================================
		var bass_freq = root_f
		match sixteenth_in_bar % 4:
			0: bass_freq = root_f
			1: bass_freq = root_f * 2.0
			2: bass_freq = fifth_f
			3: bass_freq = root_f * 2.0
		bass_phase = fposmod(bass_phase + (bass_freq * TAU) / sample_rate, TAU)
		var bass_mix = (sin(bass_phase) * 0.7 + (fmod(bass_phase, TAU) / PI - 1.0) * 0.3) * pow(1.0 - sixteenth_t, 1.25) * 0.35

		# ======================================================================
		# 4. GOTHIC CATHEDRAL CHOIR & PIPE ORGAN PAD
		# ======================================================================
		var triad = chord_triads[bar_idx]
		var organ_mix = 0.0
		for v in range(3):
			organ_phases[v] = fposmod(organ_phases[v] + (triad[v] * TAU) / sample_rate, TAU)
			organ_mix += sin(organ_phases[v]) * 0.45 + sin(fposmod(organ_phases[v] * 2.0, TAU)) * 0.25
		organ_mix *= 0.14

		# Liturgical Gregorian Chant Formant Drone
		choir_phase = fposmod(choir_phase + (root_f * 2.0 * TAU) / sample_rate, TAU)
		var choir_mix = (sin(choir_phase) * 0.6 + sin(choir_phase * 2.2) * 0.3 + sin(choir_phase * 3.4) * 0.15) * 0.12

		# ======================================================================
		# 5. TOLLING CATHEDRAL BELL (On Bar Downbeats)
		# ======================================================================
		var bell_mix = 0.0
		if (bar_idx % 2 == 0) and beat_in_bar < 2.5:
			var bt = beat_in_bar * beat_dur
			bell_phase_low = fposmod(bell_phase_low + (220.0 * TAU) / sample_rate, TAU)
			bell_phase_high = fposmod(bell_phase_high + (587.33 * TAU) / sample_rate, TAU)
			bell_mix = (sin(bell_phase_low) * 0.6 + sin(bell_phase_high) * 0.4) * exp(-2.8 * bt) * 0.25

		# ======================================================================
		# 6. DOUBLE-BASS HEAVY METAL DRUM ENGINE
		# ======================================================================
		var drum_mix = 0.0

		# Double-Bass Metal Kick (Galloping 16th notes with heavy downbeat punch)
		var is_kick = sixteenth_in_bar in [0, 2, 4, 6, 8, 10, 12, 14]
		if is_kick:
			var kt = sixteenth_t
			var punch = 1.0 if (sixteenth_in_bar in [0, 8]) else 0.75
			drum_mix += sin(lerpf(140.0, 36.0, kt) * TAU * kt * 0.1) * pow(1.0 - kt, 2.2) * (0.65 * punch)

		# Cracking Heavy Metal Snare (Beats 2 and 4)
		if sixteenth_in_bar in [4, 12]:
			var st = sixteenth_t
			var snap = sin(320.0 * TAU * st * 0.08) * pow(1.0 - st, 3.5) * 0.65
			var noise_crack = randf_range(-0.6, 0.6) * pow(1.0 - st, 2.5) * 0.60
			drum_mix += snap + noise_crack

		# Open Crash Cymbal on Bar 1 & 5 downbeats
		if (bar_idx == 0 or bar_idx == 4) and beat_in_bar < 1.0:
			var ct = beat_in_bar * beat_dur
			drum_mix += randf_range(-0.35, 0.35) * exp(-3.0 * ct)

		# Sizzling Ride / Hi-Hats
		drum_mix += randf_range(-0.10, 0.10) * (1.0 - sixteenth_t)

		# ======================================================================
		# 7. ANALOG MASTER SATURATION LIMITER (Punchy & Clean)
		# ======================================================================
		var total_sum = metal_guitar + lead_mix + bass_mix + organ_mix + choir_mix + bell_mix + drum_mix
		mix_buffer[i] = tanh(total_sum * 1.12) * 0.85

	# Seamless Loop Crossfade (0.2s)
	var xfade_samples = int(sample_rate * 0.20)
	for k in range(xfade_samples):
		var alpha = float(k) / float(xfade_samples)
		var start_idx = k
		var end_idx = total_samples - xfade_samples + k
		mix_buffer[start_idx] = lerpf(mix_buffer[end_idx], mix_buffer[start_idx], alpha)

	sfx_library["soundtrack_sister"] = _create_stream_from_buffer(mix_buffer, sample_rate, true)

# ------------------------------------------------------------------------------
# 4. PROCEDURAL GRIMDARK SFX GENERATOR
# ------------------------------------------------------------------------------

func _generate_sound_effects():
	# Ballistics & Heavy Munitions
	sfx_library["radium_shot"] = _synth_heavy_bolter_shot(0.18)
	sfx_library["laser"] = _synth_autocannon_thud(0.14)
	sfx_library["autocannon"] = _synth_autocannon_thud(0.14)
	sfx_library["flamer"] = _synth_flamer_burst(0.25)
	
	# High-Tech Energy & Xenotech
	sfx_library["volkite_beam"] = _synth_volkite_ray(0.32)
	sfx_library["arc_lightning"] = _synth_arc_lightning(0.24)
	sfx_library["necron_gauss"] = _synth_necron_gauss(0.26)
	
	# Melee, Impact & Explosions
	sfx_library["axe_swing"] = _synth_heavy_cleave(0.20)
	sfx_library["hit"] = _synth_heavy_impact(0.14)
	sfx_library["orbital_strike"] = _synth_cataclysmic_explosion(1.5)
	
	# Fortifications & Ambient UI
	sfx_library["building_place"] = _synth_pneumatic_clamp(0.24)
	sfx_library["gate_toggle"] = _synth_blast_gate(0.22)
	sfx_library["scrap_pickup"] = _synth_brass_cog_clink(0.16)
	sfx_library["klaxon_alert"] = _synth_vox_klaxon(0.75)
	sfx_library["binary_canticle"] = _synth_binary_burst(0.28)
	sfx_library["level_up"] = _synth_level_up_fanfare(0.45)
	sfx_library["ui_click"] = _synth_relay_click(0.08)

# --- SFX SYNTHESIS HELPERS ---

func _synth_necron_gauss(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase_low = 0.0
	var phase_phase = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		
		# Low 44Hz ancient hum modulated by fast phase fluctuation
		phase_phase += (180.0 * TAU) / sample_rate
		var mod = sin(phase_phase) * 35.0
		phase_low += ((44.0 + mod) * TAU) / sample_rate
		var hum = sin(phase_low) * 0.75
		
		# Green molecular disintegration hiss
		var hiss = randf_range(-0.5, 0.5) * sin(t * PI)
		var env = pow(1.0 - t, 1.2)
		var sample_val = clampf((hum + hiss) * env * 1.4, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_flamer_burst(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var roar = randf_range(-0.85, 0.85) * (1.0 - t * 0.4)
		var hiss = randf_range(-0.35, 0.35) * sin(t * PI)
		var env = sin(t * PI)
		var sample_val = clampf((roar + hiss) * env * 1.2, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_level_up_fanfare(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var p1 = 0.0; var p2 = 0.0; var p3 = 0.0
	var notes = [440.0, 554.37, 659.25, 880.0] # Ascending A Major Arpeggio

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var note_idx = clampi(int(t * 4.0), 0, 3)
		var freq = notes[note_idx]

		p1 += (freq * TAU) / sample_rate
		p2 += (freq * 2.0 * TAU) / sample_rate
		
		var tone = (sin(p1) * 0.6 + sin(p2) * 0.3)
		var env = (1.0 - fmod(t * 4.0, 1.0)) * (1.0 - t * 0.2)
		var sample_val = clampf(tone * env * 1.2, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_relay_click(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var click = randf_range(-0.7, 0.7) * pow(1.0 - t, 8.0)
		byte_data.encode_s16(i * 2, int(clampf(click * 1.3, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_heavy_bolter_shot(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase_sub = 0.0
	var phase_body = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var noise = randf_range(-1.0, 1.0) * pow(1.0 - t, 6.0) * 0.85
		var sub_freq = lerpf(180.0, 48.0, pow(t, 0.4))
		phase_sub += (sub_freq * TAU) / sample_rate
		var sub_body = sin(phase_sub) * pow(1.0 - t, 2.2) * 0.95
		phase_body += (lerpf(360.0, 90.0, t) * TAU) / sample_rate
		var mech_punch = (1.0 if sin(phase_body) > 0.0 else -1.0) * pow(1.0 - t, 3.5) * 0.35
		var raw_mix = (noise * 0.7 + sub_body * 0.8 + mech_punch * 0.4) * 1.5
		var sample_val = clampf(raw_mix - (raw_mix * raw_mix * raw_mix) * 0.15, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_autocannon_thud(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var freq = lerpf(260.0, 58.0, pow(t, 0.5))
		phase += (freq * TAU) / sample_rate
		var tone = sin(phase) * 0.85
		var snap = randf_range(-0.6, 0.6) * (1.0 - t * 5.0 if t < 0.2 else 0.0)
		var env = pow(1.0 - t, 2.8)
		byte_data.encode_s16(i * 2, int(clampf((tone + snap) * env * 1.3, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_volkite_ray(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var fm_mod_phase = 0.0
	var carrier_phase = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		fm_mod_phase += (165.0 * TAU) / sample_rate
		var mod = sin(fm_mod_phase) * 60.0
		carrier_phase += ((75.0 + mod) * TAU) / sample_rate
		var drone = sin(carrier_phase) * 0.65
		var frying_hiss = randf_range(-0.45, 0.45) * sin(t * PI)
		var env = sin(t * PI) * (1.0 - t * 0.3)
		byte_data.encode_s16(i * 2, int(clampf((drone + frying_hiss) * env * 1.4, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_arc_lightning(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase1 = 0.0
	var phase2 = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase1 += (lerpf(420.0, 80.0, t) * TAU) / sample_rate
		phase2 += (lerpf(395.0, 85.0, t) * TAU) / sample_rate
		var saw = (fmod(phase1, TAU) / PI - 1.0) * 0.4 + (fmod(phase2, TAU) / PI - 1.0) * 0.4
		var crackle = randf_range(-0.8, 0.8) * (1.0 - t)
		var env = pow(1.0 - t, 1.6)
		byte_data.encode_s16(i * 2, int(clampf((saw * 0.6 + crackle * 0.7) * env * 1.5, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_heavy_cleave(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var servo_phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		servo_phase += (lerpf(110.0, 340.0, t) * TAU) / sample_rate
		var servo = sin(servo_phase) * 0.35 * sin(t * PI)
		var whoosh = randf_range(-0.7, 0.7) * sin(t * PI) * 0.75
		byte_data.encode_s16(i * 2, int(clampf((servo + whoosh) * 1.3, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_heavy_impact(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase += (lerpf(160.0, 38.0, pow(t, 0.3)) * TAU) / sample_rate
		var thud = sin(phase) * 0.9
		var crunch = randf_range(-0.6, 0.6) * (1.0 - t * 3.5 if t < 0.28 else 0.0)
		var env = pow(1.0 - t, 2.0)
		byte_data.encode_s16(i * 2, int(clampf((thud + crunch) * env * 1.5, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_cataclysmic_explosion(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var sub_phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		sub_phase += (lerpf(88.0, 24.0, pow(t, 0.3)) * TAU) / sample_rate
		var sub_bass = sin(sub_phase) * 0.95
		var rumble = randf_range(-1.0, 1.0) * pow(1.0 - t, 1.3) * 0.7
		var initial_crack = randf_range(-1.0, 1.0) * (1.0 - t * 10.0 if t < 0.10 else 0.0)
		var env = pow(1.0 - t, 1.2)
		var raw = (sub_bass + rumble + initial_crack) * env * 1.6
		var sample_val = clampf(raw - (raw * raw * raw) * 0.12, -1.0, 1.0)
		byte_data.encode_s16(i * 2, int(sample_val * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_pneumatic_clamp(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		phase += (140.0 * TAU) / sample_rate
		var tone = sin(phase) * 0.5 * pow(1.0 - t, 3.0)
		var hiss = randf_range(-0.55, 0.55) * (1.0 - t) * (1.0 - t)
		byte_data.encode_s16(i * 2, int(clampf((tone + hiss) * 1.3, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

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
		byte_data.encode_s16(i * 2, int(clampf((motor + air_release) * (1.0 - t * 0.5), -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_brass_cog_clink(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var p1 = 0.0; var p2 = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		p1 += (1480.0 * TAU) / sample_rate
		p2 += (2240.0 * TAU) / sample_rate
		var ring = (sin(p1) * 0.5 + sin(p2) * 0.5) * pow(1.0 - t, 2.5)
		var mechanical_click = randf_range(-0.4, 0.4) * (1.0 - t * 8.0 if t < 0.12 else 0.0)
		byte_data.encode_s16(i * 2, int(clampf((ring + mechanical_click) * 1.2, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_vox_klaxon(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var p1 = 0.0; var p2 = 0.0
	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		p1 += (110.0 * TAU) / sample_rate
		p2 += (117.0 * TAU) / sample_rate
		var horn = ((1.0 if sin(p1) > 0.0 else -1.0) * 0.45 + (1.0 if sin(p2) > 0.0 else -1.0) * 0.45)
		var env = sin(t * PI) * (0.8 + sin(t * TAU * 4.0) * 0.2)
		byte_data.encode_s16(i * 2, int(clampf(horn * env * 1.3, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

func _synth_binary_burst(duration: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var total_samples = int(sample_rate * duration)
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)

	var phase1 = 0.0; var phase2 = 0.0

	for i in range(total_samples):
		var t = float(i) / float(total_samples)
		var freq1 = 880.0 if (int(t * 16.0) % 2 == 0) else 1174.66
		var freq2 = 1320.0 if (int(t * 16.0) % 2 == 0) else 1760.0
		phase1 += (freq1 * TAU) / sample_rate
		phase2 += (freq2 * TAU) / sample_rate
		var tone = (sin(phase1) * 0.5 + sin(phase2) * 0.3) * 0.6
		var env = sin(t * PI) * (1.0 - t * 0.4)
		byte_data.encode_s16(i * 2, int(clampf(tone * env, -1.0, 1.0) * 32767.0))

	return _create_stream_from_bytes(byte_data, sample_rate)

# --- BUFFER CONVERTERS ---

func _create_stream_from_bytes(bytes: PackedByteArray, sample_rate: int) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _create_stream_from_buffer(buffer: PackedFloat32Array, sample_rate: int, loop: bool = false) -> AudioStreamWAV:
	var total_samples = buffer.size()
	var byte_data = PackedByteArray()
	byte_data.resize(total_samples * 2)
	for i in range(total_samples):
		var int16_val = int(clampf(buffer[i] * 32767.0, -32768.0, 32767.0))
		byte_data.encode_s16(i * 2, int16_val)

	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = total_samples
	return stream

# ------------------------------------------------------------------------------
# 5. SMART 2D & UI AUDIO POOLING (With Voice Stealing & Rate Limiting)
# ------------------------------------------------------------------------------

func _create_audio_pools():
	# 1. Positional 2D Audio Pool
	for i in range(POOL_SIZE_2D):
		var p = AudioStreamPlayer2D.new()
		p.name = "AudioPoolPlayer2D_" + str(i)
		p.bus = "SFX"
		p.max_distance = 1600.0
		add_child(p)
		player_pool_2d.append(p)

	# 2. Non-Positional Global UI Audio Pool
	for i in range(POOL_SIZE_UI):
		var p = AudioStreamPlayer.new()
		p.name = "AudioPoolPlayerUI_" + str(i)
		p.bus = "SFX"
		add_child(p)
		player_pool_ui.append(p)

func play_sfx(sfx_name: String, world_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0, pitch_scale: float = 1.0):
	if not sfx_library.has(sfx_name): return

	# 1. Rate-limit identical rapid sound triggers to prevent ear-clipping distortion
	if sfx_cooldowns.has(sfx_name): return
	sfx_cooldowns[sfx_name] = MIN_SFX_INTERVAL

	# 2. Duck music on massive cataclysmic events
	if sfx_name == "orbital_strike" or sfx_name == "klaxon_alert":
		duck_music(-8.0, 1.4)

	# 3. ROUTE TO GLOBAL UI POOL (if non-positional alert, UI, or banner sound)
	if world_pos == Vector2.ZERO or sfx_name in ["klaxon_alert", "level_up", "ui_click", "binary_canticle"]:
		for p in player_pool_ui:
			if not p.playing:
				p.stream = sfx_library[sfx_name]
				p.volume_db = volume_db
				p.pitch_scale = pitch_scale * randf_range(0.97, 1.03)
				p.play()
				return
		# Fallback UI voice steal
		var p = player_pool_ui[0]
		p.stream = sfx_library[sfx_name]
		p.volume_db = volume_db
		p.pitch_scale = pitch_scale
		p.play()
		return

	# 4. ROUTE TO 2D SPATIAL POOL
	for p in player_pool_2d:
		if not p.playing:
			p.stream = sfx_library[sfx_name]
			p.global_position = world_pos
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale * randf_range(0.95, 1.05)
			p.play()
			return

	# 5. VOICE STEALING (If all 24 channels are busy, steal channel 0)
	var oldest_p = player_pool_2d[0]
	oldest_p.stream = sfx_library[sfx_name]
	oldest_p.global_position = world_pos
	oldest_p.volume_db = volume_db
	oldest_p.pitch_scale = pitch_scale
	oldest_p.play()
