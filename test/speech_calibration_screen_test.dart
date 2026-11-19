import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/presentation/speech_calibration_screen.dart';

void main() {
  testWidgets('shows one ten-minute speech calibration procedure', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SpeechCalibrationScreen()));

    expect(find.text('Настройка распознавания речи'), findsOneWidget);
    expect(find.text('Персональная настройка около 10 минут'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('start-speech-calibration')),
      findsOneWidget,
    );
  });
}
