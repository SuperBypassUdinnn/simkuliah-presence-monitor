import 'package:flutter/material.dart';

/// Persistent warning banner shown at the top of the feed when the Simkuliah
/// gateway is experiencing an outage (HTTP 500/502/504).
///
/// Displays [`Icons.warning_amber_rounded`] together with `errorMessage` when
/// `hasOutage` is `true`. When `hasOutage` is `false` it returns
/// `const SizedBox.shrink()` so nothing is rendered and no layout space is
/// consumed.
class GatewayAlertBanner extends StatelessWidget {
  /// Whether the gateway is currently reporting an outage.
  final bool hasOutage;

  /// Human-readable error message shown alongside the warning icon.
  final String? errorMessage;

  const GatewayAlertBanner({
    super.key,
    required this.hasOutage,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasOutage) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.amber,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.black87,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage ?? 'Gateway outage detected',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
