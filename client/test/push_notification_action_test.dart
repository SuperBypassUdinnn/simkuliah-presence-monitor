// client/test/push_notification_action_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/services/push_notification_service.dart';

void main() {
  test('AndroidManifest.xml contains ActionBroadcastReceiver registration', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    expect(manifestFile.existsSync(), isTrue);
    final content = manifestFile.readAsStringSync();
    expect(
      content.contains(
        'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver',
      ),
      isTrue,
      reason:
          'ActionBroadcastReceiver must be registered in AndroidManifest.xml',
    );
  });

  test('FcmActionEncoder decodes action token payload correctly', () {
    final encoded = FcmActionEncoder.encodeActionId(
      action: 'confirm_presence',
      token: 'test_token_123',
    );
    final decoded = FcmActionEncoder.decodeActionId(encoded);
    expect(decoded?.action, 'confirm_presence');
    expect(decoded?.token, 'test_token_123');
  });
}
