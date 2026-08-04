## Tiny procedural one-shots — no imported audio files.
##
## Generated at load as AudioStreamWAV buffers. Kept deliberately rough: this
## phase is about the street being audible, not about sound design polish.

class_name ProceduralSounds
extends RefCounted

const SAMPLE_RATE := 22050


static func ambient_loop() -> AudioStreamWAV:
	## ~2 s of soft band-limited noise, looped. Reads as distant air / estate hum.
	var frames := SAMPLE_RATE * 2
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	var prev := 0.0
	for i in frames:
		var t := float(i) / float(SAMPLE_RATE)
		var n := randf_range(-1.0, 1.0)
		prev = lerpf(prev, n, 0.04)
		var hum := sin(t * TAU * 42.0) * 0.015 + sin(t * TAU * 97.0) * 0.008
		var s := clampf(prev * 0.09 + hum, -1.0, 1.0)
		_write_i16(pcm, i * 2, int(s * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = pcm
	return stream


static func footstep() -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * 0.07)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(frames)
		var env := (1.0 - t) * (1.0 - t)
		var n := randf_range(-1.0, 1.0)
		var click := sin(t * PI * 6.0) * 0.35
		var s := (n * 0.55 + click) * env * 0.5
		_write_i16(pcm, i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _one_shot(pcm)


static func melee_thud() -> AudioStreamWAV:
	var frames := int(SAMPLE_RATE * 0.11)
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 28.0)
		var body := sin(t * TAU * 110.0) * 0.55 + sin(t * TAU * 58.0) * 0.25
		var n := randf_range(-1.0, 1.0) * 0.12
		var s := (body + n) * env
		_write_i16(pcm, i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return _one_shot(pcm)


static func _one_shot(pcm: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


static func _write_i16(buf: PackedByteArray, offset: int, sample: int) -> void:
	var v := clampi(sample, -32768, 32767)
	buf[offset] = v & 0xFF
	buf[offset + 1] = (v >> 8) & 0xFF
