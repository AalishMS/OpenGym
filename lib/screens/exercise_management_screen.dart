import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/supabase_service.dart';
import '../models/exercise_definition.dart';
import '../services/exercise_catalog.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/persistence_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _changes = SyncService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  Future<void> _merge(ExerciseDefinition source) async {
    final target = await showModalBottomSheet<ExerciseDefinition>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (_) => _MergeTargetSheet(source: source),
    );
    if (target == null || !mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => PersistenceDialog(
            title: 'Merge exercises?',
            content: Text(
              '“${source.name}” will use “${target.name}” for statistics, records, '
              'and previous sets across all your splits. All logged sets and their '
              'original names will be kept. Only merge these if they are the same movement.',
            ),
            actionLabel: 'Merge',
            progressLabel: 'Merging exercises',
            failureMessage: 'Could not merge exercises. Try again or cancel.',
            onPersist:
                () => SyncService.instance.runExclusiveLocalMutation(() async {
                  if (!mounted ||
                      SupabaseService.currentUserId != widget.userId) {
                    throw StateError('The exercise account changed.');
                  }
                  await ExerciseCatalog.merge(
                    source.id,
                    target.id,
                    userId: widget.userId,
                  );
                }),
          ),
    );
    if (!mounted || saved != true) return;
    SyncService.instance.notifyLocalChange();
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Merged into ${target.name}')));
  }

  Future<void> _rename(ExerciseDefinition exercise) async {
    String input = exercise.name;
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (context, update) => PopScope(
                  canPop: !saving,
                  child: AlertDialog(
                    title: const Text('Rename exercise'),
                    content: TextFormField(
                      initialValue: exercise.name,
                      onChanged: (value) => input = value,
                      enabled: !saving,
                      autofocus: true,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: 'Exercise name',
                        errorText: error,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed:
                            saving
                                ? null
                                : () async {
                                  update(() => saving = true);
                                  try {
                                    await SyncService.instance
                                        .runExclusiveLocalMutation(() async {
                                          if (!mounted ||
                                              SupabaseService.currentUserId !=
                                                  widget.userId) {
                                            throw StateError(
                                              'The exercise account changed.',
                                            );
                                          }
                                          await ExerciseCatalog.rename(
                                            exercise.id,
                                            input,
                                            userId: widget.userId,
                                          );
                                        });
                                    SyncService.instance.notifyLocalChange();
                                    if (!dialogContext.mounted || !mounted) {
                                      return;
                                    }
                                    Navigator.pop(dialogContext);
                                    setState(() {});
                                  } catch (failure) {
                                    debugPrint(
                                      'Could not rename exercise: $failure',
                                    );
                                    if (dialogContext.mounted) {
                                      update(() {
                                        saving = false;
                                        error =
                                            failure is FormatException
                                                ? failure.message.toString()
                                                : 'Could not rename exercise. Try again.';
                                      });
                                    }
                                  }
                                },
                        child: Text(saving ? 'Saving…' : 'Save'),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ExerciseCatalog.search(_query)..sort((a, b) {
      final customFirst = (a.builtIn ? 1 : 0).compareTo(b.builtIn ? 1 : 0);
      return customFirst == 0 ? a.name.compareTo(b.name) : customFirst;
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
                  'Merge duplicate names to bring their statistics together. Your exercise library is shared across all splits.',
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
                              Divider(height: 1, color: borderColor(context)),
                      itemBuilder: (context, index) {
                        final d = exercises[index];
                        return ListTile(
                          title: Text(d.name),
                          subtitle: Text(d.category),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Actions for ${d.name}',
                            onSelected:
                                (action) =>
                                    action == 'merge' ? _merge(d) : _rename(d),
                            itemBuilder:
                                (_) => [
                                  if (!d.builtIn)
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                  const PopupMenuItem(
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

class _MergeTargetSheet extends StatefulWidget {
  final ExerciseDefinition source;
  const _MergeTargetSheet({required this.source});
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
          children: [
            AppHeader(
              leading: AppBackButton(onPressed: () => Navigator.pop(context)),
              title: const Text('Merge into'),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  labelText: 'Search exercises',
                  prefixIcon: Icon(LucideIcons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: choices.length,
                itemBuilder:
                    (context, index) => ListTile(
                      title: Text(choices[index].name),
                      subtitle: Text(choices[index].category),
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
