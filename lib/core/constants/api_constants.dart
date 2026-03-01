class ApiConstants {
  // Use the native audio preview model for the best 'Live' experience in 2026
  static const String geminiModel =
      'gemini-2.5-flash-native-audio-preview-12-2025';

  // Voice Options for Aim:
  // 'Kore' (Clear, helpful - best for accessibility)
  // 'Puck' (Energetic, default)
  // 'Charon' (Gentle, low-pitched)
  static const String voiceName = 'Kore';

  // Vision Settings
  static const int frameRate = 1; // 1 Frame Per Second is the API standard
  static const double imageQuality = 50.0; // JPEG quality (0-100)
}
