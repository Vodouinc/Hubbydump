# res://Patcher.gd
extends Node
class_name Patcher

const LOCAL_VERSION: String = "1.1.1"
const MANIFEST_URL: String = "https://raw.githubusercontent.com/Vodouinc/Hubbydump/main/version.json"

signal patch_status_changed(status_text: String)
signal patch_completed()

var http_manifest: HTTPRequest = null
var http_download: HTTPRequest = null

var is_downloading: bool = false
var current_patch_name: String = ""

func _ready() -> void:
	# Mount existing patch into memory on boot
	var save_path = "user://game_patch.pck"
	if FileAccess.file_exists(save_path):
		var success = ProjectSettings.load_resource_pack(save_path, true)
		if success:
			print("[Patcher] Mounted active patch on boot.")

	# 2. Manifest Requester
	http_manifest = HTTPRequest.new()
	http_manifest.max_redirects = 8
	http_manifest.timeout = 10.0
	http_manifest.use_threads = true
	add_child(http_manifest)
	http_manifest.request_completed.connect(_on_manifest_received)

	# 3. Downloader (Multi-threaded for fast reliable downloads)
	http_download = HTTPRequest.new()
	http_download.max_redirects = 8
	http_download.timeout = 60.0
	http_download.use_threads = true
	add_child(http_download)
	http_download.request_completed.connect(_on_patch_downloaded)

func _process(_delta: float) -> void:
	# Real-Time Download Percentage
	if is_downloading and is_instance_valid(http_download):
		var body_size = http_download.get_body_size()
		var downloaded = http_download.get_downloaded_bytes()
		if body_size > 0:
			var pct = int((float(downloaded) / float(body_size)) * 100.0)
			emit_signal("patch_status_changed", "Downloading %s (%d%%)..." % [current_patch_name, pct])
		elif downloaded > 0:
			var kb = downloaded / 1024
			emit_signal("patch_status_changed", "Downloading %s (%d KB)..." % [current_patch_name, kb])

func check_for_updates(secret_code: String = "") -> void:
	emit_signal("patch_status_changed", "Connecting to GitHub Data-Vault...")
	set_meta("secret_code", secret_code.strip_edges())

	var headers: PackedStringArray = ["User-Agent: Godot-Patcher-Client"]
	var err = http_manifest.request(MANIFEST_URL, headers)
	if err != OK:
		emit_signal("patch_status_changed", "Request failed to start (Error %d)" % err)

func _on_manifest_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[Patcher] Manifest Response: HTTP ", response_code, " Result: ", result)

	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("patch_status_changed", "Connection failed (Code: %d)" % result)
		return

	if response_code != 200:
		emit_signal("patch_status_changed", "Manifest error (HTTP %d)" % response_code)
		return

	var raw_str = body.get_string_from_utf8()
	var json = JSON.new()
	var err = json.parse(raw_str)
	if err != OK or not (json.data is Dictionary):
		emit_signal("patch_status_changed", "Corrupted version.json.")
		return

	var manifest: Dictionary = json.data
	var secret_code: String = get_meta("secret_code", "")
	var target_patch_url: String = ""
	var patch_name: String = ""

	if not secret_code.is_empty():
		var unreleased_dict = manifest.get("unreleased_patches", {})
		if unreleased_dict.has(secret_code):
			target_patch_url = unreleased_dict[secret_code]
			patch_name = "%s" % secret_code
		else:
			emit_signal("patch_status_changed", "Invalid Secret Code: %s" % secret_code)
			return
	elif manifest.get("current_version", "") != LOCAL_VERSION:
		target_patch_url = manifest.get("patch_url", "")
		patch_name = "v%s" % manifest.get("current_version", "")

	if not target_patch_url.is_empty():
		_download_pck(target_patch_url, patch_name)
	else:
		emit_signal("patch_status_changed", "Latest build v%s active." % LOCAL_VERSION)

func _download_pck(url: String, patch_title: String) -> void:
	current_patch_name = patch_title
	is_downloading = true
	emit_signal("patch_status_changed", "Starting download %s..." % patch_title)
	print("[Patcher] Downloading from URL: ", url)

	var headers: PackedStringArray = ["User-Agent: Godot-Patcher-Client"]
	var err = http_download.request(url, headers)
	if err != OK:
		is_downloading = false
		emit_signal("patch_status_changed", "Download request failed (Error %d)" % err)

func _on_patch_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_downloading = false
	print("[Patcher] Download finished. Result: ", result, " HTTP: ", response_code, " Bytes: ", body.size())

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		emit_signal("patch_status_changed", "Download failed (HTTP %d / Code %d)" % [response_code, result])
		return

	if body.is_empty():
		emit_signal("patch_status_changed", "Error: Empty file received.")
		return

	var save_path = "user://game_patch.pck"
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		emit_signal("patch_status_changed", "Failed to write patch to user://")
		return

	file.store_buffer(body)
	file.close()

	# Save active patch tag so title screen remembers it after reloading!
	var meta_file = FileAccess.open("user://active_patch_meta.txt", FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(current_patch_name)
		meta_file.close()

	var file_size_kb = body.size() / 1024
	print("[Patcher] Saved patch: %d KB" % file_size_kb)

	# 1. Mount into virtual file system

	emit_signal("patch_status_changed", "Mounting patch (%d KB)..." % file_size_kb)
	var success = ProjectSettings.load_resource_pack(save_path, true)

	if success:
		emit_signal("patch_status_changed", "✓ Patch Installed! Restarting game...")
		emit_signal("patch_completed")
		
		# Convert user:// path to an absolute system path
		var absolute_pck_path = ProjectSettings.globalize_path(save_path)
		
		# Tell Godot to restart the executable using the downloaded patch as the PRIMARY game pack!
		await get_tree().create_timer(1.2).timeout
		OS.set_restart_on_exit(true, ["--main-pack", absolute_pck_path])
		get_tree().quit()
	else:
		emit_signal("patch_status_changed", "Failed to mount .pck file.")

static func get_active_patch_name() -> String:
	if FileAccess.file_exists("user://active_patch_meta.txt"):
		var f = FileAccess.open("user://active_patch_meta.txt", FileAccess.READ)
		if f:
			var tag = f.get_as_text().strip_edges()
			f.close()
			return tag
	return ""
