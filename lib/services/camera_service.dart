import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants/api_constants.dart';

class CameraService {
  CameraController? _controller;
  bool _isProcessing = false;
  DateTime? _lastFrameTime;

  CameraController? get controller => _controller;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception("No cameras available");

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  void startImageStream(Function(Uint8List) onFrameAvailable) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((CameraImage image) async {
      final now = DateTime.now();

      // Throttle to API standard (e.g., 1 FPS)
      if (_lastFrameTime != null &&
          now.difference(_lastFrameTime!).inMilliseconds <
              (1000 / ApiConstants.frameRate)) {
        return;
      }

      if (_isProcessing) return;
      _isProcessing = true;
      _lastFrameTime = now;

      try {
        // Convert YUV to JPEG bytes in a compute isolate to keep UI smooth
        final jpegBytes = await compute(_convertYUV420ToJPEG, image);
        onFrameAvailable(jpegBytes);
      } catch (e) {
        debugPrint("Error processing camera frame: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  void stopImageStream() {
    _controller?.stopImageStream();
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

/// Efficiently convert a [CameraImage] (YUV420) to JPEG bytes using the 'image' package.
Uint8List _convertYUV420ToJPEG(CameraImage image) {
  final int width = image.width;
  final int height = image.height;

  // Create a new image container
  final img.Image res = img.Image(width: width, height: height);

  // YUV to RGB Conversion loop
  final yPlane = image.planes[0].bytes;
  final uPlane = image.planes[1].bytes;
  final vPlane = image.planes[2].bytes;

  final int yRowStride = image.planes[0].bytesPerRow;
  final int uvRowStride = image.planes[1].bytesPerRow;
  final int uvPixelStride = image.planes[1].bytesPerPixel!;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIndex = y * yRowStride + x;
      final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final int yp = yPlane[yIndex];
      final int up = uPlane[uvIndex];
      final int vp = vPlane[uvIndex];

      // Standard YUV to RGB formula
      int r = (yp + 1.402 * (vp - 128)).toInt();
      int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).toInt();
      int b = (yp + 1.772 * (up - 128)).toInt();

      res.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }

  // Encode as JPEG with configured quality
  return Uint8List.fromList(
    img.encodeJpg(res, quality: ApiConstants.imageQuality.toInt()),
  );
}
