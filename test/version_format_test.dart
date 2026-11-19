import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pubspec version has the strict 0.x.y form without build metadata',
    () async {
      final pubspec = await File('pubspec.yaml').readAsString();
      final versionLines = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).allMatches(pubspec).toList();

      expect(versionLines, hasLength(1));
      expect(
        versionLines.single.group(1),
        matches(RegExp(r'^0\.(?:0|[1-9]\d{0,2})\.(?:0|[1-9]\d{0,2})$')),
        reason: 'Версия обязана иметь вид 0.x.y без суффикса +build.',
      );
    },
  );
}
