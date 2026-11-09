/// Purpose: Lecture card widget rendering meeting status, timers, and action controls.
/// Data & Logic Flow: Renders course info, countdown timer, presence button, and override chips with confirm dialogs.
/// Key Components: ActiveLectureCard
import 'package:flutter/material.dart';

import '../../core/app_notification.dart';
import '../../core/override_style.dart';
import '../../models/meeting_model.dart';
import '../../services/presence_service.dart';
import 'countdown_timer.dart';

/// A Material 3 card for a single lecture meeting in today's feed or active presence.
///
/// Displays course name, code, class group, time, room, lecturer, and real-time status.
/// Supports presence confirmation (strictly when allowed) and local overrides (Izin / Sakit / Alpa).
class ActiveLectureCard extends StatefulWidget {
  final MeetingModel meeting;
  final PresenceService? presenceService;
  final VoidCallback? onStatusChanged;

  /// Whether presence confirmation action is enabled (strictly true only in Presensi Aktif tab).
  final bool allowPresenceConfirmation;

  const ActiveLectureCard({
    super.key,
    required this.meeting,
    this.presenceService,
    this.onStatusChanged,
    this.allowPresenceConfirmation = false,
  });

  @override
  State<ActiveLectureCard> createState() => _ActiveLectureCardState();
}

class _ActiveLectureCardState extends State<ActiveLectureCard> {
  late PresenceService _service;
  String? _activeOverride;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    _activeOverride = widget.meeting.localOverride?['override_type']
        ?.toString()
        .toLowerCase();
  }

  @override
  void didUpdateWidget(covariant ActiveLectureCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activeOverride = widget.meeting.localOverride?['override_type']
        ?.toString()
        .toLowerCase();
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String content,
    String confirmLabel = 'Konfirmasi',
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  confirmColor ?? Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleConfirmPresence() async {
    final confirmed = await _showConfirmDialog(
      title: 'Konfirmasi Kehadiran?',
      content:
          'Apakah Anda yakin ingin melakukan konfirmasi kehadiran untuk ${widget.meeting.courseName}?',
      confirmLabel: 'Lakukan Presensi',
      confirmColor: Colors.green.shade600,
    );

    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _service.submitPresence(
        meetingId: widget.meeting.id,
        isPresent: true,
      );
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Presensi Berhasil',
          message: '${widget.meeting.courseName} tercatat sebagai Hadir.',
          color: Colors.green.shade600,
          icon: Icons.check_circle_outline,
        );
        widget.onStatusChanged?.call();
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Presensi Gagal',
          message: 'Kehadiran tidak dapat dikonfirmasi: $error',
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _handleOverrideSelected(String overrideType) async {
    final style = OverrideStyle.of(overrideType);
    final capitalized = style.label;
    final confirmed = await _showConfirmDialog(
      title: 'Konfirmasi Keterangan Mandiri',
      content:
          'Apakah Anda yakin ingin menetapkan status pertemuan ${widget.meeting.courseName} menjadi "$capitalized"?',
      confirmLabel: 'Simpan $capitalized',
      confirmColor: style.color,
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _activeOverride = overrideType.toLowerCase();
      _submitting = true;
    });

    try {
      await _service.submitOverride(
        meetingId: widget.meeting.id,
        overrideType: overrideType,
      );
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Keterangan Disimpan',
          message:
              '${widget.meeting.courseName} ditandai sebagai $capitalized.',
          color: style.color,
          icon: style.icon,
        );
        widget.onStatusChanged?.call();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _activeOverride = null);
        AppNotification.show(
          context,
          title: 'Gagal Menyimpan',
          message: 'Keterangan mandiri tidak dapat disimpan: $error',
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _overrideChip(OverrideStyle style) {
    final isSelected = _activeOverride == style.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Lighten the accent on dark surfaces so unselected labels keep readable
    // contrast, especially for deep colors such as Alpa maroon.
    final accent = isDark
        ? Color.lerp(style.color, Colors.white, 0.28)!
        : style.color;

    return ChoiceChip(
      label: Text(style.label),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: style.color,
      backgroundColor: style.color.withValues(alpha: isDark ? 0.14 : 0.07),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : accent,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
      ),
      side: BorderSide(
        color: isSelected ? Colors.white : accent,
        width: isSelected ? 2 : 1,
      ),
      elevation: isSelected ? 3 : 0,
      shadowColor: style.color,
      onSelected: _submitting
          ? null
          : (selected) {
              if (selected) {
                _handleOverrideSelected(style.type);
              }
            },
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    if (widget.meeting.isAttended) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade400),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text(
              'Sudah Hadir (Tercatat di Simkuliah)',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.meeting.isOverridden) {
      final style = OverrideStyle.of(
        widget.meeting.localOverride?['override_type']?.toString(),
      );
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final accent = isDark
          ? Color.lerp(style.color, Colors.white, 0.45)!
          : style.color;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: isDark ? 0.24 : 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, color: accent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Keterangan: ${widget.meeting.effectiveStatus}',
              style: TextStyle(color: accent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    if (widget.meeting.isPresenceOpen) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade700),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text(
              'Presensi Sedang Dibuka!',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.meeting.isBeforeScheduleTime()) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, color: Colors.blue, size: 18),
            const SizedBox(width: 8),
            Text(
              'Belum Dimulai (Pukul ${widget.meeting.startTime} WIB)',
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.meeting.isWithinScheduleTime()) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade400),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, color: Colors.orange, size: 18),
            SizedBox(width: 8),
            Text(
              'Dosen Belum Melakukan Presensi',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.meeting.simkuliahStatus.toLowerCase() == 'tidak_hadir' ||
        widget.meeting.simkuliahStatus.toLowerCase() == 'tidak hadir') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade400),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
            SizedBox(width: 8),
            Text(
              'Tidak Hadir (Tercatat di Simkuliah)',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_bottom, color: Colors.grey, size: 18),
          SizedBox(width: 8),
          Text('Jadwal Kuliah Selesai', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Attendance status completely locks the card from manual override chips.
    final showOverrideChips = !widget.meeting.isAttended;

    // Presence confirmation button is strictly shown only in Presensi Aktif tab
    // when presence is open and user has not yet attended.
    final canPerformPresence =
        widget.allowPresenceConfirmation &&
        widget.meeting.isPresenceOpen &&
        !widget.meeting.isAttended;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.meeting.courseName,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (widget.meeting.courseCode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${widget.meeting.courseCode} · Kelas ${widget.meeting.classGroup.isNotEmpty ? widget.meeting.classGroup : "A"} · Pertemuan ke-${widget.meeting.meetingNumber}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade400),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (widget.meeting.startTime.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.meeting.startTime} - ${widget.meeting.endTime} WIB',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                if (widget.meeting.room.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.meeting_room_outlined,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.meeting.room,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                if (widget.meeting.lecturerName.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.meeting.lecturerName,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _buildStatusBanner(context),
            if (canPerformPresence) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'Waktu tersisa: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  CountdownTimerWidget(deadlineAt: widget.meeting.deadlineAt),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.touch_app),
                  onPressed: _submitting ? null : _handleConfirmPresence,
                  label: Text(
                    _submitting
                        ? 'Sedang Memverifikasi...'
                        : 'Lakukan Presensi',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
            if (showOverrideChips) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 6),
              Text(
                'Keterangan Mandiri:',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: OverrideStyle.all
                    .map((style) => _overrideChip(style))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
