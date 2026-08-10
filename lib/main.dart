import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import 'tts_service.dart';

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
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090D12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
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
  final TextEditingController scriptController =
      TextEditingController();

  bool generating = false;
  double progress = 0;

  String status = 'Ready to create your video';

  String? videoPath;

  VideoPlayerController? videoController;

  @override
  void dispose() {
    scriptController.dispose();
    videoController?.dispose();
    super.dispose();
  }

  List<String> splitScript(String text) {
    final cleaned = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();

    if (cleaned.isEmpty) return [];

    final paragraphs = cleaned
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (paragraphs.length > 1) {
      return paragraphs;
    }

    final sentences = cleaned
        .split(RegExp(r'(?<=[.!?।])\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final List<String> scenes = [];

    for (int i = 0; i < sentences.length; i += 2) {
      final end = min(i + 2, sentences.length);

      scenes.add(
        sentences.sublist(i, end).join(' '),
      );
    }

    return scenes.isEmpty ? [cleaned] : scenes;
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
      progress = 0.02;
      status = 'Script को scenes में बदला जा रहा है...';
      videoPath = null;
    });

    try {
      final scenes = splitScript(script);

      if (scenes.isEmpty) {
        throw Exception('Script खाली है।');
      }

      final tempDirectory = await getTemporaryDirectory();

      final workDirectory = Directory(
        '${tempDirectory.path}/nexo_video',
      );

      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }

      await workDirectory.create(recursive: true);

      final List<String> sceneVideos = [];

      for (int i = 0; i < scenes.length; i++) {
        if (!mounted) return;

        setState(() {
          progress =
              0.05 + ((i / scenes.length) * 0.70);
          status =
              'Scene ${i + 1}/${scenes.length}: voice तैयार हो रही है...';
        });

        final textFile = File(
          '${workDirectory.path}/scene_$i.txt',
        );

        await textFile.writeAsString(
          scenes[i],
          flush: true,
        );

        final audioFile = File(
          '${workDirectory.path}/voice_$i.wav',
        );

        await TtsService.synthesizeToFile(
          text: scenes[i],
          filePath: audioFile.path,
          language: _detectLanguage(scenes[i]),
        );

        if (!await audioFile.exists()) {
          throw Exception(
            'Voice file नहीं बन पाई: Scene ${i + 1}',
          );
        }

        final sceneVideo = File(
          '${workDirectory.path}/scene_$i.mp4',
        );

        setState(() {
          status =
              'Scene ${i + 1}/${scenes.length}: video बन रहा है...';
        });

        final safeTextPath =
            _escapeForFfmpeg(textFile.path);

        final safeAudioPath =
            _escapeForFfmpeg(audioFile.path);

        final safeOutputPath =
            _escapeForFfmpeg(sceneVideo.path);

        final color = _sceneColor(i);

        final command =
            '-y '
            '-f lavfi '
            '-i "color=c=$color:s=720x1280:r=30" '
            '-i "$safeAudioPath" '
            '-vf "drawtext='
            'fontfile=/system/fonts/Roboto-Regular.ttf:'
            'textfile=$safeTextPath:'
            'fontcolor=white:'
            'fontsize=42:'
            'line_spacing=12:'
            'x=(w-text_w)/2:'
            'y=(h-text_h)/2:'
            'box=1:'
            'boxcolor=black@0.35:'
            'boxborderw=35:'
            'borderw=2:'
            'bordercolor=black@0.5'
            '" '
            '-c:v libx264 '
            '-preset ultrafast '
            '-pix_fmt yuv420p '
            '-c:a aac '
            '-b:a 128k '
            '-shortest '
            '"$safeOutputPath"';

        final session = await FFmpegKit.execute(command);

        final returnCode = await session.getReturnCode();

        if (!ReturnCode.isSuccess(returnCode)) {
          final logs = await session.getLogsAsString();

          throw Exception(
            'FFmpeg Scene ${i + 1} failed.\n$logs',
          );
        }

        sceneVideos.add(sceneVideo.path);
      }

      setState(() {
        progress = 0.80;
        status = 'सभी scenes को एक video में जोड़ा जा रहा है...';
      });

      final concatFile = File(
        '${workDirectory.path}/concat.txt',
      );

      final concatContent = sceneVideos
          .map(
            (path) =>
                "file '${path.replaceAll("'", "'\\''")}'",
          )
          .join('\n');

      await concatFile.writeAsString(
        concatContent,
        flush: true,
      );

      final documents =
          await getApplicationDocumentsDirectory();

      final outputDirectory = Directory(
        '${documents.path}/NexoAI',
      );

      if (!await outputDirectory.exists()) {
        await outputDirectory.create(
          recursive: true,
        );
      }

      final finalVideo = File(
        '${outputDirectory.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      final concatPath =
          _escapeForFfmpeg(concatFile.path);

      final finalPath =
          _escapeForFfmpeg(finalVideo.path);

      final finalCommand =
          '-y '
          '-f concat '
          '-safe 0 '
          '-i "$concatPath" '
          '-c copy '
          '"$finalPath"';

      setState(() {
        status = 'Final MP4 तैयार हो रहा है...';
        progress = 0.90;
      });

      final finalSession =
          await FFmpegKit.execute(finalCommand);

      final finalReturnCode =
          await finalSession.getReturnCode();

      if (!ReturnCode.isSuccess(finalReturnCode)) {
        final logs =
            await finalSession.getLogsAsString();

        throw Exception(
          'Final video बनाने में error आया.\n$logs',
        );
      }

      if (!await finalVideo.exists()) {
        throw Exception(
          'MP4 file नहीं बनी।',
        );
      }

      videoPath = finalVideo.path;

      await videoController?.dispose();

      videoController =
          VideoPlayerController.file(finalVideo);

      await videoController!.initialize();

      if (!mounted) return;

      setState(() {
        progress = 1.0;
        generating = false;
        status =
            'Video successfully बन गया और Save हो गया!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🎉 आपका video तैयार है!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        generating = false;
        status = 'Error: ${e.toString()}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Video नहीं बन पाया:\n$e',
          ),
          duration:
              const Duration(seconds: 6),
        ),
      );
    }
  }

  String _detectLanguage(String text) {
    final hasHindi =
        RegExp(r'[\u0900-\u097F]').hasMatch(text);

    return hasHindi ? 'hi-IN' : 'en-US';
  }

  String _sceneColor(int index) {
    const colors = [
      '0x19113D',
      '0x102A43',
      '0x3B1F2B',
      '0x12372A',
      '0x352208',
      '0x211F3A',
    ];

    return colors[index % colors.length];
  }

  String _escapeForFfmpeg(String value) {
    return value
        .replaceAll('\\', '/')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
  }

  Future<void> shareVideo() async {
    if (videoPath == null) return;

    await SharePlus.instance.share(
      ShareParams(
        text: 'Created with NEXO AI',
        files: [
          XFile(videoPath!),
        ],
      ),
    );
  }

  Future<void> playVideo() async {
    if (videoController == null) return;

    if (videoController!.value.isPlaying) {
      await videoController!.pause();
    } else {
      await videoController!.play();
    }

    setState(() {});
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
            crossAxisAlignment:
                CrossAxisAlignment.start,
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
                'Script डालें और voice के साथ MP4 video बनाएं.',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 25),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF151B23),
                  borderRadius:
                      BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
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
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    TextField(
                      controller:
                          scriptController,
                      minLines: 10,
                      maxLines: 18,
                      decoration:
                          InputDecoration(
                        hintText:
                            'अपनी पूरी script यहाँ लिखें या paste करें...',
                        filled: true,
                        fillColor:
                            const Color(0xFF0D1218),
                        border:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(
                                  15),
                          borderSide:
                              BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    if (generating)
                      Column(
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            color:
                                const Color(
                              0xFF7C4DFF,
                            ),
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height: 15,
                          ),
                        ],
                      ),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child:
                          ElevatedButton.icon(
                        onPressed: generating
                            ? null
                            : generateVideo,
                        icon: generating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .movie_creation,
                              ),
                        label: Text(
                          generating
                              ? 'Video बन रहा है...'
                              : 'Create Video',
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
                                    15),
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
                padding:
                    const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF151B23),
                  borderRadius:
                      BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color:
                          Color(0xFF9C7BFF),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(
                          color:
                              Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (videoController != null &&
                  videoController!
                      .value
                      .isInitialized) ...[
                const SizedBox(height: 25),

                const Text(
                  'Video Preview',
                  style: TextStyle(
                    fontSize: 22,
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
                        videoController!
                            .value
                            .aspectRatio,
                    child: VideoPlayer(
                      videoController!,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: playVideo,
                        icon: Icon(
                          videoController!
                                  .value
                                  .isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          videoController!
                                  .value
                                  .isPlaying
                              ? 'Pause'
                              : 'Play',
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: shareVideo,
                        icon: const Icon(
                          Icons.share,
                        ),
                        label: const Text(
                          'Save / Share',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
