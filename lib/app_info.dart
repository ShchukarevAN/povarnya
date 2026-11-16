import 'package:flutter/material.dart';

import 'data/app_settings.dart';
import 'data/recipe_database.dart';
import 'update/update_screen.dart';

/// Версия имеет формат 0.<основная версия>.<итерация кода>.
/// Последняя цифра увеличивается при каждом изменении исходного кода и
/// синхронизируется с `pubspec.yaml`.
const appVersion = '0.6.22';
const appVersionLabel = appVersion;

/// Показывает настройки непосредственно под кнопкой, не перехватывая
/// клавиатурный фокус. Меню закрывается нажатием вне него.
Future<void> showSettingsPopover(BuildContext buttonContext) async {
  final buttonBox = buttonContext.findRenderObject() as RenderBox?;
  final overlayBox =
      Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
  if (buttonBox == null || overlayBox == null) return;

  // The button label and icon must fit on one line even with Android's
  // slightly enlarged accessibility font metrics.
  const menuWidth = 288.0;
  final buttonRect =
      buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
      buttonBox.size;
  final left = (buttonRect.right - menuWidth)
      .clamp(0.0, overlayBox.size.width - menuWidth)
      .toDouble();
  final top = buttonRect.bottom;

  final action = await showMenu<_SettingsAction>(
    context: buttonContext,
    requestFocus: false,
    constraints: const BoxConstraints.tightFor(width: menuWidth),
    position: RelativeRect.fromLTRB(
      left,
      top,
      overlayBox.size.width - left - menuWidth,
      overlayBox.size.height - top,
    ),
    items: [const _SettingsMenuEntry()],
  );
  if (!buttonContext.mounted || action == null) return;
  switch (action) {
    case _SettingsAction.checkUpdates:
      await Navigator.of(buttonContext, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(builder: (_) => const UpdateScreen()),
      );
    case _SettingsAction.deletePhotos:
      if (await _confirmDestructiveAction(
        buttonContext,
        title: 'Удалить все фотографии?',
        message: 'Будут удалены фотографии всех рецептов. Сами рецепты, заметки и настройки останутся.',
        confirmLabel: 'Удалить фотографии',
      )) {
        await RecipeDatabase().deleteAllRecipePhotos();
        if (buttonContext.mounted) {
          ScaffoldMessenger.of(buttonContext).showSnackBar(
            const SnackBar(
              content: Text('Все сохранённые фотографии удалены.'),
            ),
          );
        }
      }
    case _SettingsAction.deleteAllData:
      if (await _confirmDestructiveAction(
        buttonContext,
        title: 'Удалить все локальные данные?',
        message: 'Будут удалены изменения рецептов, заметки, фотографии, избранное, статистика и настройки. Встроенный каталог будет создан заново.',
        confirmLabel: 'Удалить все данные',
      )) {
        await RecipeDatabase().resetLocalData();
        await AppSettings().resetLocalSettings();
        if (buttonContext.mounted) {
          ScaffoldMessenger.of(buttonContext).showSnackBar(
            const SnackBar(content: Text('Локальные данные удалены.')),
          );
        }
      }
  }
}

Future<bool> _confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

enum _SettingsAction { checkUpdates, deletePhotos, deleteAllData }

class _SettingsMenuEntry extends PopupMenuEntry<_SettingsAction> {
  const _SettingsMenuEntry();

  @override
  double get height => 278;

  @override
  bool represents(_SettingsAction? value) => false;

  @override
  State<_SettingsMenuEntry> createState() => _SettingsMenuEntryState();
}

class _SettingsMenuEntryState extends State<_SettingsMenuEntry> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Версия: $appVersionLabel',
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () =>
                Navigator.of(context).pop(_SettingsAction.checkUpdates),
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Проверить обновления'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_SettingsAction.deletePhotos),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Удалить все фотографии'),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () =>
                Navigator.of(context).pop(_SettingsAction.deleteAllData),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Удалить все данные'),
          ),
        ],
      ),
    ),
  );
}
