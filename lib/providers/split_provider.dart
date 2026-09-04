import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/split.dart';
import '../repositories/split_repository.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

class SplitProvider with ChangeNotifier {
  static const int maxSplits = 5;
  static const Uuid _uuid = Uuid();

  final SplitRepository _repository;
  final String? Function() _userIdProvider;
  List<Split> _splits = [];
  String? _activeSplitId;
  late final StreamSubscription<void> _syncSubscription;

  SplitProvider({
    SplitRepository? repository,
    String? Function()? userIdProvider,
  }) : _repository = repository ?? SplitRepository(),
       _userIdProvider =
           userIdProvider ?? (() => SupabaseService.currentUserId) {
    _syncSubscription = SyncService.instance.changes.listen(
      (_) => loadSplits(),
    );
    loadSplits();
  }

  List<Split> get splits => List.unmodifiable(_splits);
  String? get activeSplitId => _activeSplitId;
  Split? get activeSplit {
    for (final split in _splits) {
      if (split.id == _activeSplitId) return split;
    }
    return null;
  }

  bool get canCreate => _splits.length < maxSplits;

  SplitUsage usageFor(String splitId) => SplitUsage(
    plans: _repository.getPlanCount(splitId),
    sessions: _repository.getSessionCount(splitId),
  );

  String? nameError(String value, {String? exceptId}) {
    final name = value.trim();
    if (name.isEmpty) return 'Enter a split name.';
    if (name.length > 24) return 'Use 24 characters or fewer.';
    final normalized = name.toLowerCase();
    if (_splits.any(
      (split) => split.id != exceptId && split.name.toLowerCase() == normalized,
    )) {
      return 'A split with that name already exists.';
    }
    return null;
  }

  void loadSplits() {
    _splits = _repository.getSplits();
    final userId = _userIdProvider();
    final preferred =
        userId == null
            ? null
            : _repository.getPreference(userId)?.activeSplitId;
    _activeSplitId =
        _splits.any((split) => split.id == preferred)
            ? preferred
            : (_splits.isEmpty ? null : _splits.first.id);
    notifyListeners();
  }

  Future<void> createSplit(String rawName) async {
    final userId = _requireUser();
    final name = rawName.trim();
    if (!canCreate) throw StateError('You can have at most five splits.');
    final validationError = nameError(rawName);
    if (validationError != null) throw ArgumentError(validationError);
    final now = DateTime.now();
    final split = Split(
      id: _uuid.v4(),
      name: name,
      userId: userId,
      createdAt: now,
      updatedAt: now,
      dirty: true,
    );
    await _repository.upsertSplit(split);
    await _repository.setActive(userId, split.id);
    loadSplits();
    SyncService.instance.scheduleSync();
  }

  Future<void> renameSplit(String id, String rawName) async {
    final name = rawName.trim();
    final validationError = nameError(rawName, exceptId: id);
    if (validationError != null) throw ArgumentError(validationError);
    Split? current;
    for (final split in _splits) {
      if (split.id == id) current = split;
    }
    if (current == null) throw StateError('Split not found.');
    await _repository.upsertSplit(current.copyWith(name: name));
    loadSplits();
    SyncService.instance.scheduleSync();
  }

  Future<void> setActiveSplit(String id) async {
    final userId = _requireUser();
    await _repository.setActive(userId, id);
    loadSplits();
    SyncService.instance.scheduleSync();
  }

  Future<void> deleteSplit(String id, String replacementId) async {
    final userId = _requireUser();
    await _repository.deleteSplit(
      userId: userId,
      splitId: id,
      replacementSplitId: replacementId,
    );
    loadSplits();
    SyncService.instance.scheduleSync();
  }

  String _requireUser() {
    final userId = _userIdProvider();
    if (userId == null) throw StateError('Sign in to manage splits.');
    return userId;
  }

  @override
  void dispose() {
    _syncSubscription.cancel();
    super.dispose();
  }
}

class SplitUsage {
  final int plans;
  final int sessions;

  const SplitUsage({required this.plans, required this.sessions});
}
