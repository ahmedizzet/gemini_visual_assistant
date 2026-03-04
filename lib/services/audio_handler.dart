import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioHandler {
  static final AudioHandler _instance = AudioHandler._internal();
  factory AudioHandler() => _instance;
  AudioHandler._internal();

  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  bool _isPlaylistSet = false;

  Future<void> init() async {
    // Already handled by lazy initialization in _ensurePlaylistSet
  }

  Future<void> _ensurePlaylistSet() async {
    if (!_isPlaylistSet) {
      await _player.setAudioSource(_playlist);
      _isPlaylistSet = true;
    }
  }

  void playAudioChunk(Uint8List audioData) async {
    // Gemini Live returns raw PCM L16 (16-bit) mono at 24kHz.
    // just_audio/ExoPlayer needs a container (WAV) to recognize the format.
    final header = _getWavHeader(audioData.length);
    final wavData = Uint8List(header.length + audioData.length);
    wavData.setAll(0, header);
    wavData.setAll(header.length, audioData);

    await _ensurePlaylistSet();
    
    final source = BufferAudioSource(wavData);
    await _playlist.add(source);
    
    if (!_player.playing) {
      _player.play();
    }
  }

  Uint8List _getWavHeader(int dataLength) {
    final int sampleRate = 24000;
    final int channels = 1;
    final int byteRate = sampleRate * channels * 2;
    final int blockAlign = channels * 2;
    final int headerLength = 44;
    final int totalLength = dataLength + headerLength;

    final header = ByteData(headerLength);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, totalLength - 8, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Size of fmt chunk
    header.setUint16(20, 1, Endian.little); // Format (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little); // Bits per sample
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataLength, Endian.little);

    return header.buffer.asUint8List();
  }

  void stopAll() {
    _player.stop();
    _playlist.clear();
  }

  void dispose() {
    _player.dispose();
  }
}

class BufferAudioSource extends StreamAudioSource {
  final Uint8List _buffer;

  BufferAudioSource(this._buffer);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
