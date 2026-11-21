/// Purpose: Weekly class-entry timetable ("Jadwal Masuk") grouped by weekday.
/// Data & Logic Flow: Fetches the semester schedules with nested meetings, derives each course's class day from its meeting dates (Simkuliah carries no explicit day field), resolves the effective lecture window from any course-level customization, and silently refetches on refresh-bus events.
/// Key Components: WeeklyTimetable
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/load_epoch_guard.dart';
import '../../core/refresh_bus.dart';
import '../../models/schedule_customization_model.dart';
import '../../models/schedule_model.dart';
import '../../services/presence_service.dart';
import 'error_state_view.dart';

/// Indonesian day names indexed by `DateTime.weekday` (1 = Monday).
const List<String> _dayNames = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

/// Weekly class-entry timetable: one section per weekday listing the courses
/// scheduled that day with their effective lecture window. Distinct from the
/// presence feed ("Jadwal Absen"), which is about today's attendance windows.
class WeeklyTimetable extends StatefulWidget {
  final PresenceService? presenceService;

  const WeeklyTimetable({super.key, this.presenceService});

  @override
  State<WeeklyTimetable> createState() => _WeeklyTimetableState();
}

class _WeeklyTimetableState extends State<WeeklyTimetable> {
  late final PresenceService _service;
  final LoadEpochGuard _loadGuard = LoadEpochGuard();
  StreamSubscription<void>? _refreshSub;
  List<ScheduleModel>? _courses;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    unawaited(_load(silent: false));
    _refreshSub = RefreshBus.instance.stream.listen(
      (_) => unawaited(_load(silent: _courses != null, force: true)),
    );
  }

  @override
  void dispose() {
    unawaited(_refreshSub?.cancel());
    super.dispose();
  }

  /// Fetch the semester schedules. [silent] keeps cached data on screen and
  /// swaps it in place when the fetch completes.
  Future<void> _load({required bool silent, bool force = false}) async {
    final epoch = _loadGuard.tryBegin(
      timeout: _service.requestTimeout,
      force: force,
    );
    if (epoch == null) return;
    if (!silent || _courses == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final courses = await _service.fetchSemesterMatrix();
      if (!mounted || !_loadGuard.isCurrent(epoch)) return;
      setState(() {
        _courses = courses;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || !_loadGuard.isCurrent(epoch)) return;
      if (_courses == null) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    } finally {
      _loadGuard.complete(epoch);
    }
  }

  /// The course's class day: the most common weekday across its meetings'
  /// dates. Returns null when no meeting date is parseable.
  int? _classDayOf(ScheduleModel schedule) {
    final counts = <int, int>{};
    for (final meeting in schedule.meetings) {
      final date = DateTime.tryParse(meeting.meetingDate);
      if (date == null) continue;
      counts.update(date.weekday, (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// Trim a database time string to `HH:mm`.
  String _shortTime(String raw) {
    final match = RegExp(r'(\d{2})[:.](\d{2})').firstMatch(raw);
    if (match == null) return raw;
    return '${match.group(1)}:${match.group(2)}';
  }

  /// Shift an `HH:mm` string by a signed minute count.
  String? _shiftTime(String hhmm, int minutes) {
    final match = RegExp(r'(\d{2}):(\d{2})').firstMatch(hhmm);
    if (match == null) return null;
    final base = DateTime(
      2000,
      1,
      1,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
    final shifted = base.add(Duration(minutes: minutes));
    final hour = shifted.hour.toString().padLeft(2, '0');
    final minute = shifted.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// The first customization of the course that actually modifies the lecture
  /// window (absolute override or a non-zero offset). Per-meeting auto-absen
  /// rows carry no timing change and are skipped.
  ScheduleCustomizationModel? _timeModificationOf(ScheduleModel schedule) {
    for (final meeting in schedule.meetings) {
      final customization = meeting.customization;
      if (customization == null) continue;
      final absolute =
          customization.customStartTime != null &&
          customization.customEndTime != null;
      if (absolute || customization.timeOffsetMinutes != 0) {
        return customization;
      }
    }
    return null;
  }

  /// Effective lecture window label: the customized time wins, the official
  /// portal window stays visible as a secondary hint when shifted.
  String _timeLabel(ScheduleModel schedule) {
    final official =
        '${_shortTime(schedule.startTime)} - ${_shortTime(schedule.endTime)} WIB';
    final modification = _timeModificationOf(schedule);
    if (modification == null) return official;

    final customStart = modification.customStartTime;
    final customEnd = modification.customEndTime;
    if (customStart != null && customEnd != null) {
      return '${_shortTime(customStart)} - ${_shortTime(customEnd)} WIB '
          '(Portal: ${_shortTime(schedule.startTime)} - '
          '${_shortTime(schedule.endTime)})';
    }

    final offset = modification.timeOffsetMinutes;
    final shiftedStart = _shiftTime(_shortTime(schedule.startTime), offset);
    final shiftedEnd = _shiftTime(_shortTime(schedule.endTime), offset);
    if (shiftedStart == null || shiftedEnd == null) return official;
    return '$shiftedStart - $shiftedEnd WIB '
        '(Portal: ${_shortTime(schedule.startTime)} - '
        '${_shortTime(schedule.endTime)})';
  }

  /// Effective start time as minutes since midnight, for within-day sorting.
  int _sortKey(ScheduleModel schedule) {
    final modification = _timeModificationOf(schedule);
    final raw = modification?.customStartTime ?? schedule.startTime;
    final match = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(raw);
    if (match == null) return 24 * 60;
    return (int.tryParse(match.group(1)!) ?? 0) * 60 +
        (int.tryParse(match.group(2)!) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _courses == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _courses == null) {
      return ErrorStateView(
        title: 'Gagal memuat jadwal mingguan',
        error: _error,
        onRetry: () => unawaited(_load(silent: false, force: true)),
      );
    }

    final courses = _courses ?? const <ScheduleModel>[];
    if (courses.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada jadwal semester.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Group courses by class day; courses without a resolvable day fall into
    // an "unknown" bucket rendered last under a neutral header.
    final byDay = <int, List<ScheduleModel>>{};
    final unknown = <ScheduleModel>[];
    for (final course in courses) {
      final day = _classDayOf(course);
      if (day == null) {
        unknown.add(course);
      } else {
        byDay.putIfAbsent(day, () => []).add(course);
      }
    }
    for (final list in byDay.values) {
      list.sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    }

    final todayWeekday = DateTime.now().weekday;
    final sections = <Widget>[];
    for (var day = 1; day <= 7; day++) {
      final dayCourses = byDay[day];
      if (dayCourses == null || dayCourses.isEmpty) continue;
      sections.add(
        _buildDaySection(context, day, dayCourses, day == todayWeekday),
      );
    }
    if (unknown.isNotEmpty) {
      sections.add(_buildDaySection(context, null, unknown, false));
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true, force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            sections[i],
          ],
        ],
      ),
    );
  }

  Widget _buildDaySection(
    BuildContext context,
    int? day,
    List<ScheduleModel> dayCourses,
    bool isToday,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              day == null ? 'Hari Tidak Diketahui' : _dayNames[day - 1],
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isToday ? theme.colorScheme.primary : null,
              ),
            ),
            if (isToday) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Hari ini',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 8),
        for (final course in dayCourses)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCourseTile(context, course),
          ),
      ],
    );
  }

  Widget _buildCourseTile(BuildContext context, ScheduleModel course) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.courseName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${course.courseCode} · Kelas ${course.classGroup}'
                  '${course.room.isNotEmpty ? ' · ${course.room}' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _timeLabel(course),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (course.lecturerName.isNotEmpty &&
                  course.lecturerName.toLowerCase() != 'dosen')
                Text(
                  course.lecturerName,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
