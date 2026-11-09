/// Purpose: Semester matrix table view displaying all courses and 16 meeting tiles horizontally.
/// Data & Logic Flow: Fetches semester schedules with nested meetings, renders interactive matrix cells.
/// Key Components: SemesterMatrixView
import 'package:flutter/material.dart';

import '../models/meeting_model.dart';
import '../models/schedule_model.dart';
import '../services/presence_service.dart';
import 'widgets/meeting_grid_tile.dart';

export 'widgets/meeting_grid_tile.dart';

/// Semester presence matrix view: displays all semester courses and their 16
/// meetings arranged horizontally in a clean matrix table, matching Simkuliah portal.
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
  late Future<List<ScheduleModel>> _matrixFuture;
  late PresenceService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.presenceService ?? PresenceService();
    if (!widget.testMode) {
      _loadMatrix();
    }
  }

  void _loadMatrix() {
    setState(() {
      _matrixFuture = _service.fetchSemesterMatrix();
    });
  }

  static const int _meetingsPerCourse = 16;
  static const double _attendanceThreshold = 0.75;

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

  double _attendancePercentage(List<MeetingModel> meetings) {
    if (meetings.isEmpty) return 0.0;
    final attended = meetings.where((m) => m.isAttended).length;
    return attended / _meetingsPerCourse;
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
            width: 240,
            child: Text(
              'Mata Kuliah',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...List.generate(_meetingsPerCourse, (i) {
            return Container(
              width: 38,
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
          const SizedBox(width: 12),
          const SizedBox(
            width: 150,
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

    final meetings = List.generate(_meetingsPerCourse, (index) {
      final number = index + 1;
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

    final percentage = _attendancePercentage(meetings);
    final attendedCount = meetings.where((m) => m.isAttended).length;
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
            width: 240,
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
              width: 38,
              alignment: Alignment.center,
              child: MeetingGridTile(
                meeting: m,
                compact: true,
                presenceService: _service,
                onOverrideChanged: _loadMatrix,
              ),
            );
          }),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$attendedCount/$_meetingsPerCourse hadir',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPassing ? Colors.green : Colors.orange,
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
      appBar: AppBar(
        title: const Text('Matriks Semester'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: _loadMatrix,
          ),
        ],
      ),
      body: FutureBuilder<List<ScheduleModel>>(
        future: _matrixFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text('Gagal memuat matriks semester:\n${snapshot.error}'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                      onPressed: _loadMatrix,
                    ),
                  ],
                ),
              ),
            );
          }

          final courses = snapshot.data ?? const <ScheduleModel>[];
          if (courses.isEmpty) {
            return const Center(child: Text('Belum ada data jadwal semester.'));
          }

          return SingleChildScrollView(
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
          );
        },
      ),
    );
  }
}
