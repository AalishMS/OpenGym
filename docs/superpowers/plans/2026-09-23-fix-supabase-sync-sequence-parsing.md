# Fix Supabase Sync Sequence Parsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `server_seq` cursor comparison in `SyncService` so that cloud sync successfully pulls Supabase records (splits, split preferences, workout plans, workout sessions) without throwing `FormatException: Could not parse BigInt`, populating user data in the web app.

**Architecture:** Update `_maxSequence` in `lib/services/sync_service.dart` to support PostgreSQL `TIMESTAMPTZ` ISO 8601 strings as well as integer sequences, expose it with `@visibleForTesting`, write thorough unit tests, verify static analysis, and verify live synchronization in the running web app.

**Tech Stack:** Flutter, Dart, Supabase Flutter / PostgREST, Hive, flutter_test.

**Spec:** The Supabase database stores `server_seq` as `TIMESTAMPTZ` (default `now()`), returning ISO-8601 timestamp strings like `'2026-09-07T10:22:15.935657+00:00'`. `SyncService` cursor progression must compare these timestamp values monotonically without crashing on `BigInt.parse`.

## Global Constraints

- Never break existing offline behavior or Hive storage schema.
- Follow AGENTS.md conventions: relative imports, explicit types, run `flutter analyze` after every change.
- Do not commit generated plugin registrants' line-ending churn (`git checkout -- linux/ macos/ windows/`).
- Do not modify or delete user data in Supabase.

## Review Focus

1. **Postgres TIMESTAMPTZ strings with timezone offsets:** `'2026-09-07T10:22:15.935657+00:00'` compared to `'2026-09-12T03:51:55.094932+00:00'`. Must return the later timestamp without throwing `FormatException`.
2. **Postgres TIMESTAMPTZ with `Z` suffix:** `'2026-09-07T10:22:15Z'` compared to `'2026-09-07T11:22:15+02:00'`. Must compare by absolute point in time.
3. **Integer sequence strings:** `'10'` compared to `'2'`. Must recognize `10 > 2` numerically (not lexicographically).
4. **Null handling:** Null candidate returns current; null current returns candidate string.
5. **Identical sequence values:** Returns current without mutation.

---

### Task 1: Add Unit Tests for `SyncService.maxSequence`

**Files:**
- Create: `test/sync_sequence_test.dart`
- Modify: `lib/services/sync_service.dart:340-345` (make visible for testing)

**Interfaces:**
- Consumes: `SyncService.maxSequence(String? current, dynamic candidate)`
- Produces: Test suite validating timestamp, integer, and null sequence comparison behavior

- [x] **Step 1: Write failing unit tests in `test/sync_sequence_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gymapp/services/sync_service.dart';

void main() {
  group('SyncService.maxSequence', () {
    test('handles null inputs cleanly', () {
      expect(SyncService.maxSequence(null, '2026-09-07T10:22:15.935657+00:00'), '2026-09-07T10:22:15.935657+00:00');
      expect(SyncService.maxSequence('2026-09-07T10:22:15.935657+00:00', null), '2026-09-07T10:22:15.935657+00:00');
      expect(SyncService.maxSequence(null, null), isNull);
    });

    test('compares ISO 8601 TIMESTAMPTZ strings accurately without throwing', () {
      const earlier = '2026-09-07T10:22:15.935657+00:00';
      const later = '2026-09-12T03:51:55.094932+00:00';

      expect(SyncService.maxSequence(earlier, later), later);
      expect(SyncService.maxSequence(later, earlier), later);
      expect(SyncService.maxSequence(later, later), later);
    });

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
```

- [x] **Step 2: Expose `maxSequence` in `lib/services/sync_service.dart` and run test to verify failure**

Make `_maxSequence` visible for testing:
```dart
  @visibleForTesting
  static String? maxSequence(String? current, dynamic candidate) =>
      _maxSequence(current, candidate);
```
Run: `flutter test test/sync_sequence_test.dart`
Expected: FAIL with `FormatException: Could not parse BigInt 2026-09-07T10:22:15.935657+00:00`.

---

### Task 2: Implement Robust Sequence Comparison in `SyncService`

**Files:**
- Modify: `lib/services/sync_service.dart:340-348`

**Interfaces:**
- Consumes: `String? current`, `dynamic candidate`
- Produces: Returns `String?` representing the maximum sequence value

- [x] **Step 1: Implement `_maxSequence` with DateTime, BigInt, and fallback support**

In `lib/services/sync_service.dart`:
```dart
  static String? _maxSequence(String? current, dynamic candidate) {
    if (candidate == null) return current;
    final value = candidate.toString();
    if (current == null) return value;

    final currentDt = DateTime.tryParse(current);
    final valueDt = DateTime.tryParse(value);
    if (currentDt != null &&
        valueDt != null &&
        (value.contains('T') || current.contains('T'))) {
      return valueDt.isAfter(currentDt) ? value : current;
    }

    final currentInt = BigInt.tryParse(current);
    final valueInt = BigInt.tryParse(value);
    if (currentInt != null && valueInt != null) {
      return valueInt > currentInt ? value : current;
    }

    if (currentDt != null && valueDt != null) {
      return valueDt.isAfter(currentDt) ? value : current;
    }

    return value.compareTo(current) > 0 ? value : current;
  }
```

- [x] **Step 2: Run unit test to verify it passes**

Run: `flutter test test/sync_sequence_test.dart`
Expected: PASS (all tests pass).

- [x] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: No issues found.

- [x] **Step 4: Commit changes**

```bash
git add lib/services/sync_service.dart test/sync_sequence_test.dart
git commit -m "fix(sync): parse TIMESTAMPTZ server_seq correctly during pull"
```

---

### Task 3: Verify All Tests and Live Synchronization

**Files:**
- Test: All unit tests (`flutter test`)
- Verify: Live web app at `http://localhost:64576/`

- [x] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All existing tests pass.

- [x] **Step 2: Trigger synchronization in the running web app**

Trigger hot reload or run `syncNow()` via debug connection so the web app runs the fixed sync cycle.

- [x] **Step 3: Verify console logs and local storage in the browser**

Verify with inspection script:
- No `FormatException: Could not parse BigInt` errors in console logs.
- `splits`, `split_preferences`, `workout_plans`, and `workout_sessions` are pulled into the local Hive store.
- Web app UI displays the user's splits and workouts.
