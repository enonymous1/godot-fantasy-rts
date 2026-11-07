## Procedural sound effects — no audio files. Every effect is a
## short tone / noise burst synthesized into an AudioStreamWAV
## at 22050 Hz, 16-bit mono. Pure synthesis, so it is unit-testable
## (make_tone returns a stream with the right rate and data size).
class_name RTSSoundManager
extends Node

const MIX_RATE := 22050

var muted: bool = false


func make_tone(freq: float, duration: float, volume: float = 0.4, wave: String = "sine") -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / MIX_RATE
		var s := 0.0
		match wave:
			"sine":
				s = sin(TAU * freq * t)
			"square":
				s = 1.0 if sin(TAU * freq * t) >= 0.0 else -1.0
			"noise":
				s = randf_range(-1.0, 1.0)
		# Simple decay envelope so clicks do not pop.
		var env := 1.0 - float(i) / float(maxi(frames, 1))
		var v := int(clampf(s * volume * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


func play(effect: String) -> void:
	if muted:
		return
	var stream: AudioStreamWAV = null
	match effect:
		"click":
			stream = make_tone(660.0, 0.05, 0.3)
		"order":
			stream = make_tone(440.0, 0.07, 0.35)
		"coin":
			stream = make_tone(990.0, 0.12, 0.4)
		"train":
			stream = make_tone(520.0, 0.1, 0.35, "square")
		"build_complete":
			stream = make_tone(780.0, 0.18, 0.4)
		"attack":
			stream = make_tone(180.0, 0.09, 0.35, "noise")
		"error":
			stream = make_tone(160.0, 0.18, 0.4, "square")
		"victory":
			stream = make_tone(880.0, 0.4, 0.4)
		"defeat":
			stream = make_tone(220.0, 0.5, 0.4, "square")
		_:
			return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	# Cap concurrent players so a big battle cannot stack dozens.
	var players := 0
	for c in get_children():
		if c is AudioStreamPlayer:
			players += 1
	if players > 8:
		for c in get_children():
			if c is AudioStreamPlayer:
				c.queue_free()
				break


func toggle_mute() -> bool:
	muted = not muted
	return muted
