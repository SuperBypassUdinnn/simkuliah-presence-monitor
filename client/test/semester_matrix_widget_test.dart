import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simkuliah_client/views/semester_matrix_view.dart';

void main() {
  testWidgets('SemesterMatrixView renders 16 meeting indicator tiles', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SemesterMatrixView(testMode: true)),
    ));

    expect(find.byType(MeetingGridTile), findsNWidgets(16));
  });
}
