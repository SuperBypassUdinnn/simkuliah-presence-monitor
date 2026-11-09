import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/core/app_notification.dart';

void main() {
  setUp(() {
    AppNotification.reset();
  });

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

  testWidgets('sticky notifications have no auto-dismiss and close manually', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppNotification.show(
                context,
                title: 'Presensi Segera Ditutup',
                message: 'Kewirausahaan tutup dalam 5 menit.',
                color: Colors.red,
                duration: Duration.zero,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    // Far beyond any normal duration, the sticky banner remains.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Presensi Segera Ditutup'), findsOneWidget);

    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.text('Presensi Segera Ditutup'), findsNothing);
  });

  testWidgets('show returns an id and dismiss removes it programmatically', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                final id = AppNotification.show(
                  context,
                  title: 'Dosen Membuka Presensi',
                  message: 'Segera konfirmasi kehadiran Anda.',
                  color: Colors.red,
                  duration: Duration.zero,
                );
                // Programmatic removal (e.g. the meeting resolved).
                AppNotification.dismiss(id);
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Dosen Membuka Presensi'), findsNothing);
  });

  testWidgets('newer notifications stack below older ones', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => AppNotification.show(
                    context,
                    title: 'Notifikasi Pertama',
                    message: 'Pesan pertama.',
                    color: Colors.blue,
                    duration: const Duration(seconds: 2),
                  ),
                  child: const Text('First'),
                ),
                ElevatedButton(
                  onPressed: () => AppNotification.show(
                    context,
                    title: 'Notifikasi Kedua',
                    message: 'Pesan kedua.',
                    color: Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                  child: const Text('Second'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('First'));
    await tester.pump();
    await tester.tap(find.text('Second'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Notifikasi Pertama'), findsOneWidget);
    expect(find.text('Notifikasi Kedua'), findsOneWidget);

    // The newer notification must render below the older one.
    final firstTop = tester.getTopLeft(find.text('Notifikasi Pertama')).dy;
    final secondTop = tester.getTopLeft(find.text('Notifikasi Kedua')).dy;
    expect(secondTop, greaterThan(firstTop));

    // Both notifications eventually dismiss and clean up the overlay.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Notifikasi Pertama'), findsNothing);
    expect(find.text('Notifikasi Kedua'), findsNothing);
  });
}
