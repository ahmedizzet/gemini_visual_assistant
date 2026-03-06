import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AudioHandler {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _isPlayerRunning = false;

  Future<void> init() async {
    if (_initialized) return;
    await _player.openPlayer();
    // Setting a shorter duration can help with responsiveness
    await _player.setSubscriptionDuration(const Duration(milliseconds: 50));
    _initialized = true;
  }

  Future<void> playAudioChunk(Uint8List bytes) async {
    try {
      await init();

      if (!_isPlayerRunning) {
        // Gemini Live usually outputs PCM 16-bit at 24000 Hz.
        await _player.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000, interleaved: true, bufferSize: 8192,
        );
        _isPlayerRunning = true;
      }

      await _player.feedFromStream(bytes);
    } catch (e) {
      print("Audio stream error: $e");
    }
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  /// Stops playback immediately and resets the stream state.
  /// This is crucial to prevent the "repeating word" loop.
  Future<void> stopAll() async {
    try {
      if (_isPlayerRunning) {
        _isPlayerRunning = false;
        await _player.stopPlayer();
      }
      await _tts.stop();
    } catch (e) {
      print("Error stopping audio: $e");
    }
  }

  Future<void> dispose() async {
    await stopAll();
    await _player.closePlayer();
  }
}
