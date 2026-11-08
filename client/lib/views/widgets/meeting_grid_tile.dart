import 'package:flutter/material.dart';

import '../../models/meeting_model.dart';
import '../../services/presence_service.dart';

/// Statuses used to color a meeting indicator in the semester matrix.
enum _MeetingIndicatorStatus {
  hadir,
  izin,
  sakit,
  alpa,
  pending,
}

/// A single cell in the semester matrix grid.
///
/// Displays the meeting number (1-16) with a color-coded status indicator:
/// Hadir (green), Izin (blue), Sakit (amber), Alpa (red), Pending (grey /
/// outline). Tapping the tile opens a dialog with the meeting details.
class MeetingGridTile extends StatelessWidget {
  /// The meeting to display.
  final MeetingModel meeting;

  /// Optional service used to submit presence or overrides for the meeting.
  /// When omitted, the tile still renders but action presses are no-ops.
  final PresenceService? presenceService;

  const MeetingGridTile({super.key, required this.meeting, this.presenceService});

  _MeetingIndicatorStatus _status() {
    switch (meeting.effectiveStatus.toLowerCase()) {
      case 'hadir':
        return _MeetingIndicatorStatus.hadir;
      case 'izin':
        return _MeetingIndicatorStatus.izin;
      case 'sakit':
        return _MeetingIndicatorStatus.sakit;
      case 'alpa':
        return _MeetingIndicatorStatus.alpa;
      default:
        return _MeetingIndicatorStatus.pending;
    }
  }

  MaterialColor _indicatorColor(_MeetingIndicatorStatus status) {
    switch (status) {
      case _MeetingIndicatorStatus.hadir:
        return Colors.green;
      case _MeetingIndicatorStatus.izin:
        return Colors.blue;
      case _MeetingIndicatorStatus.sakit:
        return Colors.amber;
      case _MeetingIndicatorStatus.alpa:
        return Colors.red;
      case _MeetingIndicatorStatus.pending:
        return Colors.grey;
    }
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Pertemuan ${meeting.meetingNumber}'),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              Text('Course: ${meeting.courseName}'),
              Text('Status: ${meeting.effectiveStatus}'),
              Text('Date: ${meeting.meetingDate}'),
              Text('Meeting ID: ${meeting.id}'),
              Text('Presence open: ${meeting.isPresenceOpen}'),
              if (meeting.deadlineAt != null)
                Text('Deadline: ${meeting.deadlineAt!.toLocal()}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status();
    final color = _indicatorColor(status);
    final pending = status == _MeetingIndicatorStatus.pending;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showDetails(context),
      child: Container(
        width: 72,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border:
              pending ? Border.all(color: Colors.grey, width: 1.5) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: pending ? null : color.withValues(alpha: 0.15),
                border: pending ? Border.all(color: color) : null,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${meeting.meetingNumber}',
                  style: TextStyle(
                    color: pending ? color : color.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pertemuan ${meeting.meetingNumber}',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              meeting.effectiveStatus,
              style: TextStyle(
                color: pending ? Colors.grey : color.shade700,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
