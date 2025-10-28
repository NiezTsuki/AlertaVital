import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart'; // <--- 1. Importar el manejador de permisos
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
    // Ya que la inicialización solo verifica si la plataforma soporta el STT,
    // podemos dejar la solicitud de permiso para cuando el usuario interactúe.
    await _speechToText.initialize(); 
  }

  // ********** 2. FUNCIÓN DE VERIFICACIÓN DE PERMISOS AÑADIDA **********
  Future<bool> _checkMicrophonePermission() async {
    var status = await Permission.microphone.status;
    
    if (status.isGranted) {
      return true;
    }

    status = await Permission.microphone.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      // Si está permanentemente denegado, mostramos una alerta para ir a Configuración.
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
    
    // Para cualquier otro estado (denegado temporalmente, etc.)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permiso de micrófono denegado. Es necesario para usar el asistente.')),
    );
    return false;
  }
  // ********************************************************************

  void _startListening() async {
    // ********** 3. LLAMAR A LA FUNCIÓN DE PERMISOS **********
    final granted = await _checkMicrophonePermission();
    if (!granted) {
      // Si el permiso no fue concedido, salimos de la función sin iniciar la escucha.
      setState(() {
         _estado = "Permiso no concedido.";
      });
      return; 
    }
    // ******************************************************
    
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

  // ... (el resto de tus funciones: _enviarAGemini, _hablar, build)
  
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