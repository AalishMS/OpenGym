import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/services/sync_service.dart';

void main() {
  group('SyncService.maxSequence', () {
    test('handles null inputs cleanly', () {
      expect(
        SyncService.maxSequence(null, '2026-09-07T10:22:15.935657+00:00'),
        '2026-09-07T10:22:15.935657+00:00',
      );
      expect(
        SyncService.maxSequence('2026-09-07T10:22:15.935657+00:00', null),
        '2026-09-07T10:22:15.935657+00:00',
      );
      expect(SyncService.maxSequence(null, null), isNull);
    });

    test(
      'compares ISO 8601 TIMESTAMPTZ strings accurately without throwing',
      () {
        const earlier = '2026-09-07T10:22:15.935657+00:00';
        const later = '2026-09-12T03:51:55.094932+00:00';

        expect(SyncService.maxSequence(earlier, later), later);
        expect(SyncService.maxSequence(later, earlier), later);
        expect(SyncService.maxSequence(later, later), later);
      },
    );

    test('compares timestamps with different timezone representations', () {
      const t1 = '2026-09-07T10:00:00+00:00';
      const t2 = '2026-09-07T12:00:00+02:00'; // Same instant as t1
      const t3 = '2026-09-07T11:00:00+00:00'; // 1 hour after t1

      expect(SyncService.maxSequence(t1, t3), t3);
      expect(SyncService.maxSequence(t1, t2), t1); // Same instant retains current
    });

    test('compares integer sequence values numerically', () {
      expect(SyncService.maxSequence('2', '10'), '10');
      expect(SyncService.maxSequence('10', '2'), '10');
      expect(SyncService.maxSequence('100', '99'), '100');
    });

    test('falls back to string comparison for general string sequences', () {
      expect(SyncService.maxSequence('seq-a', 'seq-b'), 'seq-b');
      expect(SyncService.maxSequence('seq-b', 'seq-a'), 'seq-b');
    });
  });
}
