/// Универсальный поиск локального каталога по отображаемому названию.
///
/// Предметные фильтры (например, набор ингредиентов рецепта) применяются
/// вызывающим кодом до этой функции. Здесь намеренно остаются только общие
/// правила: поиск подстроки без учёта регистра и алфавитный порядок.
List<T> searchAndSortByLabel<T>(
  Iterable<T> items, {
  required String query,
  required String Function(T item) labelOf,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final matching = items
      .where(
        (item) =>
            normalizedQuery.isEmpty ||
            labelOf(item).toLowerCase().contains(normalizedQuery),
      )
      .toList();
  matching.sort(
    (left, right) =>
        labelOf(left).toLowerCase().compareTo(labelOf(right).toLowerCase()),
  );
  return matching;
}
