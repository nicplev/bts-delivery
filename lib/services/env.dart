import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get firebaseApiKey => dotenv.env['FIREBASE_API_KEY'] ?? '';
  static String get firebaseAppId => dotenv.env['FIREBASE_APP_ID'] ?? '';
  static String get firebaseMessagingSenderId => dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '';
  static String get firebaseProjectId => dotenv.env['FIREBASE_PROJECT_ID'] ?? '';
  static String get firebaseStorageBucket => dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '';
  
  static bool get useFirebaseEmulator => dotenv.env['USE_FIREBASE_EMULATOR'] == 'true';
  static String get firestoreEmulatorHost => dotenv.env['FIRESTORE_EMULATOR_HOST'] ?? 'localhost:8080';
  static String get firebaseAuthEmulatorHost => dotenv.env['FIREBASE_AUTH_EMULATOR_HOST'] ?? 'localhost:9099';
  static String get firebaseStorageEmulatorHost => dotenv.env['FIREBASE_STORAGE_EMULATOR_HOST'] ?? 'localhost:9199';
}