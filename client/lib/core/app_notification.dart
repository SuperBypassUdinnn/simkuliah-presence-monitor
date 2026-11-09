/// Purpose: Reusable top-right status notification overlay with stack support.
/// Data & Logic Flow: A manager tracks active notifications in one overlay entry; newer entries push older ones down and dismissals reflow the stack.
/// Key Components: AppNotification, _NotificationStack, _NotificationCard, _NotificationData
import 'dart:async';

import 'package:flutter/material.dart';

/// Immutable payload of a single status notification.
class _NotificationData {
  final int id;
  final String title;
  final String message;
  final Color color;
  final IconData icon;
  final Duration duration;

  const _NotificationData({
    required this.id,
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
    required this.duration,
  });
}

/// Shows modern, non-blocking status notifications in the top-right corner.
///
/// Multiple notifications stack vertically: a newer notification appears
/// below the older ones and dismissals reflow the stack smoothly.
class AppNotification {
  const AppNotification._();

  static final List<_NotificationData> _active = [];
  static OverlayEntry? _entry;
  static int _nextId = 0;

  /// Display a status notification above the current screen.
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required Color color,
    IconData icon = Icons.info_outline,
    Duration duration = const Duration(seconds: 4),
  }) {
    _active.add(
      _NotificationData(
        id: _nextId++,
        title: title,
        message: message,
        color: color,
        icon: icon,
        duration: duration,
      ),
    );
    if (_entry == null) {
      _entry = OverlayEntry(
        builder: (_) => _NotificationStack(
          notifications: List<_NotificationData>.of(_active),
          onDismissed: _handleDismissed,
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  static void _handleDismissed(int id) {
    _active.removeWhere((data) => data.id == id);
    if (_active.isEmpty) {
      _entry?.remove();
      _entry = null;
    } else {
      _entry?.markNeedsBuild();
    }
  }

  /// Clear every notification and the overlay entry (test helper).
  @visibleForTesting
  static void reset() {
    _active.clear();
    _entry?.remove();
    _entry = null;
  }
}

/// Positions and lays out the vertical notification stack.
class _NotificationStack extends StatelessWidget {
  final List<_NotificationData> notifications;
  final ValueChanged<int> onDismissed;

  const _NotificationStack({
    required this.notifications,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = screenWidth >= 440 ? 380.0 : screenWidth - 32;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      right: 16,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final data in notifications) ...[
              _NotificationCard(
                key: ValueKey<int>(data.id),
                data: data,
                width: cardWidth,
                onDismissed: () => onDismissed(data.id),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final _NotificationData data;
  final double width;
  final VoidCallback onDismissed;

  const _NotificationCard({
    super.key,
    required this.data,
    required this.width,
    required this.onDismissed,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.1, 0),
      end: Offset.zero,
    ).animate(curve);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _timer = Timer(widget.data.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.data.color;

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: widget.width,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(widget.data.icon, color: color, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.data.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.data.message,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Tutup',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: _dismiss,
                        ),
                      ],
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 1, end: 0),
                    duration: widget.data.duration,
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
