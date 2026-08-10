import 'package:flutter/services.dart';

class TtsService {
  static const MethodChannel _channel =
      MethodChannel('nexo_ai/tts');

  static Future<void> synthesizeToFile({
    required String text,
    required String filePath,
    required String language,
  }) async {
    final result =
        await _channel.invokeMethod(
      'synthesizeToFile',
      {
        'text': text,
        'filePath': filePath,
        'language': language,
      },
    );

    if (result != true) {
      throw Exception(
        'Android Text-to-Speech ने audio file नहीं बनाई।',
      );
    }
  }
}
