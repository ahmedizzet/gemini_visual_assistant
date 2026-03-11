import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../../../../services/camera_service.dart';
import '../../data/live_repository.dart';

class AimScreen extends StatefulWidget {
  const AimScreen({super.key});

  @override
  State<AimScreen> createState() => _AimScreenState();
}

class _AimScreenState extends State<AimScreen> {
  final CameraService _cameraService = CameraService();
  final FlutterTts _flutterTts = FlutterTts();
  late final LiveAssistantRepository _liveRepository;
  bool _isThinking = false;
  Timer? _thinkingTimer;
  String _lastSpeech =
      "welcome to AIM, your gemini powered visual assistant. double tap the screen for me to describe what is in front of you";

  @override
  void initState() {
    super.initState();
    _liveRepository = LiveAssistantRepository();
    _initializeCamera();
    _speakWelcome();
  }

  Future<void> _speakWelcome() async {
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.speak(_lastSpeech);
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraService.initialize();
      setState(() {});
    } catch (e) {
      debugPrint("Camera initialization failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Camera Error: $e")));
      }
    }
  }

  void _startThinkingFeedback() {
    _flutterTts.speak("Thinking");
    _thinkingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isThinking) {
        _flutterTts.speak("Thinking");
      } else {
        timer.cancel();
      }
    });
  }

  void _stopThinkingFeedback() {
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
  }

  Future<void> _analyzeCurrentView() async {
    if (_isThinking) return;

    setState(() => _isThinking = true);

    try {
      if (_cameraService.controller == null ||
          !_cameraService.controller!.value.isInitialized) {
        setState(() => _lastSpeech = "Camera not ready");
        await _flutterTts.speak("Camera not ready");
        return;
      }

      setState(() => _lastSpeech = "Capturing...");
      final XFile image = await _cameraService.controller!.takePicture();
      final bytes = await image.readAsBytes();

      setState(() => _lastSpeech = "Thinking...");
      _startThinkingFeedback();

      final text = await _liveRepository.analyzeImage(bytes);

      _stopThinkingFeedback();
      await _flutterTts.stop(); // Stop any remaining "Thinking" audio

      if (text != null) {
        setState(() => _lastSpeech = text);

        // Trigger vibration if danger is detected
        if (text.toLowerCase().contains("warning") ||
            text.toLowerCase().contains("danger") ||
            text.toLowerCase().contains("caution")) {
          _vibrate();
        }

        await _flutterTts.speak(text);
      } else {
        setState(() => _lastSpeech = "Could not describe the image.");
        await _flutterTts.speak("Could not describe the image.");
      }
    } catch (e) {
      debugPrint("Analysis Error: $e");
      _stopThinkingFeedback();
      setState(() => _lastSpeech = "Error occurred.");
      await _flutterTts.speak("Error occurred.");
    } finally {
      setState(() => _isThinking = false);
    }
  }

  void _vibrate() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 200, 500]);
    }
  }

  void _handleDoubleTap() {
    _flutterTts.stop();
    if (!_isThinking) {
      _analyzeCurrentView();
    } else {
      _flutterTts.speak("Still thinking, please wait");
    }
  }

  void _handleLongPress() async {
    await _flutterTts.stop();
    await _flutterTts.speak(_lastSpeech);
  }

  @override
  void dispose() {
    _stopThinkingFeedback();
    _cameraService.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraService.controller == null ||
        !_cameraService.controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.yellow)),
      );
    }

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _handleDoubleTap,
        onLongPress: _handleLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cameraService.controller!),
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellow, width: 2),
                ),
                child: Text(
                  _lastSpeech,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
            if (_isThinking)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.yellow,
                  strokeWidth: 8,
                ),
              ),
          ],
        ),
      ),
    );
  }
}