import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simkuliah_client/services/device_service.dart';

void main() {
  const backendUrl = 'https://simkuliah-backend.example.com';

  test('registerDeviceToken posts to the backend devices endpoint', () async {
    Uri? capturedUri;
    Map<String, dynamic>? capturedBody;
    final mockClient = MockClient((request) async {
      capturedUri = request.url;
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'code': 200, 'message': 'Device registered successfully'}),
        200,
      );
    });

    final service = DeviceService(client: mockClient, baseUrl: backendUrl);
    final ok = await service.registerDeviceToken('fcm-token-1');

    expect(ok, isTrue);
    expect(capturedUri.toString(), '$backendUrl/api/v1/devices/register');
    expect(capturedBody, {'token': 'fcm-token-1', 'platform': 'android'});
  });

  test(
    'unregisterDeviceToken posts to the backend unregister endpoint',
    () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('{}', 200);
      });

      final service = DeviceService(client: mockClient, baseUrl: backendUrl);
      final ok = await service.unregisterDeviceToken('fcm-token-1');

      expect(ok, isTrue);
      expect(capturedUri.toString(), '$backendUrl/api/v1/devices/unregister');
    },
  );

  test(
    'submitActionToken posts the signed webhook with action header',
    () async {
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'status': 'success'}), 200);
      });

      final service = DeviceService(client: mockClient, baseUrl: backendUrl);
      final ok = await service.submitActionToken(
        action: 'mark_override',
        token: 'signed-token',
      );

      expect(ok, isTrue);
      expect(capturedHeaders!['X-Action-Token'], 'signed-token');
      expect(capturedBody, {'action': 'mark_override'});
    },
  );

  test('registerDeviceToken reports failure on HTTP error', () async {
    final mockClient = MockClient((request) async {
      return http.Response('server error', 500);
    });

    final service = DeviceService(client: mockClient, baseUrl: backendUrl);
    final ok = await service.registerDeviceToken('fcm-token-1');

    expect(ok, isFalse);
  });

  test(
    'registerDeviceToken skips when backend URL is not configured',
    () async {
      var called = false;
      final mockClient = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });

      final service = DeviceService(client: mockClient, baseUrl: '');
      final ok = await service.registerDeviceToken('fcm-token-1');

      expect(ok, isFalse);
      expect(called, isFalse);
    },
  );
}
