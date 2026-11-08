import 'package:flutter/material.dart';

import '../../models/meeting_model.dart';
import '../../services/presence_service.dart';
import 'countdown_timer.dart';

/// A Material 3 card for a single lecture meeting in today's feed.
///
/// Displays the course name, meeting number, a countdown timer while presence
/// is open, a "Konfirmasi Presensi" button, and action chips for Izin / Sakit /
/// Alpa overrides. Chip presses are applied optimistically through
/// [`PresenceService`] and rolled back on failure.
class ActiveLectureCard extends StatefulWidget {
  /// The meeting to display.
  final MeetingModel meeting;

  /// Optional service used to submit presence and overrides. When omitted,
  /// the card still renders but action presses are no-ops (useful offline or
  /// in widget tests).
  final PresenceService? presenceService;

  const ActiveLectureCard({
    super.key,
    required this.meeting,
    this.presenceService,
  });

  @override
  State<ActiveLectureCard> createState() => _ActiveLectureCardState();
}

class _ActiveLectureCardState extends State<ActiveLectureCard> {
  String? _activeOverride;
  bool _submitting = false;

  Future<void> _confirmPresence() async {
    final service = widget.presenceService;
    if (service == null) return;
    setState(() => _submitting = true);
    try {
      await service.submitPresence(
        meetingId: widget.meeting.id,
        isPresent: true,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengonfirmasi kehadiran: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitOverride(String overrideType) async {
    final service = widget.presenceService;
    if (service == null) return;
    setState(() {
      _activeOverride = overrideType;
      _submitting = true;
    });
    try {
      await service.submitOverride(
        meetingId: widget.meeting.id,
        overrideType: overrideType,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _activeOverride = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan overrides: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _overrideChip(String label, String type) {
    return ChoiceChip(
      label: Text(label),
      selected: _activeOverride == type,
      onSelected: _submitting ? null : (_) => _submitOverride(type),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.meeting.courseName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Pertemuan ${widget.meeting.meetingNumber}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (widget.meeting.isPresenceOpen) ...[
              Row(
                children: [
                  const Text('Waktu tersisa: '),
                  CountdownTimerWidget(deadlineAt: widget.meeting.deadlineAt),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _submitting ? null : _confirmPresence,
                child: const Text('Konfirmasi Presensi'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _overrideChip('Izin', 'izin'),
                  _overrideChip('Sakit', 'sakit'),
                  _overrideChip('Alpa', 'alpa'),
                ],
              ),
            ] else ...[
              Text(
                'Belum dibuka oleh dosen',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
