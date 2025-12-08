// Firebase configuration for emulator-only use
// No real Firebase project needed - this is for local development only

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return web; // Use web config for Windows
      case TargetPlatform.linux:
        return web; // Use web config for Linux
      default:
        return web;
    }
  }

  // Demo Firebase config - only works with emulators
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:web:abcdef',
    messagingSenderId: '123456789',
    projectId: 'quadlii-nhl-scores',
    authDomain: 'quadlii-nhl-scores.firebaseapp.com',
    storageBucket: 'quadlii-nhl-scores.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD9EuZCieMfvmzzTJE5Fcf_4WHHY47OiKs',
    appId: '1:19541551164:android:0f213cc6d848f160697b39',
    messagingSenderId: '19541551164',
    projectId: 'quadlii-nhl-scores',
    storageBucket: 'quadlii-nhl-scores.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:ios:abcdef',
    messagingSenderId: '123456789',
    projectId: 'quadlii-nhl-scores',
    storageBucket: 'quadlii-nhl-scores.appspot.com',
    iosBundleId: 'com.example.quadliiApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:ios:abcdef',
    messagingSenderId: '123456789',
    projectId: 'quadlii-nhl-scores',
    storageBucket: 'quadlii-nhl-scores.appspot.com',
    iosBundleId: 'com.example.quadliiApp',
  );
}
