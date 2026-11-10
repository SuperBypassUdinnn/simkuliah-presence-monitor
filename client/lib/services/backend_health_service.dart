/// Purpose: Probes the backend health endpoint to detect backend and Simkuliah upstream outages.
/// Data & Logic Flow: GETs /api/v1/health with a short timeout and one retry (Render cold start), classifies the response into ok / Simkuliah degraded / backend down, and returns a ready-to-display banner message.
/// Key Components: BackendHealthService, BackendHealthResult, BackendHealthStatus
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum BackendHealthStatus {
  /// Backend reachable and the Simkuliah poller is in sync.
  ok,

  /// Backend reachable but Simkuliah syncs are failing; data goes stale.
  simkuliahDegraded,

  /// Backend unreachable or failing; data goes stale.
  backendDown,
}

/// Outcome of one health probe: the status plus its banner message.
class BackendHealthResult {
  final BackendHealthStatus status;

  /// Clean Indonesian message for the gateway alert banner.
  final String message;

  const BackendHealthResult({required this.status, required this.message});
}

/// Probes the deployed backend's health endpoint.
class BackendHealthService {
  BackendHealthService({http.Client? client, String? baseUrl})
    : _customClient = client,
      _customBaseUrl = baseUrl;

  final http.Client? _customClient;

  /// Render cold starts can exceed the probe timeout; one retry before
  /// declaring the backend down keeps the banner honest.
  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _retryDelay = Duration(seconds: 2);

  final String? _customBaseUrl;

  /// Backend origin supplied at build time via --dart-define. Probing is
  /// skipped (always healthy) when it is not configured (e.g. desktop builds
  /// without a backend).
  static const String _envBaseUrl = String.fromEnvironment(
    'SIMKULIAH_API_BASE_URL',
  );

  String get _baseUrl => _customBaseUrl ?? _envBaseUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  /// Runs one health probe; never throws, failures become [BackendHealthStatus.backendDown].
  Future<BackendHealthResult> check() async {
    if (!isConfigured) {
      return const BackendHealthResult(
        status: BackendHealthStatus.ok,
        message: '',
      );
    }
    // The service may be probed once a minute for the app's whole session;
    // only clients created here are owned (and closed) by this call.
    final ownsClient = _customClient == null;
    final client = _customClient ?? http.Client();
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final response = await client
              .get(Uri.parse('$_baseUrl/api/v1/health'))
              .timeout(_timeout);
          if (response.statusCode >= 500) {
            return BackendHealthResult(
              status: BackendHealthStatus.backendDown,
              message: _backendDownMessage,
            );
          }
          if (response.statusCode != 200) {
            // Client errors (auth, routing) are backend misconfigurations the
            // user cannot fix by retrying; surface them the same way.
            return BackendHealthResult(
              status: BackendHealthStatus.backendDown,
              message: _backendDownMessage,
            );
          }
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          if (body['simkuliah_status'] == 'degraded') {
            return const BackendHealthResult(
              status: BackendHealthStatus.simkuliahDegraded,
              message: _simkuliahDegradedMessage,
            );
          }
          // 'ok' and 'pending' (fresh backend without a first tick) are both
          // healthy from the user's point of view; 'unknown' means the
          // backend could not tell us, which is not worth alarming about.
          return const BackendHealthResult(
            status: BackendHealthStatus.ok,
            message: '',
          );
        } on TimeoutException {
          // Fall through to the retry / final verdict.
        } on Exception {
          // Fall through to the retry / final verdict.
        }
        if (attempt == 1) {
          await Future<void>.delayed(_retryDelay);
        }
      }
      return BackendHealthResult(
        status: BackendHealthStatus.backendDown,
        message: _backendDownMessage,
      );
    } finally {
      if (ownsClient) {
        client.close();
      }
    }
  }
}

const String _simkuliahDegradedMessage =
    'Simkuliah sedang bermasalah - pembaruan status presensi tertunda. '
    'Data terakhir tetap ditampilkan.';

const String _backendDownMessage =
    'Server pemantau tidak dapat dihubungi - data mungkin tidak diperbarui. '
    'Periksa koneksi internet Anda, lalu coba lagi.';
