import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/app_theme.dart';
import 'package:povarnya/presentation/recipe_search_screen.dart';

void main() {
  testWidgets('recipe order is placed beside fasting filters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(defaultAppThemeName),
        home: RecipeSearchScreen(
          onCreateRecipe: () {},
          onOpenRecipe: (_) {},
          onToggleTheme: () {},
          themeLabel: 'Тёмная тема',
        ),
      ),
    );
    await tester.pump();

    final order = find.byKey(const ValueKey('recipe-order-toggle'));
    expect(order, findsOneWidget);
    expect(
      find.ancestor(of: order, matching: find.byType(Wrap)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: order, matching: find.byType(TextField)),
      findsNothing,
    );

    final microphone = find.byKey(const ValueKey('recipe-search-microphone'));
    expect(
      find.ancestor(of: microphone, matching: find.byType(TextField)),
      findsOneWidget,
    );
  });
}
