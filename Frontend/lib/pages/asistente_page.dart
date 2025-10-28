import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart'; 
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
  // El historial usa el formato de chat de Gemini: List<Map>
  final List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    // Inicializa el motor de SpeechToText, pero los permisos se piden al interactuar.
    await _speechToText.initialize(); 
  }
  
  // ********** FUNCIÓN DE ALTERNANCIA (TOGGLE) **********
  void _toggleListening() async {
    if (_isListening) {
      // 1. Detener escucha (segundo toque)
      _stopListening();
    } else {
      // 2. Iniciar escucha (primer toque)
      await _startListening(); 
    }
  }
  // ****************************************************

  // Función para solicitar y verificar el permiso del micrófono
  Future<bool> _checkMicrophonePermission() async {
    var status = await Permission.microphone.status;
    
    if (status.isGranted) {
      return true;
    }

    status = await Permission.microphone.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('El micrófono está bloqueado. Abre la configuración de la app para activarlo.'),
          action: SnackBarAction(
            label: 'Abrir Configuración',
            onPressed: openAppSettings, 
          ),
        ),
      );
      return false;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permiso de micrófono denegado. Es necesario para usar el asistente.')),
    );
    return false;
  }

  Future<void> _startListening() async {
    final granted = await _checkMicrophonePermission();
    if (!granted) {
      setState(() {
         _estado = "Permiso no concedido.";
      });
      return; 
    }
    
    // Si el permiso está OK, procedemos a escuchar:
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
      _estado = "Escuchando... Toca para terminar.";
      _textoEscuchado = ""; // Limpiar el texto anterior antes de grabar
    });
  }

  void _stopListening() async {
    // Detener la escucha, sin importar el tiempo que haya pasado
    await _speechToText.stop();
    
    setState(() {
      _isListening = false;
      _estado = "Pensando...";
    });
    
    // Si se capturó algo, lo enviamos a Gemini
    if (_textoEscuchado.isNotEmpty) {
      _enviarAGemini(_textoEscuchado);
    } else {
      setState(() {
        _estado = "No te escuché bien, intenta de nuevo.";
      });
    }
  }

  Future<void> _enviarAGemini(String texto) async {
    // ********** CORRECCIÓN DEL FORMATO DE GEMINI **********
    // Se añade el mensaje del usuario con 'parts' como arreglo de objetos.
    _historial.add({
      "role": "user", 
      "parts": [{"text": texto}] 
    }); 
    
    try {
      final respuesta = await AsistenteApi.conversar(texto, _historial);
      
      // Se añade la respuesta del modelo, también con 'parts' como arreglo de objetos.
      _historial.add({"role": "model", "parts": [ {"text": respuesta} ]}); 
      
      await _hablar(respuesta);
    } catch (e) {
      // Registrar el error para diagnóstico (importante si falla Gemini)
      print('ERROR AL COMUNICARSE CON ASISTENTE/GEMINI: $e'); 
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
              // ********** USAR TAP PARA ALTERNAR LA GRABACIÓN **********
              onTap: _toggleListening,
              child: CircleAvatar(
                radius: 80,
                // El color del micrófono indica si está escuchando
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
