// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
}

// 2. DEFINE EL CANAL DE NOTIFICACIÓN PERSONALIZADO
const AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
  'emergency_channel', // ID interno del canal
  'Alertas de Emergencia', // Nombre que ve el usuario en los ajustes
  description: 'Canal para notificaciones de emergencia de AlertaVital.', // Descripción del canal
  importance: Importance.max, // Máxima importancia para que aparezca arriba
  playSound: true,
  sound: RawResourceAndroidNotificationSound('emergencia'),
);

Future<void> main() async {
  // Asegura que los bindings de Flutter estén inicializados
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Asigna el handler de segundo plano para FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 3. CREA EL CANAL EN EL DISPOSITIVO ANDROID
  // Esta lógica se ejecutará al iniciar la app y registrará el canal en el sistema.
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(emergencyChannel);

  // Inicia la aplicación
  runApp(const App());
}

// --- EL RESTO DEL CÓDIGO PERMANECE IGUAL ---

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