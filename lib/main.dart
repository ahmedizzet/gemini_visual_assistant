import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/accessibility_theme.dart';
import 'features/live_assistant/presentation/screens/aim_screen.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation for simplicity in this vision agent
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize Firebase (Mandatory for firebase_ai)
  await FirebaseService.initialize();

  runApp(const AimApp());
}

class AimApp extends StatelessWidget {
  const AimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aim: Visual Guide',
      debugShowCheckedModeBanner: false,
      theme: AccessibilityTheme.highContrastTheme,
      home: const AimScreen(),
    );
  }
}
