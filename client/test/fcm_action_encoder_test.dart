import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/services/push_notification_service.dart';

void main() {
  const actionsJson =
      '[{"label":"Presensi Sekarang","action":"confirm_presence","token":"tok-a"},'
      '{"label":"Izin","action":"mark_override","token":"tok-b"}]';

  test('FcmActionEncoder.parse decodes signed action buttons', () {
    final actions = FcmActionEncoder.parse(actionsJson);

    expect(actions, hasLength(2));
    expect(actions[0].label, 'Presensi Sekarang');
    expect(actions[0].action, 'confirm_presence');
    expect(actions[0].token, 'tok-a');
    expect(actions[1].action, 'mark_override');
  });

  test('FcmActionEncoder.parse returns empty on invalid JSON', () {
    expect(FcmActionEncoder.parse('not-json'), isEmpty);
    expect(FcmActionEncoder.parse(null), isEmpty);
  });

  test('toAndroidActions builds action buttons with encoded ids', () {
    final actions = FcmActionEncoder.toAndroidActions(
      FcmActionEncoder.parse(actionsJson),
    );

    expect(actions, hasLength(2));
    expect(actions[0].id, 'confirm_presence|tok-a');
    expect(actions[0].title, 'Presensi Sekarang');
  });

  test('decodeActionId splits action and token', () {
    final decoded = FcmActionEncoder.decodeActionId('mark_override|tok-b');

    expect(decoded, isNotNull);
    expect(decoded!.action, 'mark_override');
    expect(decoded.token, 'tok-b');

    expect(FcmActionEncoder.decodeActionId(null), isNull);
    expect(FcmActionEncoder.decodeActionId('no-separator'), isNull);
    expect(FcmActionEncoder.decodeActionId('|only-token'), isNull);
  });
}
