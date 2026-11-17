import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

const firebaseEmulatorHost =
    String.fromEnvironment('BTS_FIREBASE_EMULATOR_HOST');
const firebaseDemoProject = 'demo-bts-delivery';

/// Sends authenticated requests using the Firebase callable HTTPS protocol.
Future<Map<String, dynamic>> callStaffAccess(
  String function,
  Map<String, dynamic> data,
) async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser;
  final token = await user?.getIdToken();
  if (user == null || token == null || auth.currentUser?.uid != user.uid) {
    throw const StaffAccessException('Please sign in and try again.');
  }

  final projectId = Firebase.app().options.projectId;
  final endpoint = firebaseEmulatorHost.isEmpty
      ? Uri.https('us-central1-$projectId.cloudfunctions.net', '/$function')
      : Uri(
          scheme: 'http',
          host: firebaseEmulatorHost,
          port: 5001,
          path: '/$firebaseDemoProject/us-central1/$function',
        );
  if (firebaseEmulatorHost.isNotEmpty && projectId != firebaseDemoProject) {
    throw const StaffAccessException('The demo Firebase project is required.');
  }
  final response = await http
      .post(
        endpoint,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'data': data}),
      )
      .timeout(const Duration(seconds: 20));

  if (auth.currentUser?.uid != user.uid) {
    throw const StaffAccessException('The signed-in account changed.');
  }

  final Object? body;
  try {
    body = jsonDecode(response.body);
  } on FormatException {
    throw const StaffAccessException(
        'The staff service is unavailable. Try again.');
  }
  if (body is Map<String, dynamic>) {
    final error = body['error'];
    if (error is Map && error['message'] is String) {
      throw StaffAccessException(error['message'] as String);
    }
    final result = body['result'];
    if (result is Map<String, dynamic> && response.statusCode == 200) {
      return result;
    }
  }
  throw const StaffAccessException(
      'The staff service is unavailable. Try again.');
}

class StaffAccessException implements Exception {
  const StaffAccessException(this.message);
  final String message;

  @override
  String toString() => message;
}
