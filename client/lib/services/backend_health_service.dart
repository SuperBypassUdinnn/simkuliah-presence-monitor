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

/// Outcome of one health probe: the status, its banner message, and whether
/// the backend executed a fresh Simkuliah sync during this request.
class BackendHealthResult {
  final BackendHealthStatus status;

  /// Clean Indonesian message for the gateway alert banner.
  final String message;

  final bool syncedNow;

  const BackendHealthResult({
    required this.status,
    required this.message,
    this.syncedNow = false,
  });
}

/// Probes the deployed backend's health endpoint.
class BackendHealthService {
  BackendHealthService({http.Client? client, String? baseUrl})
    : _customClient = client,
      _customBaseUrl = baseUrl;

  final http.Client? _customClient;

  /// Render cold starts plus an on-demand Simkuliah sync can exceed 8s;
  /// allow enough headroom before retrying or declaring the backend down.
  static const Duration _timeout = Duration(seconds: 20);
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

  /// Runs an interactive health probe; never throws, failures become
  /// [BackendHealthStatus.backendDown].
  ///
  /// Requests an on-demand sync (`?sync=true`) so opening or refreshing the
  /// client wakes a sleeping Render container / stale poller immediately.
  Future<BackendHealthResult> check() => _probe(sync: true);

  /// Lightweight keep-alive probe without forcing an upstream Simkuliah poll.
  Future<BackendHealthResult> keepAlive() => _probe(sync: false);

  Future<BackendHealthResult> _probe({required bool sync}) async {
    if (!isConfigured) {
      return const BackendHealthResult(
        status: BackendHealthStatus.ok,
        message: '',
      );
    }
    // The service may be probed periodically for the app's whole session;
    // only clients created here are owned (and closed) by this call.
    final ownsClient = _customClient == null;
    final client = _customClient ?? http.Client();
    final endpoint = sync
        ? '$_baseUrl/api/v1/health?sync=true'
        : '$_baseUrl/api/v1/health';
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final response = await client
              .get(Uri.parse(endpoint))
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
          final syncedNow = body['synced_now'] == true;
          if (body['simkuliah_status'] == 'degraded') {
            return BackendHealthResult(
              status: BackendHealthStatus.simkuliahDegraded,
              message: _simkuliahDegradedMessage,
              syncedNow: syncedNow,
            );
          }
          // 'ok' and 'pending' (fresh backend without a first tick) are both
          // healthy from the user's point of view; 'unknown' means the
          // backend could not tell us, which is not worth alarming about.
          return BackendHealthResult(
            status: BackendHealthStatus.ok,
            message: '',
            syncedNow: syncedNow,
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
    'Sinkronisasi ke Simkuliah tertunda - status presensi mungkin tidak '
    'terbaru. Data terakhir tetap ditampilkan.';

const String _backendDownMessage =
    'Server pemantau tidak dapat dihubungi - data mungkin tidak diperbarui. '
    'Periksa koneksi internet Anda, lalu coba lagi.';
