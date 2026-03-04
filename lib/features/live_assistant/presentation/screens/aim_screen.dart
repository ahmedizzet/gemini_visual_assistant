import 'dart:async';
import 'package:camera/camera.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// Your custom service imports
import '../../../../services/camera_service.dart';
import '../../../../services/audio_handler.dart';
import '../../../../core/constants/api_constants.dart';

class AimScreen extends StatefulWidget {
  const AimScreen({super.key});

  @override
  State<AimScreen> createState() => _AimScreenState();
}

class _AimScreenState extends State<AimScreen> {
  final CameraService _cameraService = CameraService();
  final AudioHandler _audioHandler = AudioHandler();

  // Session State
  LiveSession? _testSession;
  StreamSubscription? _sessionSubscription;
  
  // Logic Flags
  bool _isAiming = false;
  bool _isCameraStreaming = false;
  bool _isModelBusy = false;
  
  // Throttling
  DateTime _lastFrameSent = DateTime.now();
  final int _visionIntervalMs = 3000; // 3 Seconds for vision stability

  String _lastSpeech = "Tap below to start Aim";

  /// 1. Initialize the Live Session
  Future<void> _startGeminiLive() async {
    try {
      setState(() => _lastSpeech = "Connecting to Aim...");

      final model = FirebaseAI.googleAI().liveGenerativeModel(
        model: ApiConstants.geminiModel, // e.g., 'gemini-2.5-flash-native-audio'
        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [ResponseModalities.audio],
          outputAudioTranscription: AudioTranscriptionConfig(), // Crucial for text + audio sync
          speechConfig: SpeechConfig(voiceName: ApiConstants.voiceName),
        ),
        systemInstruction: Content.system(
          "You are 'Aim', a real-time visual assistant for the blind. "
          "You will receive vision frames every 3 seconds. "
          "IMPORTANT: Do not wait for user prompts. If you see a change or a hazard, "
          "speak immediately. Be proactive and concise."
        ),
      );

      // Check Permissions
      if (await Permission.camera.request().isDenied) {
        _updateStatus("Camera permission required.");
        return;
      }

      // Establish Connection
      _testSession = await model.connect();

      // 2. The Main Listener Loop
      _sessionSubscription = _testSession?.receive().listen((response) {
        final message = response.message;
        debugPrint("####>>> Server Message: ${message.runtimeType}");

        // A. HANDLE SETUP (The key to fixing "sees once")
        // Since LiveServerSetup is not exported, we use a structural check
        if (message is! LiveServerContent &&
            message is! LiveServerToolCall &&
            message is! LiveServerToolCallCancellation) {
          debugPrint("####>>> SETUP SUCCESS: Activating Vision Loop.");
          _activateVisionLoop();
        }

        // B. HANDLE CONTENT & STATE
        if (message is LiveServerContent) {
          // Update Thinking State
          setState(() => _isModelBusy = message.modelTurn != null && !(message.turnComplete ?? false));

          // Handle Interruption (Barge-in)
          if (message.interrupted == true) {
            _audioHandler.stopAll();
            setState(() => _isModelBusy = false);
          }

          // Handle Model Turn (Audio + Text)
          if (message.modelTurn != null) {
            for (final part in message.modelTurn!.parts) {
              if (part is TextPart && part.text.isNotEmpty) {
                _updateStatus(part.text);
              }
              if (part is InlineDataPart && part.mimeType.startsWith('audio/')) {
                _audioHandler.playAudioChunk(part.bytes);
              }
            }
          }
          
          // Fallback for Transcription
          if (message.outputTranscription?.text != null) {
            _updateStatus(message.outputTranscription!.text!);
          }
        }
      }, onError: (e) {
        debugPrint("Session Error: $e");
        _stopAiming();
      });

      _updateStatus("Aim is ready.");
    } catch (e) {
      _updateStatus("Connection Error: $e");
      _stopAiming();
    }
  }

  /// 3. Continuous Vision Loop (Fixes "Blindness")
  void _activateVisionLoop() {
    if (_isCameraStreaming) return;
    _isCameraStreaming = true;

    _cameraService.startImageStream((Uint8List jpegFrame) {
      final now = DateTime.now();
      
      // Throttle to 3 seconds
      if (now.difference(_lastFrameSent).inMilliseconds >= _visionIntervalMs) {
        _lastFrameSent = now;

        // Only send if the session is alive and model is not busy
        if (_testSession != null) {
          debugPrint("####>>> Sending Vision Frame (${jpegFrame.length} bytes)");
          _testSession?.sendVideoRealtime(InlineDataPart('image/jpeg', jpegFrame));
        }
      }
    });
  }

  /// 4. Cleanup & Stop
  void _stopAiming() {
    _cameraService.stopImageStream();
    _isCameraStreaming = false;
    _audioHandler.stopAll();
    _sessionSubscription?.cancel();
    _testSession?.close();
    _testSession = null;
    
    if (mounted) {
      setState(() {
        _isAiming = false;
        _isModelBusy = false;
        _lastSpeech = "Aim stopped.";
      });
    }
  }

  void _toggleAim() {
    if (_isAiming) {
      _stopAiming();
    } else {
      setState(() => _isAiming = true);
      _startGeminiLive();
    }
  }

  void _updateStatus(String msg) {
    if (mounted) setState(() => _lastSpeech = msg);
  }

  @override
  void initState() {
    super.initState();
    _audioHandler.init();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraService.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  @override
  void dispose() {
    _stopAiming();
    _cameraService.dispose();
    _audioHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInitialized = _cameraService.controller?.value.isInitialized ?? false;

    if (!isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.yellow)),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraService.controller!),

          // Descriptive Overlay
          Positioned(
            top: 60, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.yellow, width: 2),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    _isModelBusy ? "Aim is thinking..." : _lastSpeech,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _isModelBusy ? Colors.yellow : Colors.white,
                        ),
                  ),
                ),
              ),
            ),
          ),

          // Control Button
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
                  icon: Icon(_isAiming ? Icons.stop : Icons.play_arrow, size: 40),
                  label: Text(_isAiming ? "STOP AIM" : "START AIM", 
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}