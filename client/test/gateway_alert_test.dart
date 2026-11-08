import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/gateway_alert_banner.dart';

void main() {
  testWidgets('GatewayAlertBanner displays warning when server has outage', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: GatewayAlertBanner(hasOutage: true, errorMessage: 'Gateway Timeout (504)'),
      ),
    ));

    expect(find.textContaining('Gateway Timeout (504)'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
