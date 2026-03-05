import 'dart:async';
import 'package:camera/camera.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
  bool _isAiming = false;
  bool _isThinking = false;
  String _lastSpeech = "Double tap to force describe. Tap button to start.";
  Timer? _recurringTimer;

  Future<void> _testGemini() async {
    if (!_isAiming || _isThinking) return;

    _recurringTimer?.cancel();
    _isThinking = true;

    try {
      if (_cameraService.controller == null ||
          !_cameraService.controller!.value.isInitialized) {
        setState(() => _lastSpeech = "Camera not ready");
        return;
      }

      setState(() => _lastSpeech = "Capturing...");

      final XFile image = await _cameraService.controller!.takePicture();
      final bytes = await image.readAsBytes();

      final prompt = [
        Content.multi([
          TextPart('''
          You are describing an image to a blind person who wants to quickly understand what is happening.

Rules:
- Be very brief (1–2 sentences maximum).
- Focus only on the main action or event.
- Mention only important objects or people.
- Do NOT describe colors, artistic style, or small details unless they are essential.
- Avoid long introductions or explanations.

Safety rule:
- If the image contains a possible danger (fire, traffic, sharp objects, falling risk, aggressive behavior, unsafe environment, etc.), clearly warn the user.
- Start the sentence with "Warning:" when danger exists.
- Don't offer extra support, your support is describe the vent briefly.

Output format:
If safe:
[Main action]. [Important context if needed].

If dangerous:
Warning: [Short description of the danger]. [Main action or context].
              '''),
          InlineDataPart('image/jpeg', bytes),
        ]),
      ];

      setState(() => _lastSpeech = "Thinking...");

      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-3.1-flash-lite-preview',
      );
      final response = await model.generateContent(prompt);
      final text = response.text;

      if (text != null) {
        setState(() => _lastSpeech = text);
        print("===> Gemini Response: $text");
        await _flutterTts.stop(); // Stop any current speech
        await _flutterTts.speak(text);
      } else {
        setState(() => _lastSpeech = "Could not describe the image.");
      }
    } catch (e) {
      debugPrint("Test Gemini Error: $e");
      setState(() => _lastSpeech = "Error: $e");
    } finally {
      _isThinking = false;
      if (_isAiming) {
        _scheduleNext();
      }
    }
  }

  void _scheduleNext() {
    _recurringTimer?.cancel();
    _recurringTimer = Timer(const Duration(seconds: 6), _testGemini);
  }

  @override
  void initState() {
    super.initState();
    _liveRepository = LiveAssistantRepository(
      onInterrupted: (interrupted) {
        if (interrupted) {
          debugPrint("Interrupted! Model should stop audio.");
        }
      },
      onSpeechReceived: (text) {
        setState(() => _lastSpeech = text);
      },
    );
    _initializeCamera();
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

  void _toggleAim() async {
    if (_isAiming) {
      _stopAiming();
    } else {
      _startAiming();
    }
  }

  void _startAiming() {
    setState(() {
      _isAiming = true;
      _lastSpeech = "Aim started. Describing every 4s...";
    });
    _testGemini();
  }

  void _stopAiming() {
    _recurringTimer?.cancel();
    _flutterTts.stop();
    setState(() {
      _isAiming = false;
      _isThinking = false;
      _lastSpeech = "Aim stopped.";
    });
  }

  void _handleDoubleTap() {
    if (!_isAiming) return;

    // Interrupt current thinking if possible (by resetting flag and stopping TTS)
    // and trigger a fresh request immediately.
    _flutterTts.stop();

    // If it's already thinking, we have to wait for the camera/network to free up
    // but we can force it to not wait for the timer.
    if (!_isThinking) {
      _testGemini();
    } else {
      setState(() => _lastSpeech = "Model is busy. Please wait...");
    }
  }

  @override
  void dispose() {
    _recurringTimer?.cancel();
    _cameraService.dispose();
    _liveRepository.stopAim();
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
        onDoubleTap: _handleDoubleTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background: Camera Preview
            CameraPreview(_cameraService.controller!),

            // Foreground: High-contrast overlay for speech and interaction
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

            // Massive interactive zone at the bottom
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 50.0),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: 100,
                  child: FloatingActionButton.extended(
                    onPressed: _toggleAim,
                    backgroundColor: _isAiming ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    icon: Icon(
                      _isAiming ? Icons.stop : Icons.play_arrow,
                      size: 40,
                    ),
                    label: Text(
                      _isAiming ? "STOP AIM" : "START AIM",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
