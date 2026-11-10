import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:simkuliah_client/core/error_message.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('no internet (the reported screenshot case)', () {
      // http wraps the raw SocketException; the UI used to print this blob.
      final error = http.ClientException(
        'SocketException: Connection failed (OS Error: Network is unreachable,'
        ' errno = 101), address = ftznonanlbshweysliar.supabase.co, port = 443',
      );
      expect(
        friendlyErrorMessage(error),
        'Tidak ada koneksi internet. Periksa jaringan Anda, lalu coba lagi.',
      );
    });

    test('DNS lookup failure maps to no internet', () {
      final error = const SocketException('Failed host lookup');
      expect(
        friendlyErrorMessage(error),
        'Tidak ada koneksi internet. Periksa jaringan Anda, lalu coba lagi.',
      );
    });

    test('errno 101 maps to no internet', () {
      final error = SocketException(
        'Connection failed',
        osError: OSError('Network is unreachable', 101),
      );
      expect(
        friendlyErrorMessage(error),
        'Tidak ada koneksi internet. Periksa jaringan Anda, lalu coba lagi.',
      );
    });

    test('connection refused maps to server unreachable', () {
      final error = SocketException(
        'Connection refused',
        osError: OSError('Connection refused', 111),
      );
      expect(
        friendlyErrorMessage(error),
        'Server tidak dapat dihubungi. Periksa koneksi internet Anda, lalu coba lagi.',
      );
    });

    test('errno 110 maps to timeout', () {
      final error = SocketException(
        'Connection timed out',
        osError: OSError('Connection timed out', 110),
      );
      expect(
        friendlyErrorMessage(error),
        'Koneksi ke server lambat atau terputus. Coba lagi beberapa saat.',
      );
    });

    test('TimeoutException maps to timeout', () {
      expect(
        friendlyErrorMessage(TimeoutException('operation timed out')),
        'Koneksi ke server lambat atau terputus. Coba lagi beberapa saat.',
      );
    });

    test('PostgrestException maps to server error', () {
      final error = const PostgrestException(
        message: 'internal server error',
        code: '500',
      );
      expect(
        friendlyErrorMessage(error),
        'Server sedang bermasalah atau sibuk. Coba lagi beberapa saat lagi.',
      );
    });

    test('auth rejection maps to auth message', () {
      final error = AuthApiException('Invalid API key', statusCode: '401');
      expect(
        friendlyErrorMessage(error),
        'Akses ke server ditolak. Coba muat ulang aplikasi; jika berlanjut, hubungi pengembang.',
      );
    });

    test('FormatException maps to invalid data', () {
      expect(
        friendlyErrorMessage(const FormatException('bad json')),
        'Data yang diterima dari server tidak valid. Coba lagi; jika berlanjut, hubungi pengembang.',
      );
    });

    test('unknown errors map to the generic message', () {
      expect(
        friendlyErrorMessage(StateError('boom')),
        'Terjadi kesalahan yang tidak terduga. Coba lagi.',
      );
    });
  });

  test('errorDetail keeps the raw representation for diagnosis', () {
    final error = const SocketException(
      'Connection failed',
      osError: OSError('Network is unreachable', 101),
    );
    expect(errorDetail(error), error.toString());
  });
}
