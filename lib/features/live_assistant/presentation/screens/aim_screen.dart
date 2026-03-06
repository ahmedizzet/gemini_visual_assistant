import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

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

  LiveSession? _session;
  StreamSubscription? _sessionSubscription;

  bool _isAiming = false;
  bool _isCameraStreaming = false;
  bool _isModelBusy = false;
  bool _sessionReady = false;

  final int _visionIntervalMs = 1000;
  DateTime _lastFrameSent = DateTime.fromMillisecondsSinceEpoch(0);

  String _lastSpeech = "Double tap to start Aim.";

  /// ----------------------------
  /// VIBRATION ALERT
  /// ----------------------------

  Future<void> _vibrateAlert() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 200, 100, 200]);
    }
  }

  /// ----------------------------
  /// START GEMINI SESSION
  /// ----------------------------

  Future<void> _startGeminiLive() async {

    try {

      _updateStatus("Connecting to Aim...");

      final model = FirebaseAI.googleAI().liveGenerativeModel(

        model: 'gemini-2.5-flash-native-audio-preview-12-2025',

        liveGenerationConfig: LiveGenerationConfig(
          responseModalities: [ResponseModalities.audio],
          outputAudioTranscription: AudioTranscriptionConfig(),
          speechConfig: SpeechConfig(
            voiceName: ApiConstants.voiceName,
          ),
        ),

        systemInstruction: Content.system(
            "You are Aim, a real-time navigation assistant for blind users. "
                "Speak very briefly. "
                "Prioritize hazards like cars, stairs, drops. "
                "Give short commands: STOP, STEP LEFT, STEP RIGHT."
        ),
      );

      /// CAMERA PERMISSION

      final permission = await Permission.camera.request();

      if (!permission.isGranted) {
        _updateStatus("Camera permission required.");
        return;
      }

      /// CONNECT

      _session = await model.connect();

      debugPrint("GEMINI SESSION CONNECTED");

      _sessionReady = true;

      /// SEND FIRST MESSAGE

      _sendInitialPrompt();

      /// START CAMERA STREAM

      _activateVisionLoop();

      /// LISTEN FOR RESPONSES

      _sessionSubscription = _session!.receive().listen(

            (response) {

          final message = response.message;

          debugPrint("===== GEMINI RESPONSE =====");
          debugPrint("TYPE: ${message.runtimeType}");

          /// SESSION READY MESSAGE
          if (message is LiveServerContent && message.modelTurn == null) {
            debugPrint("SESSION SETUP COMPLETE");
            return;
          }

          /// MAIN CONTENT
          if (message is LiveServerContent) {

            final busy =
                message.modelTurn != null && !(message.turnComplete ?? false);

            if (mounted) {
              setState(() => _isModelBusy = busy);
            }

            /// INTERRUPTED
            if (message.interrupted == true) {
              debugPrint("MODEL INTERRUPTED");
              _audioHandler.stopAll();
            }

            /// MODEL RESPONSE
            if (message.modelTurn != null) {

              for (final part in message.modelTurn!.parts) {

                /// TEXT
                if (part is TextPart && part.text.isNotEmpty) {
                  debugPrint("AI TEXT: ${part.text}");
                  _handleSpeech(part.text);
                }

                /// AUDIO
                if (part is InlineDataPart &&
                    part.mimeType.startsWith('audio/')) {

                  debugPrint("AI AUDIO RECEIVED: ${part.bytes.length}");

                  _audioHandler.playAudioChunk(part.bytes);
                }
              }
            }

            /// FALLBACK TRANSCRIPTION
            if (message.outputTranscription?.text != null) {
              _handleSpeech(message.outputTranscription!.text!);
            }
          }
        },

        onError: (e) {
          debugPrint("SESSION ERROR: $e");
          _stopAiming();
        },
      );


      _updateStatus("Aim connected.");

    } catch (e) {

      debugPrint("Connection error: $e");

      _updateStatus("Connection failed.");

      _stopAiming();
    }
  }

  /// ----------------------------
  /// INITIAL PROMPT
  /// ----------------------------

  void _sendInitialPrompt() {

    _session?.send(

      input: Content.text(
          "You can see the camera. Describe obstacles for navigation."
      ),

      turnComplete: true,
    );

    debugPrint("INITIAL PROMPT SENT");
  }

  /// ----------------------------
  /// HANDLE SPEECH
  /// ----------------------------

  void _handleSpeech(String text) {

    _updateStatus(text);

    final dangerWords = [
      "stop",
      "danger",
      "car",
      "vehicle",
      "stairs",
      "drop",
      "hole"
    ];

    for (final word in dangerWords) {

      if (text.toLowerCase().contains(word)) {
        _vibrateAlert();
        break;
      }
    }
  }

  /// ----------------------------
  /// CAMERA STREAM
  /// ----------------------------

  void _activateVisionLoop() {

    if (_isCameraStreaming) return;

    _isCameraStreaming = true;

    _cameraService.startImageStream((Uint8List jpegFrame) {

      if (!_sessionReady) return;

      final now = DateTime.now();

      if (now.difference(_lastFrameSent).inMilliseconds >= _visionIntervalMs) {

        _lastFrameSent = now;

        if (_session != null && !_isModelBusy) {

          debugPrint("Sending frame: ${jpegFrame.length}");

          _session!.sendVideoRealtime(
            InlineDataPart('image/jpeg', jpegFrame),
          );
        }
      }
    });
  }

  /// ----------------------------
  /// STOP AIM
  /// ----------------------------

  void _stopAiming() {

    _cameraService.stopImageStream();
    _isCameraStreaming = false;

    _audioHandler.stopAll();

    _sessionSubscription?.cancel();
    _sessionSubscription = null;

    _session?.close();
    _session = null;

    _sessionReady = false;

    if (mounted) {
      setState(() {
        _isAiming = false;
        _isModelBusy = false;
        _lastSpeech = "Aim stopped.";
      });
    }
  }

  /// ----------------------------
  /// TOGGLE
  /// ----------------------------

  void _toggleAim() {

    if (_isAiming) {
      _stopAiming();
    } else {
      setState(() => _isAiming = true);
      _startGeminiLive();
    }
  }

  /// LONG PRESS = REPEAT LAST MESSAGE

  void _repeatLastSpeech() {
    _audioHandler.speak(_lastSpeech);
  }

  void _updateStatus(String msg) {

    if (mounted) {
      setState(() => _lastSpeech = msg);
    }
  }

  /// ----------------------------
  /// INIT
  /// ----------------------------

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
      debugPrint("Camera init error: $e");
    }
  }

  /// ----------------------------
  /// DISPOSE
  /// ----------------------------

  @override
  void dispose() {

    _stopAiming();
    _cameraService.dispose();
    _audioHandler.dispose();

    super.dispose();
  }

  /// ----------------------------
  /// UI
  /// ----------------------------

  @override
  Widget build(BuildContext context) {

    final isInitialized =
        _cameraService.controller?.value.isInitialized ?? false;

    if (!isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.yellow),
        ),
      );
    }

    return GestureDetector(

      onDoubleTap: _toggleAim,
      onLongPress: _repeatLastSpeech,

      child: Scaffold(

        body: Stack(

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
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellow, width: 2),
                ),

                child: Text(

                  _isModelBusy
                      ? "Aim is thinking..."
                      : _lastSpeech,

                  textAlign: TextAlign.center,

                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            ),

            Align(

              alignment: Alignment.bottomCenter,

              child: Padding(

                padding: const EdgeInsets.only(bottom: 50),

                child: SizedBox(

                  width: MediaQuery.of(context).size.width * 0.85,
                  height: 100,

                  child: FloatingActionButton.extended(

                    onPressed: _toggleAim,

                    backgroundColor:
                    _isAiming ? Colors.red : Colors.green,

                    icon: Icon(
                      _isAiming ? Icons.stop : Icons.play_arrow,
                      size: 40,
                    ),

                    label: Text(

                      _isAiming
                          ? "STOP AIM"
                          : "START AIM",

                      style: const TextStyle(
                        fontSize: 24,
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