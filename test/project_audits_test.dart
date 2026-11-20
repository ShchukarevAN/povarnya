import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/domain/catalog.dart';
import 'package:povarnya/domain/recipe_node.dart';
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

  test('в каждом встроенном рецепте id узлов уникальны', () {
    for (final recipe in catalogRecipes) {
      final seen = <String>{};
      final duplicates = <String>{};

      void visit(RecipeNode node) {
        if (!seen.add(node.id)) duplicates.add(node.id);
        for (final child in node.children) {
          visit(child);
        }
      }

      for (final step in recipe.buildSteps()) {
        visit(step);
      }
      expect(
        duplicates,
        isEmpty,
        reason: 'Дубли id в рецепте «${recipe.title}»: $duplicates',
      );
    }
  });

  test('запеканка добавляет просеянную заготовку без дубля муки', () {
    final recipe = catalogRecipes.singleWhere(
      (item) => item.catalogKey == 'curd-casserole-apples',
    );
    final steps = recipe.buildSteps();
    final flourNodes = <RecipeNode>[];

    void visit(RecipeNode node) {
      if (node.card.id == CatalogCards.flour.id) flourNodes.add(node);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final step in steps) {
      visit(step);
    }
    final addStep = steps.singleWhere((node) => node.id == 'zap-4-add');

    expect(flourNodes, hasLength(1));
    expect(
      addStep.children.any(
        (node) => node.card.id == CatalogCards.preparation.id,
      ),
      isTrue,
    );
  });
}
