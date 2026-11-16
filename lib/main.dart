import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app_theme.dart';
import 'data/app_settings.dart';
import 'domain/catalog.dart';
import 'domain/recipe_node.dart';
import 'data/recipe_database.dart';
import 'performance_trace.dart';
import 'presentation/recipe_screen.dart';
import 'presentation/recipe_search_screen.dart';
import 'presentation/coordinate_transition.dart';
import 'startup_loading_video.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit использует нативный видеодвижок на Linux, Windows и Android.
  // Его необходимо подготовить до создания первого виджета с видео.
  MediaKit.ensureInitialized();
  // Первый Flutter-кадр должен появиться сразу. Файлы настроек и база
  // открываются уже под заставкой, чтобы Android не показывал пустое окно.
  runApp(const PovarnyaStartupApp());
}

const _startupWindowChannel = MethodChannel('povarnya/window_theme');

Future<void> _restoreStartupWindowState() async {
  if (!Platform.isLinux) return;
  try {
    await _startupWindowChannel.invokeMethod<void>(
      'setWindowMaximized',
      AppSettings().windowMaximized,
    );
  } on MissingPluginException {
    // Виджет-тесты не создают нативное Linux-окно.
  }
}

/// Сначала показывает заставку, затем подготавливает локальные данные и
/// тяжёлые ресурсы интерфейса. Это устраняет первую паузу при открытии
/// просмотра или редактора на медленных устройствах.
class PovarnyaStartupApp extends StatefulWidget {
  const PovarnyaStartupApp({
    super.key,
    this.prepareApplication,
    this.loadingBuilder,
    this.applicationBuilder,
  });

  /// Тестовые крючки позволяют проверить ворота запуска без нативного
  /// видеодвижка и SQLite. В обычном приложении они не задаются.
  final Future<void> Function(BuildContext context)? prepareApplication;
  final Widget Function(VoidCallback onFirstCycleCompleted)? loadingBuilder;
  final WidgetBuilder? applicationBuilder;

  @override
  State<PovarnyaStartupApp> createState() => _PovarnyaStartupAppState();
}

class _PovarnyaStartupAppState extends State<PovarnyaStartupApp> {
  bool _ready = false;
  bool _applicationPrepared = false;
  bool _startupVideoCompletedFirstCycle = false;

  @override
  void initState() {
    super.initState();
    // Тяжёлая подготовка начинается только после первого кадра заставки.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareApplication());
    });
  }

  Future<void> _prepareApplication() async {
    final override = widget.prepareApplication;
    if (override != null) {
      await override(context);
    } else {
      await Future.wait([
        AppSettings().load(),
        PerformanceTrace.instance.startIfRequested(),
        RecipeDatabase().open(),
      ]);
      await _restoreStartupWindowState();
      // Прогреваем только наиболее часто открываемые рецепты. Все остальные
      // загружаются при первом открытии, поэтому большой каталог не замедляет
      // старт приложения.
      final database = RecipeDatabase();
      final frequentlyOpenedRecipeIds = await database.mostOpenedRecipeIds();
      await database.preloadRecipeContent(frequentlyOpenedRecipeIds);
      if (!mounted) return;
      // Фотографии остальных рецептов не декодируются при запуске. Прогрев
      // ограничен тем же коротким списком, что и сами часто открываемые блюда.
      await Future.wait([
        for (final recipeId in frequentlyOpenedRecipeIds)
          database.loadRecipePhotoPath(recipeId).then((photoPath) async {
            if (photoPath != null && mounted) {
              await precacheImage(FileImage(File(photoPath)), context);
            }
          }),
        for (final recipeId in frequentlyOpenedRecipeIds)
          database.loadRecipePhotoBytes(recipeId).then((photoBytes) async {
            if (photoBytes != null && mounted) {
              await precacheImage(MemoryImage(photoBytes), context);
            }
          }),
      ]);
      await preloadRecipeInterfaceAssets(context);
    }
    _applicationPrepared = true;
    _finishStartupWhenReady();
  }

  void _markStartupVideoCycleCompleted() {
    if (_startupVideoCompletedFirstCycle) return;
    _startupVideoCompletedFirstCycle = true;
    _finishStartupWhenReady();
  }

  void _finishStartupWhenReady() {
    if (mounted &&
        !_ready &&
        _applicationPrepared &&
        _startupVideoCompletedFirstCycle) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) => _ready
      ? (widget.applicationBuilder?.call(context) ?? const PovarnyaApp())
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          home:
              widget.loadingBuilder?.call(_markStartupVideoCycleCompleted) ??
              PovarnyaLoadingVideo(
                onFirstCycleCompleted: _markStartupVideoCycleCompleted,
              ),
        );
}

class PovarnyaApp extends StatefulWidget {
  const PovarnyaApp({super.key});

  @override
  State<PovarnyaApp> createState() => _PovarnyaAppState();
}

class _PovarnyaAppState extends State<PovarnyaApp> {
  final GlobalKey _sceneKey = GlobalKey();
  String _themeName = AppSettings().themeName;
  double _scale = AppSettings().scale;
  bool _isRecipeScreenOpen = false;
  bool _shouldOpenRecipeEditor = true;
  CatalogRecipe? _selectedRecipe;
  RecipeSearchEntryGeometry? _recipeOpenOrigin;
  bool _recipeOpenTransitionReady = false;
  bool _recipeOpenContentVisible = true;
  GlobalKey? _recipeOpenTitleAnchor;
  Map<String, GlobalKey>? _recipeOpenIngredientAnchors;
  bool _showSavedRecipeNotice = false;
  Timer? _savedRecipeNoticeTimer;
  final Map<int, Offset> _touchPointers = {};
  Offset? _pinchOriginA;
  Offset? _pinchOriginB;
  double _pinchStartingScale = 1;
  bool _pinchChangedScale = false;
  DateTime? _lastTouchDownAt;
  Offset? _lastTouchDownPosition;

  static const _windowThemeChannel = MethodChannel('povarnya/window_theme');

  static const _nextThemeName = {
    'Бежевая': 'Коричневая',
    'Коричневая': 'OLED',
    'OLED': 'Светлая',
    'Светлая': 'Тёмная',
    'Тёмная': 'Бежевая',
  };

  bool get _usesDarkTheme => appPalette(_themeName).isDark;

  // Для системной рамки важна только палитра, а не плотность полей.
  ThemeData get _activeTheme => appTheme(_themeName);

  ThemeData _activeThemeFor(BoxConstraints constraints) {
    // Плотная оболочка нужна только на узком портретном экране, когда
    // пользователь заметно увеличил интерфейс. В остальных раскладках
    // сохраняются исходные интервалы и зоны касания.
    final useCompactInputs =
        constraints.maxHeight > constraints.maxWidth && _scale >= 1.2;
    return appTheme(_themeName, compactInputControls: useCompactInputs);
  }

  @override
  void initState() {
    super.initState();
    _windowThemeChannel.setMethodCallHandler(_handleWindowMethodCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWindowTheme();
      _restoreWindowState();
    });
  }

  Future<void> _handleWindowMethodCall(MethodCall call) async {
    if (call.method != 'windowMaximizedChanged' || call.arguments is! bool) {
      return;
    }
    AppSettings().windowMaximized = call.arguments as bool;
    AppSettings().save();
  }

  Future<void> _syncWindowTheme() async {
    if (!Platform.isLinux) return;
    try {
      final colors = _activeTheme.colorScheme;
      await _windowThemeChannel.invokeMethod<void>(
        'setTitleBarTheme',
        <String, int>{
          'background': colors.surfaceContainer.toARGB32(),
          'foreground': colors.onSurfaceVariant.toARGB32(),
        },
      );
    } on MissingPluginException {
      // Среды тестирования не создают нативное Linux-окно.
    }
  }

  Future<void> _restoreWindowState() async {
    if (!Platform.isLinux) return;
    try {
      await _windowThemeChannel.invokeMethod<void>(
        'setWindowMaximized',
        AppSettings().windowMaximized,
      );
    } on MissingPluginException {
      // Среды тестирования не создают нативное Linux-окно.
    }
  }

  void _toggleTheme() {
    setState(() {
      _themeName = _nextThemeName[_themeName] ?? defaultAppThemeName;
    });
    AppSettings().themeName = _themeName;
    AppSettings().save();
    _syncWindowTheme();
  }

  void _changeScale(double delta) => _setScale(_scale + delta);

  void _setScale(double value, {bool save = true}) {
    final nextScale = value.clamp(.7, 1.6).toDouble();
    if (nextScale == _scale) return;
    setState(() => _scale = nextScale);
    if (save) {
      AppSettings().scale = _scale;
      AppSettings().save();
    }
  }

  void _onTouchPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    final now = DateTime.now();
    final previousTime = _lastTouchDownAt;
    final previousPosition = _lastTouchDownPosition;
    // Двойное касание увеличивает масштаб на один шаг. Сведение пальцев
    // остаётся симметричным способом уменьшить его.
    if (_touchPointers.isEmpty &&
        previousTime != null &&
        previousPosition != null &&
        now.difference(previousTime) <= const Duration(milliseconds: 280) &&
        (event.position - previousPosition).distance <= 32) {
      _changeScale(.1);
      _lastTouchDownAt = null;
      _lastTouchDownPosition = null;
    } else {
      _lastTouchDownAt = now;
      _lastTouchDownPosition = event.position;
    }
    _touchPointers[event.pointer] = event.position;
    if (_touchPointers.length == 2) {
      final positions = _touchPointers.values.toList(growable: false);
      _pinchOriginA = positions[0];
      _pinchOriginB = positions[1];
      _pinchStartingScale = _scale;
      _pinchChangedScale = false;
    }
  }

  void _onTouchPointerMove(PointerMoveEvent event) {
    if (!_touchPointers.containsKey(event.pointer)) return;
    _touchPointers[event.pointer] = event.position;
    final originA = _pinchOriginA;
    final originB = _pinchOriginB;
    if (_touchPointers.length != 2 || originA == null || originB == null)
      return;
    final positions = _touchPointers.values.toList(growable: false);
    final originalDistance = (originA - originB).distance;
    final currentDistance = (positions[0] - positions[1]).distance;
    if (originalDistance < 8 || currentDistance < 8) return;
    _pinchChangedScale = true;
    _setScale(
      _pinchStartingScale * currentDistance / originalDistance,
      save: false,
    );
  }

  void _onTouchPointerEnd(PointerEvent event) {
    if (!_touchPointers.containsKey(event.pointer)) return;
    _touchPointers.remove(event.pointer);
    if (_touchPointers.length >= 2) return;
    _pinchOriginA = null;
    _pinchOriginB = null;
    if (_pinchChangedScale) {
      _pinchChangedScale = false;
      AppSettings().scale = _scale;
      AppSettings().save();
    }
  }

  void _returnToSearch() => setState(() {
    _isRecipeScreenOpen = false;
    _recipeOpenOrigin = null;
    _recipeOpenContentVisible = true;
    _recipeOpenTitleAnchor = null;
    _recipeOpenIngredientAnchors = null;
  });

  void _openRecipe(CatalogRecipe recipe) => _showRecipe(recipe);

  void _showRecipe(
    CatalogRecipe recipe, {
    RecipeSearchEntryGeometry? origin,
    GlobalKey? titleAnchor,
    Map<String, GlobalKey>? ingredientAnchors,
  }) => setState(() {
    _shouldOpenRecipeEditor = false;
    _selectedRecipe = recipe;
    _recipeOpenOrigin = origin;
    _recipeOpenTransitionReady = origin == null;
    _recipeOpenContentVisible = origin == null;
    _recipeOpenTitleAnchor = titleAnchor;
    _recipeOpenIngredientAnchors = ingredientAnchors;
    _isRecipeScreenOpen = true;
  });

  void _finishRecipeOpenTransition() => setState(() {
    _recipeOpenOrigin = null;
    _recipeOpenContentVisible = true;
    _recipeOpenTitleAnchor = null;
    _recipeOpenIngredientAnchors = null;
  });

  /// Входной полёт нельзя запускать по каталожному черновику: локально
  /// сохранённое дерево рецепта может отличаться от него. Экран сообщает о
  /// готовности только после загрузки и первой раскладки актуальных шагов.
  void _startRecipeOpenTransition() {
    if (!mounted || _recipeOpenOrigin == null || _recipeOpenTransitionReady) {
      return;
    }
    setState(() => _recipeOpenTransitionReady = true);
  }

  /// Входная карточка из поиска остаётся главным объектом первой половины
  /// перехода. Сам экран рецепта начинает проявляться только после неё.
  void _revealRecipeOpenContent() {
    if (mounted && !_recipeOpenContentVisible) {
      setState(() => _recipeOpenContentVisible = true);
    }
  }

  /// Координаты карточки получены в экранной системе координат. Переводим их
  /// в систему масштабируемой сцены, иначе переход смещался бы при Ctrl +/−.
  void _openRecipeWithTransition(
    CatalogRecipe recipe,
    RecipeSearchEntryGeometry origin,
  ) {
    final scene = _sceneKey.currentContext?.findRenderObject();
    if (scene is! RenderBox || !scene.hasSize) {
      _openRecipe(recipe);
      return;
    }
    Rect inScene(Rect rect) {
      final topLeft = scene.globalToLocal(rect.topLeft);
      final bottomRight = scene.globalToLocal(rect.bottomRight);
      return Rect.fromPoints(topLeft, bottomRight);
    }

    final ingredientAnchors = {
      for (final ingredient in recipe.ingredientsByAmount)
        ingredient: GlobalKey(),
    };
    _showRecipe(
      recipe,
      origin: RecipeSearchEntryGeometry(
        card: inScene(origin.card),
        title: inScene(origin.title),
        ingredients: inScene(origin.ingredients),
        ingredientRects: {
          for (final entry in origin.ingredientRects.entries)
            entry.key: inScene(entry.value),
        },
      ),
      titleAnchor: GlobalKey(),
      ingredientAnchors: ingredientAnchors,
    );
  }

  void _displaySavedRecipeNotice() {
    setState(() => _showSavedRecipeNotice = true);
    _savedRecipeNoticeTimer?.cancel();
    _savedRecipeNoticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSavedRecipeNotice = false);
    });
  }

  @override
  void dispose() {
    _windowThemeChannel.setMethodCallHandler(null);
    _savedRecipeNoticeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MaterialApp(
      title: 'Поварня',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru')],
      themeMode: _usesDarkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: _activeThemeFor(constraints),
      darkTheme: _activeThemeFor(constraints),
      home: Shortcuts(
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.equal, control: true):
              const _ZoomInIntent(),
          SingleActivator(LogicalKeyboardKey.add, control: true):
              const _ZoomInIntent(),
          SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
              const _ZoomInIntent(),
          CharacterActivator('+', control: true): const _ZoomInIntent(),
          SingleActivator(LogicalKeyboardKey.minus, control: true):
              const _ZoomOutIntent(),
          SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
              const _ZoomOutIntent(),
          CharacterActivator('-', control: true): const _ZoomOutIntent(),
        },
        child: Actions(
          actions: {
            _ZoomInIntent: CallbackAction<_ZoomInIntent>(
              onInvoke: (_) {
                _changeScale(.1);
                return null;
              },
            ),
            _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(
              onInvoke: (_) {
                _changeScale(-.1);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onTouchPointerDown,
              onPointerMove: _onTouchPointerMove,
              onPointerUp: _onTouchPointerEnd,
              onPointerCancel: _onTouchPointerEnd,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent &&
                    HardwareKeyboard.instance.isControlPressed &&
                    event.scrollDelta.dy != 0) {
                  _changeScale(event.scrollDelta.dy < 0 ? .1 : -.1);
                }
              },
              child: _ScaledViewport(
                scale: _scale,
                child: Stack(
                  key: _sceneKey,
                  children: [
                    Positioned.fill(
                      child: _isRecipeScreenOpen
                          ? IgnorePointer(
                              ignoring: !_recipeOpenContentVisible,
                              child: AnimatedOpacity(
                                key: const ValueKey('recipe-open-content'),
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                opacity: _recipeOpenContentVisible ? 1 : 0,
                                // Прозрачный экран остаётся в раскладке: его
                                // текстовые якоря нужны летящей карточке.
                                child: RecipeScreen(
                                  key: ValueKey(_selectedRecipe?.id),
                                  onClose: _returnToSearch,
                                  onRecipeSaved: _displaySavedRecipeNotice,
                                  onOpenSimilarRecipe: (recipe) => setState(() {
                                    _shouldOpenRecipeEditor = false;
                                    _selectedRecipe = recipe;
                                  }),
                                  onToggleTheme: _toggleTheme,
                                  themeLabel: _themeName,
                                  initialEditing: _shouldOpenRecipeEditor,
                                  initialRecipe: _selectedRecipe,
                                  // Окончательное дерево загружается до старта
                                  // полёта. Заголовок уже занимает место в раскладке,
                                  // но остаётся прозрачным, чтобы не мигать под
                                  // переходным текстом в этот короткий промежуток.
                                  hideEntranceTitle: _recipeOpenOrigin != null,
                                  entranceTitleAnchor: _recipeOpenTitleAnchor,
                                  entranceIngredientAnchors:
                                      _recipeOpenIngredientAnchors,
                                  onEntranceReady: _startRecipeOpenTransition,
                                  revealRecipePhoto: _recipeOpenOrigin == null,
                                ),
                              ),
                            )
                          : RecipeSearchScreen(
                              onCreateRecipe: () => setState(() {
                                _shouldOpenRecipeEditor = true;
                                _selectedRecipe = null;
                                _isRecipeScreenOpen = true;
                              }),
                              onOpenRecipe: _openRecipe,
                              onOpenRecipeWithTransition:
                                  _openRecipeWithTransition,
                              onToggleTheme: _toggleTheme,
                              themeLabel: _themeName,
                            ),
                    ),
                    if (_recipeOpenOrigin case final origin?
                        when _recipeOpenTransitionReady)
                      Positioned.fill(
                        child: _RecipeOpenTransition(
                          key: ValueKey(_selectedRecipe?.id),
                          recipe: _selectedRecipe!,
                          origin: origin,
                          titleTargetKey: _recipeOpenTitleAnchor,
                          ingredientTargetKeys:
                              _recipeOpenIngredientAnchors ?? const {},
                          onRevealContent: _revealRecipeOpenContent,
                          onFinished: _finishRecipeOpenTransition,
                        ),
                      ),
                    if (_showSavedRecipeNotice)
                      const Positioned(
                        right: 24,
                        // Над плавающей кнопкой «Создать рецепт».
                        bottom: 96,
                        child: _SavedRecipeNotice(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Временный слой над уже созданным экраном рецепта.
///
/// Он не является отдельным маршрутом: поэтому после завершения перехода
/// остаётся тот же экземпляр рецепта, с уже загруженными локальными данными.
class _RecipeOpenTransition extends StatefulWidget {
  const _RecipeOpenTransition({
    super.key,
    required this.recipe,
    required this.origin,
    required this.titleTargetKey,
    required this.ingredientTargetKeys,
    required this.onRevealContent,
    required this.onFinished,
  });

  final CatalogRecipe recipe;
  final RecipeSearchEntryGeometry origin;
  final GlobalKey? titleTargetKey;
  final Map<String, GlobalKey> ingredientTargetKeys;
  final VoidCallback onRevealContent;
  final VoidCallback onFinished;

  @override
  State<_RecipeOpenTransition> createState() => _RecipeOpenTransitionState();
}

class _RecipeOpenTransitionState extends State<_RecipeOpenTransition>
    with SingleTickerProviderStateMixin {
  Rect? _frozenTitleTarget;
  final Map<String, Rect> _frozenIngredientTargets = {};
  Rect? _candidateTitleTarget;
  Map<String, Rect>? _candidateIngredientTargets;
  var _stableTargetFrames = 0;
  var _targetCaptureAttempts = 0;
  var _contentRevealed = false;
  late final AnimationController _controller =
      AnimationController(
          vsync: this,
          // Открытие рецепта намеренно длится 50% дольше прежних 465 мс:
          // перемещение карточки и её состава остаётся различимым.
          duration: const Duration(milliseconds: 700),
        )
        ..addListener(() {
          if (!_contentRevealed && _controller.value >= .5) {
            _contentRevealed = true;
            widget.onRevealContent();
          }
        })
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onFinished();
        });

  @override
  void initState() {
    super.initState();
    // Сначала ждём, пока экран рецепта закончит свою первую раскладку, и
    // фиксируем конечные координаты. Во время полёта цель не должна меняться:
    // иначе поздно появившийся Text-виджет ингредиента вызывает заметный
    // скачок из запасной позиции к точной в последнем кадре.
    WidgetsBinding.instance.addPostFrameCallback((_) => _freezeTargets());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Rect _ingredientSourceRect(int index, int count) {
    final fraction = 1 / count;
    return Rect.fromLTWH(
      widget.origin.ingredients.left +
          widget.origin.ingredients.width * index * fraction,
      widget.origin.ingredients.top,
      widget.origin.ingredients.width * fraction,
      widget.origin.ingredients.height,
    );
  }

  Rect? _measuredTargetRect(GlobalKey? key) {
    final overlay = context.findRenderObject();
    final target = key?.currentContext?.findRenderObject();
    if (overlay is! RenderBox || target is! RenderBox || !target.hasSize) {
      return null;
    }
    final topLeft = overlay.globalToLocal(target.localToGlobal(Offset.zero));
    return topLeft & target.size;
  }

  bool _sameRect(Rect left, Rect right) =>
      (left.left - right.left).abs() < .1 &&
      (left.top - right.top).abs() < .1 &&
      (left.width - right.width).abs() < .1 &&
      (left.height - right.height).abs() < .1;

  bool _sameTargets(Map<String, Rect> left, Map<String, Rect> right) {
    if (left.length != right.length) return false;
    return left.entries.every((entry) {
      final other = right[entry.key];
      return other != null && _sameRect(entry.value, other);
    });
  }

  Rect _fallbackTitleTarget(Size size) {
    final narrow = size.width < 1000;
    final titleLeft = narrow ? 28.0 : 82.0;
    final titleTop = kToolbarHeight + 28.0;
    return Rect.fromLTWH(
      titleLeft,
      titleTop,
      (size.width - titleLeft - 28).clamp(0.0, 720.0),
      42,
    );
  }

  void _freezeTargets() {
    if (!mounted) return;
    final overlay = context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _freezeTargets());
      return;
    }
    final ingredients = widget.recipe.ingredientsByAmount;
    final title = _measuredTargetRect(widget.titleTargetKey);
    final measuredIngredients = <String, Rect>{
      for (final ingredient in ingredients)
        if (_measuredTargetRect(widget.ingredientTargetKeys[ingredient])
            case final rect?)
          ingredient: rect,
    };
    final everyTargetExists =
        title != null && measuredIngredients.length == ingredients.length;
    // Одного существования якорей недостаточно: сразу после загрузки БД
    // AnimatedSize может ещё сдвигать строку. Фиксируем цели только после
    // двух одинаковых последовательных кадров. Это исключает скачок слов в
    // последний кадр полёта к старой позиции строки.
    if (everyTargetExists) {
      final sameAsPrevious =
          _candidateTitleTarget != null &&
          _candidateIngredientTargets != null &&
          _sameRect(title!, _candidateTitleTarget!) &&
          _sameTargets(measuredIngredients, _candidateIngredientTargets!);
      _candidateTitleTarget = title;
      _candidateIngredientTargets = measuredIngredients;
      _stableTargetFrames = sameAsPrevious ? _stableTargetFrames + 1 : 0;
      if (_stableTargetFrames < 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _freezeTargets());
        return;
      }
    } else if (_targetCaptureAttempts++ < 4) {
      // На медленном устройстве ListView может создать последний якорь не в
      // первом кадре. Ждём несколько кадров, но не блокируем переход вечно.
      WidgetsBinding.instance.addPostFrameCallback((_) => _freezeTargets());
      return;
    }
    setState(() {
      _frozenTitleTarget = title ?? _fallbackTitleTarget(overlay.size);
      _frozenIngredientTargets
        ..clear()
        ..addAll(measuredIngredients);
    });
    _controller.forward();
  }

  Widget _flyingText({
    required Rect source,
    required Rect target,
    required String text,
    required double startSize,
    required double endSize,
    required double progress,
    required Color color,
    FontWeight weight = FontWeight.w400,
  }) {
    final fadeOut = Curves.easeIn.transform(
      ((progress - .72) / .28).clamp(0.0, 1.0),
    );
    final movement = Curves.easeInOutCubic.transform(progress);
    return coordinateFlight(
      source: source,
      target: target,
      progress: progress,
      opacity: 1 - fadeOut,
      // Переходный текст имеет собственный анимируемый кегль. Его нельзя
      // помещать в жёсткий прямоугольник с FittedBox: при длинном названии
      // Flutter рисует жёлто-чёрный индикатор переполнения вместо текста.
      preserveChildSize: true,
      // Временный текст рисуется Canvas-слоем, а не RenderParagraph. Поэтому
      // к нему не применяются отладочные линии базовой линии Flutter даже при
      // случайно активированной диагностике, а сам текст движется целиком.
      child: CustomPaint(
        size: Size(
          math.max(source.width, 1),
          math.max(source.height, endSize * 1.5),
        ),
        painter: _FlightTextPainter(
          text: text,
          color: color,
          fontWeight: weight,
          fontSize: startSize + (endSize - startSize) * movement,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final colors = Theme.of(context).colorScheme;
        final ingredients = widget.recipe.ingredientsByAmount;
        final narrow = constraints.maxWidth < 1000;
        final titleLeft = narrow ? 28.0 : 82.0;
        final titleTop = kToolbarHeight + 28.0;
        final titleTarget = Rect.fromLTWH(
          titleLeft,
          titleTop,
          (constraints.maxWidth - titleLeft - 28).clamp(0.0, 720.0),
          42,
        );
        final recipeSurface = Rect.fromLTWH(
          0,
          kToolbarHeight,
          constraints.maxWidth,
          (constraints.maxHeight - kToolbarHeight).clamp(0.0, double.infinity),
        );
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            final cardProgress = Curves.easeInOutCubic.transform(
              (progress / .78).clamp(0.0, 1.0),
            );
            final cardRect = Rect.lerp(
              widget.origin.card,
              recipeSurface,
              cardProgress,
            )!;
            return Stack(
              // Длинное название или ингредиент должны двигаться целиком;
              // обрезание краем временного слоя выглядит как выделение текста.
              clipBehavior: Clip.none,
              children: [
                Positioned.fromRect(
                  rect: cardRect,
                  child: Opacity(
                    opacity:
                        1 -
                        Curves.easeIn.transform(
                          ((progress - .42) / .42).clamp(0.0, 1.0),
                        ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(
                          12 * (1 - cardProgress),
                        ),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                    ),
                  ),
                ),
                _flyingText(
                  source: widget.origin.title,
                  target: _frozenTitleTarget ?? titleTarget,
                  text: widget.recipe.title,
                  startSize: 16,
                  endSize:
                      Theme.of(context).textTheme.headlineMedium?.fontSize ??
                      28,
                  progress: progress,
                  color: colors.onSurface,
                  weight: FontWeight.w600,
                ),
                for (var index = 0; index < ingredients.length; index++)
                  if (_frozenIngredientTargets[ingredients[index]]
                      case final target?)
                    _flyingText(
                      source:
                          widget.origin.ingredientRects[ingredients[index]] ??
                          _ingredientSourceRect(index, ingredients.length),
                      target: target,
                      text: ingredients[index],
                      startSize: 14,
                      endSize: 18,
                      progress: progress,
                      color: colors.onSurfaceVariant,
                    ),
              ],
            );
          },
        );
      },
    ),
  );
}

/// Рисует подпись входной анимации без отдельного RenderParagraph.
///
/// Это намеренно изолированный слой: видимый интерфейс продолжает
/// использовать обычную доступную типографику Flutter, а краткий полёт не
/// получает служебных линий диагностики текста.
class _FlightTextPainter extends CustomPainter {
  const _FlightTextPainter({
    required this.text,
    required this.color,
    required this.fontWeight,
    required this.fontSize,
  });

  final String text;
  final Color color;
  final FontWeight fontWeight;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontWeight: fontWeight,
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    painter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_FlightTextPainter oldDelegate) =>
      text != oldDelegate.text ||
      color != oldDelegate.color ||
      fontWeight != oldDelegate.fontWeight ||
      fontSize != oldDelegate.fontSize;
}

class _SavedRecipeNotice extends StatelessWidget {
  const _SavedRecipeNotice();

  @override
  Widget build(BuildContext context) => Material(
    elevation: 6,
    borderRadius: BorderRadius.circular(10),
    color: Theme.of(context).colorScheme.inverseSurface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        'Рецепт сохранён!',
        style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
      ),
    ),
  );
}

class _ZoomInIntent extends Intent {
  const _ZoomInIntent();
}

class _ZoomOutIntent extends Intent {
  const _ZoomOutIntent();
}

/// Масштабирует всю сцену Flutter, а не только TextScaler. Благодаря этому
/// одинаковый коэффициент действует на кегль, линии, отступы, пиктограммы,
/// карточки и элементы Material.
class _ScaledViewport extends StatelessWidget {
  const _ScaledViewport({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth / scale;
      final height = constraints.maxHeight / scale;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: Transform.scale(
            alignment: Alignment.topLeft,
            scale: scale,
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      );
    },
  );
}
