import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/services/silero_tts_service.dart';

void main() {
  group('SileroTtsService.normalizeRecipeText', () {
    test('склоняет кухонные единицы после числа', () {
      expect(
        SileroTtsService.normalizeRecipeText(
          'Взять 1 г, 2 г, 5 г, 21 г, 1 шт., 2 шт., 5 шт. и 200мл воды.',
        ),
        'Взять один грамм, два грамма, пять граммов, '
        'двадцать один грамм, одна штука, две штуки, пять штук '
        'и двести миллилитров воды.',
      );
    });

    test('различает миллилитры и миллиметры', () {
      expect(
        SileroTtsService.normalizeRecipeText(
          'Влить 50 мл и нарезать кубиками 8–10 мм при толщине 2 см.',
        ),
        'Влить пятьдесят миллилитров и нарезать кубиками '
        'восемь – десять миллиметров при толщине два сантиметра.',
      );
    });

    test('раскрывает температуру, проценты и ложки', () {
      expect(
        SileroTtsService.normalizeRecipeText(
          'Выпекать при 180 °C; добавить ½ ч. л. соли и 35%.',
        ),
        'Выпекать при сто восемьдесят градусов Цельсия; '
        'добавить половина чайной ложки соли и тридцать пять процентов.',
      );
    });

    test('понимает разделители тысяч', () {
      expect(
        SileroTtsService.normalizeRecipeText('Влить 1 500 мл воды.'),
        'Влить одна тысяча пятьсот миллилитров воды.',
      );
    });
  });
}
