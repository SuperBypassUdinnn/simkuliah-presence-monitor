/// Purpose: Semester matrix table view displaying all courses and their meeting tiles on a shared 16-column grid.
/// Data & Logic Flow: Fetches semester schedules with nested meetings, sizes each row by its real Simkuliah semester length, renders interactive matrix cells, and silently refetches on refresh-bus events.
/// Key Components: SemesterMatrixView
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/load_epoch_guard.dart';
import '../core/refresh_bus.dart';
import '../models/meeting_model.dart';
import '../models/schedule_model.dart';
import '../services/presence_service.dart';
import 'widgets/error_state_view.dart';
import 'widgets/meeting_grid_tile.dart';

export 'widgets/meeting_grid_tile.dart';

/// Semester presence matrix view: displays all semester courses and their
/// meetings arranged horizontally in a clean matrix table, matching Simkuliah
/// portal. Courses whose Simkuliah matrix is shorter than 16 meetings (e.g.
/// praktikum courses ending at 12) render their out-of-range columns as
/// neutral empty slots so every row still spans the same grid.
class SemesterMatrixView extends StatefulWidget {
  final bool testMode;
  final PresenceService? presenceService;

  const SemesterMatrixView({
    super.key,
    this.testMode = false,
    this.presenceService,
  });

  @override
  State<SemesterMatrixView> createState() => _SemesterMatrixViewState();
}

class _SemesterMatrixViewState extends State<SemesterMatrixView> {
  final LoadEpochGuard _loadGuard = LoadEpochGuard();
  StreamSubscription<void>? _refreshSub;
  List<ScheduleModel>? _courses;
  bool _loading = true;
  Object? _error;
  late PresenceService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    if (!widget.testMode) {
      unawaited(_loadMatrix(silent: false));
      _refreshSub = RefreshBus.instance.stream.listen(
        (_) => unawaited(_loadMatrix(silent: _courses != null, force: true)),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_refreshSub?.cancel());
    super.dispose();
  }

  /// Fetch the semester matrix. [silent] keeps any cached data on screen and
  /// swaps it in place when the fetch completes, so a focus-driven refresh
  /// never flashes a loading spinner.
  Future<void> _loadMatrix({required bool silent, bool force = false}) async {
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
      // A failed silent refresh keeps the stale view; only when no cached
      // data exists do we surface the error screen.
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

  static const int _meetingsPerCourse = 16;
  static const double _attendanceThreshold = 0.75;

  // Column layout shared by the header and every course row, sized so the
  // 16-column grid fits the default 1280x720 desktop window next to the
  // 250px sidebar: 250 sidebar + 24 page padding + 16 row padding + 190
  // name + 560 meetings + 12 gap + 130 recap = 1182 <= 1280.
  static const double _nameColumnWidth = 190;
  static const double _meetingColumnWidth = 35;
  static const double _recapColumnWidth = 130;
  static const double _recapGap = 12;

  List<MeetingModel> _mockMeetings(String courseName) {
    final statuses = <String>[
      'hadir',
      'hadir',
      'hadir',
      'tidak_hadir',
      'hadir',
      'hadir',
      'hadir',
      'tidak_hadir',
      'hadir',
      'hadir',
      'pending',
      'pending',
      'pending',
      'pending',
      'pending',
      'pending',
    ];
    return List.generate(_meetingsPerCourse, (index) {
      return MeetingModel(
        id: index + 1,
        courseName: courseName,
        meetingNumber: index + 1,
        simkuliahStatus: statuses[index],
        isPresenceOpen: false,
      );
    });
  }

  double _attendancePercentage(List<MeetingModel> meetings, int total) {
    if (meetings.isEmpty || total <= 0) return 0.0;
    final attended = meetings.where((m) => m.isAttended).length;
    return attended / total;
  }

  Widget _buildTableHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: _nameColumnWidth,
            child: Text(
              'Mata Kuliah',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...List.generate(_meetingsPerCourse, (i) {
            return Container(
              width: _meetingColumnWidth,
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            );
          }),
          const SizedBox(width: _recapGap),
          const SizedBox(
            width: _recapColumnWidth,
            child: Text(
              'Rekap Kehadiran',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseRow(BuildContext context, ScheduleModel course) {
    final byNumber = <int, MeetingModel>{};
    for (final meeting in course.meetings) {
      byNumber[meeting.meetingNumber] = meeting;
    }

    // Simkuliah publishes each course's full semester column set up front:
    // theory courses span 16 meetings while praktikum courses end at 12.
    // The highest synced meeting number is therefore that course's real
    // semester length; columns beyond it do not exist for the course and
    // render as neutral empty slots so every row still spans the same
    // 16-column grid as the header.
    final syncedMax = course.meetings.fold<int>(
      0,
      (maxNumber, meeting) =>
          meeting.meetingNumber > maxNumber ? meeting.meetingNumber : maxNumber,
    );
    final semesterLength = syncedMax == 0 ? _meetingsPerCourse : syncedMax;

    final meetings = List<MeetingModel?>.generate(_meetingsPerCourse, (index) {
      final number = index + 1;
      if (number > semesterLength) return null;
      return byNumber[number] ??
          MeetingModel(
            id: 0,
            courseName: course.courseName,
            courseCode: course.courseCode,
            classGroup: course.classGroup,
            lecturerName: course.lecturerName,
            room: course.room,
            startTime: course.startTime,
            endTime: course.endTime,
            meetingNumber: number,
            simkuliahStatus: 'Pending',
            isPresenceOpen: false,
          );
    });

    final realMeetings = meetings.whereType<MeetingModel>().toList();
    final percentage = _attendancePercentage(realMeetings, semesterLength);
    final attendedCount = realMeetings.where((m) => m.isAttended).length;
    final isPassing = percentage >= _attendanceThreshold;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _nameColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                  '${course.courseCode} · Kelas ${course.classGroup}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          ...meetings.map((m) {
            return Container(
              width: _meetingColumnWidth,
              alignment: Alignment.center,
              child: m == null
                  ? Text(
                      '–',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600.withValues(alpha: 0.4),
                      ),
                    )
                  : MeetingGridTile(
                      meeting: m,
                      compact: true,
                      presenceService: _service,
                      onOverrideChanged: () =>
                          unawaited(_loadMatrix(silent: true, force: true)),
                    ),
            );
          }),
          const SizedBox(width: _recapGap),
          SizedBox(
            width: _recapColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Flexible so a long recap (or an enlarged system text
                    // scale) truncates instead of overflowing the 150px
                    // recap column.
                    Flexible(
                      child: Text(
                        '$attendedCount/$semesterLength hadir',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPassing ? Colors.green : Colors.orange,
                        ),
                      ),
                    ),
                    Text(
                      '${(percentage * 100).round()}%',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPassing ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.testMode) {
      final mock = _mockMeetings('Pemrograman Berorientasi Objek');
      return Scaffold(
        appBar: AppBar(title: const Text('Matriks Semester')),
        body: SingleChildScrollView(
          child: Column(
            children: mock.map((m) => MeetingGridTile(meeting: m)).toList(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Matriks Semester')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _courses == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _courses == null) {
      return ErrorStateView(
        title: 'Gagal memuat matriks semester',
        error: _error,
        onRetry: () => unawaited(_loadMatrix(silent: false, force: true)),
      );
    }

    final courses = _courses ?? const <ScheduleModel>[];
    if (courses.isEmpty) {
      return const Center(child: Text('Belum ada data jadwal semester.'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadMatrix(silent: true, force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTableHeader(context),
              const SizedBox(height: 6),
              ...courses.map((course) => _buildCourseRow(context, course)),
            ],
          ),
        ),
      ),
    );
  }
}
