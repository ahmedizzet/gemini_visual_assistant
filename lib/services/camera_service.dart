import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants/api_constants.dart';

class CameraService {
  CameraController? _controller;

  bool _isProcessing = false;
  DateTime? _lastFrameTime;

  CameraController? get controller => _controller;

  /// Initialize camera
  Future<void> initialize() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw Exception("No cameras available");
    }

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  /// Start streaming frames
  void startImageStream(Function(Uint8List) onFrameAvailable) {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isStreamingImages) {
      return;
    }

    _controller!.startImageStream((CameraImage image) async {
      final now = DateTime.now();

      /// Frame throttling (default 1 FPS)
      if (_lastFrameTime != null &&
          now.difference(_lastFrameTime!).inMilliseconds <
              ApiConstants.frameIntervalMs) {
        return;
      }

      if (_isProcessing) return;

      _isProcessing = true;
      _lastFrameTime = now;

      try {
        final Map<String, dynamic> isolateData = {
          'planes': image.planes.map((p) => p.bytes).toList(),
          'width': image.width,
          'height': image.height,
          'yRowStride': image.planes[0].bytesPerRow,
          'uvRowStride': image.planes[1].bytesPerRow,
          'uvPixelStride': image.planes[1].bytesPerPixel,
        };

        final jpegBytes =
        await compute(_convertYUVToJPEGIsolate, isolateData);

        if (jpegBytes != null) {
          onFrameAvailable(jpegBytes);
        }
      } catch (e) {
        debugPrint("CameraService Error: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// Stop streaming frames
  void stopImageStream() {
    if (_controller?.value.isStreamingImages ?? false) {
      _controller?.stopImageStream();
    }
  }

  /// Dispose camera
  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

///
/// Runs in a background isolate
/// Converts YUV420 → JPEG
///
Uint8List? _convertYUVToJPEGIsolate(Map<String, dynamic> data) {
  try {
    final int width = data['width'];
    final int height = data['height'];
    final List<Uint8List> planes = data['planes'];

    final int yRowStride = data['yRowStride'];
    final int uvRowStride = data['uvRowStride'];
    final int uvPixelStride = data['uvPixelStride'];

    final img.Image image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * yRowStride + x;
        final int uvIndex =
            (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yp = planes[0][yIndex];
        final int up = planes[1][uvIndex];
        final int vp = planes[2][uvIndex];

        int r = (yp + 1.402 * (vp - 128)).toInt();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).toInt();
        int b = (yp + 1.772 * (up - 128)).toInt();

        image.setPixelRgb(
          x,
          y,
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
      }
    }

    /// Downscale image before sending to Gemini
    final img.Image resized = img.copyResize(
      image,
      width: 320,
    );

    /// Encode to JPEG
    return Uint8List.fromList(
      img.encodeJpg(
        resized,
        quality: 40,
      ),
    );
  } catch (e) {
    debugPrint("Isolate Conversion Error: $e");
    return null;
  }
}