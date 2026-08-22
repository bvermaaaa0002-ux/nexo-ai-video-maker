import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexoAIApp());
}

class NexoAIApp extends StatelessWidget {
  const NexoAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXO AI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterTts _tts = FlutterTts();

  final TextEditingController _scriptController =
      TextEditingController();

  VideoPlayerController? _videoController;

  bool _working = false;
  bool _speaking = false;

  double _progress = 0.0;

  String _status = 'Ready';

  String? _videoPath;
  String? _voicePath;

  @override
  void initState() {
    super.initState();

    _setupTts();
    _setTestScript();
  }

  Future<void> _setupTts() async {
    try {
      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('TTS setup error: $e');
    }
  }

  void _setTestScript() {
    _scriptController.text = '''
नमस्ते! यह NEXO AI का पहला वीडियो टेस्ट है।

आज हम एक ऐसी कहानी की शुरुआत कर रहे हैं,
जिसे शायद आप कभी भूल नहीं पाएंगे।

बारिश का मौसम था और स्कूल की घंटी बज चुकी थी।

लेकिन उस दिन स्कूल के पुराने कमरे में
एक ऐसी चीज मिली,
जिसने पूरी कहानी बदल दी।

क्या आपको भी अपना School Wala Pyar याद है?

अगर हाँ, तो उस इंसान को एक बार जरूर याद कीजिए।
''';
  }

  Future<Directory> _getVideoDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();

    final videoDir = Directory(
      '${appDir.path}/NEXO_AI_Videos',
    );

    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }

    return videoDir;
  }

  Future<String?> _createHindiVoice(String text) async {
    try {
      final directory = await _getVideoDirectory();

      final timestamp =
          DateTime.now().millisecondsSinceEpoch;

      final voiceFile = File(
        '${directory.path}/nexo_voice_$timestamp.wav',
      );

      await _setupTts();

      final result = await _tts.synthesizeToFile(
        text,
        voiceFile.path,
        true,
      );

      debugPrint('TTS result: $result');

      for (int i = 0; i < 30; i++) {
        await Future.delayed(
          const Duration(milliseconds: 500),
        );

        if (await voiceFile.exists()) {
          final size = await voiceFile.length();

          if (size > 1000) {
            return voiceFile.path;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Voice creation error: $e');
      return null;
    }
  }

  String _quotePath(String path) {
    return "'${path.replaceAll("'", "'\\''")}'";
  }

  Future<String?> _createVideoFromVoice(
    String voicePath,
  ) async {
    try {
      final directory = await _getVideoDirectory();

      final timestamp =
          DateTime.now().millisecondsSinceEpoch;

      final outputPath =
          '${directory.path}/NEXO_AI_$timestamp.mp4';

      final inputAudio = _quotePath(voicePath);
      final outputVideo = _quotePath(outputPath);

      final command = '''
-f lavfi
-i color=c=0x101827:s=1280x720:r=30
-i $inputAudio
-map 0:v:0
-map 1:a:0
-c:v mpeg4
-q:v 5
-pix_fmt yuv420p
-c:a aac
-b:a 128k
-shortest
-movflags +faststart
$outputVideo
''';

      final cleanCommand =
          command.replaceAll('\n', ' ');

      debugPrint(
        'FFmpeg command: $cleanCommand',
      );

      final session = await FFmpegKit.execute(
        cleanCommand,
      );

      final returnCode =
          await session.getReturnCode();

      debugPrint(
        'FFmpeg return code: $returnCode',
      );

      if (ReturnCode.isSuccess(returnCode)) {
        final file = File(outputPath);

        if (await file.exists()) {
          final size = await file.length();

          if (size > 10000) {
            return outputPath;
          }
        }
      }

      final logs = await session.getOutput();

      debugPrint(
        'FFmpeg output: $logs',
      );

      return null;
    } catch (e) {
      debugPrint(
        'Video creation error: $e',
      );

      return null;
    }
  }

  Future<void> _createVideo() async {
    if (_working) return;

    final script =
        _scriptController.text.trim();

    if (script.isEmpty) {
      _showMessage(
        'पहले अपनी script लिखें।',
      );
      return;
    }

    if (script.length < 10) {
      _showMessage(
        'Script थोड़ी बड़ी लिखें।',
      );
      return;
    }

    try {
      setState(() {
        _working = true;
        _progress = 0.05;
        _status = 'Script तैयार की जा रही है...';
        _videoPath = null;
      });

      // STEP 1
      setState(() {
        _progress = 0.15;
        _status = 'Hindi AI Voice बनाई जा रही है...';
      });

      final voicePath =
          await _createHindiVoice(script);

      if (voicePath == null) {
        throw Exception(
          'Hindi voice file नहीं बन पाई।',
        );
      }

      _voicePath = voicePath;

      // STEP 2
      setState(() {
        _progress = 0.45;
        _status = 'Voice तैयार है। Video बनाया जा रहा है...';
      });

      final videoPath =
          await _createVideoFromVoice(voicePath);

      if (videoPath == null) {
        throw Exception(
          'Video file नहीं बन पाई।',
        );
      }

      _videoPath = videoPath;

      // STEP 3
      setState(() {
        _progress = 0.85;
        _status = 'Video तैयार किया जा रहा है...';
      });

      await _openVideo(videoPath);

      setState(() {
        _progress = 1.0;
        _status = 'Video Successfully Created!';
      });

      _showMessage(
        '🎬 NEXO AI Video तैयार है!',
      );
    } catch (e) {
      setState(() {
        _status = 'Video generation failed';
      });

      _showMessage(
        'Error: $e',
      );
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

    await controller.setLooping(true);

    setState(() {
      _videoController = controller;
    });

    await controller.play();
  }

  Future<void> _testVoice() async {
    final text =
        _scriptController.text.trim();

    if (text.isEmpty) {
      _showMessage(
        'पहले कोई script लिखें।',
      );
      return;
    }

    try {
      if (_speaking) {
        await _tts.stop();

        setState(() {
          _speaking = false;
        });

        return;
      }

      await _setupTts();

      setState(() {
        _speaking = true;
      });

      await _tts.speak(text);

      if (mounted) {
        setState(() {
          _speaking = false;
        });
      }
    } catch (e) {
      setState(() {
        _speaking = false;
      });

      _showMessage(
        'Voice error: $e',
      );
    }
  }

  Future<void> _shareVideo() async {
    if (_videoPath == null) {
      _showMessage(
        'पहले video बनाएं।',
      );
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'NEXO AI Video',
          files: [
            XFile(_videoPath!),
          ],
        ),
      );
    } catch (e) {
      _showMessage(
        'Share error: $e',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _scriptController.dispose();
    _videoController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF202635),
        elevation: 0,
        title: const Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color: Color(0xFF8A4DFF),
              size: 30,
            ),
            SizedBox(width: 10),
            Text(
              'NEXO AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              const Text(
                'AI Script to Video',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'अपनी कहानी लिखें और NEXO AI से Hindi voice वाला video बनाएं।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF101720),
                  borderRadius:
                      BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                padding:
                    const EdgeInsets.all(16),
                child: TextField(
                  controller:
                      _scriptController,
                  maxLines: 18,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.5,
                  ),
                  decoration:
                      const InputDecoration(
                    border: InputBorder.none,
                    hintText:
                        'अपनी script यहाँ लिखें...',
                    hintStyle: TextStyle(
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_working) ...[
                Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 10),

                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  borderRadius:
                      BorderRadius.circular(10),
                ),

                const SizedBox(height: 8),

                Text(
                  '${(_progress * 100).toInt()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 18),
              ],

              OutlinedButton.icon(
                onPressed:
                    _working ? null : _testVoice,
                icon: Icon(
                  _speaking
                      ? Icons.stop
                      : Icons.volume_up,
                ),
                label: Text(
                  _speaking
                      ? 'Stop Hindi Voice'
                      : 'Test Hindi Voice',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                style:
                    OutlinedButton.styleFrom(
                  minimumSize:
                      const Size.fromHeight(60),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(35),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed:
                    _working ? null : _createVideo,
                icon: const Icon(
                  Icons.movie_creation,
                ),
                label: Text(
                  _working
                      ? 'Creating Video...'
                      : 'Create Video',
                  style: const TextStyle(
                    fontSize: 20,
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
                  minimumSize:
                      const Size.fromHeight(70),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(25),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              if (controller != null &&
                  controller.value.isInitialized) ...[
                const Text(
                  'Video Preview',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio:
                        controller
                            .value
                            .aspectRatio,
                    child: VideoPlayer(
                      controller,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child:
                          OutlinedButton.icon(
                        onPressed: () {
                          if (controller
                              .value
                              .isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }

                          setState(() {});
                        },
                        icon: Icon(
                          controller
                                  .value
                                  .isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: const Text(
                          'Play / Pause',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            _shareVideo,
                        icon: const Icon(
                          Icons.share,
                        ),
                        label: const Text(
                          'Share',
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 30),

              if (_videoPath != null)
                Text(
                  'Saved inside NEXO_AI_Videos',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
