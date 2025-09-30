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

  @override
  void dispose() {
    _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final auth = context.read<AuthState>();
      final token = auth.token!;
      final me = auth.user!; // { id, rol, ... }

      final correo = _correoCtrl.text.trim().toLowerCase();
      if (correo.isEmpty) {
        setState(() {
          _msg = 'Ingresa el correo de la contraparte.';
          _loading = false;
        });
        return;
      }

      final otro = await Api.buscarUsuarioPorCorreo(token, correo);
      if (otro == null) {
        setState(() {
          _msg = 'No se encontró un usuario con ese correo.';
          _loading = false;
        });
        return;
      }

      final miRol = (me['rol'] as String);
      final rolOtro = (otro['rol'] as String);

      String? adultoId;
      String? cuidadorId;

      if (miRol == 'ADULTO_MAYOR' && rolOtro == 'CUIDADOR') {
        adultoId = me['id'];
        cuidadorId = otro['id'];
      } else if (miRol == 'CUIDADOR' && rolOtro == 'ADULTO_MAYOR') {
        adultoId = otro['id'];
        cuidadorId = me['id'];
      } else {
        setState(() {
          _msg = 'Roles incompatibles. Se requiere Adulto Mayor ↔ Cuidador.';
          _loading = false;
        });
        return;
      }

      final ok = await Api.vincularAdultoCuidador(token, adultoId: adultoId!, cuidadorId: cuidadorId!);
      setState(() {
        _msg = ok ? '✅ Vínculo creado correctamente.' : 'No se pudo crear el vínculo.';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _msg = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final me = auth.user!;
    final soyAdulto = me['rol'] == 'ADULTO_MAYOR';

    return Scaffold(
      appBar: AppBar(title: const Text('Vincular')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  soyAdulto ? 'Vincula a tu Cuidador' : 'Vincula a un Adulto Mayor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _correoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo de la contraparte',
                    hintText: 'ej: nombre@correo.com',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    onPressed: _loading ? null : _vincular,
                    label: const Text('Vincular'),
                  ),
                ),
                const SizedBox(height: 12),
                if (_msg != null)
                  Text(
                    _msg!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _msg!.startsWith('✅') ? Colors.green : Colors.red),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
