import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../providers/split_provider.dart';
import '../services/backup_service.dart';
import '../services/hive_service.dart';
import '../services/sample_data_seeder.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../widgets/update_dialog.dart';
import '../widgets/action_progress.dart';
import '../widgets/persistence_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onClearData,
    this.onLoadSampleData,
    this.onSignOut,
    this.onReplayTutorial,
  });

  final Future<void> Function(String splitId)? onClearData;
  final Future<void> Function()? onLoadSampleData;
  final Future<void> Function()? onSignOut;
  final Future<void> Function()? onReplayTutorial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _busyAction;
  bool _confirmingMutation = false;

  Future<void> _confirmMutation({
    required String title,
    required String message,
    required String actionLabel,
    required String progressLabel,
    required String successMessage,
    required Future<void> Function() persist,
    bool destructive = false,
  }) async {
    if (_busyAction != null || _confirmingMutation) return;
    setState(() => _confirmingMutation = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => PersistenceDialog(
              title: title,
              content: Text(message),
              actionLabel: actionLabel,
              progressLabel: progressLabel,
              failureMessage:
                  'Could not complete this action. Try again or cancel.',
              onPersist: () async {
                if (mounted) setState(() => _busyAction = progressLabel);
                try {
                  await persist();
                } finally {
                  if (mounted) setState(() => _busyAction = null);
                }
              },
              destructive: destructive,
            ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyAction = null;
          _confirmingMutation = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Needed for the VERSION line. Cheap, cached in the provider, and harmless
    // if it fails — the label falls back to an em dash.
    context.read<UpdateProvider>().loadInstalledVersion();
  }

  String? _signedInEmail() {
    try {
      return SupabaseService.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  /// The tile's second line, which doubles as the result readout for a manual
  /// check — the outcome stays visible after the snackbar has gone.
  String _updateSubtitle(UpdateProvider updates) {
    if (updates.isPreview) return 'Preview update dialog';
    if (!UpdateService.isSupportedPlatform) {
      return 'Only available on Android';
    }
    switch (updates.status) {
      case UpdateStatus.checking:
        return 'Checking GitHub...';
      case UpdateStatus.available:
        return '${updates.release?.version.displayLabel ?? 'A new version'} is ready';
      case UpdateStatus.upToDate:
        return "You're up to date";
      case UpdateStatus.downloading:
        return 'Downloading... ${(updates.progress * 100).round()}%';
      case UpdateStatus.installing:
        return 'Opening the installer...';
      case UpdateStatus.failed:
        return updates.error ?? 'Last check failed';
      case UpdateStatus.idle:
        return 'Check GitHub for a new release';
    }
  }

  Future<void> _handleUpdateCheck(
    BuildContext context,
    UpdateProvider updates,
  ) async {
    // Already found one, or already working — reopen the dialog rather than
    // starting a second check on top of the first.
    if (updates.isUpdateAvailable || updates.isBusy) {
      await showUpdateDialog(context);
      return;
    }
    if (updates.status == UpdateStatus.checking) return;

    try {
      await updates.checkManually();
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Update check failed: $e');
      return;
    }
    if (!context.mounted) return;

    if (updates.isUpdateAvailable) {
      await showUpdateDialog(context);
      return;
    }

    // The user asked, so say something either way. Silence on a tapped button
    // reads as a bug.
    final failed = updates.status == UpdateStatus.failed;
    final ground = failed ? errorColor(context) : accentColor(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed ? updates.error ?? 'Update check failed' : "You're up to date",
          style: GoogleFonts.jetBrainsMono(color: onColor(ground)),
        ),
        backgroundColor: ground,
      ),
    );
  }

  Future<void> _runSettingsAction(
    BuildContext context,
    Future<void> Function() action, {
    String progressLabel = 'Saving settings',
  }) async {
    if (_busyAction != null || _confirmingMutation) return;
    setState(() => _busyAction = progressLabel);
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      debugPrint('$progressLabel failed: $e');
      _showError(context, 'Could not complete this action. Try again.');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.jetBrainsMono(color: onColor(errorColor(context))),
        ),
        backgroundColor: errorColor(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateProvider>();
    final accent = accentColor(context);
    final bg = backgroundColor(context);
    final surface = surfaceColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: textPrimaryColor(context)),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _busyAction != null || _confirmingMutation,
              child: Consumer<SettingsProvider>(
                builder: (context, settings, child) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeader(title: 'Appearance'),
                        _buildThemeSection(context, settings),
                        _buildAccentColorSection(context, settings),
                        const _SectionHeader(title: 'Workout'),
                        _buildSwitchTile(
                          context: context,
                          icon: LucideIcons.zap,
                          title: 'Auto-fill last weights',
                          subtitle:
                              'Automatically fill weight from previous workout',
                          value: settings.autoFillLast,
                          onChanged:
                              (value) => _runSettingsAction(
                                context,
                                () => settings.setAutoFillLast(value),
                              ),
                        ),
                        if (SupabaseService.isConfigured) ...[
                          const _SectionHeader(
                            title: 'Artificial intelligence',
                          ),
                          _buildSwitchTile(
                            context: context,
                            icon: LucideIcons.messageSquareText,
                            title: 'Coach',
                            subtitle:
                                'Ask the AI Coach to build or change your plans',
                            value: settings.coachEnabled,
                            onChanged:
                                (value) => _runSettingsAction(
                                  context,
                                  () => settings.setCoachEnabled(value),
                                ),
                          ),
                        ],
                        const _SectionHeader(title: 'Data'),
                        _buildSettingsTile(
                          icon: LucideIcons.flaskConical,
                          title: 'Load sample data',
                          subtitle: 'Add sample plans and workouts for testing',
                          onTap: () => _loadSampleData(context),
                        ),
                        _buildSettingsTile(
                          icon: LucideIcons.upload,
                          title: 'Export data',
                          subtitle: 'Backup all plans, sessions, and settings',
                          onTap: () => _exportData(context),
                        ),
                        _buildSettingsTile(
                          icon: LucideIcons.download,
                          title: 'Import data',
                          subtitle:
                              'Restore from a backup file (replaces all data)',
                          onTap: () => _importData(context),
                        ),
                        if (_signedInEmail() != null) ...[
                          const _SectionHeader(title: 'Account'),
                          StreamBuilder<void>(
                            stream: SyncService.instance.statusChanges,
                            builder: (context, _) {
                              final status = SyncService.instance.status;
                              final label = switch (status) {
                                SyncStatus.savedOnDevice => 'Saved on device',
                                SyncStatus.pending => 'Sync pending',
                                SyncStatus.synced => 'Synced',
                              };
                              final detail = switch (status) {
                                SyncStatus.savedOnDevice =>
                                  'Your data is saved on this device',
                                SyncStatus.pending =>
                                  'Waiting to finish syncing',
                                SyncStatus.synced => 'Your data is up to date',
                              };
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      LucideIcons.cloud,
                                      color: accent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label,
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                          ),
                                          Text(
                                            detail,
                                            style:
                                                Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                        const _SectionHeader(title: 'Danger zone'),
                        _buildSettingsTile(
                          icon: LucideIcons.trash2,
                          title: 'Clear current split data',
                          subtitle:
                              'Delete plans and history in the current split',
                          onTap: () => _confirmClearData(context),
                          isDestructive: true,
                        ),
                        if (widget.onSignOut != null ||
                            _signedInEmail() != null)
                          _buildSettingsTile(
                            icon: LucideIcons.logOut,
                            title: 'Sign out',
                            subtitle:
                                widget.onSignOut != null
                                    ? 'Sign out of OpenGym'
                                    : _signedInEmail() ?? 'Signed in',
                            onTap: () async {
                              await _runSettingsAction(
                                context,
                                widget.onSignOut ?? SupabaseService.signOut,
                                progressLabel: 'Signing out',
                              );
                              // AuthGate reacts and shows LoginScreen automatically.
                            },
                          ),
                        const _SectionHeader(title: 'Updates'),
                        _buildSettingsTile(
                          icon: LucideIcons.download,
                          title: 'Check for updates',
                          subtitle: _updateSubtitle(updates),
                          onTap: () => _handleUpdateCheck(context, updates),
                          valueIsMono: true,
                        ),
                        const _SectionHeader(title: 'About'),
                        if (widget.onReplayTutorial != null)
                          _buildSettingsTile(
                            icon: LucideIcons.circleHelp,
                            title: 'Replay tutorial',
                            subtitle: 'A quick guide to using OpenGym',
                            onTap:
                                () => _runSettingsAction(
                                  context,
                                  widget.onReplayTutorial!,
                                  progressLabel: 'Opening tutorial',
                                ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Version',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                updates.installedVersionLabel,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 14,
                                  color: textPrimaryColor(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Made by Aalish',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // Saving must not resize the viewport or move the controls being used.
          if (_busyAction != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ActionProgress(_busyAction!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(BuildContext context, SettingsProvider settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Choose how OpenGym looks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Theme',
            child: SegmentedButton<ThemeMode>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged:
                  (selection) => _runSettingsAction(
                    context,
                    () => settings.setThemeMode(selection.first),
                  ),
              multiSelectionEnabled: false,
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: surfaceColor(context),
                foregroundColor: textPrimaryColor(context),
                selectedBackgroundColor: accentFillColor(context),
                selectedForegroundColor: onAccentColor(context),
                side: BorderSide(color: borderColor(context)),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.control,
                ),
                minimumSize: const Size(72, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                textStyle: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentColorSection(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const columns = 4;
    const gap = 8.0;
    final count = SettingsProvider.accents.length;
    final rows = (count / columns).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Accent color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Used for buttons, highlights and charts.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          // Equal-width cells in a fixed grid, so the eight options always
          // fill complete rows instead of wrapping to a ragged last line.
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: gap),
            Row(
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: gap),
                  Expanded(
                    child:
                        row * columns + col < count
                            ? _buildColorBox(
                              context,
                              row * columns + col,
                              settings,
                              isDark,
                            )
                            : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorBox(
    BuildContext context,
    int index,
    SettingsProvider settings,
    bool isDark,
  ) {
    final option = SettingsProvider.accents[index];
    final isSelected = settings.accentIndex == index;
    // One tone per mode, resolved through the same solver the theme uses, so
    // this swatch is exactly the colour that selecting it will paint.
    final swatch = accentToneFor(
      option.seed,
      isDark ? Brightness.dark : Brightness.light,
    );

    return Semantics(
      label: '${option.name} accent',
      button: true,
      selected: isSelected,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('accent-swatch-$index'),
        onTap:
            () => _runSettingsAction(
              context,
              () => settings.setAccentColor(index),
            ),
        borderRadius: AppRadius.button,
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color:
                isSelected ? accentMutedColor(context) : surfaceColor(context),
            // Constant width so selecting never shifts the layout.
            border: Border.all(
              color: isSelected ? swatch : Colors.transparent,
              width: 2,
            ),
            borderRadius: AppRadius.button,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                ),
                child:
                    isSelected
                        ? Icon(
                          LucideIcons.check,
                          size: 18,
                          color: onColor(swatch),
                        )
                        : null,
              ),
              const SizedBox(height: 6),
              Text(
                option.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      isSelected
                          ? textPrimaryColor(context)
                          : textSecondaryColor(context),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: backgroundColor(context),
      secondary: Icon(icon, color: accentColor(context), size: 20),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool valueIsMono = false,
  }) {
    final textColor =
        isDestructive ? errorColor(context) : textPrimaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isDestructive ? textColor : accentColor(context),
                  size: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: textColor),
                      ),
                      Text(
                        subtitle,
                        style:
                            valueIsMono
                                ? GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: textSecondaryColor(context),
                                )
                                : Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  color: textSecondaryColor(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _loadSampleData(BuildContext context) {
    final splitId = context.read<SplitProvider>().activeSplitId;
    final plans = context.read<WorkoutPlanProvider>();
    final sessions = context.read<WorkoutSessionProvider>();
    _confirmMutation(
      title: 'Load sample data?',
      message:
          'This will replace workout data in the active split with fresh sample plans and workouts.',
      actionLabel: 'Load',
      progressLabel: 'Loading sample data',
      successMessage: 'Sample data refreshed',
      persist: () async {
        try {
          if (widget.onLoadSampleData != null) {
            await widget.onLoadSampleData!();
          } else {
            if (splitId == null) throw StateError('No active split available.');
            await SampleDataSeeder.clearDataForSplit(splitId);
            await SampleDataSeeder.seedSampleData(splitId: splitId);
          }
        } finally {
          plans.loadPlans();
          sessions.loadSessions();
        }
      },
    );
  }

  void _exportData(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final splits = context.read<SplitProvider>();
    _confirmMutation(
      title: 'Export data?',
      message:
          'Create a backup containing all your plans, sessions, and settings.',
      actionLabel: 'Export',
      progressLabel: 'Exporting backup',
      successMessage: 'Backup exported successfully',
      persist: () async {
        final activeSplitId = splits.activeSplitId;
        if (activeSplitId == null) {
          throw StateError('No active split available.');
        }
        final result = BackupService.exportData(
          splits: HiveService.getSplits(),
          activeSplitId: activeSplitId,
          plans: HiveService.getPlans(),
          sessions: HiveService.getSessions(),
          settings: {
            'themeMode': settings.themeMode.index,
            'accentIndex': settings.accentIndex,
            'weightUnit': settings.weightUnit,
            'autoFillLast': settings.autoFillLast,
          },
        );
        await Share.shareXFiles([
          XFile.fromData(
            utf8.encode(result.jsonString),
            name: result.fileName,
            mimeType: 'application/json',
          ),
        ], text: 'OpenGym Backup');
      },
    );
  }

  Future<void> _importData(BuildContext context) async {
    if (_busyAction != null || _confirmingMutation) return;
    setState(() => _busyAction = 'Reading backup');
    try {
      final pickResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!context.mounted || pickResult == null || pickResult.files.isEmpty) {
        return;
      }
      final pickedFile = pickResult.files.single;
      final jsonString =
          pickedFile.bytes != null
              ? utf8.decode(pickedFile.bytes!)
              : await File(pickedFile.path!).readAsString();
      if (!context.mounted) return;
      final userId = SupabaseService.currentUserId ?? 'local';
      final imported = BackupService.importData(jsonString, userId: userId);
      if (!imported.success) {
        _showError(
          context,
          imported.errorMessage ??
              'Could not read the backup. Choose another file.',
        );
        return;
      }
      final settingsError = _validateImportedSettings(imported.settings!);
      if (settingsError != null) {
        _showError(context, settingsError);
        return;
      }
      final settings = context.read<SettingsProvider>();
      final plans = context.read<WorkoutPlanProvider>();
      final sessions = context.read<WorkoutSessionProvider>();
      final splits = context.read<SplitProvider>();
      setState(() => _busyAction = null);
      await _confirmMutation(
        title: 'Import backup?',
        message:
            'This will replace all workout plans, history, and app settings. This action cannot be undone.',
        actionLabel: 'Import',
        progressLabel: 'Importing backup',
        successMessage: 'Backup imported successfully',
        destructive: true,
        persist: () async {
          // Retain this validated backup in the dialog for retries.
          try {
            await HiveService.replaceAllWorkoutData(
              userId: userId,
              splits: imported.splits!,
              activeSplitId: imported.activeSplitId!,
              plans: imported.plans!,
              sessions: imported.sessions!,
            );
            final values = imported.settings!;
            await settings.setThemeMode(
              ThemeMode.values[values['themeMode'] as int],
            );
            await settings.setAccentColor(values['accentIndex'] as int);
            await settings.setWeightUnit(values['weightUnit'] as String);
            await settings.setAutoFillLast(values['autoFillLast'] as bool);
            SyncService.instance.scheduleSync();
          } finally {
            // A settings write may fail after the workout data was replaced.
            // Always reconcile the visible workspace with persisted data.
            splits.loadSplits();
            plans.loadPlans();
            sessions.loadSessions();
          }
        },
      );
    } catch (error) {
      debugPrint('Failed to read backup: $error');
      if (context.mounted) {
        _showError(
          context,
          'Could not read the backup. Try choosing the file again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _confirmClearData(BuildContext context) {
    final split = context.read<SplitProvider>().activeSplit;
    if (split == null) {
      _showError(context, 'Select a split before clearing its data.');
      return;
    }
    final plans = context.read<WorkoutPlanProvider>();
    final sessions = context.read<WorkoutSessionProvider>();
    _confirmMutation(
      title: 'Clear split data?',
      message:
          'This will delete all workout plans and history in "${split.name}". Other splits will be kept. This action cannot be undone.',
      actionLabel: 'Clear split data',
      progressLabel: 'Clearing split data',
      successMessage: 'Data cleared for "${split.name}"',
      destructive: true,
      persist: () async {
        try {
          await (widget.onClearData ?? SampleDataSeeder.clearDataForSplit)(
            split.id,
          );
        } finally {
          plans.loadPlans();
          sessions.loadSessions();
        }
      },
    );
  }

  String? _validateImportedSettings(Map<String, dynamic> settings) {
    final themeMode = settings['themeMode'];
    final accentIndex = settings['accentIndex'];
    final weightUnit = settings['weightUnit'];
    final autoFillLast = settings['autoFillLast'];
    if (themeMode is! int ||
        themeMode < 0 ||
        themeMode >= ThemeMode.values.length ||
        accentIndex is! int ||
        accentIndex < 0 ||
        accentIndex >= SettingsProvider.accents.length ||
        weightUnit is! String ||
        (weightUnit != 'kg' && weightUnit != 'lbs') ||
        autoFillLast is! bool) {
      return 'Invalid settings in backup';
    }
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
