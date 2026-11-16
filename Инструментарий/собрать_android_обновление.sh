#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL_ROOT="$PROJECT_ROOT/Инструментарий"
CONFIG_FILE="$TOOL_ROOT/обновление.env"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

REPOSITORY="${POVARNYA_GITHUB_REPOSITORY:-ShchukarevAN/povarnya}"
ASSET_NAME="${POVARNYA_UPDATE_ASSET:-povarnya-android.apk}"
BUILD_MODE="${POVARNYA_ANDROID_BUILD_MODE:-release}"
REQUIRE_SHA256="${POVARNYA_UPDATE_REQUIRE_SHA256:-true}"
UPDATE_URL="${POVARNYA_UPDATE_URL:-https://api.github.com/repos/$REPOSITORY/releases/latest}"
APP_ICON_SOURCE="$PROJECT_ROOT/assets/media/Иконка.jpg"

if [[ ! "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf 'Ошибка: POVARNYA_GITHUB_REPOSITORY должен иметь вид owner/repository.\n' >&2
  exit 2
fi
if [[ ! "$ASSET_NAME" =~ ^[A-Za-z0-9_.-]+\.apk$ ]]; then
  printf 'Ошибка: POVARNYA_UPDATE_ASSET должен быть безопасным именем .apk.\n' >&2
  exit 2
fi
if [[ "$BUILD_MODE" != "debug" && "$BUILD_MODE" != "release" ]]; then
  printf 'Ошибка: POVARNYA_ANDROID_BUILD_MODE должен быть debug или release.\n' >&2
  exit 2
fi
if [[ "$REQUIRE_SHA256" != "true" && "$REQUIRE_SHA256" != "false" ]]; then
  printf 'Ошибка: POVARNYA_UPDATE_REQUIRE_SHA256 должен быть true или false.\n' >&2
  exit 2
fi
if [[ ! -s "$APP_ICON_SOURCE" ]]; then
  printf 'Ошибка: не найден исходник иконки приложения: %s\n' "$APP_ICON_SOURCE" >&2
  exit 2
fi
if ! command -v magick >/dev/null 2>&1; then
  printf 'Ошибка: для подготовки Android-иконок требуется ImageMagick (magick).\n' >&2
  exit 2
fi

# Android и Linux используют один исходник. PNG нужны Android только как
# технические варианты плотности и при каждой сборке заново создаются из
# той же предоставленной пользователем картинки, которую загружает окно на ПК.
for ICON_SPEC in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  ICON_DENSITY="${ICON_SPEC%%:*}"
  ICON_SIZE="${ICON_SPEC##*:}"
  ICON_TARGET="$PROJECT_ROOT/android/app/src/main/res/mipmap-$ICON_DENSITY/ic_launcher.png"
  mkdir -p "$(dirname "$ICON_TARGET")"
  magick "$APP_ICON_SOURCE" -resize "${ICON_SIZE}x${ICON_SIZE}" -strip \
    "$ICON_TARGET"
done

VERSION_SPEC="$(sed -n 's/^version:[[:space:]]*//p' "$PROJECT_ROOT/pubspec.yaml" | head -n 1)"
if [[ ! "$VERSION_SPEC" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  printf 'Ошибка: version в pubspec.yaml должна иметь вид 0.6.0+1.\n' >&2
  exit 2
fi
VERSION_NAME="${VERSION_SPEC%+*}"
VERSION_CODE="${VERSION_SPEC##*+}"
RELEASE_TAG="v$VERSION_NAME"

# Gradle-демон кэширует пути SDK между сборками. Поэтому используем постоянные
# ASCII-ссылки, а не одноразовый каталог: после завершения первого запуска путь
# остаётся действительным и следующая сборка не теряет android.jar.
LINK_ROOT="${TMPDIR:-/tmp}/povarnya-android-build"
mkdir -p "$LINK_ROOT"
ln -sfn "$TOOL_ROOT/flutter" "$LINK_ROOT/flutter"
ln -sfn "$TOOL_ROOT/android-sdk" "$LINK_ROOT/android-sdk"

mkdir -p "$TOOL_ROOT/Кэш/gradle" "$PROJECT_ROOT/build/updates"

run_flutter() {
  env -u HOME \
    XDG_CONFIG_HOME="$TOOL_ROOT/Кэш/config" \
    XDG_CACHE_HOME="$TOOL_ROOT/Кэш" \
    PUB_CACHE="$TOOL_ROOT/Кэш/pub" \
    "$TOOL_ROOT/flutter/bin/flutter" "$@"
}

encode_define() {
  printf '%s' "$1" | base64 -w 0
}

cd "$PROJECT_ROOT"
printf 'Обновляю зависимости Flutter…\n'
run_flutter pub get --offline

# java.util.Properties читает не-ASCII пути как ISO-8859-1. Временные
# ASCII-ссылки делают Android-сборку независимой от кириллицы в пути.
printf 'flutter.sdk=%s\nsdk.dir=%s\nflutter.buildMode=%s\nflutter.versionName=%s\nflutter.versionCode=%s\n' \
  "$LINK_ROOT/flutter" \
  "$LINK_ROOT/android-sdk" \
  "$BUILD_MODE" \
  "$VERSION_NAME" \
  "$VERSION_CODE" \
  > "$PROJECT_ROOT/android/local.properties"

DART_DEFINES="$(encode_define "POVARNYA_UPDATE_URL=$UPDATE_URL")"
DART_DEFINES+=",$(encode_define "POVARNYA_UPDATE_ASSET=$ASSET_NAME")"
DART_DEFINES+=",$(encode_define "POVARNYA_UPDATE_REQUIRE_SHA256=$REQUIRE_SHA256")"

if [[ "$BUILD_MODE" == "release" ]]; then
  GRADLE_TASK=assembleRelease
else
  GRADLE_TASK=assembleDebug
fi

printf 'Собираю Android %s для %s…\n' "$BUILD_MODE" "$REPOSITORY"
env -u HOME \
  JAVA_HOME="$TOOL_ROOT/jdk-17" \
  ANDROID_HOME="$LINK_ROOT/android-sdk" \
  ANDROID_SDK_ROOT="$LINK_ROOT/android-sdk" \
  ANDROID_USER_HOME="$TOOL_ROOT/android-user" \
  GRADLE_USER_HOME="$TOOL_ROOT/Кэш/gradle" \
  XDG_CONFIG_HOME="$TOOL_ROOT/Кэш/config" \
  XDG_CACHE_HOME="$TOOL_ROOT/Кэш" \
  PUB_CACHE="$TOOL_ROOT/Кэш/pub" \
  "$TOOL_ROOT/gradle-9.3.1/bin/gradle" \
    -p "$PROJECT_ROOT/android" \
    "$GRADLE_TASK" \
    "-Pdart-defines=$DART_DEFINES"

SOURCE_APK="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-$BUILD_MODE.apk"
TARGET_APK="$PROJECT_ROOT/build/updates/$ASSET_NAME"
if [[ ! -s "$SOURCE_APK" ]]; then
  printf 'Ошибка: Gradle завершился, но APK не найден: %s\n' "$SOURCE_APK" >&2
  exit 3
fi
cp "$SOURCE_APK" "$TARGET_APK"

APK_SIZE="$(stat -c '%s' "$TARGET_APK")"
APK_SHA256="$(sha256sum "$TARGET_APK" | cut -d ' ' -f 1)"
printf '%s  %s\n' "$APK_SHA256" "$ASSET_NAME" \
  > "$PROJECT_ROOT/build/updates/$ASSET_NAME.sha256"
printf '%s\n' "$TARGET_APK" > "$PROJECT_ROOT/build/updates/latest-apk.path"
printf '{\n  "repository": "%s",\n  "releaseTag": "%s",\n  "versionName": "%s",\n  "versionCode": %s,\n  "assetName": "%s",\n  "size": %s,\n  "sha256": "%s"\n}\n' \
  "$REPOSITORY" \
  "$RELEASE_TAG" \
  "$VERSION_NAME" \
  "$VERSION_CODE" \
  "$ASSET_NAME" \
  "$APK_SIZE" \
  "$APK_SHA256" \
  > "$PROJECT_ROOT/build/updates/update-manifest.json"

printf '\nAndroid-сборка готова.\n'
printf 'APK: %s\n' "$TARGET_APK"
printf 'SHA-256: %s\n' "$APK_SHA256"
printf 'GitHub Release tag: %s\n' "$RELEASE_TAG"
printf 'GitHub asset name: %s\n' "$ASSET_NAME"
printf 'Манифест: %s\n' "$PROJECT_ROOT/build/updates/update-manifest.json"
