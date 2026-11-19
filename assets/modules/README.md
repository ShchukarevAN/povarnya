# Офлайн-модули

Этот каталог целиком включён в Flutter assets.

## Zipformer2 Russian

- Модель: Alpha Cephei `vosk-model-ru`, Zipformer2 v0.54, INT8 ONNX.
- Фиксация: commit `df6a54a4d8e5d43e82675e4f5dba2d507731a0d1`.
- Источник: https://huggingface.co/alphacep/vosk-model-ru
- Рантайм: `sherpa_onnx` 2.0.1 в `pubspec.yaml`.
- Лицензия: Apache-2.0, текст в `zipformer2_ru/LICENSE.txt`.

## Silero TTS Russian

- Модель: `v5_6_ru`, голоса `aidar`, `baya`, `kseniya`, `xenia`, `eugene`.
- Частоты: 8000, 24000 и 48000 Гц.
- Исходная модель: https://models.silero.ai/models/tts/ru/v5_6_ru.pt
- Выполнение: четыре ONNX-графа из адаптации
  https://github.com/some1-in-here/silero-tts-onnx/tree/v0.5.0 через
  `dart_onnx` 0.1.1 и уже встроенную в Zipformer2 ONNX Runtime. Системный TTS
  не используется.
- В приложении активирован мужской голос `eugene`, частота вывода — 48000 Гц.
- Изменения адаптации: PyTorch-граф разделён на предикторы длительности и
  высоты, акустическую модель и вокодер; предобработка рецептурного текста
  перенесена в Dart. В двух предикторах внешняя маска `bool` заменена на
  FFI-совместимую `int64` с внутренним приведением обратно к `bool`; математика
  модели не изменена.
- Исходный PyTorch-контейнер в сборку не дублируется: приложение
  исполняет его адаптированные ONNX-веса.
- Лицензия: CC BY-NC-SA 4.0, текст в `silero_tts_ru/LICENSE.txt`.

## Hunspell Russian

- Движок: Hunspell 1.7.6, commit `15faca15532b34db3106d50f162e5edc2503d6d6`.
- Исходники: `third_party/hunspell`; в Linux и Android собирается динамическая
  библиотека, но не загружается кодом приложения.
- Лицензия движка: LGPL/GPL/MPL tri-license; тексты лицензий лежат рядом
  с исходниками.
- Словарь: LibreOffice `ru_RU.aff` + `ru_RU.dic`, commit
  `30dd499a102c930b6386d9b0b44ed13e9d4cf8d2`.
- Лицензия словаря: BSD-style, текст в `hunspell_ru/LICENSE.txt`.

## SHA-256

```text
c7a756aeb3550417d6b2ed3efde9a7aa3eea54787d4eac011e9cce6090c9c64a  zipformer2_ru/bpe.model
d6cb1c78563388bcb7c8a654a768ac2a8518c22542c5b13999b46a08c2557c81  zipformer2_ru/decoder.int8.onnx
eb6c12fbad810d5bc3e427802e604604c69b5943a91feebc43424dd09d9ec407  zipformer2_ru/encoder.int8.onnx
93f2e1d12b78d53e7802f1606488c14bb3d764b15fadf5ef6c022f6ba1fa40f7  zipformer2_ru/joiner.int8.onnx
93bbbc0bae6b78c0bbb743d4aa9fded3bb5ff3aac5f0200e3a769a5a05e0fdf6  zipformer2_ru/tokens.txt
da129dfadbd10741d836b9401508a257e24615d9d60af03811549a8f14bf6a57  silero_tts_ru/onnx/acoustic_v5_6_ru.onnx
5afda82cf1304be6417a884459b040ce0ea25e006f7377e593ab6a30d93440c4  silero_tts_ru/onnx/dur_predictor_v5_6_ru.onnx
13f70661b816cafe331e6ca2e9e915ba8c4e89029e23a6b51ffe9a11e3331e0c  silero_tts_ru/onnx/pitch_predictor_v5_6_ru.onnx
723df4f52b5dacebfc4fb96505be30f625f66a983e2fcc892ebb480bcd3e4d9a  silero_tts_ru/onnx/vocoder_v5_6_ru.onnx
38ce7d4af78e211e9bafe4bf7e3d6a2c420591136cb738ec6648f8fdf6524cd7  hunspell_ru/ru_RU.aff
f6047416a0204adbecf3a451b874ec8a97ee37e2cbc714466ef04d8dbcc0d6fc  hunspell_ru/ru_RU.dic
```
