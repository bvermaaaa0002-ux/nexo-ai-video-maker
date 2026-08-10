import 'dart:io';

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
  void initState() {
    super.initState();
    _prepareTts();
  }

  Future<void> _prepareTts() async {
    try {
      await _tts.awaitSynthCompletion(true);

      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _tts.stop();
    _videoController?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // WORK DIRECTORY
  // ------------------------------------------------------------

  Future<Directory> _getWorkDirectory() async {
    final base = await getApplicationDocumentsDirectory();

    final dir = Directory(
      '${base.path}/NEXO_AI_Videos',
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  // ------------------------------------------------------------
  // HINDI VOICE
  // ------------------------------------------------------------

  Future<String> _createHindiVoice(String text) async {
    final dir = await _getWorkDirectory();

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final voiceFile = File(
      '${dir.path}/nexo_voice_$timestamp.wav',
    );

    if (await voiceFile.exists()) {
      await voiceFile.delete();
    }

    if (mounted) {
      setState(() {
        _status = 'Hindi voice तैयार की जा रही है...';
      });
    }

    try {
      // बहुत महत्वपूर्ण
      await _tts.awaitSynthCompletion(true);

      await _tts.stop();

      await Future.delayed(
        const Duration(milliseconds: 300),
      );

      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      final result = await _tts.synthesizeToFile(
        text,
        voiceFile.path,
        true,
      );

      // flutter_tts Android पर success आम तौर पर 1 देता है
      if (result != 1) {
        throw Exception(
          'Hindi TTS ने audio file बनाने में असफलता दी।',
        );
      }

      if (mounted) {
        setState(() {
          _status =
              'Hindi voice file पूरी होने का इंतजार...';
        });
      }

      // File बनने और stable होने का इंतजार
      int lastSize = -1;
      int stableCount = 0;

      for (int i = 0; i < 60; i++) {
        await Future.delayed(
          const Duration(milliseconds: 500),
        );

        if (!await voiceFile.exists()) {
          continue;
        }

        final size = await voiceFile.length();

        if (size > 10000 && size == lastSize) {
          stableCount++;

          if (stableCount >= 3) {
            break;
          }
        } else {
          stableCount = 0;
        }

        lastSize = size;
      }

      if (!await voiceFile.exists()) {
        throw Exception(
          'Hindi voice file create नहीं हुई।',
        );
      }

      final fileSize = await voiceFile.length();

      if (fileSize < 10000) {
        throw Exception(
          'Hindi voice file बहुत छोटी/अधूरी है। '
          'फोन में Hindi TTS voice installed है या नहीं check करें।',
        );
      }

      // WAV header check
      final bytes = await voiceFile.openRead(
        0,
        fileSize > 64 ? 64 : fileSize,
      ).fold<List<int>>(
        [],
        (previous, element) {
          previous.addAll(element);
          return previous;
        },
      );

      final validWav = bytes.length >= 12 &&
          String.fromCharCodes(
            bytes.sublist(0, 4),
          ) ==
              'RIFF' &&
          String.fromCharCodes(
            bytes.sublist(8, 12),
          ) ==
              'WAVE';

      if (!validWav) {
        throw Exception(
          'Android TTS ने valid WAV audio नहीं बनाई। '
          'कृपया फोन की Hindi TTS service check करें।',
        );
      }

      return voiceFile.path;
    } catch (e) {
      throw Exception(
        'Hindi Voice Error:\n$e',
      );
    }
  }

  // ------------------------------------------------------------
  // TEST VOICE
  // ------------------------------------------------------------

  Future<void> _testHindiVoice() async {
    final text = _scriptController.text.trim();

    if (text.isEmpty) {
      _showMessage(
        'पहले Hindi script लिखें।',
      );
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
      _showMessage(
        'Hindi voice error: $e',
      );
    }
  }

  // ------------------------------------------------------------
  // FFMPEG QUOTE
  // ------------------------------------------------------------

  String _ffmpegQuote(String path) {
    return "'${path.replaceAll("'", "'\\''")}'";
  }

  // ------------------------------------------------------------
  // CREATE VIDEO
  // ------------------------------------------------------------

  Future<String> _createVideo(String voicePath) async {
    final dir = await _getWorkDirectory();

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final outputFile = File(
      '${dir.path}/NEXO_AI_VIDEO_$timestamp.mp4',
    );

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    if (mounted) {
      setState(() {
        _status =
            'FFmpeg video तैयार कर रहा है...';
      });
    }

    final audio = _ffmpegQuote(voicePath);
    final output = _ffmpegQuote(outputFile.path);

    /*
      Video:
      1280 x 720
      30 FPS
      Dark background
      Hindi voice audio
    */

    final command = [
      '-y',

      '-hide_banner',

      '-loglevel',
      'error',

      // Background video
      '-f',
      'lavfi',

      '-i',
      'color=c=0x090D14:s=1280x720:r=30',

      // Hindi audio
      '-i',
      audio,

      // Video map
      '-map',
      '0:v:0',

      // Audio map
      '-map',
      '1:a:0',

      // Video codec
      '-c:v',
      'mpeg4',

      '-q:v',
      '5',

      '-pix_fmt',
      'yuv420p',

      // Audio codec
      '-c:a',
      'aac',

      '-b:a',
      '128k',

      // Audio/video same duration
      '-shortest',

      // Better MP4
      '-movflags',
      '+faststart',

      output,
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final returnCode =
        await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      if (await outputFile.exists()) {
        final size =
            await outputFile.length();

        if (size > 20000) {
          return outputFile.path;
        }
      }

      throw Exception(
        'FFmpeg ने video output नहीं बनाई।',
      );
    }

    final logs =
        await session.getOutput();

    throw Exception(
      'FFmpeg Video Error:\n\n$logs',
    );
  }

  // ------------------------------------------------------------
  // FULL VIDEO CREATION
  // ------------------------------------------------------------

  Future<void> _createFullVideo() async {
    final text =
        _scriptController.text.trim();

    if (text.isEmpty) {
      _showMessage(
        'पहले अपनी script डालें।',
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
      _videoController?.dispose();
      _videoController = null;
      _status =
          'NEXO AI काम शुरू कर रहा है...';
    });

    try {
      // STEP 1
      final voice =
          await _createHindiVoice(text);

      if (mounted) {
        setState(() {
          _voicePath = voice;
          _status =
              'Hindi voice तैयार है। अब video बन रही है...';
        });
      }

      // STEP 2
      final video =
          await _createVideo(voice);

      if (mounted) {
        setState(() {
          _videoPath = video;
          _status =
              'Video सफलतापूर्वक तैयार है!';
        });
      }

      // STEP 3
      await _openVideo(video);

      if (mounted) {
        _showMessage(
          '🎉 NEXO AI video तैयार हो गई!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status =
              'Video बनाने में समस्या हुई।';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // OPEN VIDEO
  // ------------------------------------------------------------

  Future<void> _openVideo(String path) async {
    await _videoController?.dispose();

    final controller =
        VideoPlayerController.file(
      File(path),
    );

    await controller.initialize();

    controller.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    if (mounted) {
      setState(() {
        _videoController = controller;
      });
    }

    await controller.play();
  }

  // ------------------------------------------------------------
  // SHARE VIDEO
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

    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'NEXO AI से बनाया गया video 🎬',
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

  // ------------------------------------------------------------
  // MESSAGE
  // ------------------------------------------------------------

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
                fontSize: 32,
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
          padding:
              const EdgeInsets.all(16),
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
                'अपनी कहानी या YouTube script यहाँ डालें।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 18),

              // SCRIPT BOX
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
                        'अपनी Hindi script यहाँ लिखें...',
                    hintStyle:
                        TextStyle(
                      color:
                          Colors.white38,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // TEST VOICE
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

              // CREATE VIDEO
              SizedBox(
                width: double.infinity,
                height: 62,
                child:
                    ElevatedButton.icon(
                  onPressed: _working
                      ? null
                      : _createFullVideo,
                  icon: _working
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                Colors.white,
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
                        const Color(
                      0xFF7C4DFF,
                    ),
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

              // PROGRESS
              if (_working)
                Container(
                  width:
                      double.infinity,
                  padding:
                      const EdgeInsets.all(
                    18,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFF151B25,
                    ),
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

              // ERROR
              if (_error != null)
                Container(
                  width:
                      double.infinity,
                  margin:
                      const EdgeInsets.only(
                    top: 12,
                  ),
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFF35151A,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                  ),
                  child: Text(
                    _error!,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),

              // STATUS
              if (!_working &&
                  _status.isNotEmpty &&
                  _error == null)
                Container(
                  width:
                      double.infinity,
                  margin:
                      const EdgeInsets.only(
                    top: 12,
                  ),
                  padding:
                      const EdgeInsets.all(
            
