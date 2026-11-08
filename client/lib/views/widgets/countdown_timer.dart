import 'dart:async';

import 'package:flutter/material.dart';

/// A self-updating countdown timer showing the remaining minutes and seconds
/// until [`deadlineAt`]. Once the deadline has passed it displays `00:00`.
class CountdownTimerWidget extends StatefulWidget {
  /// The deadline to count down towards. When `null`, a dash is shown.
  final DateTime? deadlineAt;

  const CountdownTimerWidget({super.key, this.deadlineAt});

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.deadlineAt;
    if (deadline == null) {
      return const Text('-');
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) {
      return const Text('00:00');
    }
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    return Text(
      '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
      style: const TextStyle(
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
