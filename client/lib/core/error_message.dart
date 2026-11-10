/// Purpose: Maps low-level network and data exceptions to clean Indonesian user-facing messages.
/// Data & Logic Flow: Inspects the runtime type, errno, and message text of a thrown error, classifies it into a small set of failure buckets, and returns the matching user-facing message; the raw error stays available via [errorDetail] for logs and the debug detail expando.
/// Key Components: friendlyErrorMessage, errorDetail
import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// No internet connectivity or the host could not be resolved.
const String _offlineMessage =
    'Tidak ada koneksi internet. Periksa jaringan Anda, lalu coba lagi.';

/// The host resolved but the TCP connection could not be established or was
/// dropped mid-request.
const String _serverUnreachableMessage =
    'Server tidak dapat dihubungi. Periksa koneksi internet Anda, lalu coba lagi.';

/// The request gave up before the server answered.
const String _timeoutMessage =
    'Koneksi ke server lambat atau terputus. Coba lagi beberapa saat.';

/// The server answered with a failure (5xx, gateway outage, database error).
const String _serverErrorMessage =
    'Server sedang bermasalah atau sibuk. Coba lagi beberapa saat lagi.';

/// The server rejected the request's credentials or authorization.
const String _authMessage =
    'Akses ke server ditolak. Coba muat ulang aplikasi; jika berlanjut, hubungi pengembang.';

/// The response body could not be understood.
const String _dataInvalidMessage =
    'Data yang diterima dari server tidak valid. Coba lagi; jika berlanjut, hubungi pengembang.';

/// Anything else.
const String _unexpectedMessage =
    'Terjadi kesalahan yang tidak terduga. Coba lagi.';

/// Returns a short, actionable Indonesian message for [error].
///
/// UI surfaces must show this instead of `error.toString()`, which leaks
/// socket errnos, host names, and query strings (e.g. the raw
/// "ClientException with SocketException: Connection failed (OS Error:
/// Network is unreachable, errno = 101)..." blob).
String friendlyErrorMessage(Object error) {
  if (error is TimeoutException) {
    return _timeoutMessage;
  }
  if (error is PostgrestException) {
    // Database-level rejections (4xx constraint errors or 5xx failures) are
    // server-side processing failures from the user's point of view.
    return _serverErrorMessage;
  }
  if (error is AuthException) {
    return _authMessage;
  }
  if (error is SocketException) {
    final message = _socketMessage(error);
    if (message != null) {
      return message;
    }
  }
  if (error is FormatException) {
    return _dataInvalidMessage;
  }

  // Wrapped exceptions (e.g. http's ClientException carrying a
  // SocketException) are classified by their combined text.
  final text = error.toString().toLowerCase();
  if (_containsAny(text, const ['timed out', 'timeout', 'timeoutexception'])) {
    return _timeoutMessage;
  }
  if (_containsAny(text, const [
    'network is unreachable',
    'no route to host',
    'failed host lookup',
    'no address associated with hostname',
    'errno = 101',
    'errno = 113',
    'errno = -2',
  ])) {
    return _offlineMessage;
  }
  if (_containsAny(text, const [
    'connection refused',
    'connection reset',
    'connection closed',
    'connection aborted',
    'connection terminated',
    'broken pipe',
    'errno = 111',
    'errno = 104',
    'errno = 103',
  ])) {
    return _serverUnreachableMessage;
  }
  if (_containsAny(text, const [
    'internal server error',
    'service unavailable',
    'bad gateway',
    'gateway timeout',
  ])) {
    return _serverErrorMessage;
  }
  return _unexpectedMessage;
}

/// Raw technical representation of [error], for logs and the expandable
/// "Detail teknis" section; never shown as the primary message.
String errorDetail(Object error) => error.toString();

/// Classifies a [SocketException] by its errno, falling back to `null` so the
/// caller can retry with text matching.
String? _socketMessage(SocketException error) {
  final code = error.osError?.errorCode;
  // Linux errno values as seen on Android/desktop:
  // 101 ENETUNREACH, 113 EHOSTUNREACH, -2 EAI_NONAME (DNS),
  // 110 ETIMEDOUT, 111 ECONNREFUSED, 104 ECONNRESET, 103 ECONNABORTED,
  // 32 EPIPE.
  if (code == 101 || code == 113 || code == -2) {
    return _offlineMessage;
  }
  if (code == 110) {
    return _timeoutMessage;
  }
  if (code == 111 || code == 104 || code == 103 || code == 32) {
    return _serverUnreachableMessage;
  }
  return null;
}

bool _containsAny(String text, List<String> needles) {
  for (final needle in needles) {
    if (text.contains(needle)) {
      return true;
    }
  }
  return false;
}
