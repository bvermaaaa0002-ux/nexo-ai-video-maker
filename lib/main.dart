import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
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
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
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
  final TextEditingController scriptController = TextEditingController();
  final FlutterTts flutterTts = FlutterTts();

  bool generating = false;
  String status = 'Ready to create your video';
  String? videoPath;

  @override
  void initState() {
    super.initState();
    _setupTts();
  }

  Future<void> _setupTts() async {
    try {
      await flutterTts.setLanguage('hi-IN');
      await flutterTts.setSpeechRate(0.48);
      await flutterTts.setPitch(1.0);
      await flutterTts.setVolume(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    scriptController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<String> _createVoice(String text, Directory dir) async {
    final audioPath =
        '${dir.path}/nexo_voice_${DateTime.now().millisecondsSinceEpoch}.mp3';

    final result = await flutterTts.synthesizeToFile(
      text,
      audioPath,
      true,
    );

    if (result == null || result == false) {
      throw Exception('Hindi voice could not be created.');
    }

    final file = File(audioPath);

    for (int i = 0; i < 20; i++) {
      if (await file.exists()) {
        final size = await file.length();
        if (size > 1000) {
          return audioPath;
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    throw Exception('Voice file was not created by Android TTS.');
  }

  String _escapeForFfmpeg(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", r"\'")
        .replaceAll(':', r'\:')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]');
  }

  Future<String> _createVideo(
    String audioPath,
    String outputPath,
    int duration,
  ) async {
    final safeOutput = _escapeForFfmpeg(outputPath);

    final command = [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=0x0B0F14:s=720x1280:r=30',
      '-i',
      "'$audioPath'",
      '-t',
      duration.toString(),
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
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-shortest',
      "'$safeOutput'",
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getOutput();
      throw Exception('FFmpeg video creation failed.\n$logs');
    }

    return outputPath;
  }

  Future<void> generateVideo() async {
    final script = scriptController.text.trim();

    if (script.isEmpty) {
      setState(() {
        status = 'पहले अपनी script लिखें।';
      });
      return;
    }

    if (generating) return;

    setState(() {
      generating = true;
      videoPath = null;
      status = 'Hindi voice बनाई जा रही है...';
    });

    try {
      final directory = await getApplicationDocumentsDirectory();

      final audioPath = await _createVoice(script, directory);

      if (!mounted) return;

      setState(() {
        status = 'Voice तैयार है। Video बनाया जा रहा है...';
      });

      final outputPath =
          '${directory.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final durationSeconds = max(
        3,
        (script.length / 12).ceil(),
      );

      await _createVideo(
        audioPath,
        outputPath,
        durationSeconds,
      );

      if (!mounted) return;

      setState(() {
        generating = false;
        videoPath = outputPath;
        status = 'Video successfully created!';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        generating = false;
        status = 'Error: $e';
      });
    }
  }

  Future<void> shareVideo() async {
    if (videoPath == null) return;

    final file = File(videoPath!);

    if (!await file.exists()) {
      setState(() {
        status = 'Video file नहीं मिली।';
      });
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(videoPath!)],
        text: 'Created with NEXO AI',
      ),
    );
  }

  Future<void> previewVoice() async {
    final text = scriptController.text.trim();

    if (text.isEmpty) {
      setState(() {
        status = 'पहले script लिखें।';
      });
      return;
    }

    try {
      await flutterTts.setLanguage('hi-IN');
      await flutterTts.speak(text);

      setState(() {
        status = 'Hindi voice चल रही है...';
      });
    } catch (e) {
      setState(() {
        status = 'Voice error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color: Color(0xFF9C7BFF),
            ),
            SizedBox(width: 10),
            Text(
              'NEXO AI',
              style: TextStyle(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Video Maker',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Script → Hindi Voice → MP4 Video',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade400,
                ),
              ),

              const SizedBox(height: 25),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF151B23),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.edit_note,
                          color: Color(0xFF9C7BFF),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Your Script',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    TextField(
                      controller: scriptController,
                      minLines: 10,
                      maxLines: 18,
                      decoration: InputDecoration(
                        hintText:
                            'अपनी Hindi script यहाँ लिखें या paste करें...',
                        filled: true,
                        fillColor: const Color(0xFF0D1218),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: generating ? null : previewVoice,
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Test Hindi Voice'),
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: generating ? null : generateVideo,
                        icon: generating
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.movie_creation),
                        label: Text(
                          generating
                              ? 'Creating Video...'
                              : 'Create Video',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C4DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF151B23),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C4DFF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.movie_creation_outlined,
                        color: Color(0xFF9C7BFF),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (videoPath != null) ...[
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151B23),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🎬 Video Ready',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'आपका MP4 video तैयार है।',
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: shareVideo,
                          icon: const Icon(Icons.share),
                          label: const Text('Save / Share Video'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 25),

              const Text(
                'Features',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const FeatureCard(
                icon: Icons.text_fields,
                title: 'Script to Video',
                description: 'आपकी script से video project बनता है।',
              ),

              const FeatureCard(
                icon: Icons.volume_up,
                title: 'Hindi Voice',
                description: 'Android की Hindi TTS voice इस्तेमाल होती है।',
              ),

              const FeatureCard(
                icon: Icons.movie,
                title: 'MP4 Export',
                description: 'Video MP4 format में तैयार होता है।',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151B23),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF9C7BFF),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
