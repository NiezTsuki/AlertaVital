import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

import 'firebase_options.dart';
import 'auth_state.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'theme/app_theme.dart';

// Handler para notificaciones en segundo plano (sin cambios)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("📲 Notificación recibida en segundo plano: ${message.messageId}");
  String? title = message.data['title'];
  String? body = message.data['body'];

  if (title != null && body != null) {
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: UniqueKey().hashCode,
        channelKey: 'emergency_channel', 
        title: title,
        body: body,
        payload: Map<String, String>.from(message.data),
      ),
    );
  }
}

Future<void> main() async {
  // Asegura que los bindings de Flutter estén inicializados
  WidgetsFlutterBinding.ensureInitialized();

  // 2. INICIALIZA AWESOME_NOTIFICATIONS Y CREA EL CANAL
  await AwesomeNotifications().initialize(
    // Deja 'null' para no usar un ícono de app por defecto en la notificación.
    // Opcionalmente, puedes poner 'resource://drawable/res_app_icon' si tienes uno.
    null,
    [
      NotificationChannel(
        channelKey: 'emergency_channel', // ID interno del canal
        channelName: 'Alertas de Emergencia', // Nombre visible para el usuario
        channelDescription: 'Canal para notificaciones de emergencia de AlertaVital.',
        importance: NotificationImportance.Max, // Máxima importancia
        playSound: true,
        // Aquí se especifica el sonido personalizado 
        soundSource: 'resource://raw/emergencia',
        defaultColor: Colors.red,
        ledColor: Colors.white,
      )
    ],
    // Habilita el modo debug para ver logs en la consola
    debug: true,
  );

  // Inicializa Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Asigna el handler de segundo plano para FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Inicia la aplicación
  runApp(const App());
}

// --- EL RESTO DE TU CÓDIGO PERMANECE IGUAL ---

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthState()..load(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Alerta Vital',
        theme: buildAppTheme(),
        home: const RootPage(),
        routes: {
          '/login': (_) => const LoginPage(),
          '/register': (_) => const RegisterPage(),
          '/home': (_) => const HomePage(),
        },
      ),
    );
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (auth.token != null && auth.user != null) {
      return const HomePage();
    } else {
      return const LoginPage();
    }
  }
}