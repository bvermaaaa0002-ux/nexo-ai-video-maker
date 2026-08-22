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

  @override
  void initState() {
    super.initState();
    _setupTts();
  }

  // -----------------------------
  // TTS SETUP
  // -----------------------------

  Future<void> _setupTts() async {
    try {
      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      await _tts.awaitSynthCompletion(true);
    } catch (e) {
      debugPrint('TTS setup error: $e');
    }
  }

  // -----------------------------
  // VIDEO DIRECTORY
  // -----------------------------

  Future<Directory> _getVideoDirectory() async {
    final appDirectory =
        await getApplicationDocumentsDirectory();

    final videoDirectory = Directory(
      '${appDirectory.path}/NEXO_AI_Videos',
    );

    if (!await videoDirectory.exists()) {
      await videoDirectory.create(recursive: true);
    }

    return videoDirectory;
  }

  // -----------------------------
  // CREATE HINDI VOICE
  // -----------------------------

  Future<String> _createHindiVoice(
    String text,
  ) async {
    final directory =
        await _getVideoDirectory();

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final voicePath =
        '${directory.path}/nexo_voice_$timestamp.wav';

    final voiceFile = File(voicePath);

    if (await voiceFile.exists()) {
      await voiceFile.delete();
    }

    await _setupTts();

    debugPrint(
      'Starting Hindi TTS...',
    );

    final result = await _tts.synthesizeToFile(
      text,
      voicePath,
      true,
    );

    debugPrint(
      'TTS result: $result',
    );

    // Wait for Android TTS to finish writing.
    for (int i = 0; i < 60; i++) {
      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      if (await voiceFile.exists()) {
        final size =
            await voiceFile.length();

        debugPrint(
          'Voice file size: $size bytes',
        );

        if (size > 10000) {
          return voicePath;
        }
      }
    }

    throw Exception(
      'Hindi voice file तैयार नहीं हुई।',
    );
  }

  // -----------------------------
  // SAFE FFmpeg PATH
  // -----------------------------

  String _quotePath(String path) {
    final escaped =
        path.replaceAll("'", "'\\''");

    return "'$escaped'";
  }

  // -----------------------------
  // CREATE MP4
  // -----------------------------

  Future<String> _createVideoFromVoice(
    String voicePath,
  ) async {
    final directory =
        await _getVideoDirectory();

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final outputPath =
        '${directory.path}/NEXO_AI_$timestamp.mp4';

    final audioInput =
        _quotePath(voicePath);

    final videoOutput =
        _quotePath(outputPath);

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',

      // Background video
      '-f',
      'lavfi',
      '-i',
      'color=c=0x101827:s=1280x720:r=30',

      // Hindi audio
      '-i',
      audioInput,

      // Mapping
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',

      // Video
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-tune',
      'stillimage',
      '-pix_fmt',
      'yuv420p',

      // Audio
      '-c:a',
      'aac',
      '-b:a',
      '128k',

      // Stop video when audio ends
      '-shortest',

      // Better MP4 compatibility
      '-movflags',
      '+faststart',

      videoOutput,
    ].join(' ');

    debugPrint(
      'FFmpeg command:\n$command',
    );

    final session =
        await FFmpegKit.execute(command);

    final returnCode =
        await session.getReturnCode();

    final output =
        await session.getOutput();

    final logs =
        await session.getLogs();

    debugPrint(
      'FFmpeg return code: $returnCode',
    );

    debugPrint(
      'FFmpeg output: $output',
    );

    debugPrint(
      'FFmpeg logs: $logs',
    );

    if (ReturnCode.isSuccess(returnCode)) {
      final videoFile =
          File(outputPath);

      if (await videoFile.exists()) {
        final size =
            await videoFile.length();

        debugPrint(
          'MP4 size: $size bytes',
        );

        if (size > 10000) {
          return outputPath;
        }
      }
    }

    String error = output;

    if (error.trim().isEmpty) {
      error = logs.toString();
    }

    throw Exception(
      'MP4 नहीं बन पाई.\n$error',
    );
  }

  // -----------------------------
  // MAIN CREATE VIDEO
  // -----------------------------

  Future<void> _createVideo() async {
    if (_working) {
      return;
    }

    final script =
        _scriptController.text.trim();

    if (script.isEmpty) {
      _showMessage(
        'पहले अपनी Script लिखें।',
      );
      return;
    }

    if (script.length < 10) {
      _showMessage(
        'कृपया कम से कम कुछ शब्दों की Script लिखें।',
      );
      return;
    }

    try {
      setState(() {
        _working = true;
        _progress = 0.05;
        _status =
            'Script तैयार की जा रही है...';
        _videoPath = null;
      });

      // STEP 1
      setState(() {
        _progress = 0.15;
        _status =
            'Hindi Voice बनाई जा रही है...';
      });

      final voicePath =
          await _createHindiVoice(script);

      // STEP 2
      setState(() {
        _progress = 0.50;
        _status =
            'MP4 Video बनाई जा रही है...';
      });

      final videoPath =
          await _createVideoFromVoice(
        voicePath,
      );

      // STEP 3
      setState(() {
        _progress = 0.85;
        _status =
            'Video Preview तैयार हो रहा है...';
      });

      await _openVideo(videoPath);

      if (!mounted) {
        return;
      }

      setState(() {
        _videoPath = videoPath;
        _progress = 1.0;
        _status =
            'Video Successfully Created!';
      });

      _showMessage(
        '🎬 NEXO AI Video तैयार है!',
      );
    } catch (e) {
      debugPrint(
        'VIDEO ERROR:\n$e',
      );

      if (mounted) {
        setState(() {
          _status =
              'Video generation failed';
        });

        String message =
            e.toString();

        message = message.replaceFirst(
          'Exception: ',
          '',
        );

        if (message.length > 600) {
          message =
              message.substring(0, 600);
        }

        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // -----------------------------
  // OPEN VIDEO
  // -----------------------------

  Future<void> _openVideo(
    String path,
  ) async {
    await _videoController?.dispose();

    final controller =
        VideoPlayerController.file(
      File(path),
    );

    await controller.initialize();

    await controller.setLooping(true);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _videoController = controller;
    });

    await controller.play();
  }

  // -----------------------------
  // TEST HINDI VOICE
  // -----------------------------

  Future<void> _testVoice() async {
    final text =
        _scriptController.text.trim();

    if (text.isEmpty) {
      _showMessage(
        'पहले Script लिखें।',
      );
      return;
    }

    try {
      if (_speaking) {
        await _tts.stop();

        if (mounted) {
          setState(() {
            _speaking = false;
          });
        }

        return;
      }

      await _setupTts();

      if (mounted) {
        setState(() {
          _speaking = true;
        });
      }

      await _tts.speak(text);

      if (mounted) {
        setState(() {
          _speaking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _speaking = false;
        });
      }

      _showMessage(
        'Voice error: $e',
      );
    }
  }

  // -----------------------------
  // SHARE VIDEO
  // -----------------------------

  Future<void> _shareVideo() async {
    final path = _videoPath;

    if (path == null) {
      _showMessage(
        'पहले Video बनाएं।',
      );
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'NEXO AI Video',
          files: [
            XFile(path),
          ],
        ),
      );
    } catch (e) {
      _showMessage(
        'Share error: $e',
      );
    }
  }

  // -----------------------------
  // MESSAGE
  // -----------------------------

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
        duration:
            const Duration(seconds: 6),
      ),
    );
  }

  // -----------------------------
  // DISPOSE
  // -----------------------------

  @override
  void dispose() {
    _tts.stop();

    _scriptController.dispose();

    _videoController?.dispose();

    super.dispose();
  }

  // -----------------------------
  // UI
  // -----------------------------

  @override
  Widget build(BuildContext context) {
    final controller =
        _videoController;

    final hasVideo =
        controller != null &&
        controller.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF202635),
        elevation: 0,
        title: const Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color:
                  Color(0xFF8A4DFF),
              size: 30,
            ),
            SizedBox(width: 10),
            Text(
              'NEXO AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,

            children: [
              const SizedBox(height: 10),

              const Text(
                'AI Script to Video',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'अपनी कहानी या Script लिखें और Hindi Voice के साथ Video बनाएं।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 20),

              // SCRIPT BOX
              Container(
                decoration:
                    BoxDecoration(
                  color:
                      const Color(0xFF101720),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                  border: Border.all(
                    color:
                        Colors.white24,
                  ),
                ),

                padding:
                    const EdgeInsets.all(
                  16,
                ),

                child: TextField(
                  controller:
                      _scriptController,

                  maxLines: 18,

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
                        'अपनी Script यहाँ लिखें...',

                    hintStyle:
                        TextStyle(
                      color:
                          Colors.white38,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // PROGRESS
              if (_working) ...[
                Text(
                  _status,
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                Text(
                  '${(_progress * 100).toInt()}%',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),
              ],

              // TEST VOICE
              OutlinedButton.icon(
                onPressed:
                    _working
                        ? null
                        : _testVoice,

                icon: Icon(
                  _speaking
                      ? Icons.stop
                      : Icons.volume_up,
                ),

                label: Text(
                  _speaking
                      ? 'Stop Hindi Voice'
                      : 'Test Hindi Voice',

                  style:
                      const TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                style:
                    OutlinedButton.styleFrom(
                  minimumSize:
                      const Size
                          .fromHeight(
                    60,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      35,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // CREATE VIDEO
              ElevatedButton.icon(
                onPressed:
                    _working
                        ? null
                        : _createVideo,

                icon: const Icon(
                  Icons.movie_creation,
                ),

                label: Text(
                  _working
                      ? 'Creating Video...'
                      : 'Create Video',

                  style:
                      const TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(
                    0xFF7C4DFF,
                  ),

                  foregroundColor:
                      Colors.white,

                  minimumSize:
                      const Size
                          .fromHeight(
                    70,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      25,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // VIDEO PREVIEW
              if (hasVideo) ...[
                const Text(
                  'Video Preview',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),

                  child: AspectRatio(
                    aspectRatio:
                        controller
                            .value
                            .aspectRatio,

                    child:
                        VideoPlayer(
                      controller,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                          OutlinedButton
                              .icon(
                        onPressed: () {
                          if (controller
                              .value
                              .isPlaying) {
                            controller
                                .pause();
                          } else {
                            controller
                                .play();
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

                        label:
                            const Text(
                          'Play / Pause',
                        ),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          ElevatedButton
                              .icon(
                        onPressed:
                            _shareVideo,

                        icon:
                            const Icon(
    
