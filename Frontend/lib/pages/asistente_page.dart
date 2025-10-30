// archivo: asistente_page.dart

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:provider/provider.dart';
import '../asistente_api.dart';
import '../auth_state.dart'; 

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
  final List<Map<String, dynamic>> _historial = []; // Historial de la conversación

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    await _speechToText.initialize(); 
  }
  
  void _toggleListening() async {
    if (_isListening) {
      _stopListening();
    } else {
      await _startListening(); 
    }
  }

  // Función de verificación de permisos
  Future<bool> _checkMicrophonePermission() async {
    var status = await Permission.microphone.status;
    
    if (status.isGranted) return true;

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
      const SnackBar(content: Text('Permiso de micrófono denegado.')),
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
      _textoEscuchado = ""; 
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
    if (!mounted) return;
    final authState = Provider.of<AuthState>(context, listen: false);
    final userToken = authState.token; 

    if (userToken == null || authState.user == null) {
      await _hablar("No tienes una sesión activa. Por favor, inicia sesión.");
      if (mounted) setState(() { _estado = "Error de sesión."; });
      return;
    }
    
    // Se añade el mensaje del usuario al historial antes de la llamada
    _historial.add({
      "role": "user", 
      "parts": [{"text": texto}] 
    }); 
    
    try {
      final respuesta = await AsistenteApi.conversar(texto, _historial, userToken!);
      
      // Se añade la respuesta de Gemini al historial solo si fue exitosa
      _historial.add({"role": "model", "parts": [ {"text": respuesta} ]}); 
      
      await _hablar(respuesta);
      
    } catch (e) {
      print('ERROR AL COMUNICARSE CON ASISTENTE/GEMINI: $e'); 
      String fullError = e.toString();
      String errorMsg;

      // 1. Manejo específico para el 401/Sesión expirada
      if (fullError.contains('Sesión expirada') || fullError.contains('401')) {
          errorMsg = "Tu sesión ha expirado, por favor vuelve a iniciar.";
      } else {
          // 2. Extraer el mensaje detallado de la excepción para reportar
          String detail = fullError.split(': ').length > 1 
              ? fullError.split(': ').sublist(1).join(': ') 
              : "Error Desconocido. No hay detalle.";

          // 3. Devolver la causa específica por voz
          // Aquí reportará: "Fallo de la aplicación. Causa: El servidor respondió, pero el formato JSON es inválido."
          errorMsg = "Fallo de la aplicación. Causa: $detail";
      }

      // 4. CORRECCIÓN CRÍTICA: Si la llamada falló, se elimina el último mensaje de usuario.
      if (_historial.isNotEmpty && _historial.last['role'] == 'user') {
          _historial.removeLast();
      }
      
      await _hablar(errorMsg);
    }
    
    if (mounted) {
      setState(() {
        _textoEscuchado = "";
        _estado = "Toca el micrófono para hablar";
      });
    }
  }

  Future<void> _hablar(String texto) async {
    if (!mounted) return;
    setState(() { _estado = "Hablando..."; });
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(texto);
    await _flutterTts.awaitSpeakCompletion(true);
    if (mounted) setState(() { _estado = "Toca el micrófono para hablar"; });
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
              onTap: _toggleListening,
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