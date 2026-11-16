#!/usr/bin/env bash
set -euo pipefail

# Меню запуска. Flutter и его кэш остаются внутри «Инструментарий».
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL_ROOT="$PROJECT_ROOT/Инструментарий"
FLUTTER="$TOOL_ROOT/flutter/bin/flutter"
PROGRAM="$PROJECT_ROOT/build/linux/x64/release/bundle/povarnya"
BUILD_REVISION_FILE="$PROJECT_ROOT/build/linux/x64/release/bundle/.povarnya-build-revision"
GIT_DIR="$PROJECT_ROOT/Инструментарий/Версии.git"
ANDROID_UPDATE_BUILDER="$TOOL_ROOT/собрать_android_обновление.sh"
ANDROID_UPDATE_CONFIG="$TOOL_ROOT/обновление.env"
ADB="$TOOL_ROOT/android-sdk/platform-tools/adb"

# Синхронизирует пользовательский ярлык с текущей release-сборкой. Абсолютные
# пути нужны намеренно: проект запускается напрямую из своей папки, без
# установки в /usr. Если HOME отсутствует (например, в CI), ярлык просто не
# создаётся — сама сборка и запуск остаются рабочими.
install_linux_launcher() {
  [[ -n "${HOME:-}" && -x "$PROGRAM" ]] || return
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local applications_dir="$data_home/applications"
  local icons_dir="$data_home/icons/hicolor/512x512/apps"
  local icon="$icons_dir/povarnya.png"
  local desktop_file="$applications_dir/ru.shchukarevan.povarnya.desktop"
  mkdir -p "$applications_dir" "$icons_dir"
  cp "$PROJECT_ROOT/linux/runner/resources/povarnya.png" "$icon"
  sed \
    -e "s|^Exec=.*|Exec=$PROGRAM|" \
    -e "s|^Icon=.*|Icon=$icon|" \
    -e 's|^Terminal=.*|Terminal=false|' \
    "$PROJECT_ROOT/linux/runner/resources/ru.shchukarevan.povarnya.desktop" \
    > "$desktop_file"
}

android_build_mode() {
  sed -n 's/^POVARNYA_ANDROID_BUILD_MODE=//p' "$ANDROID_UPDATE_CONFIG" \
    | tail -n 1
}

run_with_project_environment() {
  env -u HOME \
    POVARNYA_DATA_DIR="$PROJECT_ROOT/database" \
    XDG_CONFIG_HOME="$TOOL_ROOT/Кэш/config" \
    XDG_CACHE_HOME="$TOOL_ROOT/Кэш" \
    PUB_CACHE="$TOOL_ROOT/Кэш/pub" \
    "$@"
}

build_project() {
  printf '\nСобираю Linux-версию проекта…\n\n'
  # Явно собираем release: в нём нет инструментов визуальной отладки Flutter
  # (в том числе жёлтых линий базовых линий текста).
  run_with_project_environment "$FLUTTER" build linux --release
  git --git-dir="$GIT_DIR" --work-tree="$PROJECT_ROOT" rev-parse HEAD \
    > "$BUILD_REVISION_FILE"
  install_linux_launcher
  printf '\nСборка завершена. Нажмите Enter, чтобы вернуться в меню.\n'
  read -r
}

build_android_update() {
  printf '\nСобираю Android %s APK для GitHub-обновления…\n' \
    "$(android_build_mode)"
  printf 'Сборка без JIT: быстрый холодный старт и меньший APK.\n\n'
  "$ANDROID_UPDATE_BUILDER"
  printf '\nНажмите Enter, чтобы вернуться в меню.\n'
  read -r
}

install_android_update() {
  local apk_path
  apk_path="$(cat "$PROJECT_ROOT/build/updates/latest-apk.path" 2>/dev/null || true)"
  if [[ -z "$apk_path" || ! -s "$apk_path" ]]; then
    printf '\nAPK обновления не найден. Сначала выполните пункт 4.\n'
    printf 'Нажмите Enter, чтобы вернуться в меню.\n'
    read -r
    return
  fi
  if ! "$ADB" get-state >/dev/null 2>&1; then
    printf '\nПодключённый Android-телефон не найден.\n'
    printf 'Нажмите Enter, чтобы вернуться в меню.\n'
    read -r
    return
  fi
  printf '\nПереношу и устанавливаю Android %s: %s\n\n' \
    "$(android_build_mode)" "$apk_path"
  "$ADB" push "$apk_path" /sdcard/Download/Povarnya-release.apk
  "$ADB" install -r "$apk_path"
  "$ADB" shell am force-stop ru.shchukarevan.povarnya
  "$ADB" shell am start -W -n ru.shchukarevan.povarnya/.MainActivity
  printf '\nRelease APK установлен и запущен. Нажмите Enter.\n'
  read -r
}

run_analysis() {
  # exec закрывает меню и передаёт управление самостоятельной программе анализа.
  exec "$TOOL_ROOT/анализировать_проект.sh"
}

run_program() {
  if [[ ! -x "$PROGRAM" ]]; then
    printf '\nГотовая сборка не найдена. Сначала выберите «Сборка проекта».\n'
    printf 'Нажмите Enter, чтобы вернуться в меню.\n'
    read -r
    return
  fi

  local current_revision
  local built_revision
  current_revision="$(git --git-dir="$GIT_DIR" --work-tree="$PROJECT_ROOT" rev-parse HEAD)"
  built_revision="$(cat "$BUILD_REVISION_FILE" 2>/dev/null || true)"
  if [[ "$built_revision" != "$current_revision" ]]; then
    printf '\nRelease-сборка не соответствует текущему коду.\n'
    printf 'Сначала выберите «Сборка проекта» (пункт 1).\n'
    printf 'Нажмите Enter, чтобы вернуться в меню.\n'
    read -r
    return
  fi
  install_linux_launcher

  # Запускаем готовый бинарник напрямую: Flutter, компиляция и отладчик не нужны.
  # Строка остаётся в терминале под окном и позволяет однозначно проверить,
  # какой именно файл запущен, если на компьютере есть старая debug-копия.
  printf '\nЗапускается release-сборка: %s\n' "$PROGRAM"
  printf 'Код сборки обновлён: %s\n\n' \
    "$(stat -c '%y' "$PROJECT_ROOT/build/linux/x64/release/bundle/lib/libapp.so")"
  printf 'Версия кода: %s\n\n' "${built_revision:0:7}"
  exec env -u HOME \
    -u LC_ALL \
    -u LC_MESSAGES \
    -u LANGUAGE \
    POVARNYA_DATA_DIR="$PROJECT_ROOT/database" \
    XDG_CONFIG_HOME="$TOOL_ROOT/Кэш/config" \
    XDG_CACHE_HOME="$TOOL_ROOT/Кэш" \
    PUB_CACHE="$TOOL_ROOT/Кэш/pub" \
    "$PROGRAM"
}

while true; do
  clear
  printf 'Поварня — меню запуска\n\n'
  printf '1. Сборка проекта (Linux release)\n'
  printf '2. Анализ проекта\n'
  printf '3. Запуск Linux release\n'
  printf '4. Сборка Android %s APK (быстрый старт + GitHub)\n' \
    "$(android_build_mode)"
  printf '5. Установка последнего Android %s APK на телефон\n\n' \
    "$(android_build_mode)"
  printf 'Выберите действие (1–5): '
  read -r choice

  case "$choice" in
    1) build_project ;;
    2) run_analysis ;;
    3) run_program ;;
    4) build_android_update ;;
    5) install_android_update ;;
    *)
      printf '\nВведите номер от 1 до 5. Нажмите Enter.\n'
      read -r
      ;;
  esac
done
