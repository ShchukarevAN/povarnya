import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import '../data/data_directory.dart';

/// Paints Hunspell results immediately, including the word under the cursor.
///
/// Flutter's built-in spell-check painter intentionally hides an error in the
/// word that is currently being edited. For the short free-text recipe module
/// that looks like delayed checking, so this controller keeps the asynchronous
/// checking but renders every returned range itself.
class HunspellTextEditingController extends TextEditingController {
  HunspellTextEditingController({
    super.text,
    SpellCheckService? spellCheckService,
  }) : _spellCheckService =
           spellCheckService ?? HunspellSpellCheckService.instance {
    _lastCheckedText = text;
    addListener(_handleTextChanged);
    if (text.isNotEmpty) _requestSpellCheck(text);
  }

  final SpellCheckService _spellCheckService;
  late String _lastCheckedText;
  List<SuggestionSpan> _misspelledSpans = const <SuggestionSpan>[];
  var _requestGeneration = 0;

  TextStyle misspelledTextStyle = const TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
  );

  List<SuggestionSpan> get misspelledSpans =>
      List<SuggestionSpan>.unmodifiable(_misspelledSpans);

  void _handleTextChanged() {
    final currentText = text;
    if (currentText == _lastCheckedText) return;
    _lastCheckedText = currentText;
    _misspelledSpans = const <SuggestionSpan>[];
    _requestSpellCheck(currentText);
  }

  void _requestSpellCheck(String checkedText) {
    final generation = ++_requestGeneration;
    if (checkedText.trim().isEmpty) {
      notifyListeners();
      return;
    }
    unawaited(_applySpellCheck(generation, checkedText));
  }

  Future<void> _applySpellCheck(int generation, String checkedText) async {
    final spans = await _spellCheckService.fetchSpellCheckSuggestions(
      const Locale('ru', 'RU'),
      checkedText,
    );
    if (spans == null ||
        generation != _requestGeneration ||
        text != checkedText) {
      return;
    }
    _misspelledSpans = spans;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_misspelledSpans.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final children = <InlineSpan>[];
    var offset = 0;
    for (final span in _misspelledSpans) {
      final start = span.range.start.clamp(offset, text.length);
      final end = span.range.end.clamp(start, text.length);
      if (start > offset) {
        children.add(TextSpan(text: text.substring(offset, start)));
      }
      if (end > start) {
        children.add(
          TextSpan(
            text: text.substring(start, end),
            style: misspelledTextStyle,
          ),
        );
      }
      offset = end;
    }
    if (offset < text.length) {
      children.add(TextSpan(text: text.substring(offset)));
    }
    return TextSpan(style: style, children: children);
  }

  @override
  void dispose() {
    _requestGeneration++;
    removeListener(_handleTextChanged);
    super.dispose();
  }
}

/// Flutter spell-check service backed by the bundled Russian Hunspell data.
///
/// Checking happens in a persistent isolate. When the native library is not
/// available (for example in a widget-test process), the service degrades to
/// an empty result instead of disrupting text input.
class HunspellSpellCheckService implements SpellCheckService {
  HunspellSpellCheckService._();

  static final instance = HunspellSpellCheckService._();

  Future<SendPort>? _workerFuture;
  ReceivePort? _responsePort;
  final _requests = <int, Completer<List<SuggestionSpan>?>>{};
  var _nextRequestId = 0;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (text.trim().isEmpty) return const <SuggestionSpan>[];
    try {
      final worker = await (_workerFuture ??= _startWorker());
      final id = _nextRequestId++;
      final completer = Completer<List<SuggestionSpan>?>();
      _requests[id] = completer;
      worker.send(<Object?>[id, text]);
      return await completer.future;
    } catch (_) {
      _workerFuture = null;
      return const <SuggestionSpan>[];
    }
  }

  Future<SendPort> _startWorker() async {
    final dictionaryPaths = await _prepareDictionaryFiles();
    _responsePort = ReceivePort();
    final ready = Completer<SendPort>();
    _responsePort!.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is! List || message.length < 2) return;
      final request = _requests.remove(message[0] as int);
      if (request == null) return;
      final rawRanges = (message[1] as List).cast<List<dynamic>>();
      request.complete(<SuggestionSpan>[
        for (final range in rawRanges)
          SuggestionSpan(
            TextRange(start: range[0] as int, end: range[1] as int),
            const <String>[],
          ),
      ]);
    });
    await Isolate.spawn<List<Object?>>(_hunspellWorkerMain, <Object?>[
      _responsePort!.sendPort,
      dictionaryPaths.$1,
      dictionaryPaths.$2,
    ], debugName: 'hunspell-ru');
    return ready.future;
  }

  Future<(String, String)> _prepareDictionaryFiles() async {
    final supportDirectory = await povarnyaDataDirectory();
    final dictionaryDirectory = Directory(
      path.join(supportDirectory.path, 'dictionaries', 'hunspell_ru'),
    );
    await dictionaryDirectory.create(recursive: true);

    Future<String> copy(String name, int expectedLength) async {
      final output = File(path.join(dictionaryDirectory.path, name));
      final isCurrent =
          await output.exists() && await output.length() == expectedLength;
      if (!isCurrent) {
        final asset = await rootBundle.load('assets/modules/hunspell_ru/$name');
        await output.writeAsBytes(
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
          flush: true,
        );
      }
      return output.path;
    }

    return (await copy('ru_RU.aff', 71236), await copy('ru_RU.dic', 3473191));
  }
}

typedef _HunspellCreateNative = Pointer<Void> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _HunspellCreate = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _HunspellDestroyNative = Void Function(Pointer<Void>);
typedef _HunspellDestroy = void Function(Pointer<Void>);
typedef _HunspellSpellNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _HunspellSpell = int Function(Pointer<Void>, Pointer<Utf8>);

@pragma('vm:entry-point')
Future<void> _hunspellWorkerMain(List<Object?> startup) async {
  final mainPort = startup[0] as SendPort;
  final commands = ReceivePort();
  mainPort.send(commands.sendPort);

  Pointer<Void> handle = nullptr;
  _HunspellSpell? spell;
  _HunspellDestroy? destroy;
  try {
    if (!Platform.isLinux && !Platform.isAndroid) {
      throw UnsupportedError('Hunspell is not bundled on this platform');
    }
    final library = DynamicLibrary.open('libhunspell-1.7.so');
    final create = library
        .lookupFunction<_HunspellCreateNative, _HunspellCreate>(
          'Hunspell_create',
        );
    destroy = library.lookupFunction<_HunspellDestroyNative, _HunspellDestroy>(
      'Hunspell_destroy',
    );
    spell = library.lookupFunction<_HunspellSpellNative, _HunspellSpell>(
      'Hunspell_spell',
    );
    final aff = (startup[1] as String).toNativeUtf8();
    final dic = (startup[2] as String).toNativeUtf8();
    try {
      handle = create(aff, dic);
    } finally {
      calloc.free(aff);
      calloc.free(dic);
    }
  } catch (_) {
    handle = nullptr;
  }

  final russianWord = RegExp(r'[А-Яа-яЁё]+(?:-[А-Яа-яЁё]+)*');
  await for (final dynamic message in commands) {
    if (message is! List || message.length < 2) continue;
    final id = message[0] as int;
    final text = message[1] as String;
    final misspelled = <List<int>>[];
    if (handle != nullptr && spell != null) {
      for (final match in russianWord.allMatches(text)) {
        final word = match.group(0)!;
        if (word.length < 2) continue;
        final nativeWord = word.toNativeUtf8();
        var isCorrect = false;
        try {
          isCorrect = spell(handle, nativeWord) != 0;
        } finally {
          calloc.free(nativeWord);
        }
        if (!isCorrect && word != word.toLowerCase()) {
          final lowercaseWord = word.toLowerCase().toNativeUtf8();
          try {
            isCorrect = spell(handle, lowercaseWord) != 0;
          } finally {
            calloc.free(lowercaseWord);
          }
        }
        if (!isCorrect) misspelled.add(<int>[match.start, match.end]);
      }
    }
    mainPort.send(<Object?>[id, misspelled]);
  }

  if (handle != nullptr && destroy != null) destroy(handle);
}
