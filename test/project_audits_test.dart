import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/presentation/project_analyzer_screen.dart';

void main() {
  test('целевые проверки проекта проходят', () async {
    final snapshot = await ProjectAnalyzerService(Directory.current.path)
        .scanProject();
    final failures = snapshot.audits
        .where((audit) => !audit.passed)
        .map((audit) => '${audit.title}: ${audit.details}')
        .toList();

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
