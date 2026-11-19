import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/domain/catalog.dart';
import 'package:povarnya/services/speech_calibration_prompts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'calibration uses a varied corpus from modules and recipe steps',
    () async {
      final texts = await createSpeechCalibrationTexts(random: Random(17));

      expect(texts.modules, hasLength(24));
      expect(texts.modules.toSet(), hasLength(24));
      expect(
        texts.modules.every(
          (name) => CatalogCards.all.any((module) => module.nominative == name),
        ),
        isTrue,
      );
      expect(texts.trainingSteps, hasLength(14));
      expect(texts.validationSteps, hasLength(10));
      expect(
        texts.trainingSteps.toSet().intersection(texts.validationSteps.toSet()),
        isEmpty,
      );

      final closeModules = <(String, String)>[];
      for (var left = 0; left < texts.modules.length; left++) {
        for (var right = left + 1; right < texts.modules.length; right++) {
          if (speechPhoneticSimilarity(
                texts.modules[left],
                texts.modules[right],
              ) >=
              .72) {
            closeModules.add((texts.modules[left], texts.modules[right]));
          }
        }
      }
      expect(
        closeModules,
        isEmpty,
        reason: 'Слишком похожие модули: $closeModules',
      );

      final allSteps = [...texts.trainingSteps, ...texts.validationSteps];
      final closeSteps = <(String, String)>[];
      for (var left = 0; left < allSteps.length; left++) {
        for (var right = left + 1; right < allSteps.length; right++) {
          if (speechPhoneticSimilarity(allSteps[left], allSteps[right]) >=
              .73) {
            closeSteps.add((allSteps[left], allSteps[right]));
          }
        }
      }
      expect(
        closeSteps.length,
        lessThanOrEqualTo(2),
        reason: 'Слишком похожие шаги: $closeSteps',
      );
    },
  );

  test('different runs change the controlled random selection', () async {
    final first = await createSpeechCalibrationTexts(random: Random(1));
    final second = await createSpeechCalibrationTexts(random: Random(2));

    expect(first.modules, isNot(equals(second.modules)));
    expect(first.trainingSteps, isNot(equals(second.trainingSteps)));
  });

  test('phonetic comparison detects close Russian pronunciation', () {
    expect(speechPhoneticSimilarity('масло', 'мясо'), greaterThan(.7));
    expect(speechPhoneticSimilarity('дуршлаг', 'картофель'), lessThan(.5));
  });
}
