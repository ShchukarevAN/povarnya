import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/services/recipe_voice_guide.dart';

void main() {
  group('parseRecipeVoiceCommand', () {
    test('recognizes next-step variants inside a natural phrase', () {
      expect(
        parseRecipeVoiceCommand('Ну, давай дальше, пожалуйста'),
        RecipeVoiceCommand.next,
      );
      expect(parseRecipeVoiceCommand('Следующий шаг'), RecipeVoiceCommand.next);
    });

    test('recognizes repeat, previous, and finish variants', () {
      expect(parseRecipeVoiceCommand('Ещё раз'), RecipeVoiceCommand.repeat);
      expect(
        parseRecipeVoiceCommand('Вернись назад'),
        RecipeVoiceCommand.previous,
      );
      expect(
        parseRecipeVoiceCommand('Всё, закончили'),
        RecipeVoiceCommand.finish,
      );
    });

    test('does not mistake unrelated speech for a command', () {
      expect(
        parseRecipeVoiceCommand('Добавь соль и перемешай'),
        RecipeVoiceCommand.unknown,
      );
    });
  });
}
