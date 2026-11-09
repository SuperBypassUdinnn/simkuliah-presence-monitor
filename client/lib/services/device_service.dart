/// Purpose: Registers FCM device tokens with the backend push registry.
/// Data & Logic Flow: Posts the Firebase token to the backend /api/v1/devices endpoints when a backend base URL is configured.
/// Key Components: DeviceService
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Registers/unregisters this device's FCM token with the backend.
class DeviceService {
  DeviceService({http.Client? client, String? baseUrl})
    : _customClient = client,
      _customBaseUrl = baseUrl;

  final http.Client? _customClient;
  final String? _customBaseUrl;

  /// Backend origin supplied at build time via --dart-define. Registration is
  /// skipped silently when it is not configured (e.g. desktop builds).
  static const String _envBaseUrl = String.fromEnvironment(
    'SIMKULIAH_API_BASE_URL',
  );

  String get _baseUrl => _customBaseUrl ?? _envBaseUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  http.Client get _client => _customClient ?? http.Client();

  /// Register or refresh this device's push token. Idempotent server-side.
  Future<bool> registerDeviceToken(
    String token, {
    String platform = 'android',
  }) async {
    if (!isConfigured || token.isEmpty) {
      return false;
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/devices/register'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      // Registration is best-effort; the next app start or token refresh
      // retries without disturbing the user.
      return false;
    }
  }

  /// Remove this device's push token (e.g. on logout).
  Future<bool> unregisterDeviceToken(String token) async {
    if (!isConfigured || token.isEmpty) {
      return false;
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/devices/unregister'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Trigger the signed backend webhook (confirm presence / mark override).
  ///
  /// The HMAC token is the authorization; the body only carries the action
  /// kind while schedule/meeting identifiers travel inside the token.
  Future<bool> submitActionToken({
    required String action,
    required String token,
  }) async {
    if (!isConfigured || token.isEmpty) {
      return false;
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/webhook/action'),
            headers: {
              'Content-Type': 'application/json',
              'X-Action-Token': token,
            },
            body: jsonEncode({'action': action}),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
