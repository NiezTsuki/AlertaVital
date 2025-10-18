// lib/pages/vincular_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../auth_state.dart';

class VincularPage extends StatefulWidget {
  const VincularPage({super.key});

  @override
  State<VincularPage> createState() => _VincularPageState();
}

class _VincularPageState extends State<VincularPage> {
  final _correoCtrl = TextEditingController();
  bool _loading = false;
  String? _msg;
  Color _msgColor = Colors.red;

  @override
  void dispose() {
    _correoCtrl.dispose();
    super.dispose();
  }

  // ✅ CORRECCIÓN: La función ahora usa el flujo de "solicitud".
  Future<void> _solicitarVinculo() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final auth = context.read<AuthState>();
      final token = auth.token;
      final me = auth.user;

      if (token == null || me == null) {
        throw Exception('No se pudo obtener tu información de usuario. Intenta reiniciar sesión.');
      }
      
      final miCorreo = me['correo'] as String?;
      final miRol = me['rol'] as String?;
      final correoContraparte = _correoCtrl.text.trim().toLowerCase();

      if (miCorreo == null || miRol == null) {
         throw Exception('Tu información de usuario está incompleta.');
      }
      if (correoContraparte.isEmpty) {
        throw Exception('Por favor, ingresa el correo electrónico a vincular.');
      }
      if (correoContraparte == miCorreo) {
        throw Exception('No puedes vincularte a ti mismo.');
      }

      // Llama al nuevo endpoint 'solicitar' de la API
      await Api.solicitarVinculo(
        token,
        adultoCorreo: miRol == 'ADULTO_MAYOR' ? miCorreo : correoContraparte,
        cuidadorCorreo: miRol == 'CUIDADOR' ? miCorreo : correoContraparte,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _msgColor = Colors.green.shade800;
        _msg = "✅ ¡Solicitud enviada!\nLa otra persona debe aceptar la invitación para completar el vínculo.";
        _correoCtrl.clear();
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msgColor = Colors.red;
        _msg = "Error: ${e.toString().replaceFirst('Exception: ', '')}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final me = auth.user;

    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vincular')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final soyAdulto = me['rol'] == 'ADULTO_MAYOR';

    return Scaffold(
      appBar: AppBar(title: const Text('Vincular')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    soyAdulto ? 'Vincula a tu Cuidador' : 'Vincula a un Adulto Mayor',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa el correo electrónico de la persona con la que deseas vincularte.',
                     style: Theme.of(context).textTheme.bodyMedium,
                     textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _correoCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo de la contraparte',
                      hintText: 'nombre@ejemplo.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    onSubmitted: (_) => _solicitarVinculo(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      icon: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                          : const Icon(Icons.send_outlined),
                      onPressed: _loading ? null : _solicitarVinculo,
                      label: const Text('Enviar Solicitud'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_msg != null)
                    Text(
                      _msg!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _msgColor, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}