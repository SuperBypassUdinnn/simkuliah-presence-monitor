import 'package:flutter/material.dart';

import '../models/meeting_model.dart';
import '../models/schedule_model.dart';
import '../services/presence_service.dart';
import 'widgets/meeting_grid_tile.dart';

export 'widgets/meeting_grid_tile.dart';

/// Semester presence matrix: one row per enrolled course showing the course
/// name, an attendance progress bar with a 75% threshold marker, and a tile
/// for each meeting of the semester.
///
/// When [testMode] is true a mock course with exactly 16 meetings is rendered
/// without touching the network, which is useful for offline previews and
/// widget tests. Otherwise courses and meetings are fetched from
/// [presenceService] (or [`PresenceService`] when omitted).
///
/// The semester matrix future is initialized once in [State.initState] so
/// that rebuilds do not re-trigger the network fetch.
class SemesterMatrixView extends StatefulWidget {
  /// When true, renders a mock course with 16 meetings without calling the
  /// network.
  final bool testMode;

  /// Service used to fetch courses and meetings. Defaults to
  /// [`PresenceService`] when omitted.
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
  /// Future resolving to the enrolled courses. Initialized once in
  /// [initState] so rebuilds do not re-trigger the network fetch.
  late Future<List<ScheduleModel>> _matrixFuture;

  /// Presence service used for live-mode fetches. Only set in live mode.
  late PresenceService _service;

  @override
  void initState() {
    super.initState();
    if (!widget.testMode) {
      _service = widget.presenceService ?? PresenceService();
      _matrixFuture = _service.fetchSemesterMatrix();
    }
  }

  /// Number of meetings per course in the semester matrix.
  static const int _meetingsPerCourse = 16;

  /// Minimum attendance fraction expected of students (75%).
  static const double _attendanceThreshold = 0.75;

  /// Mock meetings for test mode: meetings 1..16 with a mix of statuses so
  /// the progress bar, threshold marker, and all five status colors are
  /// exercised.
  List<MeetingModel> _mockMeetings(String courseName) {
    final statuses = <String>[
      'hadir',
      'hadir',
      'hadir',
      'hadir',
      'izin',
      'izin',
      'sakit',
      'alpa',
      'pending',
      'pending',
      'pending',
      'pending',
      'hadir',
      'pending',
      'izin',
      'sakit',
    ];
    return List.generate(_meetingsPerCourse, (index) {
      final number = index + 1;
      return MeetingModel(
        id: number,
        courseName: courseName,
        meetingNumber: number,
        meetingDate: '2026-11-${(number % 28 + 1).toString().padLeft(2, '0')}',
        simkuliahStatus: statuses[index],
        isPresenceOpen: false,
      );
    });
  }

  /// Fraction of meetings with status Hadir, clamped to 0.0-1.0.
  double _attendancePercentage(List<MeetingModel> meetings) {
    if (meetings.isEmpty) return 0.0;
    final hadir = meetings
        .where((m) => m.effectiveStatus.toLowerCase() == 'hadir')
        .length;
    return (hadir / meetings.length).clamp(0.0, 1.0);
  }

  /// Attendance progress bar with a vertical marker at the 75% threshold.
  Widget _attendanceBar(BuildContext context, double percentage) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final thresholdX = constraints.maxWidth * _attendanceThreshold;
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            LinearProgressIndicator(
              value: percentage,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Colors.green),
            ),
            Positioned(
              left: thresholdX - 1,
              top: 0,
              bottom: 0,
              width: 2,
              child: Container(
                color: Colors.red,
                margin: const EdgeInsets.symmetric(horizontal: 1),
              ),
            ),
            Positioned(
              left: thresholdX.clamp(0, constraints.maxWidth - 14),
              top: -18,
              child: const Text(
                '75% target',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Grid of meeting tiles for one course, always showing [_meetingsPerCourse]
  /// tiles numbered 1..16.
  Widget _meetingGrid(List<MeetingModel> meetings) {
    final byNumber = <int, MeetingModel>{};
    for (final meeting in meetings) {
      byNumber[meeting.meetingNumber] = meeting;
    }
    final tiles = List.generate(_meetingsPerCourse, (index) {
      final number = index + 1;
      return MeetingGridTile(meeting: byNumber[number] ?? _placeholder(number));
    });
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.72,
      children: tiles,
    );
  }

  /// Placeholder pending meeting used when a course has fewer than 16 meetings
  /// loaded, so the matrix always shows a complete 1..16 grid.
  MeetingModel _placeholder(int number) {
    return MeetingModel(
      id: 0,
      courseName: '',
      meetingNumber: number,
      simkuliahStatus: 'Pending',
      isPresenceOpen: false,
    );
  }

  /// One course section: name, attendance bar, and meeting grid.
  Widget _courseSection(
    BuildContext context,
    String courseName,
    List<MeetingModel> meetings,
  ) {
    final percentage = _attendancePercentage(meetings);
    final hadir = meetings
        .where((m) => m.effectiveStatus.toLowerCase() == 'hadir')
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(courseName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${(percentage * 100).round()}% hadir',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  '$hadir/${meetings.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _attendanceBar(context, percentage),
            const SizedBox(height: 12),
            Text('Pertemuan', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            _meetingGrid(meetings),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Test mode renders a mock course without touching Supabase, which is
    // unavailable in widget tests.
    if (widget.testMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Matriks Semester')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: _courseSection(
            context,
            'Pemrograman Berorientasi Objek',
            _mockMeetings('Pemrograman Berorientasi Objek'),
          ),
        ),
      );
    }

    // Live mode: courses are fetched once via the memoized [_matrixFuture],
    // so rebuilds do not re-trigger the network request.
    return Scaffold(
      appBar: AppBar(title: const Text('Matriks Semester')),
      body: FutureBuilder<List<ScheduleModel>>(
        future: _matrixFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat jadwal: ${snapshot.error}'),
            );
          }
          final schedules = snapshot.data ?? const <ScheduleModel>[];
          if (schedules.isEmpty) {
            return const Center(child: Text('Belum ada jadwal kuliah.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: schedules.length,
            itemBuilder: (context, index) {
              final schedule = schedules[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _courseSectionFuture(context, _service, schedule),
              );
            },
          );
        },
      ),
    );
  }

  /// Course section for live mode that fetches the meetings of one schedule.
  Widget _courseSectionFuture(
    BuildContext context,
    PresenceService service,
    ScheduleModel schedule,
  ) {
    return FutureBuilder<List<MeetingModel>>(
      future: service.fetchMeetingsForSchedule(scheduleId: schedule.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.courseName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Gagal memuat pertemuan untuk ${schedule.courseName}: ${snapshot.error}',
              ),
            ),
          );
        }
        final meetings = snapshot.data ?? const <MeetingModel>[];
        return _courseSection(context, schedule.courseName, meetings);
      },
    );
  }
}
