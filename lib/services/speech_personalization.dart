String normalizeSpeechText(String text) => text
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

int speechWordDistance(String expected, String actual) {
  final left = normalizeSpeechText(expected).split(' ')
    ..removeWhere((word) => word.isEmpty);
  final right = normalizeSpeechText(actual).split(' ')
    ..removeWhere((word) => word.isEmpty);
  return _sequenceDistance(left, right);
}

int speechCharacterDistance(String left, String right) =>
    _sequenceDistance(left.runes, right.runes);

String applySpeechPersonalization(
  String text, {
  required Iterable<String> personalWords,
  required Map<String, String> corrections,
}) {
  final normalized = normalizeSpeechText(text);
  if (normalized.isEmpty) return text.trim();

  final normalizedCorrections = <String, String>{
    for (final entry in corrections.entries)
      normalizeSpeechText(entry.key): normalizeSpeechText(entry.value),
  }..removeWhere((key, value) => key.isEmpty || value.isEmpty || key == value);
  if (normalizedCorrections[normalized] case final exact?) return exact;

  final vocabulary = personalWords
      .map(normalizeSpeechText)
      .where((word) => word.length >= 4 && !word.contains(' '))
      .toSet();
  final result = <String>[];
  for (final token in normalized.split(' ')) {
    if (normalizedCorrections[token] case final corrected?) {
      result.add(corrected);
      continue;
    }
    String? best;
    var bestDistance = 1 << 20;
    var tied = false;
    for (final candidate in vocabulary) {
      if (candidate[0] != token[0]) continue;
      final allowedDistance = candidate.length >= 6 ? 2 : 1;
      if ((candidate.length - token.length).abs() > allowedDistance) continue;
      final distance = _sequenceDistance(candidate.runes, token.runes);
      if (distance > allowedDistance) continue;
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
        tied = false;
      } else if (distance == bestDistance) {
        tied = true;
      }
    }
    result.add(best != null && !tied ? best : token);
  }
  return result.join(' ');
}

int _sequenceDistance<T>(Iterable<T> leftValues, Iterable<T> rightValues) {
  final left = leftValues.toList(growable: false);
  final right = rightValues.toList(growable: false);
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
      final substitution =
          previous[rightIndex] + (left[leftIndex] == right[rightIndex] ? 0 : 1);
      final insertion = current[rightIndex] + 1;
      final deletion = previous[rightIndex + 1] + 1;
      current[rightIndex + 1] = [
        substitution,
        insertion,
        deletion,
      ].reduce((best, value) => value < best ? value : best);
    }
    previous = current;
  }
  return previous.last;
}
