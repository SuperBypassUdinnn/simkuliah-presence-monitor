/// Purpose: Dialog widget for customizing lecture schedule timing, offsets, reminders, and auto-presence.
/// Data & Logic Flow: Collects user inputs for relative/absolute timing and automation flags, saving to Supabase via PresenceService.
/// Key Components: ScheduleCustomizationDialog
import 'package:flutter/material.dart';

import '../../core/app_notification.dart';
import '../../core/error_message.dart';
import '../../models/schedule_customization_model.dart';
import '../../services/presence_service.dart';

enum CustomizationScope { meeting, course }

enum TimingMode { relative, absolute }

class ScheduleCustomizationDialog extends StatefulWidget {
  final String courseName;
  final String courseCode;
  final int scheduleId;
  final int? meetingId;
  final int? meetingNumber;
  final ScheduleCustomizationModel? initialCustomization;
  final PresenceService? presenceService;
  final ValueChanged<ScheduleCustomizationModel?>? onSaved;

  const ScheduleCustomizationDialog({
    super.key,
    required this.courseName,
    required this.courseCode,
    required this.scheduleId,
    this.meetingId,
    this.meetingNumber,
    this.initialCustomization,
    this.presenceService,
    this.onSaved,
  });

  @override
  State<ScheduleCustomizationDialog> createState() =>
      _ScheduleCustomizationDialogState();
}

class _ScheduleCustomizationDialogState
    extends State<ScheduleCustomizationDialog> {
  late PresenceService _service;
  late CustomizationScope _scope;
  late TimingMode _timingMode;

  int _timeOffsetMinutes = 0;
  int? _customDayOfWeek;
  TimeOfDay? _customStartTime;
  TimeOfDay? _customEndTime;
  bool _autoPresenceEnabled = false;
  int? _reminderLeadMinutes = 15;
  bool _saving = false;

  final TextEditingController _customOffsetController = TextEditingController();
  final TextEditingController _customReminderController =
      TextEditingController();

  static const List<int> _quickOffsets = [-30, -15, 0, 15, 30, 60, 120];
  static const List<int> _quickReminders = [10, 15, 30];

  static const List<String> _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    final init = widget.initialCustomization;

    if (init != null && init.meetingId != null) {
      _scope = CustomizationScope.meeting;
    } else {
      _scope = widget.meetingId != null
          ? CustomizationScope.meeting
          : CustomizationScope.course;
    }

    if (init != null &&
        init.customStartTime != null &&
        init.customEndTime != null) {
      _timingMode = TimingMode.absolute;
      _customDayOfWeek = init.customDayOfWeek;
      _customStartTime = _parseTimeOfDay(init.customStartTime!);
      _customEndTime = _parseTimeOfDay(init.customEndTime!);
    } else {
      _timingMode = TimingMode.relative;
    }

    _timeOffsetMinutes = init?.timeOffsetMinutes ?? 0;
    _autoPresenceEnabled = init?.autoPresenceEnabled ?? false;
    _reminderLeadMinutes = init?.reminderLeadMinutes ?? 15;
    _customOffsetController.text = _timeOffsetMinutes.toString();
    if (_reminderLeadMinutes != null) {
      _customReminderController.text = _reminderLeadMinutes.toString();
    }
  }

  @override
  void dispose() {
    _customOffsetController.dispose();
    _customReminderController.dispose();
    super.dispose();
  }

  static TimeOfDay? _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return null;
  }

  static String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      final targetMeetingId = _scope == CustomizationScope.meeting
          ? widget.meetingId
          : null;

      final model = ScheduleCustomizationModel(
        id: widget.initialCustomization?.id,
        scheduleId: widget.scheduleId,
        meetingId: targetMeetingId,
        timeOffsetMinutes: _timingMode == TimingMode.relative
            ? _timeOffsetMinutes
            : 0,
        customDayOfWeek: _timingMode == TimingMode.absolute
            ? _customDayOfWeek
            : null,
        customStartTime:
            _timingMode == TimingMode.absolute && _customStartTime != null
            ? _formatTimeOfDay(_customStartTime!)
            : null,
        customEndTime:
            _timingMode == TimingMode.absolute && _customEndTime != null
            ? _formatTimeOfDay(_customEndTime!)
            : null,
        autoPresenceEnabled: _autoPresenceEnabled,
        reminderLeadMinutes: _reminderLeadMinutes,
      );

      final saved = await _service.saveCustomization(model);
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Pengaturan Disimpan',
          message: 'Penyesuaian jadwal dan automasi berhasil diperbarui.',
          color: Colors.green.shade600,
          icon: Icons.check_circle_outline,
        );
        Navigator.of(context).pop();
        widget.onSaved?.call(saved);
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Menyimpan',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete() async {
    final initId = widget.initialCustomization?.id;
    if (initId == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.deleteCustomization(initId);
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Penyesuaian Dihapus',
          message: 'Jadwal dikembalikan ke jadwal resmi Simkuliah.',
          color: Colors.blueGrey,
          icon: Icons.restore,
        );
        Navigator.of(context).pop();
        widget.onSaved?.call(null);
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Menghapus',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sesuaikan Jadwal & Automasi',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.courseName} (${widget.courseCode})',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Scope selector
              if (widget.meetingNumber != null) ...[
                Text(
                  'Cakupan Penyesuaian',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: Text('Pertemuan ke-${widget.meetingNumber}'),
                        selected: _scope == CustomizationScope.meeting,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _scope = CustomizationScope.meeting);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Semua Pertemuan'),
                        selected: _scope == CustomizationScope.course,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _scope = CustomizationScope.course);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Timing mode selector (Relatif vs Pindah Jadwal)
              Text(
                'Penyesuaian Waktu',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<TimingMode>(
                segments: const [
                  ButtonSegment(
                    value: TimingMode.relative,
                    label: Text('Relatif'),
                    icon: Icon(Icons.more_time),
                  ),
                  ButtonSegment(
                    value: TimingMode.absolute,
                    label: Text('Pindah Jadwal'),
                    icon: Icon(Icons.calendar_month),
                  ),
                ],
                selected: {_timingMode},
                onSelectionChanged: (newSelection) {
                  setState(() => _timingMode = newSelection.first);
                },
              ),
              const SizedBox(height: 12),

              if (_timingMode == TimingMode.relative) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickOffsets.map((offset) {
                    final label = offset == 0
                        ? '0m (Asli)'
                        : '${offset > 0 ? "+" : ""}${offset}m';
                    return ChoiceChip(
                      label: Text(label),
                      selected: _timeOffsetMinutes == offset,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _timeOffsetMinutes = offset;
                            _customOffsetController.text = offset.toString();
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Kustom (menit):'),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _customOffsetController,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null) {
                            setState(() => _timeOffsetMinutes = parsed);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Absolute mode
                DropdownButtonFormField<int>(
                  value: _customDayOfWeek ?? 1,
                  decoration: const InputDecoration(
                    labelText: 'Hari Perkuliahan',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(7, (i) {
                    return DropdownMenuItem(
                      value: i + 1,
                      child: Text(_days[i]),
                    );
                  }),
                  onChanged: (val) {
                    setState(() => _customDayOfWeek = val);
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time),
                        label: Text(
                          _customStartTime != null
                              ? '${_customStartTime!.hour.toString().padLeft(2, "0")}:${_customStartTime!.minute.toString().padLeft(2, "0")}'
                              : 'Mulai',
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _customStartTime ??
                                const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (picked != null) {
                            setState(() => _customStartTime = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_filled),
                        label: Text(
                          _customEndTime != null
                              ? '${_customEndTime!.hour.toString().padLeft(2, "0")}:${_customEndTime!.minute.toString().padLeft(2, "0")}'
                              : 'Selesai',
                        ),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime:
                                _customEndTime ??
                                const TimeOfDay(hour: 9, minute: 40),
                          );
                          if (picked != null) {
                            setState(() => _customEndTime = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Auto-Presence Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Presensi Otomatis (Auto-Absen)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Konfirmasi kehadiran secara otomatis begitu dosen membuka sesi presensi.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _autoPresenceEnabled,
                onChanged: (val) {
                  setState(() => _autoPresenceEnabled = val);
                },
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),

              // Reminder Lead Time
              Text(
                'Pengingat Masuk Kuliah',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _quickReminders.map((mins) {
                  return ChoiceChip(
                    label: Text('${mins}m'),
                    selected: _reminderLeadMinutes == mins,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _reminderLeadMinutes = mins;
                          _customReminderController.text = mins.toString();
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Kustom (menit):'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _customReminderController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed >= 0) {
                          setState(() => _reminderLeadMinutes = parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.initialCustomization != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: _saving ? null : _handleDelete,
                      child: const Text('Reset Asli'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _handleSave,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Simpan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
