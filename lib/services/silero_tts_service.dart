import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dart_onnx/dart_onnx.dart';
import 'package:flutter/services.dart';

/// Offline Russian speech synthesis backed by the bundled Silero TTS v5.6
/// ONNX adaptation. No platform/system TTS is used.
class SileroTtsService {
  SileroTtsService._();

  static final instance = SileroTtsService._();

  static const _modelRoot = 'assets/modules/silero_tts_ru/onnx';
  static const _sampleRate = 48000;
  static const _speakerEugene = 3;
  static const _speechRate = .85;
  static const _symbolToId = <String, int>{
    '_': 0,
    '~': 1,
    '|': 2,
    '!': 3,
    '+': 4,
    ',': 5,
    '-': 6,
    '.': 7,
    ':': 8,
    ';': 9,
    '?': 10,
    'а': 11,
    'б': 12,
    'в': 13,
    'г': 14,
    'д': 15,
    'е': 16,
    'ж': 17,
    'з': 18,
    'и': 19,
    'й': 20,
    'к': 21,
    'л': 22,
    'м': 23,
    'н': 24,
    'о': 25,
    'п': 26,
    'р': 27,
    'с': 28,
    'т': 29,
    'у': 30,
    'ф': 31,
    'х': 32,
    'ц': 33,
    'ч': 34,
    'ш': 35,
    'щ': 36,
    'ъ': 37,
    'ы': 38,
    'ь': 39,
    'э': 40,
    'ю': 41,
    'я': 42,
    'ё': 43,
    '–': 44,
    '…': 45,
    ' ': 46,
  };

  final _player = AudioPlayer();
  Future<void>? _preparing;
  DartONNX? _environment;
  DartONNXSession? _duration;
  DartONNXSession? _pitch;
  DartONNXSession? _acoustic;
  DartONNXSession? _vocoder;
  Completer<void>? _playbackDone;
  int _generation = 0;

  Future<void> prepare() => _preparing ??= _prepare();

  Future<void> _prepare() async {
    try {
      final environment = _environment ??= DartONNX(
        loggingLevel: DartONNXLoggingLevel.error,
        logId: 'povarnya_silero',
      );
      _duration = await _createSessionFromAsset(
        environment,
        '$_modelRoot/dur_predictor_v5_6_ru.onnx',
      );
      _pitch = await _createSessionFromAsset(
        environment,
        '$_modelRoot/pitch_predictor_v5_6_ru.onnx',
      );
      _acoustic = await _createSessionFromAsset(
        environment,
        '$_modelRoot/acoustic_v5_6_ru.onnx',
      );
      _vocoder = await _createSessionFromAsset(
        environment,
        '$_modelRoot/vocoder_v5_6_ru.onnx',
      );
    } catch (error) {
      _disposeSessions();
      _preparing = null;
      throw SileroTtsException(
        'Файлы Silero TTS v5.6 недоступны или повреждены.',
        error,
      );
    }
  }

  Future<void> speak(String text) async {
    final generation = _generation;
    final sequence = _tokenize(text);
    if (sequence.length <= 2) return;
    await prepare();

    final length = sequence.length;
    final speaker = Int64List.fromList(const [_speakerEugene]);
    final mask = Int64List(length);
    final sentenceType = _sentenceType(text);
    final typeIds = Int64List.fromList(List<int>.filled(length, sentenceType));
    final baseTypeIds = Int64List.fromList(
      List<int>.filled(length, sentenceType % 6),
    );
    final focusMask = Int64List(length);

    final durationOutputs = _run(_duration!, <String, _TensorData>{
      'text': _TensorData(sequence, [1, length]),
      'speaker_ids': _TensorData(speaker, const [1]),
      'mask': _TensorData(mask, [1, length]),
      'type_ids': _TensorData(typeIds, [1, length]),
      'focus_mask': _TensorData(focusMask, [1, length]),
    });
    final durationValue = durationOutputs.values.single;
    final durationRaw = Float32List.fromList(durationValue.data as Float32List);
    final durationShape = durationValue.shape;
    _disposeTensors(durationOutputs.values);

    final pitchOutputs = _run(_pitch!, <String, _TensorData>{
      'text': _TensorData(sequence, [1, length]),
      'speaker_ids': _TensorData(speaker, const [1]),
      'mask': _TensorData(mask, [1, length]),
      'type_ids': _TensorData(baseTypeIds, [1, length]),
      'focus_mask': _TensorData(focusMask, [1, length]),
    });
    final pitchValue = pitchOutputs.values.single;
    final pitchRaw = Float32List.fromList(pitchValue.data as Float32List);
    final pitchShape = pitchValue.shape;
    _disposeTensors(pitchOutputs.values);

    final durations = Float32List.fromList(
      durationRaw.map((value) => math.exp(value) - 1).toList(),
    );
    final pitch = Float32List.fromList(pitchRaw);

    final ones = Float32List.fromList(List<double>.filled(length, 1));
    final durationRates = Float32List.fromList(
      List<double>.filled(length, _speechRate),
    );
    final acousticOutputs = _run(_acoustic!, <String, _TensorData>{
      'sequence': _TensorData(sequence, [1, length]),
      'speaker_ids': _TensorData(speaker, const [1]),
      'durs_rate': _TensorData(durationRates, [1, length]),
      'gt_durs': _TensorData(durations, durationShape),
      'gt_pitch': _TensorData(pitch, pitchShape),
      'pitch_coefs': _TensorData(ones, [1, length]),
      'type_ids': _TensorData(typeIds, [1, length]),
      'focus_mask': _TensorData(focusMask, [1, length]),
    });
    final mel = acousticOutputs['mel'] ?? acousticOutputs.values.first;
    late final Float32List audio;
    Map<String, DartONNXTensor>? vocoderOutputs;
    try {
      vocoderOutputs = _vocoder!.run(<String, DartONNXTensor>{'mel': mel});
      final audioValue = vocoderOutputs['audio'] ?? vocoderOutputs.values.first;
      audio = Float32List.fromList(audioValue.data as Float32List);
    } finally {
      _disposeTensors(acousticOutputs.values);
      if (vocoderOutputs != null) {
        _disposeTensors(vocoderOutputs.values);
      }
    }

    if (generation != _generation) return;
    final playbackDone = Completer<void>();
    final completionSubscription = _player.onPlayerComplete.listen((_) {
      if (!playbackDone.isCompleted) playbackDone.complete();
    });
    _playbackDone = playbackDone;
    try {
      await _player.play(
        BytesSource(_encodeWave(audio), mimeType: 'audio/wav'),
        mode: PlayerMode.mediaPlayer,
      );
      if (generation != _generation && !playbackDone.isCompleted) {
        playbackDone.complete();
      }
      await playbackDone.future;
    } finally {
      await completionSubscription.cancel();
      if (identical(_playbackDone, playbackDone)) _playbackDone = null;
    }
  }

  Future<void> stop() async {
    _generation++;
    final playbackDone = _playbackDone;
    if (playbackDone != null && !playbackDone.isCompleted) {
      playbackDone.complete();
    }
    await _player.stop();
  }

  Map<String, DartONNXTensor> _run(
    DartONNXSession session,
    Map<String, _TensorData> values,
  ) {
    final inputs = <String, DartONNXTensor>{};
    try {
      for (final entry in values.entries) {
        inputs[entry.key] = entry.value.toTensor();
      }
      return session.run(inputs);
    } finally {
      _disposeTensors(inputs.values);
    }
  }

  static Future<DartONNXSession> _createSessionFromAsset(
    DartONNX environment,
    String asset,
  ) async {
    final data = await rootBundle.load(asset);
    return DartONNXSession.fromBytes(
      environment,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  void _disposeSessions() {
    _duration?.dispose();
    _pitch?.dispose();
    _acoustic?.dispose();
    _vocoder?.dispose();
    _environment?.dispose();
    _duration = null;
    _pitch = null;
    _acoustic = null;
    _vocoder = null;
    _environment = null;
  }

  static void _disposeTensors(Iterable<DartONNXTensor> values) {
    for (final value in values) {
      value.dispose();
    }
  }

  static Int64List _tokenize(String source) {
    final expanded = normalizeRecipeText(source)
        .toLowerCase()
        .replaceAll('—', '–')
        .replaceAll('‑', '-');
    final ids = <int>[_symbolToId['|']!];
    for (final rune in expanded.runes) {
      final id = _symbolToId[String.fromCharCode(rune)];
      if (id != null) ids.add(id);
    }
    ids.add(_symbolToId['~']!);
    return Int64List.fromList(ids);
  }

  /// Раскрывает числа и единицы рецепта до передачи в Silero.
  /// Границы заданы явно: Dart RegExp не считает кириллицу
  /// словесными символами для `\b`.
  static String normalizeRecipeText(String source) {
    var text = _expandSpoons(source.replaceAll('−', '–'));
    const number = r'\d+(?:[ \u00a0\u202f]\d{3})*(?:[.,]\d+)?';
    final measurement = RegExp(
      '(^|[^а-яёa-z0-9])'
      '($number)'
      '(?:\\s*[–—-]\\s*($number))?'
      '\\s*(°\\s*[cс]|кг|мг|мл|мм|см|шт\\.?|мин\\.?|сек\\.?|г|л|%)'
      '(?![а-яёa-z])',
      caseSensitive: false,
      multiLine: true,
      unicode: true,
    );
    text = text.replaceAllMapped(measurement, (match) {
      final lower = match.group(2)!;
      final upper = match.group(3);
      final unit = match.group(4)!;
      final amount = _numericValue(upper ?? lower);
      final feminine = _usesFeminineNumber(unit);
      final spokenAmount = upper == null
          ? _numberToWords(lower, feminine: feminine)
          : '${_numberToWords(lower, feminine: feminine)} – '
                '${_numberToWords(upper, feminine: feminine)}';
      return '${match.group(1)}$spokenAmount '
          '${_measurementWord(unit, amount)}';
    });

    // Свободный текст может содержать единицу без числа.
    final standaloneUnit = RegExp(
      r'(^|[^а-яёa-z])(°\s*[cс]|кг|мг|мл|мм|см|шт\.?|мин\.?|сек\.?|г|л|%)(?![а-яёa-z])',
      caseSensitive: false,
      multiLine: true,
      unicode: true,
    );
    text = text.replaceAllMapped(
      standaloneUnit,
      (match) => '${match.group(1)}${_measurementWord(match.group(2)!, 0)}',
    );
    text = text.replaceAllMapped(RegExp(number, unicode: true), (match) {
      return _numberToWords(match.group(0)!);
    });
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _expandSpoons(String source) {
    final spoon = RegExp(
      r'(^|[^а-яёa-z0-9])((?:\d+(?:[.,]\d+)?)?[¼½¾]|\d+(?:[.,]\d+)?)\s*(ч\.\s*л\.|дес\.\s*л\.|ст\.\s*л\.)(?![а-яёa-z])',
      caseSensitive: false,
      multiLine: true,
      unicode: true,
    );
    return source.replaceAllMapped(spoon, (match) {
      final amount = match.group(2)!;
      final unit = match.group(3)!.toLowerCase();
      final phrase = switch (amount) {
        '¼' => 'четверть ${_spoonWord(unit, 3)}',
        '½' => 'половина ${_spoonWord(unit, 3)}',
        '¾' => 'три четверти ${_spoonWord(unit, 3)}',
        '1½' => 'полторы ${_spoonWord(unit, 1)}',
        _ =>
          '${_numberToWords(amount, feminine: true)} '
              '${_spoonWord(unit, _countFormIndex(_numericValue(amount)))}',
      };
      return '${match.group(1)}$phrase';
    });
  }

  static String _spoonWord(String unit, int form) {
    final forms = unit.startsWith('ч.')
        ? const ['чайная ложка', 'чайные ложки', 'чайных ложек', 'чайной ложки']
        : unit.startsWith('дес.')
        ? const [
            'десертная ложка',
            'десертные ложки',
            'десертных ложек',
            'десертной ложки',
          ]
        : const [
            'столовая ложка',
            'столовые ложки',
            'столовых ложек',
            'столовой ложки',
          ];
    return forms[form];
  }

  static String _measurementWord(String source, double amount) {
    final unit = _normalizedUnit(source);
    final form = _countFormIndex(amount);
    final forms = switch (unit) {
      'кг' => const ['килограмм', 'килограмма', 'килограммов'],
      'мг' => const ['миллиграмм', 'миллиграмма', 'миллиграммов'],
      'г' => const ['грамм', 'грамма', 'граммов'],
      'мл' => const ['миллилитр', 'миллилитра', 'миллилитров'],
      'л' => const ['литр', 'литра', 'литров'],
      'мм' => const ['миллиметр', 'миллиметра', 'миллиметров'],
      'см' => const ['сантиметр', 'сантиметра', 'сантиметров'],
      'шт' => const ['штука', 'штуки', 'штук'],
      'мин' => const ['минута', 'минуты', 'минут'],
      'сек' => const ['секунда', 'секунды', 'секунд'],
      '°c' => const ['градус Цельсия', 'градуса Цельсия', 'градусов Цельсия'],
      '%' => const ['процент', 'процента', 'процентов'],
      _ => const ['', '', ''],
    };
    return forms[form];
  }

  static bool _usesFeminineNumber(String source) =>
      const {'шт', 'мин', 'сек'}.contains(_normalizedUnit(source));

  static String _normalizedUnit(String source) {
    final unit = source
        .toLowerCase()
        .replaceAll('.', '')
        .replaceAll(RegExp(r'\s+'), '');
    return unit == '°с' ? '°c' : unit;
  }

  static int _countFormIndex(double value) {
    if (value != value.roundToDouble()) return 1;
    final integer = value.round().abs();
    final lastTwo = integer % 100;
    if (lastTwo >= 11 && lastTwo <= 14) return 2;
    return switch (integer % 10) {
      1 => 0,
      2 || 3 || 4 => 1,
      _ => 2,
    };
  }

  static double _numericValue(String source) => double.parse(
    source.replaceAll(RegExp(r'[ \u00a0\u202f]'), '').replaceAll(',', '.'),
  );

  static String _numberToWords(String source, {bool feminine = false}) {
    final token = source.replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
    final separator = token.contains(',') ? ',' : '.';
    if (!token.contains(separator)) {
      return _integerToWords(int.parse(token), feminine: feminine);
    }
    final parts = token.split(separator);
    return '${_integerToWords(int.parse(parts.first), feminine: true)} целых '
        '${parts.last.split('').map((digit) => _integerToWords(int.parse(digit))).join(' ')}';
  }

  static String _integerToWords(int value, {bool feminine = false}) {
    if (value == 0) return 'ноль';
    if (value < 0) {
      return 'минус ${_integerToWords(-value, feminine: feminine)}';
    }
    if (value >= 1000000) return value.toString();
    const units = <String>[
      '',
      'один',
      'два',
      'три',
      'четыре',
      'пять',
      'шесть',
      'семь',
      'восемь',
      'девять',
      'десять',
      'одиннадцать',
      'двенадцать',
      'тринадцать',
      'четырнадцать',
      'пятнадцать',
      'шестнадцать',
      'семнадцать',
      'восемнадцать',
      'девятнадцать',
    ];
    const tens = <String>[
      '',
      '',
      'двадцать',
      'тридцать',
      'сорок',
      'пятьдесят',
      'шестьдесят',
      'семьдесят',
      'восемьдесят',
      'девяносто',
    ];
    const hundreds = <String>[
      '',
      'сто',
      'двести',
      'триста',
      'четыреста',
      'пятьсот',
      'шестьсот',
      'семьсот',
      'восемьсот',
      'девятьсот',
    ];

    String belowThousand(int number, {bool feminine = false}) {
      final words = <String>[];
      if (number >= 100) words.add(hundreds[number ~/ 100]);
      final remainder = number % 100;
      if (remainder < 20) {
        if (remainder > 0) {
          if (feminine && remainder == 1) {
            words.add('одна');
          } else if (feminine && remainder == 2) {
            words.add('две');
          } else {
            words.add(units[remainder]);
          }
        }
      } else {
        words.add(tens[remainder ~/ 10]);
        if (remainder % 10 > 0) words.add(units[remainder % 10]);
      }
      return words.join(' ');
    }

    final words = <String>[];
    final thousands = value ~/ 1000;
    if (thousands > 0) {
      words.add(belowThousand(thousands, feminine: true));
      final ending = thousands % 100;
      words.add(
        ending >= 11 && ending <= 19
            ? 'тысяч'
            : switch (thousands % 10) {
                1 => 'тысяча',
                2 || 3 || 4 => 'тысячи',
                _ => 'тысяч',
              },
      );
    }
    final remainder = value % 1000;
    if (remainder > 0) {
      words.add(belowThousand(remainder, feminine: feminine));
    }
    return words.join(' ');
  }

  static int _sentenceType(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.endsWith('!')) return 5;
    if (!normalized.endsWith('?')) return 0;
    const questionWords = <String>{
      'кто',
      'что',
      'где',
      'куда',
      'когда',
      'почему',
      'зачем',
      'как',
      'сколько',
      'какой',
      'какая',
      'какие',
      'чей',
      'который',
    };
    final words = normalized.split(RegExp(r'[^а-яё]+'));
    if (words.take(4).any(questionWords.contains)) return 1;
    if (words.contains('или')) return 3;
    return 2;
  }

  static Uint8List _encodeWave(List<double> samples) {
    final result = Uint8List(44 + samples.length * 2);
    final data = ByteData.sublistView(result);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        result[offset + index] = value.codeUnitAt(index);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _sampleRate, Endian.little);
    data.setUint32(28, _sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index].clamp(-1.0, 1.0);
      data.setInt16(44 + index * 2, (sample * 32767).round(), Endian.little);
    }
    return result;
  }
}

class SileroTtsException implements Exception {
  const SileroTtsException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message $cause';
}

class _TensorData {
  const _TensorData(this.values, this.shape);

  final Object values;
  final List<int> shape;

  DartONNXTensor toTensor() => switch (values) {
    final Float32List data => DartONNXTensor.float32(data: data, shape: shape),
    final Int64List data => DartONNXTensor.int64(data: data, shape: shape),
    _ => throw ArgumentError(
      'Unsupported ONNX tensor type: ${values.runtimeType}',
    ),
  };
}
