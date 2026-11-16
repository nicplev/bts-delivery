import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';
import 'env.dart';

class FirebaseConfig {
  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    if (Env.useFirebaseEmulator && kDebugMode) {
      await _connectToEmulators();
    }
    
    // Enable Firestore offline persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
  
  static Future<void> _connectToEmulators() async {
    try {
      // Connect to Firebase Auth emulator
      await FirebaseAuth.instance.useAuthEmulator(
        'localhost',
        9099,
      );
      
      // Connect to Firestore emulator
      FirebaseFirestore.instance.useFirestoreEmulator(
        'localhost',
        8080,
      );
      
      // Connect to Firebase Storage emulator
      await FirebaseStorage.instance.useStorageEmulator(
        'localhost',
        9199,
      );
    } catch (e) {
      // Emulators might already be connected
      if (kDebugMode) {
        debugPrint('Firebase emulator connection: $e');
      }
    }
  }
}