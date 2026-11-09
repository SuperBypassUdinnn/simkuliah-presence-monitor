/// Purpose: Firebase initialization for native FCM push on Android and iOS.
/// Data & Logic Flow: Reads Firebase project values from --dart-define and initializes the Firebase app only on supported, configured platforms.
/// Key Components: FirebaseConfig
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Initializes Firebase from compile-time values so a missing configuration
/// degrades to a safe no-op instead of crashing desktop or test builds.
class FirebaseConfig {
  FirebaseConfig._();

  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
  );
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  /// True when every value required to reach the Firebase project is present.
  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  /// FCM is only implemented for Android and iOS.
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Initialize Firebase when running on a supported platform with values
  /// present. Safe no-op on desktop, web, tests, and unconfigured builds.
  static Future<void> initialize() async {
    if (!isSupportedPlatform || !isConfigured) {
      debugPrint(
        'Firebase push skipped (unsupported platform or unset config)',
      );
      return;
    }
    if (Firebase.apps.isNotEmpty) {
      return;
    }
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        storageBucket: storageBucket,
      ),
    );
  }
}
