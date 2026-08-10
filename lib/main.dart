import 'dart:io';
import 'dart:math';

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
        scaffoldBackgroundColor: const Color(0xFF080B12),
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

  // ------------------------------------------------------------
  // HINDI TTS
  // ------------------------------------------------------------

  Future<String> _createHindiVoice(String text) async {
    final dir = await _getWorkDirectory();

    final file = File(
      '${dir.path}/nexo_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    if (await file.exists()) {
      await file.delete();
    }

    setState(() {
      _status = 'Hindi voice बनाई जा रही है...';
    });

    await _tts.stop();

    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(0.95);

    final result = await _tts.synthesizeToFile(
      text,
      file.path,
      true,
    );

    if (result != 1) {
      throw Exception(
        'Hindi TTS audio file नहीं बन सकी।',
      );
    }

    for (int i = 0; i < 40; i++) {
      await Future.delayed(
        const Duration(milliseconds: 300),
      );

      if (await file.exists()) {
        final size = await file.length();

        if (size > 1000) {
          return file.path;
        }
      }
    }

    throw Exception(
      'Hindi voice file create नहीं हुई।',
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
      await _tts.setSpeechRate(0.47);
      await _tts.setVolume(1.0);
      await _tts.setPitch(0.95);

      await _tts.speak(text);
    } catch (e) {
      _showMessage(
        'Hindi voice error: $e',
      );
    }
  }

  // ------------------------------------------------------------
  // SCRIPT SCENES
  // ------------------------------------------------------------

  List<String> _makeScenes(String text) {
    final clean = text
        .replaceAll('\r', '')
        .trim();

    if (clean.isEmpty) {
      return [];
    }

    final paragraphs = clean
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (paragraphs.length >= 2) {
      return paragraphs;
    }

    final sentences = clean
        .split(RegExp(r'(?<=[।!?])\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final List<String> scenes = [];

    String current = '';

    for (final sentence in sentences) {
      current += '$sentence ';

      if (current.length > 180) {
        scenes.add(current.trim());
        current = '';
      }
    }

    if (current.trim().isNotEmpty) {
      scenes.add(current.trim());
    }

    if (scenes.isEmpty) {
      scenes.add(clean);
    }

    return scenes;
  }

  // ------------------------------------------------------------
  // CREATE SVG VISUALS
  // ------------------------------------------------------------

  Future<List<String>> _createSceneImages(
    List<String> scenes,
  ) async {
    final dir = await _getWorkDirectory();

    final List<String> images = [];

    final colors = [
      '#17102B',
      '#0B2638',
      '#24120E',
      '#10251C',
      '#27152A',
      '#101B35',
      '#281F0C',
      '#14252A',
    ];

    for (int i = 0; i < scenes.length; i++) {
      setState(() {
        _status =
            'Scene ${i + 1}/${scenes.length} का visual बनाया जा रहा है...';
      });

      final imagePath =
          '${dir.path}/scene_$i.svg';

      final safeText = _escapeXml(
        scenes[i].length > 180
            ? '${scenes[i].substring(0, 180)}...'
            : scenes[i],
      );

      final color =
          colors[i % colors.length];

      final svg = '''
<svg xmlns="http://www.w3.org/2000/svg"
width="1280"
height="720"
viewBox="0 0 1280 720">

<defs>

<linearGradient id="bg"
x1="0"
y1="0"
x2="1"
y2="1">

<stop offset="0%"
stop-color="$color"/>

<stop offset="100%"
stop-color="#05070D"/>

</linearGradient>

<filter id="shadow">
<feDropShadow
dx="0"
dy="8"
stdDeviation="12"
flood-opacity="0.5"/>
</filter>

</defs>

<rect
width="1280"
height="720"
fill="url(#bg)"/>

<circle
cx="${180 + (i * 83) % 850}"
cy="150"
r="110"
fill="#8B5CF6"
opacity="0.10"/>

<circle
cx="${1000 - (i * 71) % 600}"
cy="560"
r="180"
fill="#06B6D4"
opacity="0.08"/>

<text
x="80"
y="100"
font-family="sans-serif"
font-size="34"
font-weight="bold"
fill="#BFA8FF">
NEXO AI
</text>

<text
x="80"
y="185"
font-family="sans-serif"
font-size="30"
font-weight="bold"
fill="#FFFFFF">
SCENE ${i + 1}
</text>

<rect
x="70"
y="230"
width="1140"
height="330"
rx="32"
fill="#000000"
opacity="0.35"
filter="url(#shadow)"/>

<text
x="110"
y="310"
font-family="sans-serif"
font-size="30"
font-weight="bold"
fill="#FFFFFF">

<tspan x="110" dy="0">
$safeText
</tspan>

</text>

<text
x="80"
y="650"
font-family="sans-serif"
font-size="22"
fill="#C9C9D4">
Script to Video • Hindi AI Voice
</text>

</svg>
''';

      await File(imagePath).writeAsString(svg);

      images.add(imagePath);
    }

    return images;
  }

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ------------------------------------------------------------
  // CREATE BACKGROUND MUSIC
  // ------------------------------------------------------------

  Future<String> _createBackgroundMusic() async {
    final dir = await _getWorkDirectory();

    final musicPath =
        '${dir.path}/background_music.wav';

    setState(() {
      _status = 'Background music तैयार की जा रही है...';
    });

    final command = [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=220:sample_rate=44100',
      '-t',
      '60',
      '-filter_complex',
      'volume=0.06',
      musicPath,
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final code =
        await session.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      throw Exception(
        'Background music create नहीं हुई।',
      );
    }

    return musicPath;
  }

  // ------------------------------------------------------------
  // CREATE SOUND EFFECT
  // ------------------------------------------------------------

  Future<String> _createSoundEffect() async {
    final dir = await _getWorkDirectory();

    final soundPath =
        '${dir.path}/scene_sfx.wav';

    final command = [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=880:sample_rate=44100',
      '-t',
      '0.35',
      '-af',
      'afade=t=out:st=0.05:d=0.30,volume=0.12',
      soundPath,
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final code =
        await session.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      throw Exception(
        'Sound effect create नहीं हुआ।',
      );
    }

    return soundPath;
  }

  // ------------------------------------------------------------
  // CREATE VIDEO
  // ------------------------------------------------------------

  Future<String> _createVideo(
    String voicePath,
    List<String> scenes,
  ) async {
    final dir =
        await _getWorkDirectory();

    final outputFile = File(
      '${dir.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final images =
        await _createSceneImages(scenes);

    final music =
        await _createBackgroundMusic();

    final sfx =
        await _createSoundEffect();

    setState(() {
      _status =
          'Voice + images + music + sound effects मिलाए जा रहे हैं...';
    });

    /*
      सभी scene images को 5 सेकंड के clips में बदलना।
    */

    final inputs = <String>[];

    for (final image in images) {
      inputs.add(
        '-loop 1 -t 5 -i ${_quote(image)}',
      );
    }

    final voiceInput =
        '-i ${_quote(voicePath)}';

    final musicInput =
        '-stream_loop -1 -i ${_quote(music)}';

    final sfxInput =
        '-stream_loop -1 -i ${_quote(sfx)}';

    final filterParts = <String>[];

    for (int i = 0; i < images.length; i++) {
      filterParts.add(
        '[$i:v]scale=1280:720:force_original_aspect_ratio=decrease,'
        'pad=1280:720:(ow-iw)/2:(oh-ih)/2,'
        'zoompan=z=\'min(zoom+0.0007,1.08)\':'
        'x=\'iw/2-(iw/zoom/2)\':'
        'y=\'ih/2-(ih/zoom/2)\':'
        'd=150:s=1280x720:fps=30,'
        'format=yuv420p[v$i]',
      );
    }

    final concatInputs = List.generate(
      images.length,
      (i) => '[v$i]',
    ).join();

    filterParts.add(
      '$concatInputs'
      'concat=n=${images.length}:v=1:a=0[video]',
    );

    final videoFilter =
        filterParts.join(';');

    final audioFilter =
        '[${images.length}:a]'
        'volume=1.0[voice];'
        '[${images.length + 1}:a]'
        'volume=0.055[music];'
        '[${images.length + 2}:a]'
        'volume=0.08[sfx];'
        '[voice][music][sfx]'
        'amix=inputs=3:duration=first:dropout_transition=2'
        '[audio]';

    final fullFilter =
        '$videoFilter;$audioFilter';

    final command = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',

      ...inputs,

      voiceInput,
      musicInput,
      sfxInput,

      '-filter_complex',
      _quote(fullFilter),

      '-map',
      '[video]',

      '-map',
      '[audio]',

      '-c:v',
      'mpeg4',

      '-q:v',
      '4',

      '-pix_fmt',
      'yuv420p',

      '-c:a',
      'aac',

      '-b:a',
      '160k',

      '-shortest',

      '-movflags',
      '+faststart',

      _quote(outputFile.path),
    ].join(' ');

    final session =
        await FFmpegKit.execute(command);

    final returnCode =
        await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      if (await outputFile.exists()) {
        final size =
            await outputFile.length();

        if (size > 10000) {
          return outputFile.path;
        }
      }

      throw Exception(
        'Video output file नहीं मिली।',
      );
    }

    final logs =
        await session.getOutput();

    throw Exception(
      'FFmpeg video creation failed.\n\n$logs',
    );
  }

  String _quote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  // ------------------------------------------------------------
  // COMPLETE VIDEO
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
      final scenes =
          _makeScenes(text);

      if (scenes.isEmpty) {
        throw Exception(
          'Script से scene नहीं बन सके।',
        );
      }

      final voice =
          await _createHindiVoice(text);

      if (mounted) {
        setState(() {
          _voicePath = voice;
        });
      }

      final video =
          await _createVideo(
        voice,
        scenes,
      );

      if (mounted) {
        setState(() {
          _videoPath = video;
          _status =
              'Video सफलतापूर्वक तैयार है।';
        });
      }

      await _openVideo(video);

      if (mounted) {
        _showMessage(
          'NEXO AI video तैयार हो गया!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = 'Video नहीं बन सका।';
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
  // VIDEO PLAYER
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
  }

  // ------------------------------------------------------------
  // SHARE
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
                fontSize: 25,
                fontWeight:
                    FontWeight.bold,
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
              const SizedBox(height: 10),

              const Text(
                'Script to Video',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'अपनी Hindi कहानी या YouTube script डालें और video बनाएं।',
                style: TextStyle(
                  color:
                      Colors.white70,
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
                  border:
                      Border.all(
                    color:
                        Colors.white12,
                  ),
                ),
                padding:
                    const EdgeInsets.all(
                  16,
                ),
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

              SizedBox(
                width:
                    double.infinity,
                height: 58,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _working
                          ? null
                          : _testHindiVoice,
                  icon:
                      const Icon(
                    Icons.volume_up,
                    color:
                        Color(0xFFB48CFF),
                  ),
                  label:
                      const Text(
                    'Test Hindi Voice',
                    style:
                        TextStyle(
                      fontSize: 17,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width:
                    double.infinity,
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
                 
