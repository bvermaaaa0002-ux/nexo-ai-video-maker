import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
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
        scaffoldBackgroundColor: const Color(0xFF080C12),
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
  final String keyword;

  const Scene({
    required this.text,
    required this.keyword,
  });
}

class NexoHome extends StatefulWidget {
  const NexoHome({super.key});

  @override
  State<NexoHome> createState() => _NexoHomeState();
}

class _NexoHomeState extends State<NexoHome> {
  final TextEditingController _scriptController =
      TextEditingController();

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

  void _setStatus(String text) {
    if (!mounted) return;

    setState(() {
      _status = text;
    });
  }

  Future<void> _testVoice() async {
    final text = _scriptController.text.trim();

    if (text.isEmpty) {
      _message('पहले script लिखें।');
      return;
    }

    try {
      await _tts.stop();

      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.47);
      await _tts.setVolume(1.0);
      await _tts.setPitch(0.95);

      await _tts.speak(text);
    } catch (e) {
      _message('Voice error: $e');
    }
  }

  List<Scene> _makeScenes(String script) {
    final cleaned = script
        .replaceAll('\r', '')
        .trim();

    if (cleaned.isEmpty) {
      return [];
    }

    final paragraphs = cleaned
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final List<Scene> scenes = [];

    for (final paragraph in paragraphs) {
      final sentences = paragraph
          .split(RegExp(r'(?<=[.!?।])\s+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (sentences.isEmpty) {
        continue;
      }

      String current = '';

      for (final sentence in sentences) {
        final candidate =
            current.isEmpty ? sentence : '$current $sentence';

        if (candidate.length > 180 && current.isNotEmpty) {
          scenes.add(
            Scene(
              text: current,
              keyword: _keywordFromText(current),
            ),
          );

          current = sentence;
        } else {
          current = candidate;
        }
      }

      if (current.isNotEmpty) {
        scenes.add(
          Scene(
            text: current,
            keyword: _keywordFromText(current),
          ),
        );
      }
    }

    if (scenes.isEmpty) {
      scenes.add(
        Scene(
          text: cleaned,
          keyword: _keywordFromText(cleaned),
        ),
      );
    }

    return scenes;
  }

  String _keywordFromText(String text) {
    final lower = text.toLowerCase();

    if (lower.contains('school') ||
        lower.contains('स्कूल') ||
        lower.contains('class') ||
        lower.contains('कक्षा')) {
      return 'school';
    }

    if (lower.contains('love') ||
        lower.contains('प्यार') ||
        lower.contains('इश्क') ||
        lower.contains('दिल')) {
      return 'love';
    }

    if (lower.contains('रात') ||
        lower.contains('night') ||
        lower.contains('अंधेरा') ||
        lower.contains('dark')) {
      return 'night';
    }

    if (lower.contains('जंगल') ||
        lower.contains('forest') ||
        lower.contains('पेड़')) {
      return 'forest';
    }

    if (lower.contains('समुद्र') ||
        lower.contains('sea') ||
        lower.contains('ocean') ||
        lower.contains('beach')) {
      return 'ocean';
    }

    if (lower.contains('शहर') ||
        lower.contains('city') ||
        lower.contains('सड़क')) {
      return 'city';
    }

    if (lower.contains('बारिश') ||
        lower.contains('rain')) {
      return 'rain';
    }

    if (lower.contains('घर') ||
        lower.contains('home') ||
        lower.contains('कमरा')) {
      return 'home';
    }

    if (lower.contains('रहस्य') ||
        lower.contains('mystery') ||
        lower.contains('भूत') ||
        lower.contains('ghost')) {
      return 'mystery';
    }

    return 'cinematic';
  }

  Future<String> _downloadImage(
    String keyword,
    Directory dir,
    int index,
  ) async {
    final safeKeyword = Uri.encodeComponent(
      keyword.replaceAll(' ', ','),
    );

    final url =
        'https://loremflickr.com/1280/720/$safeKeyword';

    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'NEXO-AI/1.0',
          },
        )
        .timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200 ||
        response.bodyBytes.isEmpty) {
      throw Exception(
        'Image download failed for: $keyword',
      );
    }

    final file = File(
      '${dir.path}/scene_$index.jpg',
    );

    await file.writeAsBytes(
      response.bodyBytes,
      flush: true,
    );

    return file.path;
  }

  Future<String> _createVoice(
    String text,
    Directory dir,
  ) async {
    final voiceFile = File(
      '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    if (await voiceFile.exists()) {
      await voiceFile.delete();
    }

    _setStatus('Hindi voice बनाई जा रही है...');

    await _tts.stop();

    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.95);

    final result = await _tts.synthesizeToFile(
      text,
      voiceFile.path,
      true,
    );

    if (result != 1) {
      throw Exception(
        'Hindi TTS voice file नहीं बन पाई।',
      );
    }

    for (int i = 0; i < 40; i++) {
      await Future.delayed(
        const Duration(milliseconds: 300),
      );

      if (await voiceFile.exists()) {
        final size = await voiceFile.length();

        if (size > 2000) {
          return voiceFile.path;
        }
      }
    }

    throw Exception(
      'Voice file तैयार नहीं हुई।',
    );
  }

  Future<String> _createSceneVideo(
    Scene scene,
    String imagePath,
    String voicePath,
    Directory dir,
    int index,
  ) async {
    final output = File(
      '${dir.path}/scene_video_$index.mp4',
    );

    if (await output.exists()) {
      await output.delete();
    }

    final image = _quote(imagePath);
    final voice = _quote(voicePath);
    final out = _quote(output.path);

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',

      '-loop',
      '1',
      '-i',
      image,

      '-i',
      voice,

      '-map',
      '0:v:0',
      '-map',
      '1:a:0',

      '-vf',
      'scale=1280:720:force_original_aspect_ratio=increase,'
          'crop=1280:720,'
          'format=yuv420p',

      '-c:v',
      'mpeg4',

      '-q:v',
      '5',

      '-r',
      '30',

      '-c:a',
      'aac',

      '-b:a',
      '128k',

      '-shortest',

      '-movflags',
      '+faststart',

      out,
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final code =
        await session.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      final logs = await session.getOutput();

      throw Exception(
        'Scene video failed:\n$logs',
      );
    }

    if (!await output.exists()) {
      throw Exception(
        'Scene video file नहीं बनी।',
      );
    }

    if (await output.length() < 10000) {
      throw Exception(
        'Scene video खाली है।',
      );
    }

    return output.path;
  }

  Future<String> _concatVideos(
    List<String> videos,
    Directory dir,
  ) async {
    final listFile = File(
      '${dir.path}/videos.txt',
    );

    final buffer = StringBuffer();

    for (final video in videos) {
      buffer.writeln(
        "file '${video.replaceAll("'", "'\\''")}'",
      );
    }

    await listFile.writeAsString(
      buffer.toString(),
      flush: true,
    );

    final finalVideo = File(
      '${dir.path}/NEXO_AI_FINAL_${DateTime.now().millisecondsSinceEpoch}.mp4',
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
      _quote(listFile.path),

      '-c',
      'copy',

      '-movflags',
      '+faststart',

      _quote(finalVideo.path),
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final code =
        await session.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      final logs = await session.getOutput();

      throw Exception(
        'Final video merge failed:\n$logs',
      );
    }

    if (!await finalVideo.exists()) {
      throw Exception(
        'Final MP4 नहीं बनी।',
      );
    }

    return finalVideo.path;
  }

  Future<String> _createFinalVideo() async {
    final script =
        _scriptController.text.trim();

    if (script.isEmpty) {
      throw Exception(
        'Script खाली है।',
      );
    }

    final dir = await _workDirectory();

    final scenes = _makeScenes(script);

    if (scenes.isEmpty) {
      throw Exception(
        'Script से scenes नहीं बन सके।',
      );
    }

    _setStatus(
      '${scenes.length} scenes तैयार किए जा रहे हैं...',
    );

    final List<String> sceneVideos = [];

    for (int i = 0; i < scenes.length; i++) {
      final scene = scenes[i];

      _setStatus(
        'Scene ${i + 1}/${scenes.length}\n'
        'चित्र डाउनलोड किया जा रहा है...',
      );

      final imagePath = await _downloadImage(
        scene.keyword,
        dir,
        i,
      );

      _setStatus(
        'Scene ${i + 1}/${scenes.length}\n'
        'Voice बनाई जा रही है...',
      );

      final voicePath = await _createVoice(
        scene.text,
        dir,
      );

      _setStatus(
        'Scene ${i + 1}/${scenes.length}\n'
        'Video बनाई जा रही है...',
      );

      final sceneVideo =
          await _createSceneVideo(
        scene,
        imagePath,
        voicePath,
        dir,
        i,
      );

      sceneVideos.add(sceneVideo);
    }

    _setStatus(
      'सभी scenes को एक video में जोड़ा जा रहा है...',
    );

    return _concatVideos(
      sceneVideos,
      dir,
    );
  }

  String _quote(String value) {
    return "'${value.replaceAll(
      "'",
      "'\\''",
    )}'";
  }

  Future<void> _createVideo() async {
    if (_working) return;

    final script =
        _scriptController.text.trim();

    if (script.isEmpty) {
      _message(
        'पहले Hindi script लिखें।',
      );
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
      final video =
          await _createFinalVideo();

      if (!mounted) return;

      setState(() {
        _videoPath = video;
        _status = 'Video तैयार है।';
      });

      await _openVideo(video);

      if (mounted) {
        _message(
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

  Future<void> _openVideo(String path) async {
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
  }

  Future<void> _shareVideo() async {
    final path = _videoPath;

    if (path == null) {
      _message(
        'पहले video बनाएं।',
      );
      return;
    }

    final file = File(path);

    if (!await file.exists()) {
      _message(
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

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF151B25),
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
                fontSize: 25,
                fontWeight: FontWeight.bold,
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
              const SizedBox(height: 12),

              const Text(
                'Script to Video',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'अपनी Hindi कहानी या YouTube script डालें।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 18),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111720),
                  borderRadius:
                      BorderRadius.circular(20),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.5,
                  ),
                  decoration:
                      const InputDecoration(
                    border: InputBorder.none,
                    hintText:
                        'यहाँ अपनी Hindi script लिखें...',
                    hintStyle: TextStyle(
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : _testVoice,
                  icon: const Icon(
                    Icons.volume_up,
                    color:
                        Color(0xFFB48CFF),
                  ),
                  label: const Text(
                    'Test Hindi Voice',
                    style: TextStyle(
                      fontSize: 17,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 62,
                child: ElevatedButton.icon(
                  onPressed: _working
                      ? null
                      : _createVideo,
                  icon: _working
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.movie_creation,
                        ),
                  label: Text(
                    _working
                        ? 'Video बन रही है...'
                        : 'Create Video',
                    style:
                        const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF7C4DFF),
                    foregroundColor:
                        Colors.white,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        18,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              if (_working)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(18),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(0xFF151B25),
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        color:
                            Color(0xFF9C6BFF),
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      Text(
                        _status,
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

              if (_error != null)
                Container(
                  width: double.infinity,
                  margi
