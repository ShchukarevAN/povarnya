import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarnya/presentation/speech_input_button.dart';

Uint8List pcmChunk(int sampleCount, int amplitude) {
  final bytes = Uint8List(sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < sampleCount; index++) {
    data.setInt16(index * 2, amplitude, Endian.little);
  }
  return bytes;
}

void main() {
  group('SilenceEndpointDetector', () {
    test('ends a phrase after trailing silence', () {
      final detector = SilenceEndpointDetector(sampleRate: 1000);

      expect(detector.add(pcmChunk(150, 2000)), isFalse);
      expect(detector.hasSpeech, isTrue);
      expect(detector.add(pcmChunk(999, 0)), isFalse);
      expect(detector.add(pcmChunk(1, 0)), isTrue);
    });

    test('ignores a short noise impulse', () {
      final detector = SilenceEndpointDetector(sampleRate: 1000);

      expect(detector.add(pcmChunk(50, 2000)), isFalse);
      expect(detector.add(pcmChunk(1000, 0)), isFalse);
      expect(detector.hasSpeech, isFalse);
    });

    test('stops waiting when no speech arrives', () {
      final detector = SilenceEndpointDetector(sampleRate: 1000);

      expect(detector.add(pcmChunk(6999, 0)), isFalse);
      expect(detector.add(pcmChunk(1, 0)), isTrue);
      expect(detector.hasSpeech, isFalse);
    });

    test('keeps PCM16 samples aligned across odd chunks', () {
      final detector = SilenceEndpointDetector(sampleRate: 1000);
      final speech = pcmChunk(200, 1000);

      expect(detector.add(Uint8List.sublistView(speech, 0, 101)), isFalse);
      expect(detector.add(Uint8List.sublistView(speech, 101)), isFalse);
      expect(detector.totalSamples, 200);
      expect(detector.hasSpeech, isTrue);
    });

    test('accepts quiet but sustained speech', () {
      final detector = SilenceEndpointDetector(sampleRate: 1000);

      expect(detector.add(pcmChunk(200, 320)), isFalse);
      expect(detector.hasSpeech, isTrue);
      expect(detector.maxRms, 320);
      expect(detector.overallRms, 320);
      expect(detector.speechStart, Duration.zero);
    });
  });
}
