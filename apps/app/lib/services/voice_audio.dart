import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'file_io.dart' as fio;

/// Microphone + speaker for walkie-talkie mode.
///
/// Captures 8 kHz mono PCM when the platform supports it; otherwise emits a
/// short tone so PTT still exercises the mesh path (desktop/web without mic).
final class VoiceAudio {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final BytesBuilder _capture = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _streamSub;
  bool _recording = false;
  String? _wavPath;
  bool micAvailable = true;
  String? lastError;

  bool get isRecording => _recording;

  Future<bool> ensureMicPermission() async {
    try {
      final ok = await _recorder.hasPermission();
      micAvailable = ok;
      return ok;
    } catch (e) {
      lastError = e.toString();
      micAvailable = false;
      return false;
    }
  }

  /// Start capturing PCM (or prepare tone fallback).
  Future<void> startCapture() async {
    if (_recording) return;
    _capture.clear();
    _wavPath = null;
    lastError = null;

    final permitted = await ensureMicPermission();
    if (!permitted) {
      _recording = true;
      return;
    }

    try {
      if (await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: VoiceWire.defaultSampleRate,
            numChannels: VoiceWire.defaultChannels,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
          ),
        );
        _streamSub = stream.listen((chunk) {
          if (_capture.length >= VoiceWire.maxPcmBytes) return;
          final room = VoiceWire.maxPcmBytes - _capture.length;
          if (chunk.length <= room) {
            _capture.add(chunk);
          } else if (room > 0) {
            _capture.add(Uint8List.sublistView(chunk, 0, room));
          }
        });
        _recording = true;
        return;
      }

      if (!kIsWeb) {
        final path =
            '/tmp/zvcomm_ptt_${DateTime.now().microsecondsSinceEpoch}.wav';
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: VoiceWire.defaultSampleRate,
            numChannels: VoiceWire.defaultChannels,
          ),
          path: path,
        );
        _wavPath = path;
        _recording = true;
        return;
      }

      // Web without PCM stream: tone fallback after permission quirks.
      micAvailable = false;
      lastError = 'PCM stream not available on this platform';
      _recording = true;
    } catch (e) {
      lastError = e.toString();
      micAvailable = false;
      _recording = true;
    }
  }

  /// Stop capture and return PCM s16le mono @ 8 kHz (tone if mic failed).
  Future<Uint8List> stopCapture() async {
    if (!_recording) return Uint8List(0);
    _recording = false;

    await _streamSub?.cancel();
    _streamSub = null;

    try {
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        if (path != null && path.isNotEmpty) {
          _wavPath ??= path;
        }
      }
    } catch (e) {
      lastError = e.toString();
    }

    if (_capture.length > 0) {
      final pcm = _evenLength(_capture.toBytes());
      _capture.clear();
      _wavPath = null;
      return pcm;
    }

    if (_wavPath != null) {
      try {
        final bytes = await fio.readBytes(_wavPath!);
        final pcm = wavToPcm16(bytes);
        _wavPath = null;
        if (pcm != null && pcm.isNotEmpty) return _evenLength(pcm);
      } catch (e) {
        lastError = e.toString();
      }
      _wavPath = null;
    }

    return generateTonePcm(
      frequencyHz: 700,
      durationMs: 400,
      sampleRate: VoiceWire.defaultSampleRate,
    );
  }

  Future<void> cancelCapture() async {
    _recording = false;
    await _streamSub?.cancel();
    _streamSub = null;
    _capture.clear();
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    _wavPath = null;
  }

  /// Play a PCM clip (WAV in memory).
  Future<void> playPcm(
    Uint8List pcm, {
    int sampleRate = VoiceWire.defaultSampleRate,
    int channels = VoiceWire.defaultChannels,
  }) async {
    if (pcm.isEmpty) return;
    final wav = pcm16ToWav(pcm, sampleRate: sampleRate, channels: channels);
    try {
      await _player.stop();
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e) {
      lastError = e.toString();
      if (kIsWeb) return;
      try {
        final path =
            '/tmp/zvcomm_rx_${DateTime.now().microsecondsSinceEpoch}.wav';
        await fio.writeBytes(path, wav);
        await _player.play(DeviceFileSource(path));
      } catch (e2) {
        lastError = e2.toString();
      }
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await cancelCapture();
    await stopPlayback();
    await _recorder.dispose();
    await _player.dispose();
  }

  static Uint8List _evenLength(Uint8List pcm) {
    if (pcm.length.isEven) return pcm;
    return Uint8List.sublistView(pcm, 0, pcm.length - 1);
  }
}

/// Generate a mono s16le tone (mic-less fallback / tests).
Uint8List generateTonePcm({
  double frequencyHz = 880,
  int durationMs = 350,
  int sampleRate = VoiceWire.defaultSampleRate,
  double amplitude = 0.35,
}) {
  final n = (sampleRate * durationMs / 1000).round();
  final out = ByteData(n * 2);
  final twoPiF = 2 * pi * frequencyHz / sampleRate;
  for (var i = 0; i < n; i++) {
    final s =
        (sin(i * twoPiF) * amplitude * 32767).round().clamp(-32768, 32767);
    out.setInt16(i * 2, s, Endian.little);
  }
  return out.buffer.asUint8List();
}
