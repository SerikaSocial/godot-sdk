@tool
@icon("res://addons/serika_sdk/icons/portal.svg")
class_name SerikaVideoPlayer
extends MeshInstance3D

## A cinema-style video surface. Fetches a YouTube thumbnail and, if a direct stream URL is
## available, plays it on the mesh. Authors set the YouTube video ID; the runtime resolves it.
## The server resolves the URL via yt-dlp and, if the engine can't decode the format (e.g. mp4),
## transcodes to ogv/Theora via ffmpeg on the fly through /v1/video/transcode.

@export_group("Video")
## YouTube video ID (the part after v= in the URL).
@export var youtube_video_id: String = "01cgf4eb7us"
## If the CDN already has a transcoded stream, use this URL instead of YouTube.
@export var stream_url: String = ""
## Whether to start playing automatically.
@export var autoplay: bool = true
## Loop the video.
@export var loop: bool = true

@export_group("Surface")
## 16:9 screen size in metres.
@export var screen_size: Vector2 = Vector2(12.0, 6.75)

@export_group("Audio")
## Volume (0-1).
@export_range(0.0, 1.0, 0.01) var volume: float = 0.8

var _video_player: VideoStreamPlayer
var _http: HTTPRequest
var _screen_mat: StandardMaterial3D

func _ready() -> void:
	if mesh == null:
		mesh = QuadMesh.new()
	mesh.size = screen_size

	_screen_mat = StandardMaterial3D.new()
	_screen_mat.emission = Color.WHITE
	_screen_mat.emission_energy_multiplier = 2.0
	_screen_mat.roughness = 0.1
	material_override = _screen_mat

	if stream_url.is_empty():
		_fetch_youtube_thumbnail()
	else:
		_play_stream(stream_url)

func _fetch_youtube_thumbnail() -> void:
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_thumbnail)
	add_child(_http)
	_http.request("https://img.youtube.com/vi/%s/maxresdefault.jpg" % youtube_video_id)

func _on_thumbnail(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200 or body.size() == 0:
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(body) != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	_screen_mat.albedo_texture = tex
	_screen_mat.emission_texture = tex

func _play_stream(url: String) -> void:
	_video_player = VideoStreamPlayer.new()
	add_child(_video_player)
	_video_player.stream = load(url) as VideoStream
	_video_player.volume = volume
	_video_player.autoplay = autoplay
	_video_player.loop = loop
	_video_player.expand = true
	_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if youtube_video_id.is_empty() and stream_url.is_empty():
		warnings.append("Set youtube_video_id or stream_url")
	return warnings
