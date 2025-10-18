// lib/pages/aceptar_vinculo_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../auth_state.dart';

class AceptarVinculoPage extends StatefulWidget {
  const AceptarVinculoPage({super.key});

  @override
  State<AceptarVinculoPage> createState() => _AceptarVinculoPageState();
}

class _AceptarVinculoPageState extends State<AceptarVinculoPage> {
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _msg;
  Color _msgColor = Colors.red;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _aceptarVinculo() async {
    FocusScope.of(context).unfocus();
    final tokenDeVinculo = _tokenCtrl.text.trim();
    if (tokenDeVinculo.isEmpty) {
      setState(() {
        _msg = 'Por favor, pega el código de invitación.';
        _msgColor = Colors.red;
      });
      return;
    }
    
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final authToken = context.read<AuthState>().token;
      if (authToken == null) throw Exception('No estás autenticado.');
      
      final bool exito = await Api.aceptarVinculo(authToken, tokenDeVinculo);

      if (exito && mounted) {
        _tokenCtrl.clear();
        setState(() {
          _loading = false;
          _msgColor = Colors.green.shade800;
          _msg = '✅ ¡Vínculo aceptado y creado exitosamente! Ya puedes verlo en "Mis Vínculos".';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _msgColor = Colors.red;
          _msg = "Error: ${e.toString().replaceFirst('Exception: ', '')}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aceptar Invitación'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.drafts_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Confirmar Vínculo',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Si recibiste un código de invitación, pégalo aquí para completar el vínculo de forma segura.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _tokenCtrl,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Código de Invitación',
                        hintText: 'Pega el código aquí...',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        icon: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                            : const Icon(Icons.check_circle_outline),
                        onPressed: _loading ? null : _aceptarVinculo,
                        label: const Text('Aceptar y Vincular'),
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
      ),
    );
  }
}