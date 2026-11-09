import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/core/app_notification.dart';

void main() {
  testWidgets('AppNotification shows and auto-dismisses a status message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppNotification.show(
                context,
                title: 'Keterangan Disimpan',
                message: 'Kewirausahaan ditandai sebagai Alpa.',
                color: Colors.red,
                duration: const Duration(seconds: 2),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Keterangan Disimpan'), findsOneWidget);
    expect(find.text('Kewirausahaan ditandai sebagai Alpa.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Keterangan Disimpan'), findsNothing);
  });
}
