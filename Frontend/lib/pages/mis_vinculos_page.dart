import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../auth_state.dart';
import 'vincular_page.dart';

class MisVinculosPage extends StatefulWidget {
  const MisVinculosPage({super.key});

  @override
  State<MisVinculosPage> createState() => _MisVinculosPageState();
}

class _MisVinculosPageState extends State<MisVinculosPage> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    final auth = context.read<AuthState>();
    final me = auth.user!;
    final token = auth.token!;

    setState(() {
      if (me['rol'] == 'ADULTO_MAYOR') {
        _future = Api.listarCuidadoresDeAdulto(token, me['id']);
      } else {
        _future = Api.listarAdultosDeCuidador(token, me['id']);
      }
    });
  }

  Future<void> _desvincular(Map<String, dynamic> item) async {
    final auth = context.read<AuthState>();
    final me = auth.user!;
    final token = auth.token!;

    String adultoId, cuidadorId;
    if (me['rol'] == 'ADULTO_MAYOR') {
      adultoId = me['id'];
      cuidadorId = item['cuidador_id'];
    } else {
      adultoId = item['adulto_id'];
      cuidadorId = me['id'];
    }

    final ok = await Api.desvincular(token, adultoId: adultoId, cuidadorId: cuidadorId);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vínculo eliminado')));
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final soyAdulto = auth.user!['rol'] == 'ADULTO_MAYOR';

    return Scaffold(
      appBar: AppBar(title: Text(soyAdulto ? 'Mis cuidadores' : 'Mis adultos')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final data = snap.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text('Sin vínculos por ahora'));
          }
          return ListView.separated(
            itemCount: data.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final it = data[i];
              final nombre = (it['nombre_completo'] ?? '') as String? ?? '';
              final correo = (it['correo'] ?? '') as String? ?? '';
              final telefono = (it['telefono'] ?? '') as String? ?? '';
              final subtitle = [correo, telefono].where((s) => s.isNotEmpty).join(' · ');

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(nombre.isEmpty ? '(sin nombre)' : nombre),
                subtitle: Text(subtitle),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Desvincular'),
                        content: const Text('¿Estás seguro de eliminar el vínculo?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancelar')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Desvincular')),
                        ],
                      ),
                    );
                    if (ok == true) _desvincular(it);
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const VincularPage()))
            .then((_) => _cargar()),
        icon: const Icon(Icons.link),
        label: const Text('Vincular'),
      ),
    );
  }
}
