import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:io';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'providers/game_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Connect to Firebase emulators in debug mode - MUST be done before using any Firebase services
  if (kDebugMode) {
    try {
      // Android emulator uses 10.0.2.2 to refer to host machine's localhost
      const host = '10.0.2.2';
      const firestorePort = 8080;
      const functionsPort = 5001;

      // Test connectivity to emulator
      try {
        debugPrint('🔍 Testing connectivity to $host:$functionsPort...');
        final socket = await Socket.connect(host, functionsPort,
            timeout: Duration(seconds: 3));
        socket.destroy();
        debugPrint('✅ Successfully connected to $host:$functionsPort');
      } catch (e) {
        debugPrint('❌ Cannot reach emulator at $host:$functionsPort: $e');
        debugPrint('⚠️  Make sure Firebase emulators are running!');
      }

      // CRITICAL: Set emulator settings BEFORE any Firebase service is used
      FirebaseFirestore.instance.settings = Settings(
        host: '$host:$firestorePort',
        sslEnabled: false,
        persistenceEnabled: false,
      );

      FirebaseFunctions.instance.useFunctionsEmulator(host, functionsPort);

      debugPrint('✅ Configured Firestore emulator at $host:$firestorePort');
      debugPrint('✅ Configured Functions emulator at $host:$functionsPort');
    } catch (e) {
      debugPrint('❌ Error connecting to emulators: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
      ],
      child: MaterialApp.router(
        title: 'Quadlii App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
