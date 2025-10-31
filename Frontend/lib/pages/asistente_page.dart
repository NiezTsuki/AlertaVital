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

class _AsistentePageState extends State<AsistentePage> with SingleTickerProviderStateMixin {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  // --- VARIABLES DE ESTADO PARA MEJORAR LA UI/UX ---
  String _estado = "Toca el micrófono para hablar";
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isProcessing = false; // Para el estado "Pensando..."
  String _textoEscuchado = "";
  final List<Map<String, dynamic>> _historial = [];

  // Controlador para la animación del micrófono
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    // Configuración de la animación de pulso
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _speechToText.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  void _initSpeech() async {
    await _speechToText.initialize(); 
  }
  
  void _toggleListening() async {
    // Bloquea el botón si está hablando o procesando
    if (_isSpeaking || _isProcessing) return; 

    if (_isListening) {
      _stopListening();
    } else {
      await _startListening(); 
    }
  }

  Future<void> _startListening() async {
    final granted = await _checkMicrophonePermission();
    if (!granted) return;
    
    await _speechToText.listen(
      onResult: (result) => setState(() => _textoEscuchado = result.recognizedWords),
      localeId: 'es_ES',
    );
    
    setState(() {
      _isListening = true;
      _estado = "Escuchando...";
      _textoEscuchado = ""; 
    });
  }

  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
      if (_textoEscuchado.isNotEmpty) {
        _isProcessing = true; // Inicia el estado "Pensando"
        _estado = "Pensando...";
      } else {
        _estado = "No te escuché bien, intenta de nuevo.";
      }
    });
    
    if (_textoEscuchado.isNotEmpty) {
      _enviarAGemini(_textoEscuchado);
    }
  }

  Future<void> _enviarAGemini(String texto) async {
    if (!mounted) return;
    final authState = Provider.of<AuthState>(context, listen: false);
    final userToken = authState.token; 

    if (userToken == null) {
      await _hablar("Tu sesión ha expirado.");
      setState(() => _isProcessing = false);
      return;
    }
    
    _historial.add({"role": "user", "parts": [{"text": texto}]}); 
    
    try {
      final respuesta = await AsistenteApi.conversar(texto, _historial, userToken);
      _historial.add({"role": "model", "parts": [{"text": respuesta}]}); 
      
      if (mounted) setState(() => _isProcessing = false);
      await _hablar(respuesta);
      
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      await _hablar("Lo siento, ocurrió un error al conectar con el asistente.");
      if (_historial.isNotEmpty && _historial.last['role'] == 'user') {
          _historial.removeLast();
      }
    }
    
    if (mounted) {
      setState(() => _textoEscuchado = "");
    }
  }

  Future<void> _hablar(String texto) async {
    if (!mounted) return;
    
    setState(() {
      _estado = "Hablando...";
      _isSpeaking = true; 
    });
    
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.speak(texto);
    await _flutterTts.awaitSpeakCompletion(true);
    
    if (mounted) {
      setState(() { 
        _estado = "Toca el micrófono para hablar";
        _isSpeaking = false; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asistente de Compañía')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Spacer(),
            SizedBox(
              height: 60,
              child: Center(
                child: Text(
                  _estado,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  _textoEscuchado,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey.shade600,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _buildMicButton(),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    Widget icon;
    Color buttonColor;
    bool isPulsing = false;

    if (_isProcessing) {
      icon = const SizedBox(width: 50, height: 50, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 4));
      buttonColor = Colors.grey.shade800;
    } else if (_isSpeaking) {
      icon = const Icon(Icons.voice_over_off, color: Colors.white, size: 80);
      buttonColor = Colors.grey.shade600;
    } else if (_isListening) {
      icon = const Icon(Icons.mic, color: Colors.white, size: 100);
      buttonColor = Colors.redAccent;
      isPulsing = true;
    } else {
      icon = const Icon(Icons.mic, color: Colors.white, size: 100);
      buttonColor = Theme.of(context).colorScheme.primary;
    }

    if (isPulsing) {
      _animationController.repeat(reverse: true);
    } else {
      _animationController.stop();
    }

    return GestureDetector(
      onTap: _toggleListening,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              boxShadow: isPulsing ? [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.5),
                  spreadRadius: _animation.value,
                  blurRadius: 20.0,
                ),
              ] : [],
            ),
            child: child,
          );
        },
        child: icon,
      ),
    );
  }

  Future<bool> _checkMicrophonePermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;
    status = await Permission.microphone.request();
    if (status.isGranted) return true;
    
    if (status.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permiso de micrófono bloqueado. Ábrelo en la configuración.'),
          action: SnackBarAction(label: 'Abrir', onPressed: openAppSettings),
        ),
      );
    }
    return false;
  }
}