import 'package:flutter_test/flutter_test.dart';
import 'package:bts_delivery_app/services/result.dart';

void main() {
  group('Result Tests', () {
    test('should create success result correctly', () {
      const result = Result<String>.success('test data');
      
      expect(result.isSuccess, true);
      expect(result.isFailure, false);
      expect(result.dataOrNull, 'test data');
      expect(result.errorOrNull, null);
    });

    test('should create failure result correctly', () {
      const result = Result<String>.failure('error message');
      
      expect(result.isSuccess, false);
      expect(result.isFailure, true);
      expect(result.dataOrNull, null);
      expect(result.errorOrNull, 'error message');
    });

    test('should handle when method correctly for success', () {
      const result = Result<int>.success(42);
      
      final output = result.when(
        success: (data) => 'Got: $data',
        failure: (error, exception) => 'Error: $error',
      );
      
      expect(output, 'Got: 42');
    });

    test('should handle when method correctly for failure', () {
      const result = Result<int>.failure('something went wrong');
      
      final output = result.when(
        success: (data) => 'Got: $data',
        failure: (error, exception) => 'Error: $error',
      );
      
      expect(output, 'Error: something went wrong');
    });

    test('should handle nullable data correctly', () {
      const successResult = Result<String?>.success(null);
      const failureResult = Result<String?>.failure('error');
      
      expect(successResult.isSuccess, true);
      expect(successResult.dataOrNull, null);
      expect(failureResult.isFailure, true);
      expect(failureResult.dataOrNull, null);
    });
  });
}