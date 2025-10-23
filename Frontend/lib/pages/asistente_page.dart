import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../asistente_api.dart';

class AsistentePage extends StatefulWidget {
  const AsistentePage({super.key});
  @override
  State<AsistentePage> createState() => _AsistentePageState();
}

class _AsistentePageState extends State<AsistentePage> {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  String _estado = "Toca el micrófono para hablar";
  bool _isListening = false;
  String _textoEscuchado = "";
  final List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
  }

  void _startListening() async {
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _textoEscuchado = result.recognizedWords;
        });
      },
      localeId: 'es_ES', // Español
    );
    setState(() {
      _isListening = true;
      _estado = "Escuchando...";
    });
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
      _estado = "Pensando...";
    });
    if (_textoEscuchado.isNotEmpty) {
      _enviarAGemini(_textoEscuchado);
    } else {
      setState(() {
        _estado = "No te escuché bien, intenta de nuevo.";
      });
    }
  }

  Future<void> _enviarAGemini(String texto) async {
    // Añade el mensaje del usuario al historial
    _historial.add({"role": "user", "parts": texto});
    
    try {
      final respuesta = await AsistenteApi.conversar(texto, _historial);
      _historial.add({"role": "model", "parts": respuesta}); // Añade la respuesta de Gemini
      await _hablar(respuesta);
    } catch (e) {
      await _hablar("Lo siento, hubo un error. Por favor, intenta de nuevo.");
    }
    
    setState(() {
      _textoEscuchado = "";
      _estado = "Toca el micrófono para hablar";
    });
  }

  Future<void> _hablar(String texto) async {
    setState(() { _estado = "Hablando..."; });
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(texto);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente de Compañía')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Spacer(),
            Text(_estado, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text(_textoEscuchado, style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            GestureDetector(
              onTapDown: (_) => _startListening(),
              onTapUp: (_) => _stopListening(),
              child: CircleAvatar(
                radius: 80,
                backgroundColor: _isListening ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.mic, color: Colors.white, size: 100),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}