import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/exercise_definition.dart';
import '../services/exercise_catalog.dart';
import '../services/exercise_rename_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/exercise_rename_dialog.dart';
import '../widgets/motion/app_modals.dart';
import '../widgets/persistence_dialog.dart';

/// The account's exercise library: rename any movement, and merge two
/// entries for the same movement. Movements you train come first, each with
/// how much of your training uses it, so duplicates are easy to spot.
class ExerciseManagementScreen extends StatefulWidget {
  final String? userId;
  const ExerciseManagementScreen({super.key, required this.userId});

  @override
  State<ExerciseManagementScreen> createState() =>
      _ExerciseManagementScreenState();
}

class _ExerciseManagementScreenState extends State<ExerciseManagementScreen> {
  String _query = '';
  late final StreamSubscription<void> _changes;
  late Map<String, ExerciseUsage> _usage = _readUsage();

  Map<String, ExerciseUsage> _readUsage() =>
      ExerciseRenameService.usageByExercise(userId: widget.userId);

  @override
  void initState() {
    super.initState();
    _changes = SyncService.instance.changes.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _usage = _readUsage());
  }

  bool _accountChanged() =>
      SupabaseService.isConfigured &&
      SupabaseService.currentUserId != widget.userId;

  Future<void> _rename(ExerciseDefinition exercise) async {
    final outcome = await showExerciseRenameDialog(
      context,
      exerciseId: exercise.id,
      currentName: exercise.name,
      userId: widget.userId,
    );
    if (outcome == null || !mounted) return;
    _refresh();
    if (outcome case ExerciseMerged(:final into)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Merged into ${into.name}')));
    }
  }

  Future<void> _merge(ExerciseDefinition source) async {
    final target = await showAppSheet<ExerciseDefinition>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _MergeTargetSheet(source: source, usage: _usage),
    );
    if (target == null || !mounted) return;
    final saved = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => PersistenceDialog(
            title: 'Merge into ${target.name}?',
            content: Text(
              '${source.name} and ${target.name} become one exercise called '
              '${target.name}. Every plan, workout and chart shows '
              '${target.name}, and their history, records and previous sets '
              'are combined across all your splits. All logged sets are '
              "kept. This can't be undone, so only merge the same movement.",
            ),
            actionLabel: 'Merge',
            progressLabel: 'Merging exercises',
            failureMessage: 'Could not merge exercises. Try again or cancel.',
            onPersist: () async {
              if (!mounted || _accountChanged()) {
                throw StateError('The exercise account changed.');
              }
              await ExerciseRenameService.merge(
                sourceId: source.id,
                targetId: target.id,
                userId: widget.userId,
              );
            },
          ),
    );
    if (!mounted || saved != true) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Merged into ${target.name}')));
  }

  @override
  Widget build(BuildContext context) {
    bool trained(ExerciseDefinition d) =>
        !d.builtIn || !(_usage[d.id]?.isEmpty ?? true);
    final exercises = ExerciseCatalog.search(_query)..sort((a, b) {
      final first = (trained(a) ? 0 : 1).compareTo(trained(b) ? 0 : 1);
      return first == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : first;
    });
    return Scaffold(
      appBar: const AppHeader(title: Text('Manage exercises')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Renaming an exercise changes its name everywhere. If two '
                  'entries are the same movement, merge them to bring their '
                  'history together. Your exercise library is shared across '
                  'all splits.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: 'Search exercises',
                    prefixIcon: Icon(LucideIcons.search),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                exercises.isEmpty
                    ? const Center(child: Text('No exercises found'))
                    : ListView.separated(
                      itemCount: exercises.length,
                      separatorBuilder:
                          (_, _) =>
                              Divider(height: 1, color: hairlineColor(context)),
                      itemBuilder: (context, index) {
                        final d = exercises[index];
                        return ListTile(
                          title: Text(d.name),
                          subtitle: Text(_describe(d, _usage[d.id])),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Actions for ${d.name}',
                            onSelected:
                                (action) =>
                                    action == 'merge' ? _merge(d) : _rename(d),
                            itemBuilder:
                                (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'merge',
                                    child: Text('Merge into another exercise'),
                                  ),
                                ],
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

/// The exercise's group, and how much of the account's training uses it.
String _describe(ExerciseDefinition d, ExerciseUsage? usage) {
  String count(int value, String noun) =>
      '$value ${value == 1 ? noun : '${noun}s'}';
  return [
    d.category,
    if (usage != null && usage.workouts > 0) count(usage.workouts, 'workout'),
    if (usage != null && usage.plans > 0) count(usage.plans, 'plan'),
  ].join(' · ');
}

class _MergeTargetSheet extends StatefulWidget {
  final ExerciseDefinition source;
  final Map<String, ExerciseUsage> usage;
  const _MergeTargetSheet({required this.source, required this.usage});
  @override
  State<_MergeTargetSheet> createState() => _MergeTargetSheetState();
}

class _MergeTargetSheetState extends State<_MergeTargetSheet> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final choices =
        ExerciseCatalog.search(
          _query,
        ).where((d) => d.id != widget.source.id).toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppHeader(
              leading: AppBackButton(onPressed: () => Navigator.pop(context)),
              title: Text('Merge ${widget.source.name} into'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Choose the exercise to keep. ${widget.source.name} takes its '
                'name and joins its history.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  labelText: 'Search exercises',
                  prefixIcon: Icon(LucideIcons.search),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView.builder(
                itemCount: choices.length,
                itemBuilder:
                    (context, index) => ListTile(
                      title: Text(choices[index].name),
                      subtitle: Text(
                        _describe(
                          choices[index],
                          widget.usage[choices[index].id],
                        ),
                      ),
                      onTap: () => Navigator.pop(context, choices[index]),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
