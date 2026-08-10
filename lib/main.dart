import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
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

  // ------------------------------------------------------------
  // DIRECTORY
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
  // HINDI TTS
  // ------------------------------------------------------------

  Future<String> _createHindiVoice(String text) async {
    final dir = await _getWorkDirectory();

    final voiceFile = File(
      '${dir.path}/nexo_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    if (await voiceFile.exists()) {
      await voiceFile.delete();
    }

    _setStatus('Hindi voice बनाई जा रही है...');

    await _tts.stop();

    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

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

        if (size > 1000) {
          return voiceFile.path;
        }
      }
    }

    throw Exception(
      'Voice file create नहीं हुई। '
      'कृपया फोन में Hindi TTS voice installed है या नहीं देखें।',
    );
  }

  // ------------------------------------------------------------
  // TEST VOICE
  // ------------------------------------------------------------

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

  // ------------------------------------------------------------
  // IMAGE URLS
  //
  // These are public Unsplash images.
  // They are downloaded to the phone first.
  // ------------------------------------------------------------

  final List<String> _schoolImages = [
    'https://images.unsplash.com/photo-1580582932707-520aed937b7b?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1509062522246-3755977927d7?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
  ];

  final List<String> _loveImages = [
    'https://images.unsplash.com/photo-1518199266791-5375a83190b7?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1522673607200-164d1b6ce486?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1516589178581-6cd7833ae3b2?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
  ];

  final List<String> _mysteryImages = [
    'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
  ];

  final List<String> _generalImages = [
    'https://images.unsplash.com/photo-1497366754035-f200968a6e72?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
    'https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?auto=format&fit=crop&w=1280&h=720&q=80&fm=jpg',
  ];

  // ------------------------------------------------------------
  // CHOOSE IMAGE CATEGORY
  // ------------------------------------------------------------

  List<String> _getImageUrls(String text) {
    final lower = text.toLowerCase();

    if (lower.contains('school') ||
        lower.contains('स्कूल') ||
        lower.contains('class') ||
        lower.contains('क्लास') ||
        lower.contains('teacher') ||
        lower.contains('टीचर') ||
        lower.contains('student') ||
        lower.contains('स्टूडेंट')) {
      return _schoolImages;
    }

    if (lower.contains('love') ||
        lower.contains('प्यार') ||
        lower.contains('प्रेम') ||
        lower.contains('दिल') ||
        lower.contains('मोहब्बत') ||
        lower.contains('romantic')) {
      return _loveImages;
    }

    if (lower.contains('mystery') ||
        lower.contains('रहस्य') ||
        lower.contains('राज') ||
        lower.contains('भूत') ||
        lower.contains('dark') ||
        lower.contains('डरावना')) {
      return _mysteryImages;
    }

    return _generalImages;
  }

  // ------------------------------------------------------------
  // DOWNLOAD IMAGE
  // ------------------------------------------------------------

  Future<File> _downloadImage(
    String url,
    Directory dir,
    int index,
  ) async {
    final imageFile = File(
      '${dir.path}/scene_$index.jpg',
    );

    try {
      _setStatus(
        'Picture $index डाउनलोड हो रही है...',
      );

      final client = HttpClient();

      client.connectionTimeout =
          const Duration(seconds: 15);

      final request = await client.getUrl(
        Uri.parse(url),
      );

      request.headers.set(
        HttpHeaders.userAgentHeader,
        'NEXO-AI/1.0',
      );

      final response = await request.close();

      if (response.statusCode != 200) {
        client.close(force: true);

        throw Exception(
          'Image download failed: ${response.statusCode}',
        );
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (previous, element) {
          previous.addAll(element);
          return previous;
        },
      );

      client.close(force: true);

      if (bytes.length < 1000) {
        throw Exception(
          'Downloaded image बहुत छोटी है।',
        );
      }

      await imageFile.writeAsBytes(
        bytes,
        flush: true,
      );

      return imageFile;
    } catch (e) {
      // Internet image fail होने पर
      // fallback picture बनाते हैं।
      return _createFallbackImage(
        dir,
        index,
      );
    }
  }

  // ------------------------------------------------------------
  // FALLBACK PICTURE
  //
  // Creates a valid PPM image without any extra package.
  // ------------------------------------------------------------

  Future<File> _createFallbackImage(
    Directory dir,
    int index,
  ) async {
    final file = File(
      '${dir.path}/scene_$index.ppm',
    );

    const int width = 1280;
    const int height = 720;

    final List<int> bytes = [];

    bytes.addAll(
      'P6\n$width $height\n255\n'.codeUnits,
    );

    final Random random = Random(index * 99);

    final int r1 = 30 + random.nextInt(60);
    final int g1 = 30 + random.nextInt(60);
    final int b1 = 70 + random.nextInt(80);

    final int r2 = 80 + random.nextInt(80);
    final int g2 = 30 + random.nextInt(60);
    final int b2 = 100 + random.nextInt(100);

    for (int y = 0; y < height; y++) {
      final double p = y / height;

      final int r =
          (r1 + ((r2 - r1) * p)).round();

      final int g =
          (g1 + ((g2 - g1) * p)).round();

      final int b =
          (b1 + ((b2 - b1) * p)).round();

      for (int x = 0; x < width; x++) {
        bytes.add(r);
        bytes.add(g);
        bytes.add(b);
      }
    }

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return file;
  }

  // ------------------------------------------------------------
  // AUDIO DURATION
  // ------------------------------------------------------------

  Future<double> _getAudioDuration(
    String voicePath,
  ) async {
    final session =
        await FFprobeKit.getMediaInformation(
      voicePath,
    );

    final information =
        session.getMediaInformation();

    if (information == null) {
      throw Exception(
        'Voice duration पता नहीं चल सकी।',
      );
    }

    final durationString =
        information.getDuration();

    final duration =
        double.tryParse(
              durationString ?? '',
            ) ??
            0;

    if (duration <= 0) {
      throw Exception(
        'Voice duration invalid है।',
      );
    }

    return duration;
  }

  // ------------------------------------------------------------
  // FFMPEG VIDEO
  // ------------------------------------------------------------

  Future<String> _createVideo(
    String voicePath,
  ) async {
    final dir =
        await _getWorkDirectory();

    final outputFile = File(
      '${dir.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    _setStatus(
      'Voice की duration पता की जा रही है...',
    );

    final audioDuration =
        await _getAudioDuration(
      voicePath,
    );

    final imageUrls =
        _getImageUrls(
      _scriptController.text,
    );

    final imageFiles =
        <File>[];

    final maxImages =
        min(imageUrls.length, 3);

    // ----------------------------------------------------------
    // DOWNLOAD 3 PICTURES
    // ----------------------------------------------------------

    for (int i = 0; i < maxImages; i++) {
      final image =
          await _downloadImage(
        imageUrls[i],
        dir,
        i + 1,
      );

      imageFiles.add(image);
    }

    if (imageFiles.isEmpty) {
      throw Exception(
        'कोई picture तैयार नहीं हुई।',
      );
    }

    _setStatus(
      'Pictures को video scenes में बदला जा रहा है...',
    );

    // ----------------------------------------------------------
    // EACH IMAGE DURATION
    // ----------------------------------------------------------

    final sceneDuration =
        audioDuration / imageFiles.length;

    final inputs = <String>[];

    final filters = <String>[];

    for (int i = 0;
        i < imageFiles.length;
        i++) {
      final image =
          _ffmpegQuote(
        imageFiles[i].path,
      );

      // -loop 1 = image को लगातार चलाओ
      // -t = इस scene की duration
      inputs.add(
        '-loop 1 -t ${sceneDuration.toStringAsFixed(3)} -i $image',
      );

      // हल्का zoom/pan effect.
      //
      // अगर zoompan किसी device पर problem करे,
      // तो scale + crop वाला भाग फिर भी काम करेगा.
      filters.add(
        '[$i:v]'
        'scale=1400:900:force_original_aspect_ratio=increase,'
        'crop=1280:720,'
        'zoompan='
        'z=\'min(zoom+0.0008,1.10)\':'
        'x=\'iw/2-(iw/zoom/2)\':'
        'y=\'ih/2-(ih/zoom/2)\':'
        'd=${(sceneDuration * 30).round()}:'
        's=1280x720:'
        'fps=30'
        '[v$i]',
      );
    }

    final concatInputs =
        List.generate(
      imageFiles.length,
      (i) => '[v$i]',
    ).join();

    filters.add(
      '$concatInputs'
      'concat=n=${imageFiles.length}:v=1:a=0,'
      'format=yuv420p[vout]',
    );

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',

      ...inputs,

      '-i',
      _ffmpegQuote(voicePath),

      '-filter_complex',
      _ffmpegQuote(
        filters.join(';'),
      ),

      '-map',
      '[vout]',

      '-map',
      '${imageFiles.length}:a:0',

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

      _ffmpegQuote(
        outputFile.path,
      ),
    ].join(' ');

    _setStatus(
      'FFmpeg video बना रहा है...',
    );

    final session =
        await FFmpegKit.execute(
      command,
    );

    final returnCode =
        await session.getReturnCode();

    if (ReturnCode.isSuccess(
      returnCode,
    )) {
      if (await outputFile.exists()) {
        final size =
            await outputFile.length();

        if (size > 10000) {
          return outputFile.path;
        }
      }

      throw Exception(
        'FFmpeg ने video file नहीं बनाई।',
      );
    }

    final logs =
        await session.getOutput();

    throw Exception(
      'FFmpeg video creation failed.\n\n'
      '${logs ?? 'No FFmpeg output'}',
    );
  }

  // ------------------------------------------------------------
  // FULL VIDEO
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
      _status = 'काम शुरू हो रहा है...';
    });

    try {
      // ---------------------------------------------
      // STEP 1: Hindi voice
      // ---------------------------------------------

      final voice =
          await _createHindiVoice(
        text,
      );

      if (!mounted) return;

      setState(() {
        _voicePath = voice;
      });

      // ---------------------------------------------
      // STEP 2: Pictures + Video
      // ---------------------------------------------

      final video =
          await _createVideo(
        voice,
      );

      if (!mounted) return;

      setState(() {
        _videoPath = video;
        _status = 'Video तैयार है!';
      });

      // ---------------------------------------------
      // STEP 3: Preview
      // ---------------------------------------------

      await _openVideo(
        video,
      );

      if (mounted) {
        _showMessage(
          '🎉 Video सफलतापूर्वक बन गया!',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _status = 'Video नहीं बन पाया।';
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
  // OPEN VIDEO
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
      _videoController =
          controller;
    });

    await controller.play();
  }

  // ------------------------------------------------------------
  // SHARE VIDEO
  // ------------------------------------------------------------

  Future<void> _shareVideo() async {
    final path =
        _videoPath;

    if (path == null) {
      _showMessage(
        'पहले video बनाएं।',
      );
      return;
    }

    final file =
        File(path);

    if (!await file.exists()) {
      _showMessage(
        'Video file नहीं मिली।',
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text:
            'NEXO AI से बनाया गया video',
        files: [
          XFile(path),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // FFMPEG QUOTE
  // ------------------------------------------------------------

  String _ffmpegQuote(
    String path,
  ) {
    return "'${path.replaceAll(
      "'",
      "'\\''",
    )}'";
  }

  // ------------------------------------------------------------
  // STATUS
  // ------------------------------------------------------------

  void _setStatus(
    String status,
  ) {
    if (!mounted) return;

    setState(() {
      _status = status;
    });
  }

  // ------------------------------------------------------------
  // MESSAGE
  // ------------------------------------------------------------

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

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
        child:
            SingleChildScrollView(
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
                  fontSize: 27,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              const Text(
                'Hindi script डालें और NEXO AI voice + pictures के साथ MP4 video बनाएगा।',
       
