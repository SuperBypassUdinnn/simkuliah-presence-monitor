import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/core/firebase_config.dart';
import 'package:simkuliah_client/services/push_notification_service.dart';

void main() {
  test('FirebaseConfig is a safe no-op without dart-define values', () async {
    // Default test build has no FIREBASE_* dart-define values, so the config
    // is unconfigured and initialization must not throw.
    expect(FirebaseConfig.isConfigured, isFalse);
    await FirebaseConfig.initialize();
  });

  test(
    'PushNotificationService initializes as a no-op on unsupported hosts',
    () async {
      // The test host is not Android/iOS, so initialization completes without
      // touching any native plugin.
      await PushNotificationService.instance.initialize();
    },
  );
}
