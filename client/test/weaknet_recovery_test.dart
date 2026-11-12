/// Purpose: Live Toxiproxy weak-network reliability tests against ActivePresenceView, TodayFeedView, and PresenceService.
/// Data & Logic Flow: Mutates Toxiproxy fault profiles (stalled socket latency, full outage, slow jittery 3G) and verifies the app never hangs permanently on a spinner and recovers automatically once the network stabilizes.
/// Key Components: weaknet_recovery_test
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:simkuliah_client/core/refresh_bus.dart';
import 'package:simkuliah_client/services/backend_health_service.dart';
import 'package:simkuliah_client/services/presence_service.dart';
import 'package:simkuliah_client/views/active_presence_view.dart';
import 'package:simkuliah_client/views/semester_matrix_view.dart';
import 'package:simkuliah_client/views/today_feed_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _proxyUrl = String.fromEnvironment('WEAKNET_PROXY_URL');
const String _ctrlUrl = String.fromEnvironment('WEAKNET_CTRL_URL');
const bool _hasWeaknetEnv = _proxyUrl != '' && _ctrlUrl != '';

Future<void> _setProxyEnabled(bool enabled) async {
  final res = await http.post(
    Uri.parse('$_ctrlUrl/proxies/supabase_rest'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'enabled': enabled}),
  );
  if (res.statusCode >= 300) {
    throw StateError('Failed to toggle proxy: ${res.statusCode} ${res.body}');
  }
}

Future<void> _addToxic(
  String name,
  String type,
  Map<String, dynamic> attributes,
) async {
  final res = await http.post(
    Uri.parse('$_ctrlUrl/proxies/supabase_rest/toxics'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': name,
      'type': type,
      'stream': 'downstream',
      'toxicity': 1.0,
      'attributes': attributes,
    }),
  );
  if (res.statusCode >= 300) {
    throw StateError(
      'Failed to add toxic $name: ${res.statusCode} ${res.body}',
    );
  }
}

Future<void> _removeToxic(String name) async {
  await http.delete(Uri.parse('$_ctrlUrl/proxies/supabase_rest/toxics/$name'));
}

Future<void> _resetProxy() async {
  await _setProxyEnabled(true);
  final res = await http.get(Uri.parse('$_ctrlUrl/proxies/supabase_rest'));
  if (res.statusCode == 200) {
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final toxics = (data['toxics'] as List<dynamic>?) ?? const [];
    for (final t in toxics) {
      final name = (t as Map<String, dynamic>)['name'] as String;
      await _removeToxic(name);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_hasWeaknetEnv) {
    // Allow real loopback HTTP traffic to Toxiproxy instead of Flutter's
    // test-binding HTTP 400 stub.
    HttpOverrides.global = null;
  }

  group('Weak-network Toxiproxy simulation', skip: _hasWeaknetEnv ? null : 'requires live Toxiproxy stack: pass --dart-define=WEAKNET_PROXY_URL/...', () {
    late SupabaseClient supabase;

    setUp(() async {
      supabase = SupabaseClient(_proxyUrl, 'dummy-anon-key');
      await _resetProxy();
    });

    tearDown(() async {
      await _resetProxy();
    });

    testWidgets(
      'stalled TCP socket does not lock ActivePresenceView spinner forever after network recovers',
      (tester) async {
        await tester.runAsync(() async {
          // Simulate a hung half-open TCP link (30s stall).
          await _addToxic('stall', 'latency', {'latency': 30000});

          final presenceService = PresenceService(
            client: supabase,
            requestTimeout: const Duration(milliseconds: 600),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: ActivePresenceView(presenceService: presenceService),
            ),
          );
          await tester.pump();

          // Spinner starts while the hung request is in flight.
          expect(find.byType(CircularProgressIndicator), findsOneWidget);

          // Network recovers while the first request was stalled.
          await _removeToxic('stall');

          // User triggers a refresh (switching tabs / focus / retry).
          RefreshBus.instance.requestRefresh();

          // Wait up to 3 seconds for recovery instead of getting trapped
          // forever on the first hung socket.
          var recovered = false;
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              recovered = true;
              break;
            }
          }

          expect(
            recovered,
            isTrue,
            reason: 'View stayed permanently stuck on CircularProgressIndicator after network recovered',
          );
        });
      },
    );

    testWidgets(
      'outage transitions to ErrorStateView within timeout and recovers cleanly on retry',
      (tester) async {
        await tester.runAsync(() async {
          await _setProxyEnabled(false);

          final presenceService = PresenceService(
            client: supabase,
            requestTimeout: const Duration(milliseconds: 500),
          );
          final healthService = BackendHealthService(baseUrl: _proxyUrl);

          await tester.pumpWidget(
            MaterialApp(
              home: TodayFeedView(
                presenceService: presenceService,
                backendHealthService: healthService,
              ),
            ),
          );
          await tester.pump();

          var sawError = false;
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find.text('Coba Lagi').evaluate().isNotEmpty) {
              sawError = true;
              break;
            }
          }
          expect(sawError, isTrue);

          // Restore link and retry.
          await _setProxyEnabled(true);
          await tester.tap(find.text('Coba Lagi'));
          await tester.pump();

          var loadedCourse = false;
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find
                .textContaining('KECERDASAN ARTIFISIAL')
                .evaluate()
                .isNotEmpty) {
              loadedCourse = true;
              break;
            }
          }
          expect(loadedCourse, isTrue);
        });
      },
    );

    testWidgets(
      'slow jittery 3G completes load on SemesterMatrixView without spurious failure',
      (tester) async {
        await tester.runAsync(() async {
          await _addToxic('slow_3g', 'latency', {
            'latency': 400,
            'jitter': 150,
          });

          final presenceService = PresenceService(
            client: supabase,
            requestTimeout: const Duration(seconds: 3),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: SemesterMatrixView(presenceService: presenceService),
            ),
          );
          await tester.pump();

          var loadedMatrix = false;
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find
                .textContaining('KECERDASAN ARTIFISIAL')
                .evaluate()
                .isNotEmpty) {
              loadedMatrix = true;
              break;
            }
          }
          expect(loadedMatrix, isTrue);
        });
      },
    );

    testWidgets(
      'mid-stream TCP timeout cut recovers automatically once toxic is removed',
      (tester) async {
        await tester.runAsync(() async {
          await _addToxic('cut', 'timeout', {'timeout': 50});

          final presenceService = PresenceService(
            client: supabase,
            requestTimeout: const Duration(milliseconds: 600),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: ActivePresenceView(presenceService: presenceService),
            ),
          );
          await tester.pump();

          var sawError = false;
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find.text('Coba Lagi').evaluate().isNotEmpty) {
              sawError = true;
              break;
            }
          }
          expect(sawError, isTrue);

          await _removeToxic('cut');
          RefreshBus.instance.requestRefresh();

          var recovered = false;
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find.text('Coba Lagi').evaluate().isEmpty &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              recovered = true;
              break;
            }
          }
          expect(recovered, isTrue);
        });
      },
    );
  });
}
