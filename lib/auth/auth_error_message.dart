import 'package:supabase_flutter/supabase_flutter.dart';

const String kOfflineMessage =
    "You're offline. Check your connection and try again.";
const String kServerUnavailableMessage =
    "Couldn't reach the server. Try again in a moment.";
const String kGenericAuthErrorMessage = 'Something went wrong. Try again.';

/// Whether [error] is the SDK's report of a request that never got a response
/// (no network, DNS failure, timeout).
///
/// gotrue wraps transport failures in [AuthRetryableFetchException] with no
/// status code; a 5xx response uses the same type but carries one.
bool isNetworkError(Object error) =>
    error is AuthRetryableFetchException && error.statusCode == null;

/// Copy for an auth failure. The SDK's own message for a transport failure is
/// the raw `ClientException`/`SocketException` text, so it is never shown.
String authErrorMessage(Object error) {
  if (isNetworkError(error)) return kOfflineMessage;
  if (error is AuthRetryableFetchException) return kServerUnavailableMessage;
  if (error is AuthException) return error.message;
  return kGenericAuthErrorMessage;
}
