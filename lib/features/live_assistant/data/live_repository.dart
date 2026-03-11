import 'dart:async';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';

class LiveAssistantRepository {
  late final GenerativeModel _model;
  
  LiveAssistantRepository() {
    _model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3.1-flash-lite-preview',
    );
  }

  Future<String?> analyzeImage(Uint8List imageBytes) async {
    try {
      final prompt = [
        Content.multi([
          TextPart('''
          You are describing an image to a blind person who wants to quickly understand what is happening.

Rules:
- Be very brief (1 sentence maximum).
- Focus only on the main action or event.
- Mention only important objects or people.
- Give estimated distance of objects or people from the camera
- Do NOT describe colors, artistic style, or small details unless they are essential.
- Avoid long introductions or explanations.

Safety rule:
- If the image contains a possible danger (fire, traffic, sharp objects, falling risk, aggressive behavior, unsafe environment, etc.), clearly warn the user.
- Start the sentence with "Warning:" when danger exists.
- Don't offer extra support, your support is describe the event briefly.

Output format:
If safe:
[Main action]. [Important context if needed].

If dangerous:
Warning: [Short description of the danger]. [Main action or context].
              '''),
          InlineDataPart('image/jpeg', imageBytes),
        ]),
      ];

      final response = await _model.generateContent(prompt);
      return response.text;
    } catch (e) {
      debugPrint("LiveAssistantRepository analyzeImage Error: $e");
      rethrow;
    }
  }

  // Placeholder for real-time live session if needed in future
  void stopAim() {
    // Logic for stopping continuous sessions if any
  }
}
