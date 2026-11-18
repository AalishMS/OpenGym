import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gymapp/services/sync_service.dart';

const String _header = 'x-opengym-training-schema';

/// A real [SupabaseClient], created the way the app creates it (the schema
/// header defaults to 3), over a transport that records what leaves the
/// device.
(SupabaseClient, List<http.Request>) _client() {
  final sent = <http.Request>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'publishable',
    headers: const {_header: '3'},
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      sent.add(request);
      final rpc = request.url.path.contains('/rpc/');
      return http.Response(
        // The server answers an activation with the level it was asked for.
        rpc ? request.headers[_header] ?? 'null' : '[]',
        200,
        // The SDK reads the request back off the response.
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return (client, sent);
}

void main() {
  test('the level asked for is the level the activation carries', () async {
    final (client, sent) = _client();
    addTearDown(client.dispose);

    SyncService.applySchemaHeader(client, 4);
    final answer = await client.rpc('activate_training_schema');

    expect(sent.single.url.path, endsWith('/rpc/activate_training_schema'));
    expect(sent.single.headers[_header], '4');
    expect(answer, 4);
  });

  test('pushes and pulls after it carry the negotiated level', () async {
    final (client, sent) = _client();
    addTearDown(client.dispose);

    SyncService.applySchemaHeader(client, 4);
    await client.rpc('activate_training_schema');
    await client.from('splits').select();
    await client.from('workout_sessions').upsert({'id': 'a'});

    expect([for (final request in sent) request.headers[_header]], [
      '4',
      '4',
      '4',
    ]);
  });

  test('falling back to a lower level is carried too', () async {
    final (client, sent) = _client();
    addTearDown(client.dispose);

    SyncService.applySchemaHeader(client, 4);
    await client.rpc('activate_training_schema');
    SyncService.applySchemaHeader(client, 3);
    final answer = await client.rpc('activate_training_schema');
    await client.from('splits').select();

    expect([for (final request in sent) request.headers[_header]], [
      '4',
      '3',
      '3',
    ]);
    expect(answer, 3);
  });

  test('the other headers the client sends are kept', () async {
    final (client, sent) = _client();
    addTearDown(client.dispose);
    final before = Map.of(client.headers)..remove(_header);

    SyncService.applySchemaHeader(client, 4);
    await client.from('splits').select();

    final after = Map.of(client.headers)..remove(_header);
    expect(after, before);
    expect(sent.single.headers['apikey'], 'publishable');
    expect(sent.single.headers['Authorization'], 'Bearer publishable');
  });
}
