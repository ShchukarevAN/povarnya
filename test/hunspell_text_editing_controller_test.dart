import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/services/hunspell_spell_check_service.dart';

class _FakeSpellCheckService implements SpellCheckService {
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => <SuggestionSpan>[
    SuggestionSpan(TextRange(start: 0, end: text.length), const <String>[]),
  ];
}

void main() {
  testWidgets('underlines a misspelled word while the cursor is inside it', (
    tester,
  ) async {
    final controller = HunspellTextEditingController(
      spellCheckService: _FakeSpellCheckService(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    controller.value = const TextEditingValue(
      text: 'ашибка',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();

    expect(controller.misspelledSpans, hasLength(1));
    final textSpan = controller.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      style: const TextStyle(),
      withComposing: true,
    );
    final misspelled = textSpan.children!.whereType<TextSpan>().singleWhere(
      (span) => span.text == 'ашибка',
    );
    expect(misspelled.style?.decoration, TextDecoration.underline);
    expect(misspelled.style?.decorationStyle, TextDecorationStyle.wavy);
  });
}
