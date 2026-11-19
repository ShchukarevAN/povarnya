import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../startup_loading_video.dart';
import 'update_installer.dart';
import 'update_service.dart';

enum _UpdateViewState {
  working,
  upToDate,
  ready,
  permission,
  installer,
  failed,
}

typedef UpdateServiceBuilder = UpdateService Function(
  UpdateProgressCallback onProgress,
  UpdateLogCallback onLog,
);
typedef UpdateLoadingBuilder = Widget Function(
  VoidCallback onFirstCycleCompleted,
);

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, this.serviceBuilder, this.loadingBuilder});

  final UpdateServiceBuilder? serviceBuilder;
  final UpdateLoadingBuilder? loadingBuilder;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen>
    with WidgetsBindingObserver {
  late final UpdateService _service;
  final UpdateInstaller _installer = UpdateInstaller();
  final List<String> _diagnostics = [];
  _UpdateViewState _state = _UpdateViewState.working;
  UpdateProgress _progress = const UpdateProgress(
    UpdateStage.checking,
    'Подготавливаю проверку обновлений…',
  );
  UpdateCheckResult? _checkResult;
  UpdateFailure? _failure;
  File? _downloadedApk;
  ApkInspection? _apkInspection;
  bool _openingPermissionSettings = false;
  String? _diagnosticFilePath;
  Completer<void> _loadingCycle = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service =
        widget.serviceBuilder?.call(_handleProgress, _addDiagnostic) ??
        UpdateService(onProgress: _handleProgress, onLog: _addDiagnostic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runUpdate());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _state == _UpdateViewState.permission &&
        _openingPermissionSettings) {
      _openingPermissionSettings = false;
      unawaited(_continueAfterPermission());
    }
  }

  void _handleProgress(UpdateProgress progress) {
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  void _addDiagnostic(String message) {
    final now = DateTime.now().toIso8601String();
    _diagnostics.add('[$now] $message');
  }

  Future<void> _runUpdate() async {
    if (!mounted) return;
    if (_loadingCycle.isCompleted) {
      _loadingCycle = Completer<void>();
    }
    setState(() {
      _state = _UpdateViewState.working;
      _failure = null;
      _checkResult = null;
      _downloadedApk = null;
      _apkInspection = null;
      _progress = const UpdateProgress(
        UpdateStage.checking,
        'Подключаюсь к GitHub…',
      );
    });
    _addDiagnostic('=== Начата проверка обновления ===');
    try {
      final check = await _service.check();
      if (!mounted) return;
      _checkResult = check;
      if (!check.updateAvailable) {
        _addDiagnostic('Обновление не требуется.');
        await _persistDiagnostics();
        await _waitForLoadingCycle();
        if (mounted) setState(() => _state = _UpdateViewState.upToDate);
        return;
      }
      if (!Platform.isAndroid) {
        throw const UpdateFailure(
          code: 'PLATFORM_NOT_SUPPORTED',
          title: 'Автообновление только для Android',
          message: 'Эта сборка запущена не на Android.',
          suggestion: 'Для Linux соберите и замените приложение с ПК.',
        );
      }
      final apk = await _service.download(check.release);
      if (!mounted) return;
      _downloadedApk = apk;
      _addDiagnostic('APK сохранён: ${apk.path}');
      _handleProgress(
        const UpdateProgress(
          UpdateStage.verifying,
          'Сверяю пакет, версию, код и подпись APK…',
        ),
      );
      final inspection = await _installer.inspect(
        apk,
        expectedVersionName: check.release.version,
        expectedVersionCode: check.release.versionCode,
      );
      if (!mounted) return;
      _apkInspection = inspection;
      _addDiagnostic(
        'APK проверен: ${inspection.packageName}; '
        'версия ${inspection.versionName}; '
        'внутренний код ${inspection.versionCode}; '
        'подпись совпадает.',
      );
      await _persistDiagnostics();
      await _waitForLoadingCycle();
      if (mounted) setState(() => _state = _UpdateViewState.ready);
    } catch (error, stackTrace) {
      await _showFailure(error, stackTrace);
    }
  }

  Future<void> _continueAfterPermission() async {
    final apk = _downloadedApk;
    final check = _checkResult;
    if (apk == null || check == null) return;
    try {
      final allowed = await _installer.canRequestInstall();
      if (!allowed) {
        _addDiagnostic(
          'Система не разрешает этому приложению устанавливать APK.',
        );
        await _waitForLoadingCycle();
        if (mounted) {
          setState(() {
            _state = _UpdateViewState.permission;
            _progress = const UpdateProgress(
              UpdateStage.requestingPermission,
              'Требуется разрешение Android',
            );
          });
        }
        await _persistDiagnostics();
        return;
      }
      if (mounted) {
        setState(() {
          _state = _UpdateViewState.working;
          _progress = const UpdateProgress(
            UpdateStage.openingInstaller,
            'Открываю системный установщик…',
          );
        });
      }
      await _installer.install(
        apk,
        expectedVersionName: check.release.version,
        expectedVersionCode: check.release.versionCode,
      );
      _addDiagnostic('Системный установщик Android запущен.');
      await _persistDiagnostics();
      await _waitForLoadingCycle();
      if (mounted) setState(() => _state = _UpdateViewState.installer);
    } catch (error, stackTrace) {
      await _showFailure(error, stackTrace);
    }
  }

  Future<void> _openPermissionSettings() async {
    try {
      _openingPermissionSettings = true;
      _addDiagnostic('Открываю настройки неизвестных источников.');
      await _installer.openInstallPermissionSettings();
    } catch (error, stackTrace) {
      _openingPermissionSettings = false;
      await _showFailure(error, stackTrace);
    }
  }

  Future<void> _showFailure(Object error, StackTrace stackTrace) async {
    final failure = error is UpdateFailure
        ? error
        : UpdateFailure(
            code: 'UNEXPECTED_UPDATE_ERROR',
            title: 'Непредвиденная ошибка обновления',
            message: '$error',
            suggestion: 'Сохраните диагностику, вернитесь в программу и повторите позже.',
            technicalDetails: stackTrace.toString(),
          );
    _addDiagnostic('ERROR ${failure.code}: ${failure.message}');
    if (failure.technicalDetails case final details?) {
      _addDiagnostic(details);
    }
    _addDiagnostic('STACK TRACE:\n$stackTrace');
    await _waitForLoadingCycle();
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _state = _UpdateViewState.failed;
    });
    // Show the exact reason immediately. Writing a diagnostic file is useful,
    // but a slow or unavailable filesystem must never hold the error screen.
    await _persistDiagnostics();
    if (mounted) setState(() {});
  }

  Future<void> _persistDiagnostics() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File(path.join(directory.path, 'update-last.log'));
      await file.writeAsString('${_diagnostics.join('\n')}\n', flush: true);
      _diagnosticFilePath = file.path;
    } catch (_) {
      // The on-screen diagnostics remain available even if storage is full.
    }
  }

  void _returnToApplication() => Navigator.of(context).pop();

  void _markLoadingCycleCompleted() {
    if (!_loadingCycle.isCompleted) _loadingCycle.complete();
  }

  Future<void> _waitForLoadingCycle() => _loadingCycle.future.timeout(
    const Duration(seconds: 7),
    onTimeout: () {},
  );

  @override
  Widget build(BuildContext context) {
    final canPop = _state != _UpdateViewState.working;
    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: _state == _UpdateViewState.working
            ? PovarnyaLoadingVideo.backgroundColor
            : null,
        appBar: _state == _UpdateViewState.working
            ? null
            : AppBar(
                automaticallyImplyLeading: canPop,
                title: const Text('Обновление «Поварни»'),
              ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _state == _UpdateViewState.working
              ? _workingView()
              : SafeArea(
                  child: switch (_state) {
                    _UpdateViewState.working => const SizedBox.shrink(),
                    _UpdateViewState.upToDate => _upToDateView(),
                    _UpdateViewState.ready => _readyView(),
                    _UpdateViewState.permission => _permissionView(),
                    _UpdateViewState.installer => _installerView(),
                    _UpdateViewState.failed => _failureView(),
                  },
                ),
        ),
      ),
    );
  }

  Widget _readyView() {
    final check = _checkResult!;
    final inspection = _apkInspection!;
    return _UpdateCenteredView(
      key: const ValueKey('ready'),
      icon: Icons.verified_user_outlined,
      title: 'APK проверен перед установкой',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'На телефоне: ${check.installedVersion}\n'
            'GitHub и исходники: ${check.release.version}\n'
            'Внутри APK: ${inspection.versionName}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Пакет ${inspection.packageName} и его подпись '
            'совпадают с установленной «Поварней».',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _continueAfterPermission,
            icon: const Icon(Icons.install_mobile_outlined),
            label: const Text('Установить проверенное обновление'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _returnToApplication,
            child: const Text('Отменить и вернуться'),
          ),
        ],
      ),
    );
  }

  Widget _workingView() => Semantics(
    key: const ValueKey('working'),
    label: 'Проверка обновлений. ${_progress.message}',
    liveRegion: true,
    child:
        widget.loadingBuilder?.call(_markLoadingCycleCompleted) ??
        PovarnyaLoadingVideo(onFirstCycleCompleted: _markLoadingCycleCompleted),
  );

  Widget _upToDateView() {
    final result = _checkResult!;
    return _UpdateCenteredView(
      key: const ValueKey('up-to-date'),
      icon: Icons.verified_outlined,
      title: 'Установлена актуальная версия',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'На телефоне: ${result.installedVersion}\n'
            'Последний GitHub Release: ${result.release.tag}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _returnToApplication,
            child: const Text('Вернуться в программу'),
          ),
        ],
      ),
    );
  }

  Widget _permissionView() => _UpdateCenteredView(
    key: const ValueKey('permission'),
    icon: Icons.admin_panel_settings_outlined,
    title: 'Разрешите установку обновлений',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Android один раз просит разрешить «Поварне» '
          'запускать системный установщик. APK уже скачан и проверен.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _openPermissionSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Открыть настройки Android'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _returnToApplication,
          child: const Text('Отменить и вернуться'),
        ),
      ],
    ),
  );

  Widget _installerView() => _UpdateCenteredView(
    key: const ValueKey('installer'),
    icon: Icons.install_mobile_outlined,
    title: 'Системный установщик открыт',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Подтвердите обновление в окне Android. '
          'Если вы отменили установку, текущая версия останется без изменений.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _continueAfterPermission,
          child: const Text('Открыть установщик ещё раз'),
        ),
        TextButton(
          onPressed: _returnToApplication,
          child: const Text('Вернуться в текущую версию'),
        ),
      ],
    ),
  );

  Widget _failureView() {
    final failure = _failure!;
    return SingleChildScrollView(
      key: const ValueKey('failure'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 72,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                failure.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                failure.message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Код: ${failure.code}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(failure.suggestion),
                      if (_diagnosticFilePath case final filePath?) ...[
                        const SizedBox(height: 8),
                        SelectableText('Журнал: $filePath'),
                      ],
                    ],
                  ),
                ),
              ),
              ExpansionTile(
                title: const Text('Технические подробности'),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: SelectableText(
                      [
                        if (failure.technicalDetails != null)
                          failure.technicalDetails!,
                        ..._diagnostics,
                      ].join('\n'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _runUpdate,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _returnToApplication,
                child: const Text('Вернуться в текущую версию'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateCenteredView extends StatelessWidget {
  const _UpdateCenteredView({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 28),
            child,
          ],
        ),
      ),
    ),
  );
}
