/// Purpose: Shared full-screen error state for data-loading views, replacing duplicated icon-plus-raw-error bodies.
/// Data & Logic Flow: Renders an icon, the view's failure title, the friendly message from core/error_message for the underlying error, an optional retry action, and an expandable technical detail section for diagnosis.
/// Key Components: ErrorStateView
import 'package:flutter/material.dart';

import '../../core/error_message.dart';

/// Full-screen error state with a clean user-facing message.
///
/// [title] names what failed (e.g. "Gagal memuat jadwal"); [error] drives the
/// friendly message and the expandable technical detail. The raw error text
/// is never shown as the primary message - it leaks errnos, hosts, and query
/// strings - but stays one tap away for diagnosis and bug reports.
class ErrorStateView extends StatefulWidget {
  /// What failed, e.g. 'Gagal memuat status presensi'.
  final String title;

  /// The caught error; drives the friendly message and technical detail.
  final Object? error;

  /// Optional retry callback; the button is omitted when null.
  final VoidCallback? onRetry;

  const ErrorStateView({
    super.key,
    required this.title,
    this.error,
    this.onRetry,
  });

  @override
  State<ErrorStateView> createState() => _ErrorStateViewState();
}

class _ErrorStateViewState extends State<ErrorStateView> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              error == null ? '' : friendlyErrorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            if (widget.onRetry != null)
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
                onPressed: widget.onRetry,
              ),
            if (error != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => setState(() => _showDetail = !_showDetail),
                child: Text(
                  _showDetail ? 'Sembunyikan detail teknis' : 'Detail teknis',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_showDetail)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      errorDetail(error),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
