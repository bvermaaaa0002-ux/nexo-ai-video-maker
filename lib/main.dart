import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexoApp());
}

class NexoApp extends StatelessWidget {
  const NexoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXO AI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const NexoHome(),
    );
  }
}

class Scene {
  final String text;
  final int colorIndex;

  const Scene({
    required this.text,
    required this.colorIndex,
  });
}

class NexoHome extends StatefulWidget {
  const NexoHome({super.key});

  @override
  State<NexoHome> createState() => _NexoHomeState();
}

class _NexoHomeState extends State<NexoHome> {
  final TextEditingController _scriptController = TextEditingController();
  final FlutterTts _tts = FlutterTts();

  VideoPlayerController? _videoController;

  bool _working = false;

  String _status = '';
  String? _videoPath;
  String? _voicePath;
  String? _error;

  @override
  void dispose() {
    _scriptController.dispose();
    _tts.stop();
    _videoController?.dispose();
    super.dispose();
  }

  Future<Directory> _workDirectory() async {
    final base = await getApplicationDocumentsDirectory();

    final dir = Directory(
      '${base.path}/NEXO_AI_Videos',
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  void _setStatus(String value) {
    if (!mounted) return;

    setState(() {
      _status = value;
    });
  }

  // ------------------------------------------------------------
  // HINDI VOICE
  // ------------------------------------------------------------

  Future<String> _createHindiVoice(String text) async {
    final dir = await _workDirectory();

    final file = File(
      '${dir.path}/nexo_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    if (await file.exists()) {
      await file.delete();
    }

    _setStatus('Hindi voice तैयार हो रही है...');

    await _tts.stop();

    final languageResult = await _tts.setLanguage('hi-IN');

    if (languageResult == 0) {
      throw Exception(
        'Hindi TTS language उपलब्ध नहीं है। फोन की Text-to-Speech settings में Hindi voice install करें।',
      );
    }

    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    final result = await _tts.synthesizeToFile(
      text,
      file.path,
      true,
    );

    if (result != 1) {
      throw Exception(
        'Hindi voice file नहीं बन सकी।',
      );
    }

    for (int i = 0; i < 40; i++) {
      await Future.delayed(
        const Duration(milliseconds: 250),
      );

      if (await file.exists()) {
        final length = await file.length();

        if (length > 1000) {
          return file.path;
        }
      }
    }

    throw Exception(
      'Voice file तैयार होने में समस्या आई।',
    );
  }

  Future<void> _testHindiVoice() async {
    final text = _scriptController.text.trim();

    if (text.isEmpty) {
      _showMessage('पहले script लिखें।');
      return;
    }

    try {
      await _tts.stop();

      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      await _tts.speak(text);
    } catch (e) {
      _showMessage('Hindi voice error: $e');
    }
  }

  // ------------------------------------------------------------
  // SCRIPT -> SCENES
  // ------------------------------------------------------------

  List<Scene> _makeScenes(String script) {
    final cleaned = script
        .replaceAll('\r', '')
        .replaceAll('\n\n', '\n')
        .trim();

    if (cleaned.isEmpty) {
      return [];
    }

    final paragraphs = cleaned
        .split(RegExp(r'\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final List<String> parts = [];

    if (paragraphs.length > 1) {
      for (final paragraph in paragraphs) {
        final words = paragraph.split(RegExp(r'\s+'));

        if (words.length <= 45) {
          parts.add(paragraph);
        } else {
          for (int i = 0; i < words.length; i += 35) {
            final end = math.min(
              i + 35,
              words.length,
            );

            parts.add(
              words.sublist(i, end).join(' '),
            );
          }
        }
      }
    } else {
      final words = cleaned.split(RegExp(r'\s+'));

      for (int i = 0; i < words.length; i += 35) {
        final end = math.min(
          i + 35,
          words.length,
        );

        parts.add(
          words.sublist(i, end).join(' '),
        );
      }
    }

    final result = <Scene>[];

    for (int i = 0; i < parts.length; i++) {
      result.add(
        Scene(
          text: parts[i],
          colorIndex: i % 6,
        ),
      );
    }

    return result;
  }

  // ------------------------------------------------------------
  // CREATE VISUAL PNG FOR EACH SCENE
  // ------------------------------------------------------------

  Future<String> _createSceneImage(
    Scene scene,
    int index,
  ) async {
    final dir = await _workDirectory();

    final file = File(
      '${dir.path}/scene_$index.png',
    );

    const width = 1280.0;
    const height = 720.0;

    final recorder = ui.PictureRecorder();

    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(
        0,
        0,
        width,
        height,
      ),
    );

    final colors = <List<Color>>[
      [
        const Color(0xFF111827),
        const Color(0xFF312E81),
      ],
      [
        const Color(0xFF0F172A),
        const Color(0xFF581C87),
      ],
      [
        const Color(0xFF172554),
        const Color(0xFF1E3A8A),
      ],
      [
        const Color(0xFF1F2937),
        const Color(0xFF7C2D12),
      ],
      [
        const Color(0xFF18181B),
        const Color(0xFF831843),
      ],
      [
        const Color(0xFF052E16),
        const Color(0xFF14532D),
      ],
    ];

    final selected = colors[
        scene.colorIndex % colors.length];

    final gradient = ui.Gradient.linear(
      const Offset(0, 0),
      const Offset(width, height),
      selected,
    );

    final backgroundPaint = Paint()
      ..shader = gradient;

    canvas.drawRect(
      const Rect.fromLTWH(
        0,
        0,
        width,
        height,
      ),
      backgroundPaint,
    );

    // Decorative circles
    final circlePaint1 = Paint()
      ..color = Colors.white.withOpacity(0.08);

    final circlePaint2 = Paint()
      ..color = const Color(0xFFB388FF).withOpacity(0.10);

    canvas.drawCircle(
      const Offset(110, 100),
      150,
      circlePaint1,
    );

    canvas.drawCircle(
      const Offset(1170, 610),
      220,
      circlePaint2,
    );

    canvas.drawCircle(
      const Offset(1050, 130),
      80,
      circlePaint1,
    );

    // NEXO AI title
    final titlePainter = TextPainter(
      text: const TextSpan(
        text: 'NEXO AI',
        style: TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    titlePainter.layout();

    titlePainter.paint(
      canvas,
      const Offset(55, 45),
    );

    // Scene number
    final scenePainter = TextPainter(
      text: TextSpan(
        text: 'SCENE ${index + 1}',
        style: const TextStyle(
          color: Color(0xFFCEB5FF),
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    scenePainter.layout();

    scenePainter.paint(
      canvas,
      const Offset(58, 95),
    );

    // Main script text
    final textPainter = TextPainter(
      text: TextSpan(
        text: scene.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 8,
    );

    textPainter.layout(
      maxWidth: 1080,
    );

    final textX =
        (width - textPainter.width) / 2;

    final textY =
        (height - textPainter.height) / 2;

    // Text background
    final boxPaint = Paint()
      ..color = Colors.black.withOpacity(0.32);

    final boxRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        textX - 40,
        textY - 35,
        textPainter.width + 80,
        textPainter.height + 70,
      ),
      const Radius.circular(28),
    );

    canvas.drawRRect(
      boxRect,
      boxPaint,
    );

    textPainter.paint(
      canvas,
      Offset(textX, textY),
    );

    // Bottom line
    final linePaint = Paint()
      ..color = const Color(0xFFB388FF)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      const Offset(55, 665),
      const Offset(1225, 665),
      linePaint,
    );

    final picture = recorder.endRecording();

    final image = await picture.toImage(
      width.toInt(),
      height.toInt(),
    );

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      throw Exception(
        'Scene image create नहीं हुई।',
      );
    }

    final bytes = byteData.buffer.asUint8List();

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return file.path;
  }

  // ------------------------------------------------------------
  // FFMPEG COMMAND QUOTING
  // ------------------------------------------------------------

  String _quote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  // ------------------------------------------------------------
  // CREATE VIDEO
  // ------------------------------------------------------------

  Future<String> _createVideo(
    String voicePath,
    List<String> sceneImages,
  ) async {
    final dir = await _workDirectory();

    final output = File(
      '${dir.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    if (await output.exists()) {
      await output.delete();
    }

    if (sceneImages.isEmpty) {
      throw Exception(
        'कोई scene image नहीं मिली।',
      );
    }

    _setStatus(
      'Video scenes तैयार हो रहे हैं...',
    );

    // ----------------------------------------------------------
    // Create concat file.
    //
    // Each image is displayed for 5 seconds.
    // The audio is attached later and -shortest makes the final
    // video stop when voice finishes.
    // ----------------------------------------------------------

    final concatFile = File(
      '${dir.path}/scenes.txt',
    );

    final buffer = StringBuffer();

    for (final image in sceneImages) {
      buffer.writeln(
        "file '${image.replaceAll("'", "'\\''")}'",
      );
      buffer.writeln('duration 5');
    }

    // Last frame repeated so concat demuxer handles it correctly.
    buffer.writeln(
      "file '${sceneImages.last.replaceAll("'", "'\\''")}'",
    );

    await concatFile.writeAsString(
      buffer.toString(),
      flush: true,
    );

    _setStatus(
      'FFmpeg video बना रहा है...',
    );

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',

      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      _quote(concatFile.path),

      '-i',
      _quote(voicePath),

      '-map',
      '0:v:0',
      '-map',
      '1:a:0',

      '-c:v',
      'libx264',

      '-preset',
      'veryfast',

      '-pix_fmt',
      'yuv420p',

      '-r',
      '30',

      '-c:a',
      'aac',

      '-b:a',
      '128k',

      '-shortest',

      '-movflags',
      '+faststart',

      _quote(output.path),
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final code =
        await session.getReturnCode();

    if (ReturnCode.isSuccess(code)) {
      if (await output.exists()) {
        final size = await output.length();

        if (size > 10000) {
          return output.path;
        }
      }

      throw Exception(
        'FFmpeg ने video output नहीं बनाया।',
      );
    }

    final logs =
        await session.getOutput();

    throw Exception(
      'FFmpeg video creation failed.\n\n$logs',
    );
  }

  // ------------------------------------------------------------
  // FULL GENERATION
  // ------------------------------------------------------------

  Future<void> _createFullVideo() async {
    final script =
        _scriptController.text.trim();

    if (script.isEmpty) {
      _showMessage(
        'पहले अपनी Hindi script लिखें।',
      );
      return;
    }

    if (_working) {
      return;
    }

    setState(() {
      _working = true;
      _error = null;
      _videoPath = null;
      _voicePath = null;
      _status = 'काम शुरू हो रहा है...';
    });

    try {
      // 1. Make voice
      final voice =
          await _createHindiVoice(script);

      if (!mounted) return;

      setState(() {
        _voicePath = voice;
      });

      // 2. Split script
      _setStatus(
        'Script को scenes में बदला जा रहा है...',
      );

      final scenes =
          _makeScenes(script);

      if (scenes.isEmpty) {
        throw Exception(
          'Script से scene नहीं बन पाए।',
        );
      }

      // 3. Create scene images
      final images = <String>[];

      for (int i = 0; i < scenes.length; i++) {
        _setStatus(
          'Scene ${i + 1}/${scenes.length} तैयार हो रहा है...',
        );

        final image =
            await _createSceneImage(
          scenes[i],
          i,
        );

        images.add(image);
      }

      // 4. Create MP4
      final video =
          await _createVideo(
        voice,
        images,
      );

      if (!mounted) return;

      setState(() {
        _videoPath = video;
        _status = 'Video तैयार है!';
      });

      // 5. Preview
      await _openVideo(video);

      if (mounted) {
        _showMessage(
          'NEXO AI video सफलतापूर्वक बन गई।',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _status = 'Video नहीं बन पाई।';
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // VIDEO PREVIEW
  // ------------------------------------------------------------

  Future<void> _openVideo(
    String path,
  ) async {
    await _videoController?.dispose();

    final controller =
        VideoPlayerController.file(
      File(path),
    );

    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _videoController = controller;
    });

    await controller.play();

    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // ------------------------------------------------------------
  // SHARE
  // ------------------------------------------------------------

  Future<void> _shareVideo() async {
    final path = _videoPath;

    if (path == null) {
      _showMessage(
        'पहले video बनाएं।',
      );
      return;
    }

    final file = File(path);

    if (!await file.exists()) {
      _showMessage(
        'Video file नहीं मिली।',
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text: 'NEXO AI से बनाई गई video',
        files: [
          XFile(path),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF151B25),
        elevation: 0,
        title: const Row(
          children: [
            Text(
              '✦',
              style: TextStyle(
                color: Color(0xFF9C6BFF),
                fontSize: 30,
              ),
            ),
            SizedBox(width: 8),
            Text(
              'NEXO AI',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 25,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              const Text(
                'Script to Video',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'अपनी Hindi कहानी या YouTube script यहां डालें।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 18),

              Container(
                decoration:
                    BoxDecoration(
                  color:
                      const Color(0xFF111720),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                  border: Border.all(
                    color: Colors.white12,
                  ),
                ),
                padding:
                    const EdgeInsets.all(16),
                child: TextField(
                  controller:
                      _scriptController,
                  minLines: 12,
                  maxLines: 25,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.5,
                  ),
                  decoration:
                      const InputDecoration(
                    border:
                        InputBorder.none,
                    hintText:
                        'अपनी Hindi script यहां लिखें...',
                    hintStyle:
                        TextStyle(
                      color:
                          Colors.white38,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 58,
                child:
                    OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : _testHindiVoice,
                  icon: const Icon(
                    Icons.volume_up,
                    color:
                        Color(0xFFB48CFF),
    
