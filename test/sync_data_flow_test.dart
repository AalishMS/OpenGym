import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/services/sync_service.dart';

void main() {
  group('SyncService cursor progression on realistic Supabase rows', () {
    test('progresses maxSeq monotonically across Supabase TIMESTAMPTZ rows', () {
      final rows = [
        {'id': 'split-1', 'server_seq': '2026-09-07T10:22:15.935657+00:00'},
        {'id': 'split-2', 'server_seq': '2026-09-12T03:51:55.094932+00:00'},
        {'id': 'split-3', 'server_seq': '2026-09-13T11:54:14.855112+00:00'},
        {'id': 'split-4', 'server_seq': '2026-09-14T11:18:28.223233+00:00'},
      ];

      String? maxSeq;
      for (final row in rows) {
        maxSeq = SyncService.maxSequence(maxSeq, row['server_seq']);
      }

      expect(maxSeq, '2026-09-14T11:18:28.223233+00:00');
    });

    test('retains latest timestamp even if rows arrive out of chronological order', () {
      final rows = [
        {'id': 'split-1', 'server_seq': '2026-09-14T11:18:28.223233+00:00'},
        {'id': 'split-2', 'server_seq': '2026-09-07T10:22:15.935657+00:00'},
        {'id': 'split-3', 'server_seq': '2026-09-12T03:51:55.094932+00:00'},
      ];

      String? maxSeq;
      for (final row in rows) {
        maxSeq = SyncService.maxSequence(maxSeq, row['server_seq']);
      }

      expect(maxSeq, '2026-09-14T11:18:28.223233+00:00');
    });
  });
}
