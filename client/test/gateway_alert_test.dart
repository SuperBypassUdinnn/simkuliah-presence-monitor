import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/widgets/gateway_alert_banner.dart';

void main() {
  testWidgets('GatewayAlertBanner displays warning when server has outage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GatewayAlertBanner(
            hasOutage: true,
            errorMessage: 'Gateway Timeout (504)',
          ),
        ),
      ),
    );

    expect(find.textContaining('Gateway Timeout (504)'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('GatewayAlertBanner renders nothing when there is no outage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GatewayAlertBanner(hasOutage: false)),
      ),
    );

    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.text('Gateway outage detected'), findsNothing);
    expect(find.textContaining('504'), findsNothing);
  });
}
