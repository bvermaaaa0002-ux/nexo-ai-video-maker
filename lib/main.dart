import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  bool _speaking = false;

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
नमस्ते! यह NEXO AI का टेस्ट है।

आज हम अपनी पहली AI वीडियो बनाने की कोशिश कर रहे हैं।

इस कहानी की शुरुआत एक छोटे से स्कूल से होती है।

बारिश का मौसम था और स्कूल की घंटी बज चुकी थी।

लेकिन उस दिन एक पुरानी याद फिर से सामने आने वाली थी।

क्या आपको भी अपना School Wala Pyar याद है?

अगर हाँ, तो उस इंसान को एक बार जरूर याद कीजिए।
''';
  }

  Future<void> _testVoice() async {
    if (_scriptController.text.trim().isEmpty) {
      _showMessage('पहले कोई स्क्रिप्ट लिखें।');
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

      await _tts.speak(_scriptController.text);

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

      _showMessage('Voice error: $e');
    }
  }

  void _createVideo() {
    _showMessage(
      'Video generation module अभी तैयार किया जा रहा है।',
    );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF202635),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              const Text(
                'AI Script to Video',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'अपनी कहानी या स्क्रिप्ट लिखें और Hindi voice का test करें।',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF101720),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _scriptController,
                  maxLines: 18,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'अपनी स्क्रिप्ट यहाँ लिखें...',
                    hintStyle: TextStyle(
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              OutlinedButton.icon(
                onPressed: _testVoice,
                icon: Icon(
                  _speaking
                      ? Icons.stop
                      : Icons.volume_up,
                  color: const Color(0xFFB58AFF),
                ),
                label: Text(
                  _speaking
                      ? 'Stop Hindi Voice'
                      : 'Test Hindi Voice',
                  style: const TextStyle(
                    color: Color(0xFFCCB5FF),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(65),
                  side: const BorderSide(
                    color: Colors.white54,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(35),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              ElevatedButton.icon(
                onPressed: _createVideo,
                icon: const Icon(
                  Icons.movie_creation,
                  color: Colors.white,
                ),
                label: const Text(
                  'Create Video',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
