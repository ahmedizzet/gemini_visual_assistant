import 'dart:async';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';

class LiveAssistantRepository {
  late final LiveGenerativeModel _model;
  LiveSession? _session;
  StreamSubscription? _subscription;

  final Function(bool) onInterrupted;
  final Function(String) onSpeechReceived;

  LiveAssistantRepository({
    required this.onInterrupted,
    required this.onSpeechReceived,
  }) {

    // _model = FirebaseAI.googleAI().liveGenerativeModel(
    //   model: ApiConstants.geminiModel,
    //   liveGenerationConfig: LiveGenerationConfig(
    //     responseModalities: [ResponseModalities.audio],
    //     speechConfig: SpeechConfig(voiceName: ApiConstants.voiceName),
    //   ),
    //   systemInstruction: Content.system(
    //     "You are 'Aim', a real-time visual guide for the blind. Proactively describe obstacles, doorways, and people concisely (e.g., 'Curb ahead'). If the user speaks, STOP your audio immediately. You are a listener first.",
    //   ),
    // );
  }

  Future<void> startAim() async {
    try {
      _session = await _model.connect();
      print("Connected to Aim");



      // _subscription = _session?.receive().listen(
      //   (response) {
      //     final message = response.message;
      //
      //     // Handle Interruption (Barge-in Logic)
      //     if (message is LiveServerContent && message.interrupted == true) {
      //       onInterrupted(true);
      //     }
      //
      //     // Extract text if the model provides text chunks alongside audio
      //     if (message is LiveServerContent && message.modelTurn != null) {
      //       final text = message.modelTurn!.parts
      //           .whereType<TextPart>()
      //           .map((p) => p.text)
      //           .join();
      //
      //       if (text.isNotEmpty) {
      //         onSpeechReceived(text);
      //       }
      //     }
      //   },
      //   onError: (error) {
      //     debugPrint("Live Session Error: $error");
      //     stopAim();
      //   },
      //   onDone: () {
      //     debugPrint("Live Session Closed");
      //     stopAim();
      //   },
      // );

      // No startAudioConversation() in this version.
      // Modality AUDIO triggers automatic bidirectional audio if configured.
    } catch (e) {
      debugPrint("Failed to start Aim: $e");
      rethrow;
    }
  }

  void sendVisionFrame(Uint8List jpegBytes) {
    if (_session == null) return;

    try {
      // Use the correct sendVideoRealtime method for continuous frames
      _session?.sendVideoRealtime(InlineDataPart('image/jpeg', jpegBytes));
    } catch (e) {
      debugPrint("Error sending vision frame: $e");
    }
  }

  void stopAim() {
    _subscription?.cancel();
    _subscription = null;
    _session?.close(); // Gracefully disconnect the WebSocket
    _session = null;
  }
}
