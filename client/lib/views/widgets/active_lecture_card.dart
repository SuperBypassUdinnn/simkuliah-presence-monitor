/// Purpose: Lecture card widget rendering meeting status, timers, and action controls.
/// Data & Logic Flow: Renders course info, countdown timer, presence button, and override chips with confirm dialogs.
/// Key Components: ActiveLectureCard
import 'package:flutter/material.dart';

import '../../core/app_notification.dart';
import '../../core/error_message.dart';
import '../../core/override_style.dart';
import '../../models/meeting_model.dart';
import '../../models/schedule_customization_model.dart';
import '../../services/presence_service.dart';
import 'countdown_timer.dart';

/// A Material 3 card for a single lecture meeting in today's feed or active presence.
///
/// Displays course name, code, class group, time, room, lecturer, and real-time status.
/// Supports presence confirmation (strictly when allowed) and local overrides (Izin / Sakit / Alpa).
class ActiveLectureCard extends StatefulWidget {
  final MeetingModel meeting;
  final ScheduleCustomizationModel? customization;
  final PresenceService? presenceService;
  final VoidCallback? onStatusChanged;
  final ValueChanged<ScheduleCustomizationModel?>? onCustomizationChanged;

  /// Whether presence confirmation action is enabled (strictly true only in Presensi Aktif tab).
  final bool allowPresenceConfirmation;

  const ActiveLectureCard({
    super.key,
    required this.meeting,
    this.customization,
    this.presenceService,
    this.onStatusChanged,
    this.onCustomizationChanged,
    this.allowPresenceConfirmation = false,
  });

  @override
  State<ActiveLectureCard> createState() => _ActiveLectureCardState();
}

class _ActiveLectureCardState extends State<ActiveLectureCard> {
  /// Upper bound for the card's inline controls. Without it the auto-absen row
  /// and the presence button stretch across the whole card, which turns them
  /// into screen-wide controls in a desktop window. Mobile widths stay
  /// full-width because the constraint never widens a narrow layout.
  static const double _controlMaxWidth = 420;

  late PresenceService _service;
  String? _activeOverride;
  bool _submitting = false;
  bool _autoPresence = false;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    _activeOverride = widget.meeting.localOverride?['override_type']
        ?.toString()
        .toLowerCase();
    _autoPresence = widget.customization?.autoPresenceEnabled ?? false;
  }

  @override
  void didUpdateWidget(covariant ActiveLectureCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activeOverride = widget.meeting.localOverride?['override_type']
        ?.toString()
        .toLowerCase();
    _autoPresence = widget.customization?.autoPresenceEnabled ?? false;
  }

  Future<void> _handleToggleAutoPresence(bool value) async {
    final prev = _autoPresence;
    setState(() => _autoPresence = value);
    try {
      final saved = await _service.saveMeetingAutoPresence(
        scheduleId: widget.meeting.scheduleId ?? 0,
        meetingId: widget.meeting.id,
        enabled: value,
      );
      if (mounted) {
        AppNotification.show(
          context,
          title: value ? 'Auto-Absen Aktif' : 'Auto-Absen Dinonaktifkan',
          message: value
              ? 'Presensi pertemuan ke-${widget.meeting.meetingNumber} akan otomatis dikonfirmasi begitu dosen membuka absensi.'
              : 'Presensi otomatis untuk pertemuan ini dinonaktifkan.',
          color: value ? Colors.amber.shade800 : Colors.blueGrey,
          icon: value ? Icons.bolt : Icons.power_settings_new,
        );
        widget.onCustomizationChanged?.call(saved);
        widget.onStatusChanged?.call();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _autoPresence = prev);
        AppNotification.show(
          context,
          title: 'Gagal Mengubah Auto-Absen',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
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
          message: friendlyErrorMessage(error),
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
      confirmLabel: 'Konfirmasi',
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
          message: friendlyErrorMessage(error),
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
              } else if (isSelected) {
                // Tapping the selected chip once more cancels the status.
                _handleOverrideCancel(style);
              }
            },
    );
  }

  /// Cancels the active self-reported status after an explicit
  /// confirmation, mirroring the submit flow's dialogs and notifications.
  Future<void> _handleOverrideCancel(OverrideStyle style) async {
    final confirmed = await _showConfirmDialog(
      title: 'Batalkan Keterangan Mandiri?',
      content:
          'Apakah Anda yakin ingin membatalkan status "${style.label}" untuk ${widget.meeting.courseName}?',
      confirmLabel: 'Konfirmasi',
      confirmColor: style.color,
    );

    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _service.clearOverride(meetingId: widget.meeting.id);
      if (mounted) {
        setState(() => _activeOverride = null);
        AppNotification.show(
          context,
          title: 'Keterangan Dibatalkan',
          message:
              'Status "${style.label}" untuk ${widget.meeting.courseName} dihapus.',
          color: Colors.blueGrey,
          icon: Icons.undo,
        );
        widget.onStatusChanged?.call();
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Membatalkan',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// True when the displayed time actually differs from the official portal
  /// schedule. Only then should the `(Portal: HH:mm)` badge be shown.
  ///
  /// A customization row that only carries `autoPresenceEnabled = true` with
  /// `timeOffsetMinutes == 0` and no absolute overrides does NOT change the
  /// displayed time, so the badge must stay hidden.
  bool _hasEffectiveTimeOverride() {
    final cust = widget.customization;
    if (cust == null) return false;
    if (cust.customStartTime != null && cust.customEndTime != null) return true;
    return cust.timeOffsetMinutes != 0;
  }

  String _getEffectiveTimeText() {
    final cust = widget.customization;
    if (cust == null) {
      return '${widget.meeting.startTimeShort} - ${widget.meeting.endTimeShort} WIB';
    }

    if (cust.customStartTime != null && cust.customEndTime != null) {
      final start = _stripSeconds(cust.customStartTime!);
      final end = _stripSeconds(cust.customEndTime!);
      return '$start - $end WIB';
    }

    if (cust.timeOffsetMinutes != 0 &&
        widget.meeting.startTime.isNotEmpty &&
        widget.meeting.endTime.isNotEmpty) {
      final startParsed = _parseTime(widget.meeting.startTime);
      final endParsed = _parseTime(widget.meeting.endTime);
      if (startParsed != null && endParsed != null) {
        final shiftedStart = startParsed.add(
          Duration(minutes: cust.timeOffsetMinutes),
        );
        final shiftedEnd = endParsed.add(
          Duration(minutes: cust.timeOffsetMinutes),
        );
        final sh = shiftedStart.hour.toString().padLeft(2, '0');
        final sm = shiftedStart.minute.toString().padLeft(2, '0');
        final eh = shiftedEnd.hour.toString().padLeft(2, '0');
        final em = shiftedEnd.minute.toString().padLeft(2, '0');
        return '$sh:$sm - $eh:$em WIB';
      }
    }

    return '${widget.meeting.startTimeShort} - ${widget.meeting.endTimeShort} WIB';
  }

  static DateTime? _parseTime(String time) {
    final match = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(time);
    if (match == null) return null;
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  static String _stripSeconds(String time) {
    final match = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(time);
    if (match == null) return time;
    return '${match.group(1)}:${match.group(2)}';
  }

  /// Explains the auto-absen state without overstating what the user must do.
  ///
  /// A switched-off toggle has several distinct causes (attendance already
  /// recorded, presence window closed, lecture finished), so the subtitle
  /// names the real one. The reasons that make automation impossible are
  /// checked first, which also keeps a stale "on" flag from promising
  /// automation that can no longer fire.
  String _autoPresenceSubtitle() {
    final meeting = widget.meeting;
    if (meeting.isAttended) {
      // If auto-absen was enabled, it was most likely the one that submitted
      // the attendance; show a distinct "berhasil" message.
      if (_autoPresence) {
        return 'Auto-Absen berhasil: kehadiran tercatat otomatis di Simkuliah';
      }
      return 'Tidak diperlukan: presensi sudah tercatat di Simkuliah';
    }
    final deadline = meeting.deadlineAt;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      return 'Tidak berlaku: jendela presensi sudah ditutup';
    }
    if (meeting.isPastScheduleTime()) {
      return 'Tidak berlaku: jadwal kuliah sudah berakhir';
    }
    if (_autoPresence) {
      return 'Aktif: otomatis absen saat dosen membuka presensi';
    }
    if (meeting.isPresenceOpen) {
      return 'Nonaktif: presensi sedang dibuka, lakukan manual';
    }
    return 'Nonaktif: aktifkan agar presensi otomatis saat dosen membuka '
        'absensi';
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

    final deadline = widget.meeting.deadlineAt;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      // The lecturer did open presence, but the window has closed. Without
      // this branch the card falls through to "Dosen Belum Melakukan
      // Presensi", which is false and was the owner-reported confusion.
      final hh = deadline.hour.toString().padLeft(2, '0');
      final mm = deadline.minute.toString().padLeft(2, '0');
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock, color: Colors.blueGrey, size: 18),
            const SizedBox(width: 8),
            Text(
              'Presensi Ditutup (Batas $hh:$mm WIB)',
              style: const TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600,
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
              'Belum Dimulai (Pukul ${widget.meeting.startTimeShort} WIB)',
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
                        _getEffectiveTimeText(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_hasEffectiveTimeOverride()) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '(Portal: ${widget.meeting.startTimeShort})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                      if (widget.customization?.autoPresenceEnabled ==
                          true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.amber.shade700,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt,
                                size: 12,
                                color: Colors.amber.shade800,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Auto-Absen',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _controlMaxWidth),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _autoPresence
                        ? Colors.amber.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _autoPresence
                          ? Colors.amber.shade400
                          : Colors.grey.shade300,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 20,
                        color: _autoPresence
                            ? Colors.amber.shade800
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto-Absen Pertemuan Ini',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _autoPresence
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _autoPresence
                                    ? Colors.amber.shade900
                                    : null,
                              ),
                            ),
                            Text(
                              _autoPresenceSubtitle(),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoPresence,
                        onChanged: widget.meeting.isAttended
                            ? null
                            : _handleToggleAutoPresence,
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _controlMaxWidth),
                  child: SizedBox(
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
