import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/auth/auth_error_message.dart';

void main() {
  test('a failed request with no response reads as offline', () {
    final error = AuthRetryableFetchException(
      message:
          "ClientException with SocketException: Failed host lookup: 'example.supabase.co'",
    );
    expect(isNetworkError(error), isTrue);
    expect(authErrorMessage(error), kOfflineMessage);
  });

  test('a server failure is not reported as offline', () {
    final error = AuthRetryableFetchException(
      message: '<html>Bad gateway</html>',
      statusCode: '502',
    );
    expect(isNetworkError(error), isFalse);
    expect(authErrorMessage(error), kServerUnavailableMessage);
  });

  test('server-written auth messages pass through', () {
    expect(
      authErrorMessage(const AuthApiException('Invalid login credentials')),
      'Invalid login credentials',
    );
  });

  test('unknown errors get a generic message', () {
    expect(authErrorMessage(StateError('boom')), kGenericAuthErrorMessage);
  });
}
