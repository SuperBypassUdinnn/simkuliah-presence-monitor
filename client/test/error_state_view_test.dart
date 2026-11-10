import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:simkuliah_client/views/widgets/error_state_view.dart';

void main() {
  testWidgets('renders the friendly message instead of the raw error', (
    tester,
  ) async {
    // The exact error shape reported from the field: http's ClientException
    // carrying a SocketException with errno and the host name.
    final error = http.ClientException(
      'SocketException: Connection failed (OS Error: Network is unreachable,'
      ' errno = 101), address = ftznonanlbshweysliar.supabase.co, port = 443,'
      ' uri=https://ftznonanlbshweysliar.supabase.co/rest/v1/meetings?select=*',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorStateView(
            title: 'Gagal memuat status presensi',
            error: error,
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Gagal memuat status presensi'), findsOneWidget);
    expect(
      find.text(
        'Tidak ada koneksi internet. Periksa jaringan Anda, lalu coba lagi.',
      ),
      findsOneWidget,
    );
    // The raw blob stays out of sight until the user asks for it.
    expect(find.textContaining('errno = 101'), findsNothing);
    expect(find.textContaining('supabase.co'), findsNothing);
  });

  testWidgets('technical detail is opt-in and shows the raw error', (
    tester,
  ) async {
    final error = http.ClientException(
      'SocketException: Connection failed (OS Error: Network is unreachable,'
      ' errno = 101), address = ftznonanlbshweysliar.supabase.co, port = 443',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorStateView(
            title: 'Gagal memuat status presensi',
            error: error,
            onRetry: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Detail teknis'));
    await tester.pumpAndSettle();

    expect(find.text('Sembunyikan detail teknis'), findsOneWidget);
    expect(find.textContaining('errno = 101'), findsOneWidget);
  });

  testWidgets('retry button invokes the callback', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorStateView(
            title: 'Gagal memuat jadwal',
            error: const FormatException('bad'),
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Coba Lagi'));
    await tester.pump();

    expect(retried, isTrue);
    expect(
      find.text(
        'Data yang diterima dari server tidak valid. Coba lagi; jika berlanjut, hubungi pengembang.',
      ),
      findsOneWidget,
    );
  });
}
