/// Purpose: Dedicated automation and settings tab for global reminders and per-course schedule configuration.
/// Data & Logic Flow: Loads user preferences and semester schedules, allowing global reminder templates and per-course auto-presence/timing customizations.
/// Key Components: SettingsAutomationView
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_notification.dart';
import '../core/error_message.dart';
import '../core/load_epoch_guard.dart';
import '../core/refresh_bus.dart';
import '../models/schedule_customization_model.dart';
import '../models/schedule_model.dart';
import '../models/user_preferences_model.dart';
import '../services/presence_service.dart';
import 'widgets/error_state_view.dart';

/// How a course's effective lecture time is derived.
enum _TimingMode { official, relative, absolute }

/// Day labels indexed by the database `custom_day_of_week` value (1 = Monday).
const List<String> _dayLabels = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

class SettingsAutomationView extends StatefulWidget {
  final PresenceService? presenceService;

  /// Optional pre-loaded state for tests / widget previews: when provided,
  /// the async Supabase load is skipped and these values render directly.
  final List<ScheduleModel>? initialSchedules;
  final List<ScheduleCustomizationModel>? initialCustomizations;
  final UserPreferencesModel? initialPreferences;

  const SettingsAutomationView({
    super.key,
    this.presenceService,
    this.initialSchedules,
    this.initialCustomizations,
    this.initialPreferences,
  });

  @override
  State<SettingsAutomationView> createState() => _SettingsAutomationViewState();
}

class _SettingsAutomationViewState extends State<SettingsAutomationView> {
  late final PresenceService _service;
  final LoadEpochGuard _loadGuard = LoadEpochGuard();
  StreamSubscription<void>? _refreshSub;

  List<ScheduleModel>? _schedules;
  List<ScheduleCustomizationModel> _customizations = const [];
  UserPreferencesModel? _preferences;
  bool _loading = true;
  Object? _error;

  static const List<int> _reminderTemplates = [10, 15, 30];

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    if (widget.initialSchedules != null) {
      _schedules = widget.initialSchedules;
      _customizations = widget.initialCustomizations ?? const [];
      _preferences = widget.initialPreferences;
      _loading = false;
      return;
    }
    unawaited(_load(silent: false));
    _refreshSub = RefreshBus.instance.stream.listen((_) {
      unawaited(_load(silent: _schedules != null, force: true));
    });
  }

  @override
  void dispose() {
    unawaited(_refreshSub?.cancel());
    super.dispose();
  }

  Future<void> _load({required bool silent, bool force = false}) async {
    final epoch = _loadGuard.tryBegin(
      timeout: _service.requestTimeout,
      force: force,
    );
    if (epoch == null) return;
    if (!silent || _schedules == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchSemesterMatrix(),
        _service.fetchUserPreferences(),
      ]);
      final schedules = results[0] as List<ScheduleModel>;
      final preferences = results[1] as UserPreferencesModel;

      final scheduleIds = schedules.map((s) => s.id).toList();
      final customizations = await _service.fetchCustomizations(scheduleIds);

      if (!mounted || !_loadGuard.isCurrent(epoch)) return;
      setState(() {
        _schedules = schedules;
        _customizations = customizations;
        _preferences = preferences;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || !_loadGuard.isCurrent(epoch)) return;
      if (_schedules == null) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } finally {
      _loadGuard.complete(epoch);
    }
  }

  ScheduleCustomizationModel? _customizationFor(ScheduleModel schedule) {
    for (final c in _customizations) {
      if (c.scheduleId == schedule.id && c.meetingId == null) {
        return c;
      }
    }
    return null;
  }

  /// Return the meeting-level customization for one specific meeting, or null.
  ScheduleCustomizationModel? _customizationForMeeting(
    int scheduleId,
    int meetingId,
  ) {
    for (final c in _customizations) {
      if (c.scheduleId == scheduleId && c.meetingId == meetingId) return c;
    }
    return null;
  }

  /// How many meetings in [schedule] have `autoPresenceEnabled == true`.
  int _autoPresenceEnabledCount(ScheduleModel schedule) => _customizations
      .where(
        (c) =>
            c.scheduleId == schedule.id &&
            c.meetingId != null &&
            c.autoPresenceEnabled,
      )
      .length;

  /// Toggle the global reminder on/off flag.
  Future<void> _saveGlobalReminderEnabled(bool enabled) async {
    try {
      final updated = (_preferences ?? const UserPreferencesModel()).copyWith(
        reminderEnabled: enabled,
      );
      final saved = await _service.saveUserPreferences(updated);
      if (mounted) setState(() => _preferences = saved);
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Menyimpan Pengingat',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
  }

  /// Toggle auto-presence for a single meeting (called from the per-meeting
  /// selection dialog in settings and kept in sync with the card toggle).
  Future<void> _saveMeetingAutoPresenceInSettings({
    required int scheduleId,
    required int meetingId,
    required bool enabled,
  }) async {
    try {
      final saved = await _service.saveMeetingAutoPresence(
        scheduleId: scheduleId,
        meetingId: meetingId,
        enabled: enabled,
      );
      if (mounted) {
        setState(() {
          _customizations = [
            ..._customizations.where(
              (c) => !(c.scheduleId == scheduleId && c.meetingId == meetingId),
            ),
            saved,
          ];
        });
        RefreshBus.instance.requestRefresh();
      }
    } catch (error) {
      if (mounted) {
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

  /// Open the per-meeting auto-presence selection dialog.
  Future<void> _showAutoPresenceMeetingsDialog(
    BuildContext ctx,
    ScheduleModel schedule,
  ) async {
    final meetings = schedule.meetings;
    if (meetings.isEmpty) {
      if (mounted) {
        AppNotification.show(
          ctx,
          title: 'Data Pertemuan Belum Tersedia',
          message: 'Muat ulang halaman untuk memuat daftar pertemuan.',
          color: Colors.orange,
          icon: Icons.info_outline,
        );
      }
      return;
    }

    final initialEnabled = {
      for (final m in meetings)
        m.id:
            _customizationForMeeting(schedule.id, m.id)?.autoPresenceEnabled ??
            false,
    };

    if (!mounted) return;
    await showDialog<void>(
      context: ctx,
      builder: (_) => _AutoPresenceMeetingsDialog(
        schedule: schedule,
        initialEnabled: initialEnabled,
        onToggle: (meetingId, enabled) => unawaited(
          _saveMeetingAutoPresenceInSettings(
            scheduleId: schedule.id,
            meetingId: meetingId,
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  Future<void> _saveGlobalReminder(int minutes) async {
    try {
      final updated = (_preferences ?? UserPreferencesModel()).copyWith(
        defaultReminderMinutes: minutes,
      );
      final saved = await _service.saveUserPreferences(updated);
      if (mounted) {
        setState(() => _preferences = saved);
        AppNotification.show(
          context,
          title: 'Pengingat Global Disimpan',
          message: 'Pengingat default masuk kuliah kini $minutes menit.',
          color: Colors.indigo.shade600,
          icon: Icons.notifications_active,
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Menyimpan Pengingat',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
  }

  /// Persist a course-level customization.
  ///
  /// Absolute overrides (`custom_start_time` / `custom_end_time`) and the
  /// per-course reminder override are nullable columns, so switching a course
  /// back to its official schedule or to the global reminder has to clear
  /// them explicitly: `copyWith` cannot express a null.
  Future<void> _saveCourseCustomization(
    ScheduleModel schedule, {
    bool? autoPresence,
    int? timeOffsetMinutes,
    int? customDayOfWeek,
    String? customStartTime,
    String? customEndTime,
    bool clearAbsolute = false,
    int? reminderLeadMinutes,
    bool clearReminder = false,
    bool? reminderEnabled,
    bool clearReminderEnabled = false,
  }) async {
    try {
      final existing = _customizationFor(schedule);
      final base =
          existing ?? ScheduleCustomizationModel(scheduleId: schedule.id);

      final resolvedStart = clearAbsolute
          ? null
          : customStartTime ?? base.customStartTime;
      final resolvedEnd = clearAbsolute
          ? null
          : customEndTime ?? base.customEndTime;
      final hasAbsolute = resolvedStart != null && resolvedEnd != null;

      final model = ScheduleCustomizationModel(
        id: base.id,
        scheduleId: schedule.id,
        meetingId: null,
        timeOffsetMinutes: timeOffsetMinutes ?? base.timeOffsetMinutes,
        customDayOfWeek: hasAbsolute
            ? customDayOfWeek ?? base.customDayOfWeek ?? 1
            : null,
        customStartTime: hasAbsolute ? resolvedStart : null,
        customEndTime: hasAbsolute ? resolvedEnd : null,
        autoPresenceEnabled: autoPresence ?? base.autoPresenceEnabled,
        reminderLeadMinutes: clearReminder
            ? null
            : reminderLeadMinutes ?? base.reminderLeadMinutes,
        reminderEnabled: clearReminderEnabled
            ? null
            : reminderEnabled ?? base.reminderEnabled,
      );

      final saved = await _service.saveCustomization(model);
      if (mounted) {
        setState(() {
          _customizations = [
            ..._customizations.where(
              (c) => c.id != saved.id || saved.id == null,
            ),
            saved,
          ];
        });
        RefreshBus.instance.requestRefresh();
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Menyimpan Penyesuaian',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
  }

  /// Reset timing-only fields (offset, absolute override, reminder) for a
  /// course back to the official Simkuliah schedule while preserving
  /// `autoPresenceEnabled`. If nothing remains after clearing, the row is
  /// deleted entirely.
  Future<void> _resetCourseCustomization(ScheduleModel schedule) async {
    try {
      final existing = _customizationFor(schedule);
      if (existing == null) return;

      final keepAutoPresence = existing.autoPresenceEnabled;

      if (!keepAutoPresence) {
        // Nothing to preserve — delete the row entirely.
        if (existing.id != null) {
          await _service.deleteCustomization(existing.id!);
        }
        if (mounted) {
          setState(() {
            _customizations = _customizations
                .where((c) => c.id != existing.id)
                .toList();
          });
        }
      } else {
        // Keep auto-presence; clear only timing and reminder overrides.
        final saved = await _service.saveCustomization(
          ScheduleCustomizationModel(
            id: existing.id,
            scheduleId: schedule.id,
            autoPresenceEnabled: true,
          ),
        );
        if (mounted) {
          setState(() {
            _customizations = [
              ..._customizations.where((c) => c.id != saved.id),
              saved,
            ];
          });
        }
      }
      if (mounted) {
        RefreshBus.instance.requestRefresh();
        AppNotification.show(
          context,
          title: 'Jadwal Direset',
          message: keepAutoPresence
              ? '${schedule.courseName} kembali ke jadwal resmi; presensi otomatis tetap aktif.'
              : '${schedule.courseName} kembali ke jadwal resmi Simkuliah.',
          color: Colors.blueGrey,
          icon: Icons.restore,
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Mereset Jadwal',
          message: friendlyErrorMessage(error),
          color: Colors.red.shade600,
          icon: Icons.error_outline,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan & Automasi')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _schedules == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _schedules == null) {
      return ErrorStateView(
        title: 'Gagal memuat pengaturan',
        error: _error,
        onRetry: () => unawaited(_load(silent: false, force: true)),
      );
    }

    final schedules = _schedules ?? const <ScheduleModel>[];
    return RefreshIndicator(
      onRefresh: () => _load(silent: true, force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildGlobalReminderCard(context),
          const SizedBox(height: 16),
          Text(
            'Penyesuaian Mata Kuliah',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Belum ada mata kuliah terdaftar semester ini.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...schedules.map((s) => _buildCourseCard(context, s)),
        ],
      ),
    );
  }

  Widget _buildGlobalReminderCard(BuildContext context) {
    final current = _preferences?.defaultReminderMinutes ?? 15;
    final reminderEnabled = _preferences?.reminderEnabled ?? true;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Pengingat Masuk Kuliah (Global)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Switch(
                  value: reminderEnabled,
                  onChanged: (val) =>
                      unawaited(_saveGlobalReminderEnabled(val)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              reminderEnabled
                  ? 'Notifikasi pengingat dikirim $current menit sebelum kuliah dimulai.'
                  : 'Pengingat dinonaktifkan secara global.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            if (reminderEnabled) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._reminderTemplates.map(
                    (m) => ChoiceChip(
                      label: Text('${m}m'),
                      selected: current == m,
                      onSelected: (_) => unawaited(_saveGlobalReminder(m)),
                    ),
                  ),
                  ActionChip(
                    label: Text('Kustom (${current}m)'),
                    avatar: const Icon(Icons.edit, size: 16),
                    onPressed: () =>
                        unawaited(_showCustomReminderDialog(current)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomReminderDialog(int current) async {
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pengingat Kustom (Menit)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            suffixText: 'menit',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      await _saveGlobalReminder(result);
    }
  }

  /// Derive the active timing mode from the stored customization.
  _TimingMode _timingModeFor(ScheduleCustomizationModel? cust) {
    if (cust == null) return _TimingMode.official;
    if (cust.customStartTime != null && cust.customEndTime != null) {
      return _TimingMode.absolute;
    }
    if (cust.timeOffsetMinutes != 0) return _TimingMode.relative;
    return _TimingMode.official;
  }

  /// Trim a database time string to `HH:mm`.
  String _shortTime(String raw) {
    final match = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(raw);
    if (match == null) return raw;
    return '${match.group(1)}:${match.group(2)}';
  }

  /// Switch a course between official, relative, and absolute timing.
  Future<void> _selectTimingMode(
    ScheduleModel schedule,
    _TimingMode mode,
    ScheduleCustomizationModel? cust,
  ) async {
    final future = switch (mode) {
      _TimingMode.official => _saveCourseCustomization(
        schedule,
        timeOffsetMinutes: 0,
        clearAbsolute: true,
      ),
      _TimingMode.relative => _saveCourseCustomization(
        schedule,
        timeOffsetMinutes: (cust != null && cust.timeOffsetMinutes != 0)
            ? cust.timeOffsetMinutes
            : 15,
        clearAbsolute: true,
      ),
      _TimingMode.absolute => _saveCourseCustomization(
        schedule,
        customDayOfWeek: cust?.customDayOfWeek ?? 1,
        customStartTime: _shortTime(
          cust?.customStartTime ?? schedule.startTime,
        ),
        customEndTime: _shortTime(cust?.customEndTime ?? schedule.endTime),
      ),
    };
    await future;
  }

  /// Pick the absolute start or end time for a course.
  Future<void> _pickAbsoluteTime(
    ScheduleModel schedule, {
    required bool isStart,
  }) async {
    final cust = _customizationFor(schedule);
    final raw = isStart
        ? cust?.customStartTime ?? schedule.startTime
        : cust?.customEndTime ?? schedule.endTime;
    final parts = _shortTime(raw).split(':');
    final initial = TimeOfDay(
      hour: parts.isNotEmpty ? int.tryParse(parts.first) ?? 8 : 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;

    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final other = isStart
        ? cust?.customEndTime ?? schedule.endTime
        : cust?.customStartTime ?? schedule.startTime;

    await _saveCourseCustomization(
      schedule,
      customDayOfWeek: cust?.customDayOfWeek ?? 1,
      customStartTime: isStart ? formatted : _shortTime(other),
      customEndTime: isStart ? _shortTime(other) : formatted,
    );
  }

  Widget _buildCourseCard(BuildContext context, ScheduleModel schedule) {
    final cust = _customizationFor(schedule);
    final offset = cust?.timeOffsetMinutes ?? 0;
    final mode = _timingModeFor(cust);
    final enabledCount = _autoPresenceEnabledCount(schedule);
    final totalMeetings = schedule.meetings.length;

    // Effective reminder enabled: per-course override wins, falls back to global.
    final globalReminderEnabled = _preferences?.reminderEnabled ?? true;
    final courseReminderEnabled =
        cust?.reminderEnabled ?? globalReminderEnabled;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              schedule.courseName,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '${schedule.courseCode} · Kelas ${schedule.classGroup} · '
              '${_shortTime(schedule.startTime)} - '
              '${_shortTime(schedule.endTime)} WIB',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),

            // --- Auto-presence per-meeting selection (Fix #3) ---
            const Text(
              'Presensi Otomatis',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    totalMeetings == 0
                        ? 'Belum ada data pertemuan'
                        : enabledCount == 0
                        ? 'Tidak ada pertemuan yang dipilih'
                        : enabledCount == totalMeetings
                        ? 'Semua pertemuan ($totalMeetings) dipilih'
                        : '$enabledCount dari $totalMeetings pertemuan dipilih',
                    style: TextStyle(
                      fontSize: 12,
                      color: enabledCount > 0
                          ? Colors.amber.shade800
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: Icon(
                    Icons.bolt,
                    size: 16,
                    color: enabledCount > 0 ? Colors.amber.shade800 : null,
                  ),
                  label: const Text('Pilih Pertemuan'),
                  style: enabledCount > 0
                      ? OutlinedButton.styleFrom(
                          foregroundColor: Colors.amber.shade800,
                          side: BorderSide(color: Colors.amber.shade400),
                        )
                      : null,
                  onPressed: totalMeetings == 0
                      ? null
                      : () => unawaited(
                          _showAutoPresenceMeetingsDialog(context, schedule),
                        ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Text(
              'Penyesuaian Waktu',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SegmentedButton<_TimingMode>(
              segments: const [
                ButtonSegment(value: _TimingMode.official, label: Text('Asli')),
                ButtonSegment(
                  value: _TimingMode.relative,
                  label: Text('Relatif'),
                ),
                ButtonSegment(
                  value: _TimingMode.absolute,
                  label: Text('Pindah'),
                ),
              ],
              selected: {mode},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (selection) =>
                  unawaited(_selectTimingMode(schedule, selection.first, cust)),
            ),
            if (mode == _TimingMode.relative) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in const [-30, -15, 15, 30, 60, 120])
                    ChoiceChip(
                      label: Text('${o > 0 ? '+' : ''}${o}m'),
                      selected: offset == o,
                      onSelected: (_) => unawaited(
                        _saveCourseCustomization(
                          schedule,
                          timeOffsetMinutes: o,
                        ),
                      ),
                    ),
                  if (offset != 0 &&
                      !const [-30, -15, 15, 30, 60, 120].contains(offset))
                    ChoiceChip(
                      label: Text('${offset > 0 ? '+' : ''}${offset}m'),
                      selected: true,
                      onSelected: null,
                    ),
                ],
              ),
            ],
            if (mode == _TimingMode.absolute) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: cust?.customDayOfWeek ?? 1,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var day = 1; day <= 7; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text(_dayLabels[day - 1]),
                        ),
                    ],
                    onChanged: (day) {
                      if (day == null) return;
                      unawaited(
                        _saveCourseCustomization(
                          schedule,
                          customDayOfWeek: day,
                          customStartTime: _shortTime(
                            cust?.customStartTime ?? schedule.startTime,
                          ),
                          customEndTime: _shortTime(
                            cust?.customEndTime ?? schedule.endTime,
                          ),
                        ),
                      );
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      'Mulai '
                      '${_shortTime(cust?.customStartTime ?? schedule.startTime)}',
                    ),
                    onPressed: () =>
                        unawaited(_pickAbsoluteTime(schedule, isStart: true)),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      'Selesai '
                      '${_shortTime(cust?.customEndTime ?? schedule.endTime)}',
                    ),
                    onPressed: () =>
                        unawaited(_pickAbsoluteTime(schedule, isStart: false)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),
            const Text(
              'Pengingat Kuliah',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),

            // Per-course reminder override toggle (Fix #5).
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pengingat mata kuliah ini',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                // "Ikuti global" chip resets the per-course override.
                if (cust?.reminderEnabled != null)
                  TextButton(
                    onPressed: () => unawaited(
                      _saveCourseCustomization(
                        schedule,
                        clearReminderEnabled: true,
                      ),
                    ),
                    child: const Text('Ikuti global'),
                  ),
                Switch(
                  value: courseReminderEnabled,
                  onChanged: (val) => unawaited(
                    _saveCourseCustomization(schedule, reminderEnabled: val),
                  ),
                ),
              ],
            ),
            if (courseReminderEnabled) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Ikuti Global'),
                    selected: cust?.reminderLeadMinutes == null,
                    onSelected: (_) => unawaited(
                      _saveCourseCustomization(schedule, clearReminder: true),
                    ),
                  ),
                  for (final minutes in const [5, 10, 15, 30])
                    ChoiceChip(
                      label: Text('${minutes}m'),
                      selected: cust?.reminderLeadMinutes == minutes,
                      onSelected: (_) => unawaited(
                        _saveCourseCustomization(
                          schedule,
                          reminderLeadMinutes: minutes,
                        ),
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Reset Jadwal Asli'),
                onPressed: cust == null
                    ? null
                    : () => unawaited(_resetCourseCustomization(schedule)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for per-meeting auto-presence selection.
///
/// Shows a list of all meetings for the schedule with individual toggles and a
/// "Pilih Semua" / "Batalkan Semua" quick-action button.
class _AutoPresenceMeetingsDialog extends StatefulWidget {
  final ScheduleModel schedule;
  final Map<int, bool> initialEnabled;
  final void Function(int meetingId, bool enabled) onToggle;

  const _AutoPresenceMeetingsDialog({
    required this.schedule,
    required this.initialEnabled,
    required this.onToggle,
  });

  @override
  State<_AutoPresenceMeetingsDialog> createState() =>
      _AutoPresenceMeetingsDialogState();
}

class _AutoPresenceMeetingsDialogState
    extends State<_AutoPresenceMeetingsDialog> {
  late final Map<int, bool> _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = Map.from(widget.initialEnabled);
  }

  bool get _allEnabled =>
      widget.schedule.meetings.every((m) => _enabled[m.id] == true);

  void _toggleAll(bool enable) {
    for (final m in widget.schedule.meetings) {
      if ((_enabled[m.id] ?? false) != enable) {
        setState(() => _enabled[m.id] = enable);
        widget.onToggle(m.id, enable);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meetings = widget.schedule.meetings;
    final enabledCount = _enabled.values.where((v) => v).length;

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auto-Absen — ${widget.schedule.courseName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$enabledCount dari ${meetings.length} pertemuan aktif',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Pilih Semua" / "Batalkan Semua" quick-action.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _toggleAll(!_allEnabled),
                    child: Text(_allEnabled ? 'Batalkan Semua' : 'Pilih Semua'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: meetings.length,
                itemBuilder: (_, i) {
                  final meeting = meetings[i];
                  final isEnabled = _enabled[meeting.id] ?? false;
                  return SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Pertemuan ${meeting.meetingNumber}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: meeting.meetingDate.isNotEmpty
                        ? Text(
                            meeting.meetingDate,
                            style: const TextStyle(fontSize: 11),
                          )
                        : null,
                    value: isEnabled,
                    onChanged: (val) {
                      setState(() => _enabled[meeting.id] = val);
                      widget.onToggle(meeting.id, val);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Selesai'),
        ),
      ],
    );
  }
}
