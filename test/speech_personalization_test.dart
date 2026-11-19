import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/services/speech_personalization.dart';

void main() {
  test('applies a repeated personal pronunciation correction', () {
    expect(
      applySpeechPersonalization(
        'каре андр',
        personalWords: const <String>[],
        corrections: const <String, String>{'каре андр': 'кориандр'},
      ),
      'кориандр',
    );
  });

  test('repairs a unique close personal term', () {
    expect(
      applySpeechPersonalization(
        'добавить папреку',
        personalWords: const <String>['паприка'],
        corrections: const <String, String>{},
      ),
      'добавить паприка',
    );
  });

  test('computes word errors for calibration validation', () {
    expect(
      speechWordDistance('добавить соль и перец', 'добавить соль перец'),
      1,
    );
  });
}
