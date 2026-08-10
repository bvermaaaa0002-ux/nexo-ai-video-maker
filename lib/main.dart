import 'dart:io';
import 'dart:math' as math;
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
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
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
  final TextEditingController _script = TextEditingController();
  final FlutterTts _tts = FlutterTts();

  VideoPlayerController? _player;

  bool _busy = false;

  String _status = '';

  String? _videoPath;

  String? _error;

  @override
  void dispose() {
    _script.dispose();
    _tts.stop();
    _player?.dispose();
    super.dispose();
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();

    final dir = Directory(
      '${base.path}/NEXO_AI_Videos',
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  String _q(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  void _statusText(String s) {
    if (!mounted) return;

    setState(() {
      _status = s;
    });
  }

  Future<void> _ttsSetup() async {
    await _tts.awaitSpeakCompletion(true);

    await _tts.setLanguage('hi-IN');

    await _tts.setSpeechRate(0.46);

    await _tts.setVolume(1.0);

    await _tts.setPitch(1.0);
  }

  Future<String> _makeVoice(
    String text,
    Directory dir,
  ) async {
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }

    _statusText(
      'Hindi voice बनाई जा रही है...',
    );

    await _ttsSetup();

    final result = await _tts.synthesizeToFile(
      text,
      path,
      true,
    );

    final ok =
        result.toString() == '1' ||
        result.toString().toLowerCase() == 'true';

    if (!ok) {
      throw Exception(
        'Hindi TTS file नहीं बनी। फोन की Text-to-Speech settings में Hindi voice install करें।',
      );
    }

    for (int i = 0; i < 40; i++) {
      await Future.delayed(
        const Duration(milliseconds: 250),
      );

      if (await file.exists()) {
        if (await file.length() > 1000) {
          return path;
        }
      }
    }

    throw Exception(
      'Hindi voice file खाली या invalid है।',
    );
  }

  Future<void> _testVoice() async {
    final text = _script.text.trim();

    if (text.isEmpty) {
      _message(
        'पहले script लिखें।',
      );
      return;
    }

    try {
      await _tts.stop();

      await _ttsSetup();

      await _tts.speak(text);
    } catch (e) {
      _message(
        'Voice error: $e',
      );
    }
  }

  List<String> _scenes(String text) {
    final clean =
        text.replaceAll('\r', ' ').trim();

    if (clean.isEmpty) {
      return [];
    }

    final parts = clean
        .split(
          RegExp(
            r'(?<=[.!?।])\s+|\n+',
          ),
        )
        .map(
          (e) => e.trim(),
        )
        .where(
          (e) => e.isNotEmpty,
        )
        .toList();

    final out = <String>[];

    String current = '';

    for (final part in parts) {
      if (current.isEmpty) {
        current = part;
      } else if (
          current.length + part.length <= 190) {
        current = '$current $part';
      } else {
        out.add(current);

        current = part;
      }
    }

    if (current.isNotEmpty) {
      out.add(current);
    }

    if (out.isEmpty) {
      out.add(clean);
    }

    if (out.length <= 10) {
      return out;
    }

    final merged = <String>[];

    for (
      int i = 0;
      i < out.length;
      i += 2
    ) {
      if (i + 1 < out.length) {
        merged.add(
          '${out[i]} ${out[i + 1]}',
        );
      } else {
        merged.add(out[i]);
      }
    }

    return merged.take(10).toList();
  }

  double _duration(String text) {
    final d =
        5.0 + text.length / 5.0;

    return d.clamp(
      5.0,
      30.0,
    );
  }

  String _kind(String text) {
    final t = text.toLowerCase();

    if (
      t.contains('school') ||
      t.contains('स्कूल') ||
      t.contains('कक्षा') ||
      t.contains('teacher') ||
      t.contains('शिक्षक') ||
      t.contains('कॉलेज')
    ) {
      return 'school';
    }

    if (
      t.contains('love') ||
      t.contains('प्यार') ||
      t.contains('प्रेम') ||
      t.contains('दिल') ||
      t.contains('इश्क') ||
      t.contains('मोहब्बत')
    ) {
      return 'love';
    }

    if (
      t.contains('mystery') ||
      t.contains('रहस्य') ||
      t.contains('राज') ||
      t.contains('अनसुलझा') ||
      t.contains('सच')
    ) {
      return 'mystery';
    }

    if (
      t.contains('night') ||
      t.contains('रात') ||
      t.contains('अंधेरा') ||
      t.contains('चांद') ||
      t.contains('चाँद')
    ) {
      return 'night';
    }

    if (
      t.contains('danger') ||
      t.contains('खतरा') ||
      t.contains('डर') ||
      t.contains('भय') ||
      t.contains('हादसा')
    ) {
      return 'danger';
    }

    return 'story';
  }

  Future<String> _scenePng(
    String text,
    int index,
    Directory dir,
  ) async {
    const width = 1280;
    const height = 720;

    final recorder =
        ui.PictureRecorder();

    final canvas = Canvas(recorder);

    final rnd = math.Random(
      index * 991 + text.length,
    );

    final bgA = [
      const Color(0xFF101827),
      const Color(0xFF20132F),
      const Color(0xFF081D2B),
      const Color(0xFF171225),
      const Color(0xFF2A1218),
    ][index % 5];

    final bgB = [
      const Color(0xFF36205A),
      const Color(0xFF0B3B4D),
      const Color(0xFF102C45),
      const Color(0xFF3A1E58),
      const Color(0xFF4B2020),
    ][index % 5];

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(1280, 720),
        [
          bgA,
          bgB,
        ],
      );

    canvas.drawRect(
      const Rect.fromLTWH(
        0,
        0,
        1280,
        720,
      ),
      paint,
    );

    final glow = Paint()
      ..color =
          const Color(0xFF8B5CF6)
              .withOpacity(0.18)
      ..maskFilter =
          const MaskFilter.blur(
        BlurStyle.normal,
        80,
      );

    canvas.drawCircle(
      Offset(
        170 +
            rnd.nextInt(220).toDouble(),
        120,
      ),
      130,
      glow,
    );

    canvas.drawCircle(
      Offset(
        1100,
        560 +
            rnd.nextInt(70).toDouble(),
      ),
      150,
      glow,
    );

    final kind = _kind(text);

    if (kind == 'school') {
      _school(canvas);
    } else if (kind == 'love') {
      _heart(canvas);
    } else if (kind == 'mystery') {
      _mystery(canvas);
    } else if (kind == 'night') {
      _night(canvas);
    } else if (kind == 'danger') {
      _danger(canvas);
    } else {
      _story(
        canvas,
        index,
      );
    }

    final title = {
      'school': 'SCHOOL MEMORY',
      'love': 'A BEAUTIFUL MEMORY',
      'mystery': 'MYSTERY',
      'night': 'THE NIGHT',
      'danger': 'DANGER',
      'story': 'STORY SCENE',
    }[kind]!;

    final badge = Paint()
      ..color =
          const Color(0xFF7C4DFF);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(
          600,
          80,
          175,
          44,
        ),
        const Radius.circular(22),
      ),
      badge,
    );

    _text(
      canvas,
      'NEXO AI  •  ${index + 1}',
      const Offset(616, 91),
      17,
      Colors.white,
      bold: true,
    );

    _text(
      canvas,
      title,
      const Offset(600, 155),
      46,
      Colors.white,
      bold: true,
      maxWidth: 600,
    );

    _text(
      canvas,
      text,
      const Offset(600, 235),
      27,
      Colors.white70,
      maxWidth: 600,
      maxLines: 7,
    );

    final picture =
        recorder.endRecording();

    final image =
        await picture.toImage(
      width,
      height,
    );

    final data =
        await image.toByteData(
      format:
          ui.ImageByteFormat.png,
    );

    image.dispose();

    if (data == null) {
      throw Exception(
        'Scene image नहीं बनी।',
      );
    }

    final path =
        '${dir.path}/scene_${index + 1}.png';

    await File(path).writeAsBytes(
      data.buffer.asUint8List(),
    );

    return path;
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    Color color, {
    bool bold = false,
    double maxWidth = 1100,
    int maxLines = 2,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold
              ? FontWeight.w800
              : FontWeight.w400,
          height: 1.3,
        ),
      ),
      textDirection:
          TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '...',
    );

    p.layout(
      maxWidth: maxWidth,
    );

    p.paint(
      canvas,
      offset,
    );
  }

  void _school(Canvas c) {
    final wall = Paint()
      ..color =
          const Color(0xFFE8E4FF);

    final roof = Paint()
      ..color =
          const Color(0xFF7C4DFF);

    final dark = Paint()
      ..color =
          const Color(0xFF28213E);

    final blue = Paint()
      ..color =
          const Color(0xFF7DD3FC);

    c.drawRect(
      const Rect.fromLTWH(
        90,
        300,
        390,
        260,
      ),
      wall,
    );

    final roofPath = Path()
      ..moveTo(65, 300)
      ..lineTo(285, 160)
      ..lineTo(510, 300)
      ..close();

    c.drawPath(
      roofPath,
      roof,
    );

    c.drawRect(
      const Rect.fromLTWH(
        235,
        405,
        100,
        155,
      ),
      dark,
    );

    for (
      int r = 0;
      r < 2;
      r++
    ) {
      for (
        int col = 0;
        col < 3;
        col++
      ) {
        c.drawRect(
          Rect.fromLTWH(
            120 + col * 110,
            335 + r * 70,
            70,
            48,
          ),
          blue,
        );
      }
    }

    c.drawRect(
      const Rect.fromLTWH(
        150,
        585,
        270,
        60,
      ),
      Paint()
        ..color =
            const Color(0xFF15251D),
    );

    _text(
      c,
      'SCHOOL',
      const Offset(205, 595),
      28,
      Colors.white,
      bold: true,
    );
  }

  void _heart(Canvas c) {
    final p = Paint()
      ..color =
          const Color(0xFFFF3B6B);

    final path = Path()
      ..moveTo(285, 550)
      ..cubicTo(
        240,
        500,
        100,
        410,
        100,
        300,
      )
      ..cubicTo(
        100,
        195,
        235,
        175,
        285,
        270,
      )
      ..cubicTo(
        335,
        175,
        470,
        195,
        470,
        300,
      )
      ..cubicTo(
        470,
        410,
        330,
        500,
        285,
        550,
      )
      ..close();

    c.drawPath(
      path,
      p,
    );

    final shine = Paint()
      ..color =
          Colors.white.withOpacity(0.30)
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 14;

    c.drawArc(
      const Rect.fromLTWH(
        170,
        225,
        85,
        120,
      ),
      math.pi * 1.05,
      math.pi * 0.65,
      false,
      shine,
    );
  }

  void _mystery(Canvas c) {
    final p = Paint()
      ..color =
          const Color(0xFFB48CFF)
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 18;

    c.drawCircle(
      const Offset(270, 315),
      120,
      p,
    );

    c.drawLine(
      const Offset(350, 400),
      const Offset(470, 520),
      p,
    );

    _text(
      c,
      '?',
      const Offset(225, 235),
      140,
      Colors.white,
      bold: true,
    );

    final dot = Paint()
      ..color =
          const Color(0xFF7C4DFF);

    for (final o in const [
      Offset(120, 180),
      Offset(470, 180),
      Offset(135, 500),
      Offset(470, 580),
    ]) {
      c.drawCircle(
        o,
        9,
        dot,
      );
    }
  }

  void _night(Canvas c) {
    final moon = Paint()
      ..color =
          const Color(0xFFFFF2B2);

    c.drawCircle(
      const Offset(270, 300),
      125,
      moon,
    );

    c.drawCircle(
      const Offset(325, 255),
      120,
      Paint()
        ..color =
            const Color(0xFF111827),
    );

    final star = Paint()
      ..color = Colors.white;

    for (final o in const [
      Offset(105, 180),
      Offset(450, 190),
      Offset(120, 430),
      Offset(445, 460),
    ]) {
      c.drawCircle(
        o,
        5,
        star,
      );
    }

    final ground = Paint()
      ..color =
          const Color(0xFF0A0F18);

    c.drawRect(
      const Rect.fromLTWH(
        0,
        570,
        520,
        150,
      ),
      ground,
    );
  }

  void _danger(Canvas c) {
    final p = Paint()
      ..color =
          const Color(0xFFFFB020);

    final path = Path()
      ..moveTo(285, 145)
      ..lineTo(495, 550)
      ..lineTo(75, 550)
      ..close();

    c.drawPath(
      path,
      p,
    );

    _text(
      c,
      '!',
      const Offset(245, 245),
      220,
      const Color(0xFF291700),
      bold: true,
    );
  }

  void _story(
    Canvas c,
    int index,
  ) {
    final body = Paint()
      ..color =
          const Color(0xFF8B5CF6);

    final dark = Paint()
      ..color =
          const Color(0xFF171225);

    final lens = Paint()
      ..color =
          const Color(0xFF67E8F9)
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 18;

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(
          95,
          250,
          380,
          255,
        ),
        const Radius.circular(35),
      ),
      body,
    );

    final top = Path()
      ..moveTo(165, 250)
      ..lineTo(225, 185)
      ..lineTo(345, 185)
      ..lineTo(405, 250)
      ..close();

    c.drawPath(
      top,
      body,
    );

    c.drawCircle(
      const Offset(285, 375),
      88,
      dark,
    );

    c.drawCircle(
      const Offset(285, 375),
      60,
      lens,
    );

    _text(
      c,
      '${index + 1}',
      const Offset(267, 348),
      42,
      Colors.white,
      bold: true,
    );
  }

  Future<String> _sceneVideo(
    String image,
    double duration,
    int index,
    Directory dir,
  ) async {
    final output =
        '${dir.path}/clip_${index + 1}.mp4';

    final cmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-loop',
      '1',
      '-i',
      _q(image),
      '-t',
      duration.toStringAsFixed(2),
      '-vf',
      'scale=1280:720:force_original_aspect_ratio=decrease,'
          'pad=1280:720:(ow-iw)/2:(oh-ih)/2,'
          'format=yuv420p',
      '-r',
      '30',
      '-c:v',
      'mpeg4',
      '-q:v',
      '4',
      '-an',
      _q(output),
    ].join(' ');

    final s =
        await FFmpegKit.execute(cmd);

    final code =
        await s.getReturnCode();

    if (!ReturnCode.isSuccess(code)) {
      throw Exception(
        'Scene ${index + 1} video failed:\n'
        '${await s.getOutput()}',
      );
    }

    final file = File(output);

    if (
      !await file.exists() ||
      await file.length() < 5000
    ) {
      throw Exception(
        'Scene ${index + 1} file नहीं बनी।',
      );
    }

    return output;
  }

  Future<String> _joinScenes(
    List<String> clips,
    Directory dir,
  ) async {
    final list =
        File('${dir.path}/concat.txt');

    final text = clips
        .map(
          (p) =>
              "file '${p.replaceAll("'", "'\\''")}'",
        )
        .join('\n');

    await list.writeAsString(
      '$text\n',
    );

    final output =
        '${dir.path}/visual.mp4';

    final cmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      _q(list.path),
      '-c',
      'copy',
      _q(output),
    ].join(' ');

    final s =
        await FFmpegKit.execute(cmd);

    if (
      !ReturnCode.isSuccess(
        await s.getReturnCode(),
      )
    ) {
      throw Exception(
        'Scenes join नहीं हुए:\n'
        '${await s.getOutput()}',
      );
    }

    return output;
  }

  Future<String> _music(
    double seconds,
    Directory dir,
  ) async {
    final output =
        '${dir.path}/music.m4a';

    final d =
        seconds.toStringAsFixed(2);

    final cmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=196:sample_rate=44100:duration=$d',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=246.94:sample_rate=44100:duration=$d',
      '-filter_complex',
      '[0:a]volume=0.045[a0];'
          '[1:a]volume=0.032[a1];'
          '[a0][a1]amix=inputs=2:duration=longest,'
          'afade=t=in:st=0:d=1,'
          'afade=t=out:st=${math.max(0, seconds - 2).toStringAsFixed(2)}:d=2[m]',
      '-map',
      '[m]',
      '-c:a',
      'aac',
      '-b:a',
      '96k',
      _q(output),
    ].join(' ');

    final s =
        await FFmpegKit.execute(cmd);

    if (
      !ReturnCode.isSuccess(
        await s.getReturnCode(),
      )
    ) {
      throw Exception(
        'Background music नहीं बनी:\n'
        '${await s.getOutput()}',
      );
    }

    return output;
  }

  Future<String> _effects(
    List<double> starts,
    double seconds,
    Directory dir,
  ) async {
    final output =
        '${dir.path}/effects.m4a';

    if (starts.isEmpty) {
      final cmd = [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=channel_layout=mono:sample_rate=44100',
        '-t',
        seconds.toStringAsFixed(2),
        '-c:a',
        'aac',
        _q(output),
      ].join(' ');

      final s =
          await FFmpegKit.execute(cmd);

      if (
        !ReturnCode.isSuccess(
          await s.getReturnCode(),
        )
      ) {
        throw Exception(
          'Silent effects track नहीं बनी।',
        );
      }

      return output;
    }

    final args = <String>[];

    final filters = <String>[];

    for (
      int i = 0;
      i < starts.length;
      i++
    ) {
      args.addAll([
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=${700 + i * 55}:sample_rate=44100:duration=0.18',
      ]);

      final delay =
          (starts[i] * 1000).round();

      filters.add(
        '[$i:a]volume=0.16,'
        'afade=t=out:st=0.04:d=0.14,'
        'adelay=$delay|$delay[e$i]',
      );
    }

    final labels =
        List.generate(
          starts.length,
          (i) => '[e$i]',
        ).join();

    final filter =
        '${filters.join(';')};'
        '$labels'
        'amix=inputs=${starts.length}:'
        'duration=longest:'
        'dropout_transition=0[e]';

    final cmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      ...args,
      '-filter_complex',
      filter,
      '-map',
      '[e]',
      '-t',
      seconds.toStringAsFixed(2),
      '-c:a',
      'aac',
      '-b:a',
      '64k',
      _q(output),
    ].join(' ');

    final s =
        await FFmpegKit.execute(cmd);

    if (
      !ReturnCode.isSuccess(
        await s.getReturnCode(),
      )
    ) {
      throw Exception(
        'Sound effects नहीं बने:\n'
        '${await s.getOutput()}',
      );
    }

    return output;
  }

  Future<String> _finalVideo(
    String visual,
    String voice,
    String music,
    String effects,
    Directory dir,
  ) async {
    final output =
        '${dir.path}/NEXO_AI_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final cmd = [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      _q(visual),
      '-i',
      _q(voice),
      '-i',
      _q(music),
      '-i',
      _q(effects),
      '-filter_complex',
      '[2:a]volume=0.10[m];'
          '[3:a]volume=0.35[s];'
          '[1:a][m][s]amix=inputs=3:duration=first:dropout_transition=2[a]',
      '-map',
      '0:v:0',
      '-map',
      '[a]',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-shortest',
      '-movflags',
      '+faststart',
      _q(output),
    ].join(' ');

    final s =
        await FFmpegKit.execute(cmd);

    if (
      !ReturnCode.isSuccess(
        await s.getReturnCode(),
      )
    ) {
      throw Exception(
        'Final video नहीं बनी:\n'
        '${await s.getOutput()}',
      );
    }

    final file = File(output);

    if (
      !await file.exists() ||
      await file.length() < 10000
    ) {
      throw Exception(
        'Final MP4 file invalid है।',
      );
    }

    return output;
  }

  Future<void> _createVideo() async {
    final script =
        _script.text.trim();

    if (script.isEmpty) {
      _message(
        'पहले script लिखें।',
      );
      return;
    }

    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _videoPath = null;
      _status =
          'काम शुरू हो रहा है...';
    });

    try {
      final dir =
          await _dir();

      final scenes =
          _scenes(script);

      if (scenes.isEmpty) {
        throw Exception(
          'Script से scene नहीं बने।',
        );
      }

      _statusText(
        '1/6 • Hindi voice बनाई जा रही है...',
      );

      final voice =
          await _makeVoice(
        script,
        dir,
      );

      _statusText(
        '2/6 • Script के अनुसार pictures बनाई जा रही हैं...',
      );

      final images = <String>[];

      final durations =
          <double>[];

      for (
        int i = 0;
        i < scenes.length;
        i++
      ) {
        images.add(
          await _scenePng(
            scenes[i],
            i,
            dir,
          ),
        );

        durations.add(
          _duration(
            scenes[i],
          ),
        );
      }

      _statusText(
        '3/6 • Pictures से video scenes बनाए जा रहे हैं...',
      );

      final clips = <String>[];

      for (
        int i = 0;
        i < images.length;
        i++
      ) {
        clips.add(
          await _sceneVideo(
            images[i],
            durations[i],
            i,
            dir,
          ),
        );
      }

      _statusText(
        '4/6 • सभी scenes जोड़े जा रहे हैं...',
      );

      final visual =
          await _joinScenes(
        clips,
        dir,
      );

      final total =
          durations.fold<double>(
        0,
        (a, b) => a + b,
      );

      final starts =
          <double>[];

      double pos = 0;

      for (final d in durations) {
        starts.add(pos);
        pos += d;
      }

      _statusText(
        '5/6 • Background music और sound effects...',
      );

      final music =
          await _music(
        total,
        dir,
      );

      final effects =
          await _effects(
        starts,
        total,
        dir,
      );

      _statusText(
        '6/6 • Voice + music + effects final video में...',
      );

      final video =
          await _finalVideo(
        visual,
        voice,
        music,
        effects,
        dir,
      );

      if (!mounted) return;

      setState(() {
        _videoPath = video;
        _status =
            'वीडियो तैयार है।';
      });

      await _openVideo(video);

      _message(
        'वीडियो सफलतापूर्वक बन गया।',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status =
              'वीडियो नहीं बन पाया।';
        });
      }
    } finally {
      if (mounted) {
        setState(
          () => _busy = false,
        );
      }
    }
  }

  Future<void> _openVideo(
    String path,
  ) async {
    await _player?.dispose();

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
      _player = controller;
    });

    await controller.play();
  }

  Future<void> _share() async {
    final path =
        _videoPath;

    if (path == null) {
      _message(
        'पहले video बनाएं।',
      );
      return;
    }

    if (!await File(path).exists()) {
      _message(
        'Video file नहीं मिली।',
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text:
            'NEXO AI से बनाया गया वीडियो',
        files: [
          XFile(path),
        ],
      ),
    );
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(text),
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
              const SizedBox(
                height: 8,
              ),
              const Text(
                'Script to Video',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                'Script डालें और NEXO AI voice, pictures, music और sound effects के साथ MP4 बनाएगा।',
                style: TextStyle(
                  color:
                      Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              Container(
                padding:
                    const EdgeInsets.all(16),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(0xFF111720),
                  borderRadius:
                      BorderRadius.circular(20),
                  border:
                      Border.all(
                    color:
                        Colors.white12,
                  ),
                ),
                child: TextField(
                  controller: _script,
                  minLines: 12,
                  maxLines: 25,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
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
              SizedBox(
                width:
                    double.infinity,
                height: 58,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : _testVoice,
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
              const SizedBox(
                height: 14,
              ),
              SizedBox(
                width:
                    double.infinity,
                height: 62,
                child:
                    ElevatedButton.icon(
                  onPressed:
                      _busy
                          ? null
                          : _createVideo,
                  icon: _busy
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
                    _busy
                        ? 'वीडियो बन रही है...'
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
                          BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              if (_busy)
                _statusCard(),
              if (_error != null)
                Container(
                  width:
                      double.infinity,
                  margin:
                      const EdgeInsets.only(
                    top: 12,
                  ),
                  padding:
                      const EdgeInsets.all(16),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(0xFF35151A),
                    borderRadius:
                        BorderRadius.circular(18),
                  ),
                  child:
                      SelectableText(
                    _error!,
                    style:
                        const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              if (
                _player != null &&
                _player!
                    .value
                    .isInitialized
              )
                _preview(),
              if (_videoPath != null)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    top: 14,
                  ),
                  child:
                      SizedBox(
                    width:
                        double.infinity,
                    height: 55,
                    child:
                        ElevatedButton.icon(
                      onPressed:
                          _share,
                      icon:
                          const Icon(
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
                Icons.image,
                'Script-based Pictures',
                'School, love, mystery, night और danger जैसे शब्दों के अनुसार अलग visual scene।',
              ),
              _feature(
                Icons.record_voice_over,
                'Hindi Voice',
                'Android Hindi TTS से narration।',
              ),
              _feature(
                Icons.music_note,
                'Background Music',
                'हल्का cinematic background track automatically।',
              ),
              _feature(
                Icons.graphic_eq,
                'Sound Effects',
                'हर scene पर छोटे sound effects।',
              ),
              _feature(
                Icons.movie,
                'MP4 Video',
                'Pictures + voice + music + effects एक MP4 में।',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard() {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(18),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFF151B25),
        borderRadius:
            BorderRadius.circular(18),
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
    );
  }

  Widget _preview() {
    final c = _player!;

    return Container(
      margin:
          const EdgeInsets.only(
        top: 20,
      ),
      decoration:
          BoxDecoration(
        color: Colors.black,
        borderRadius:
            BorderRadius.circular(18),
      ),
      clipBehavior:
          Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio:
                c.value.aspectRatio,
            child:
                VideoPlayer(c),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                if (
                    c.value.isPlaying) {
                  c.pause();
                } else {
                  c.play();
                }
              });
            },
            icon: Icon(
              c.value.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
            ),
            iconSize: 38,
          ),
        ],
      ),
    );
  }

  Widget _feature(
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      width:
          double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      padding:
          const EdgeInsets.all(18),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFF151B25),
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration:
                BoxDecoration(
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
          const SizedBox(
            width: 15,
          ),
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
                const SizedBox(
                  height: 4,
                ),
                Text(
                  description,
                  style:
                      const TextStyle(
                    color:
                        Colors.white60,
                    fontSize: 14,
                    height: 1.35,
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
