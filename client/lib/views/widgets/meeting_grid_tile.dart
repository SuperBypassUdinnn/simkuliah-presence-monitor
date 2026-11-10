/// Purpose: Individual meeting cell widget for the semester matrix.
/// Data & Logic Flow: Renders colored meeting number/icon and interactive details dialog with override selector.
/// Key Components: MeetingGridTile
import 'package:flutter/material.dart';

import '../../core/app_notification.dart';
import '../../core/error_message.dart';
import '../../core/override_style.dart';
import '../../models/meeting_model.dart';
import '../../services/presence_service.dart';

/// Statuses used to color a meeting indicator in the semester matrix.
enum _MeetingIndicatorStatus {
  hadir,
  tidakHadir,
  izin,
  sakit,
  alpa,
  lupaAbsen,
  dosenTidakAbsen,
  pending,
}

/// A single cell in the semester matrix grid.
///
/// Displays the meeting number (1-16) with a color-coded status indicator:
/// Hadir (green), Izin (blue), Sakit (amber), Alpa (red), Pending (grey / outline).
/// Tapping the tile opens a dialog with the meeting details and local override options.
class MeetingGridTile extends StatelessWidget {
  /// The meeting to display.
  final MeetingModel meeting;

  /// Whether to render in compact table cell mode.
  final bool compact;

  /// Presence service for submitting local overrides.
  final PresenceService? presenceService;

  /// Callback when a local override is created, updated, or removed.
  final VoidCallback? onOverrideChanged;

  const MeetingGridTile({
    super.key,
    required this.meeting,
    this.compact = false,
    this.presenceService,
    this.onOverrideChanged,
  });

  _MeetingIndicatorStatus _status() {
    switch (meeting.effectiveStatus.toLowerCase()) {
      case 'hadir':
        return _MeetingIndicatorStatus.hadir;
      case 'tidak_hadir':
      case 'tidak hadir':
        return _MeetingIndicatorStatus.tidakHadir;
      case 'izin':
        return _MeetingIndicatorStatus.izin;
      case 'sakit':
        return _MeetingIndicatorStatus.sakit;
      case 'alpa':
        return _MeetingIndicatorStatus.alpa;
      case 'lupa_absen':
      case 'lupa absen':
        return _MeetingIndicatorStatus.lupaAbsen;
      case 'dosen_tidak_absen':
      case 'dosen tidak absen':
        return _MeetingIndicatorStatus.dosenTidakAbsen;
      default:
        return _MeetingIndicatorStatus.pending;
    }
  }

  Color _indicatorColor(_MeetingIndicatorStatus status) {
    switch (status) {
      case _MeetingIndicatorStatus.hadir:
        return const Color(0xFF16A34A);
      case _MeetingIndicatorStatus.tidakHadir:
        return const Color(0xFFDC2626);
      case _MeetingIndicatorStatus.izin:
        return OverrideStyle.izin.color;
      case _MeetingIndicatorStatus.sakit:
        return OverrideStyle.sakit.color;
      case _MeetingIndicatorStatus.alpa:
        return OverrideStyle.alpa.color;
      case _MeetingIndicatorStatus.lupaAbsen:
        return OverrideStyle.lupaAbsen.color;
      case _MeetingIndicatorStatus.dosenTidakAbsen:
        return OverrideStyle.dosenTidakAbsen.color;
      case _MeetingIndicatorStatus.pending:
        return Colors.grey;
    }
  }

  void _showDetails(BuildContext context) {
    final service = presenceService ?? PresenceService();
    // Captured for error notifications: the dialog builder's own context
    // unmounts as soon as the dialog pops.
    final viewContext = context;
    String? currentOverride = meeting.localOverride?['override_type']
        ?.toString()
        .toLowerCase();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              'Pertemuan ${meeting.meetingNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: ListBody(
                children: [
                  _detailRow('Mata Kuliah', meeting.courseName),
                  if (meeting.courseCode.isNotEmpty)
                    _detailRow(
                      'Kode & Kelas',
                      '${meeting.courseCode} (Kelas ${meeting.classGroup})',
                    ),
                  _detailRow('Status Kehadiran', meeting.effectiveStatus),
                  if (meeting.meetingDate.isNotEmpty)
                    _detailRow('Tanggal', meeting.meetingDate),
                  if (meeting.startTime.isNotEmpty)
                    _detailRow(
                      'Jam',
                      '${meeting.startTimeShort} - ${meeting.endTimeShort} WIB',
                    ),
                  if (meeting.room.isNotEmpty)
                    _detailRow('Ruang', meeting.room),
                  if (meeting.lecturerName.isNotEmpty &&
                      meeting.lecturerName.toLowerCase() != 'dosen')
                    _detailRow('Dosen', meeting.lecturerName),
                  if (meeting.isPresenceOpen) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Presensi sedang dibuka oleh dosen!',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (!meeting.isAttended) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 6),
                    Text(
                      'Keterangan Mandiri:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: OverrideStyle.all.map((style) {
                        final type = style.type;
                        final isSelected = currentOverride == type;
                        final label = style.label;
                        return ChoiceChip(
                          label: Text(label),
                          selected: isSelected,
                          showCheckmark: false,
                          selectedColor: style.color,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : style.color,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(color: style.color),
                          onSelected: (selected) async {
                            // Tapping the selected chip once more cancels
                            // the status; tapping an unselected chip when
                            // no override is active does nothing.
                            final isCancel = !selected && isSelected;
                            if (!selected && !isCancel) return;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text(
                                  isCancel
                                      ? 'Batalkan Keterangan Mandiri?'
                                      : 'Konfirmasi Keterangan Mandiri',
                                ),
                                content: Text(
                                  isCancel
                                      ? 'Apakah Anda yakin ingin membatalkan status "$label" untuk pertemuan ini?'
                                      : 'Apakah Anda yakin ingin menetapkan status pertemuan ini menjadi "$label"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(c).pop(false),
                                    child: const Text('Batal'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: style.color,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.of(c).pop(true),
                                    child: const Text(
                                      'Konfirmasi',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed != true || meeting.id <= 0) return;

                            try {
                              if (isCancel) {
                                await service.clearOverride(
                                  meetingId: meeting.id,
                                );
                              } else {
                                await service.submitOverride(
                                  meetingId: meeting.id,
                                  overrideType: type,
                                );
                              }
                              setDialogState(() {
                                currentOverride = isCancel ? null : type;
                              });
                              if (context.mounted) {
                                Navigator.of(dialogContext).pop();
                                onOverrideChanged?.call();
                              }
                            } catch (error) {
                              // Surface the failure instead of swallowing it:
                              // close the dialog first so the notification is
                              // visible above the page.
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                              if (viewContext.mounted) {
                                AppNotification.show(
                                  viewContext,
                                  title: isCancel
                                      ? 'Gagal Membatalkan'
                                      : 'Gagal Menyimpan',
                                  message: friendlyErrorMessage(error),
                                  color: Colors.red.shade600,
                                  icon: Icons.error_outline,
                                );
                              }
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _letterBadge(String letter) {
    return Text(
      letter,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status();
    final color = _indicatorColor(status);
    final pending = status == _MeetingIndicatorStatus.pending;

    if (compact) {
      Color bgColor;
      Widget content;

      switch (status) {
        case _MeetingIndicatorStatus.hadir:
          bgColor = _indicatorColor(status);
          content = const Icon(Icons.check, size: 16, color: Colors.white);
          break;
        case _MeetingIndicatorStatus.tidakHadir:
          bgColor = _indicatorColor(status);
          content = const Icon(Icons.close, size: 16, color: Colors.white);
          break;
        case _MeetingIndicatorStatus.izin:
          bgColor = OverrideStyle.izin.color;
          content = _letterBadge(OverrideStyle.izin.letter);
          break;
        case _MeetingIndicatorStatus.sakit:
          bgColor = OverrideStyle.sakit.color;
          content = _letterBadge(OverrideStyle.sakit.letter);
          break;
        case _MeetingIndicatorStatus.alpa:
          bgColor = OverrideStyle.alpa.color;
          content = _letterBadge(OverrideStyle.alpa.letter);
          break;
        case _MeetingIndicatorStatus.lupaAbsen:
          bgColor = OverrideStyle.lupaAbsen.color;
          content = _letterBadge(OverrideStyle.lupaAbsen.letter);
          break;
        case _MeetingIndicatorStatus.dosenTidakAbsen:
          bgColor = OverrideStyle.dosenTidakAbsen.color;
          content = _letterBadge(OverrideStyle.dosenTidakAbsen.letter);
          break;
        case _MeetingIndicatorStatus.pending:
          bgColor = Colors.grey.withValues(alpha: 0.12);
          content = Text(
            '${meeting.meetingNumber}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          );
          break;
      }

      return Tooltip(
        message:
            'P${meeting.meetingNumber}: ${meeting.effectiveStatus}\n${meeting.meetingDate}',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _showDetails(context),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: pending
                  ? Border.all(color: Colors.grey.shade600, width: 0.8)
                  : null,
            ),
            child: Center(child: content),
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showDetails(context),
      child: Container(
        width: 72,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: pending ? Border.all(color: Colors.grey, width: 1.5) : null,
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
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pertemuan ${meeting.meetingNumber}',
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
            Text(
              meeting.effectiveStatus,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
