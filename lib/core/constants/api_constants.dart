class ApiConstants {
  // Use the native audio preview model for the best 'Live' experience in 2026
  static const String geminiModel =
      'gemini-2.5-flash-native-audio-preview';

  // Voice Options for Aim:
  // 'Kore' (Clear, helpful - best for accessibility)
  // 'Puck' (Energetic, default)
  // 'Charon' (Gentle, low-pitched)
  static const String voiceName = 'Kore';
  static const int frameIntervalMs = 1000;

  // Vision Settings
  static const double frameRate = 0.333; // 1 Frame every 3 seconds
  static const double imageQuality = 30.0; // JPEG quality (0-100)
}
