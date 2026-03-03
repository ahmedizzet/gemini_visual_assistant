import 'package:camera/camera.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import '../../../../services/camera_service.dart';
import '../../data/live_repository.dart';

class AimScreen extends StatefulWidget {
  const AimScreen({super.key});

  @override
  State<AimScreen> createState() => _AimScreenState();
}

class _AimScreenState extends State<AimScreen> {
  final CameraService _cameraService = CameraService();
  late final LiveAssistantRepository _liveRepository;
  bool _isAiming = false;
  String _lastSpeech = "Tap below to start Aim";

  Future<void> _testGemini() async {
    try {
      final model = FirebaseAI.googleAI().generativeModel(model: 'gemini-3-flash-preview');

      if (_cameraService.controller == null || !_cameraService.controller!.value.isInitialized) {
        setState(() => _lastSpeech = "Camera not ready");
        return;
      }

      setState(() => _lastSpeech = "Capturing image...");
      
      // 1. Capture the image from the camera
      final XFile image = await _cameraService.controller!.takePicture();
      final bytes = await image.readAsBytes();

      // 2. Prepare the multi-modal prompt (Text + Image)
      final prompt = [
        Content.multi([
          TextPart('Describe what is in this image concisely for a blind person.'),
          InlineDataPart('image/jpeg', bytes),
        ])
      ];

      setState(() => _lastSpeech = "Analyzing image...");

      // 3. Generate content
      final response = await model.generateContent(prompt);
      final text = response.text;

      if (text != null) {
        setState(() => _lastSpeech = text);
        print("===> Gemini Response: $text");
      } else {
        setState(() => _lastSpeech = "Could not describe the image.");
      }
    } catch (e) {
      debugPrint("Test Gemini Error: $e");
      setState(() => _lastSpeech = "Error: $e");
    }
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
    // Triggering the vision test
    await _testGemini();

    // Original live logic commented out
    /*
    if (_isAiming) {
      _stopAiming();
    } else {
      _startAiming();
    }
    */
  }

  void _startAiming() async {
    try {
      setState(() {
        _isAiming = true;
        _lastSpeech = "Aim is starting...";
      });

      await _liveRepository.startAim();

      _cameraService.startImageStream((frame) {
        _liveRepository.sendVisionFrame(frame);
      });

      setState(() => _lastSpeech = "Aim is listening and watching.");
    } catch (e) {
      _stopAiming();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to start Aim: $e")));
      }
    }
  }

  void _stopAiming() {
    _cameraService.stopImageStream();
    _liveRepository.stopAim();
    setState(() {
      _isAiming = false;
      _lastSpeech = "Aim stopped. Tap to restart.";
    });
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _liveRepository.stopAim();
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
      body: Stack(
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
                    _isAiming ? "START AIM" : "START AIM",
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
    );
  }
}
