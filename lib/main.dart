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
  void dispose() {
    _scriptController.dispose();
    _tts.stop();
    _videoController?.dispose();
    super.dispose();
  }

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

  // ---------------------------------------------------------
  // HINDI TTS TEST
  // ---------------------------------------------------------

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
      _showMessage(
        'Hindi voice error: $e',
      );
    }
  }

  // ---------------------------------------------------------
  // CREATE HINDI VOICE FILE
  // ---------------------------------------------------------

  Future<String> _createHindiVoice(String text) async {
    final dir = await _getWorkDirectory();

    final voiceFile = File(
      '${dir.path}/nexo_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    if (await voiceFile.exists()) {
      await voiceFile.delete();
    }

    if (mounted) {
      setState(() {
        _status = 'Hindi voice बनाई जा रही है...';
      });
    }

    await _tts.stop();

    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Important:
    // Wait for synthesis to finish before FFmpeg reads the file.
    try {
      await _tts.awaitSynthCompletion(true);
    } catch (_) {
      // Some flutter_tts versions may not support this properly.
    }

    final result = await _tts.synthesizeToFile(
      text,
      voiceFile.path,
      true,
    );

    if (result != 1) {
      throw Exception(
        'Hindi TTS voice file नहीं बन सकी।',
      );
    }

    // Wait until the file exists and its size becomes stable.
    int previousSize = -1;
    int stableCount = 0;

    for (int i = 0; i < 40; i++) {
      await Future.delayed(
        const Duration(milliseconds: 500),
      );

      if (!await voiceFile.exists()) {
        continue;
      }

      final size = await voiceFile.length();

      if (size > 1000 && size == previousSize) {
        stableCount++;

        if (stableCount >= 3) {
          break;
        }
      } else {
        stableCount = 0;
      }

      previousSize = size;
    }

    if (!await voiceFile.exists()) {
      throw Exception(
        'Voice file create नहीं हुई।',
      );
    }

    final fileSize = await voiceFile.length();

    if (fileSize < 1000) {
      throw Exception(
        'Hindi voice file बहुत छोटी है। फोन में Hindi TTS voice check करें।',
      );
    }

    // Check WAV header.
    final bytes = await voiceFile.openRead(0, 12).fold<List<int>>(
      [],
      (previous, element) => previous..addAll(element),
    );

    if (bytes.length < 12) {
      throw Exception(
        'Voice WAV file अधूरी बनी है।',
      );
    }

    final riff =
        String.fromCharCodes(bytes.sublist(0, 4));

    final wave =
        String.fromCharCodes(bytes.sublist(8, 12));

    if (riff != 'RIFF' || wave != 'WAVE') {
      throw Exception(
        'Android TTS ने सही WAV audio नहीं बनाया। '
        'Hindi TTS engine को फिर से check करें।',
      );
    }

    return voiceFile.path;
  }

  // ---------------------------------------------------------
  // FFMPEG PATH QUOTE
  // ---------------------------------------------------------

  String _ffmpegQuote(String path) {
    final escaped = path.replaceAll(
      "'",
      "'\\''",
    );

    return "'$escaped'";
  }

  // ---------------------------------------------------------
  // CREATE VIDEO
  // ---------------------------------------------------------

  Future<String> _createVideo(String voicePath) async {
    final dir = await _getWorkDirectory();

    final outputFile = File(
      '${dir.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    if (mounted) {
      setState(() {
        _status = 'Video बनाई जा रही है...';
      });
    }

    final audio = _ffmpegQuote(voicePath);
    final output = _ffmpegQuote(outputFile.path);

    /*
      1280x720 dark background video.

      Voice की duration जितनी होगी,
      video भी उतनी ही देर चलेगी.
    */

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',

      '-f',
      'lavfi',

      '-i',
      'color=c=0x111827:s=1280x720:r=30',

      '-i',
      audio,

      '-map',
      '0:v:0',

      '-map',
      '1:a:0',

      '-c:v',
      'mpeg4',

      '-q:v',
      '5',

      '-pix_fmt',
      'yuv420p',

      '-c:a',
      'aac',

      '-b:a',
      '128k',

      '-shortest',

      '-movflags',
      '+faststart',

      output,
    ].join(' ');

    final session = await FFmpegKit.execute(
      command,
    );

    final returnCode =
        await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      if (await outputFile.exists()) {
        final size = await outputFile.length();

        if (size > 10000) {
          return outputFile.path;
        }
      }

      throw Exception(
        'FFmpeg ने video file नहीं बनाई।',
      );
    }

    final logs = await session.getOutput();

    String? failStack;

    try {
      failStack =
          await session.getFailStackTrace();
    } catch (_) {}

    throw Exception(
      'FFmpeg video creation failed.\n\n'
      '$logs\n\n'
      '${failStack ?? ''}',
    );
  }

  // ---------------------------------------------------------
  // CREATE COMPLETE VIDEO
  // ---------------------------------------------------------

  Future<void> _createFullVideo() async {
    final text = _scriptController.text.trim();

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
      _status = 'काम शुरू हो रहा है...';
    });

    try {
      // STEP 1
      final voice =
          await _createHindiVoice(text);

      if (mounted) {
        setState(() {
          _voicePath = voice;
          _status =
              'Hindi voice तैयार है। Video बनाई जा रही है...';
        });
      }

      // STEP 2
      final video =
          await _createVideo(voice);

      if (mounted) {
        setState(() {
          _videoPath = video;
          _status =
              'Video सफलतापूर्वक तैयार है।';
        });
      }

      // STEP 3
      await _openVideo(video);

      if (mounted) {
        _showMessage(
          'NEXO AI video तैयार हो गई!',
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

  // ---------------------------------------------------------
  // VIDEO PLAYER
  // ---------------------------------------------------------

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

  // ---------------------------------------------------------
  // SHARE VIDEO
  // ---------------------------------------------------------

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

  // ---------------------------------------------------------
  // MESSAGE
  // ---------------------------------------------------------

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ---------------------------------------------------------
  // VIDEO PREVIEW
  // ---------------------------------------------------------

  Widget _buildVideoPreview() {
    final controller =
        _videoController!;

    return Container(
      margin: const EdgeInsets.only(
        top: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
            BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio:
                controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    if (controller
                        .value
                        .isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  });
                },
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                iconSize: 35,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // FEATURE CARD
  // ---------------------------------------------------------

  Widget _feature(
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151B25),
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              color:
                  const Color(0xFF2B2050),
              borderRadius:
                  BorderRadius.circular(15),
            ),
            child: Icon(
              icon,
              color:
                  const Color(0xFFA678FF),
              size: 28,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  description,
                  style:
                      const TextStyle(
                    color:
                        Colors.white60,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------

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
                color:
                    Color(0xFF9C6BFF),
                fontSize: 30,
              ),
            ),

            SizedBox(width: 8),

            Text(
              'NEXO AI',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
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
              const SizedBox(
                height: 10,
              ),

              const Text(
                'Script to Video',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              const Text(
                'अपनी कहानी या YouTube script यहाँ डालें।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(
                height: 18,
              ),

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

              const SizedBox(
                height: 18,
              ),

              // TEST VOICE
              SizedBox(
                width: double.infinity,
                height: 58,

                child:
                    OutlinedButton.icon(
                  onPressed:
                      _working
                          ? null
                          : _testHindiVoice,

                  icon: const Icon(
                    Icons.volume_up,
                    color:
                        Color(0xFFB48CFF),
                  ),

                  label: const Text(
                    'Test Hindi Voice',
                    style:
                        TextStyle(
                      fontSize: 17,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 14,
              ),

              // CREATE VIDEO
              SizedBox(
                width: double.infinity,
                height: 62,

                child:
                    ElevatedButton.icon(
                  onPressed:
                      _working
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

              const SizedBox(
                height: 18,
              ),

              // PROGRESS
              if (_working)
                Container(
                  width: double.infinity,

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
                            Color(
                          0xFF9C6BFF,
                        ),
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
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),

              // VIDEO
              if (_videoController != null &&
                  _videoController!
                      .value
                      .isInitialized)
                _buildVideoPreview(),

              // SHARE
              if (_videoPath != null)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    top: 14,
                  ),

                  child: SizedBox(
                    width:
                        double.infinity,
                    height: 55,

                    child:
                        ElevatedButton.icon(
                      onPressed:
                          _shareVideo,

                      icon: const Icon(
                        Icons.share,
                      ),

                      label:
                          const Text(
                        'Save / Share Video',
                        style:
                            TextStyle(
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(
                height: 30,
              ),

              const Text(
                'Features',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 14,
              ),

              _feature(
                Icons.text_fields,
                'Script to Video',
                'आपकी script से video project बनता है।',
              ),

              _feature(
                Icons.record_voice_over,
                'Hindi Voice',
                'Android Hindi TTS से voice बनाई जाती है।',
              ),

              _feature(
                Icons.movie,
                'MP4 Video',
                'Hindi voice के साथ MP4 video तैयार होती है।',
              ),

              _feature(
                Icons.save,
                'Save & Share',
                'Video को share किया जा सकता है।',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
