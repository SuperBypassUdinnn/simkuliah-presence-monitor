import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simkuliah_client/services/backend_health_service.dart';

http.Client _clientWith(List<http.Response> responses) {
  var index = 0;
  return MockClient((request) async {
    if (index >= responses.length) {
      throw http.ClientException('no more canned responses');
    }
    return responses[index++];
  });
}

http.Client _throwingClient({int failures = 99}) {
  var remaining = failures;
  return MockClient((request) async {
    if (remaining-- > 0) {
      throw http.ClientException(
        'SocketException: Connection failed (OS Error: Network is unreachable,'
        ' errno = 101)',
      );
    }
    return http.Response('{"status":"ok","simkuliah_status":"ok"}', 200);
  });
}

void main() {
  test('healthy backend with in-sync Simkuliah reports ok', () async {
    final service = BackendHealthService(
      client: _clientWith([
        http.Response('{"status":"ok","simkuliah_status":"ok"}', 200),
      ]),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.ok);
    expect(result.message, isEmpty);
  });

  test('pending poller (fresh backend) still reports ok', () async {
    final service = BackendHealthService(
      client: _clientWith([
        http.Response('{"status":"ok","simkuliah_status":"pending"}', 200),
      ]),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.ok);
  });

  test('degraded Simkuliah reports the stale-data banner', () async {
    final service = BackendHealthService(
      client: _clientWith([
        http.Response('{"status":"ok","simkuliah_status":"degraded"}', 200),
      ]),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.simkuliahDegraded);
    expect(result.message, contains('Simkuliah sedang bermasalah'));
  });

  test('server 5xx reports the backend down banner', () async {
    final service = BackendHealthService(
      client: _clientWith([http.Response('Service Unavailable', 502)]),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.backendDown);
    expect(result.message, contains('Server pemantau tidak dapat dihubungi'));
  });

  test('network failure retries once, then reports backend down', () async {
    // Two canned failures cover the initial probe and its single retry.
    final service = BackendHealthService(
      client: _throwingClient(failures: 2),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.backendDown);
  });

  test('network failure with recovery on the retry reports ok', () async {
    final service = BackendHealthService(
      client: _throwingClient(failures: 1),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.ok);
  });

  test('unconfigured base URL short-circuits to ok', () async {
    final service = BackendHealthService(
      client: _throwingClient(),
      baseUrl: '',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.ok);
  });

  test('probe never throws on a hard network error', () async {
    final service = BackendHealthService(
      client: MockClient((request) async {
        throw TimeoutException('timed out');
      }),
      baseUrl: 'https://backend.example',
    );

    final result = await service.check();

    expect(result.status, BackendHealthStatus.backendDown);
  });
}
