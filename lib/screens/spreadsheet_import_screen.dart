import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/backup_service.dart';
import '../services/hive_service.dart';
import '../services/spreadsheet_import_service.dart';
import '../theme/app_theme.dart';

enum _ImportState { connect, upload, preview }

class SpreadsheetImportScreen extends StatefulWidget {
  const SpreadsheetImportScreen({super.key});

  @override
  State<SpreadsheetImportScreen> createState() =>
      _SpreadsheetImportScreenState();
}

class _SpreadsheetImportScreenState extends State<SpreadsheetImportScreen> {
  _ImportState _state = _ImportState.connect;
  final _urlController = TextEditingController(text: 'http://localhost:8000');

  bool _connecting = false;
  bool _converting = false;
  bool _importing = false;

  String? _selectedFilePath;
  String? _selectedFileName;

  Map<String, dynamic>? _conversionResult;
  List<String> _warnings = [];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    setState(() => _connecting = true);
    try {
      final service =
          SpreadsheetImportService(baseUrl: _urlController.text.trim());
      final ok = await service.checkHealth();
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('> Connection OK', style: GoogleFonts.jetBrainsMono()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('> Connection failed',
                style: GoogleFonts.jetBrainsMono()),
            backgroundColor: errorColor(context),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> ${e.toString()}',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final service =
          SpreadsheetImportService(baseUrl: _urlController.text.trim());
      final ok = await service.checkHealth();
      if (!mounted) return;
      if (ok) {
        setState(() {
          _state = _ImportState.upload;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('> Cannot connect to server',
                style: GoogleFonts.jetBrainsMono()),
            backgroundColor: errorColor(context),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> ${e.toString()}',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _convert() async {
    if (_selectedFilePath == null) return;
    setState(() => _converting = true);
    try {
      final service =
          SpreadsheetImportService(baseUrl: _urlController.text.trim());
      final result = await service.convertFile(_selectedFilePath!);
      if (!mounted) return;
      final warnings = (result['warnings'] as List?)?.cast<String>() ?? [];
      setState(() {
        _conversionResult = result;
        _warnings = warnings;
        _state = _ImportState.preview;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> Conversion failed: ${e.toString()}',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _importToApp() async {
    if (_conversionResult == null) return;

    final jsonMap = _conversionResult!['json'] as Map<String, dynamic>?;
    if (jsonMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> No JSON data in response',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
      return;
    }

    final jsonString = jsonEncode(jsonMap);
    final importResult = BackupService.importData(jsonString);

    if (!importResult.success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> ${importResult.errorMessage}',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
      return;
    }

    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final error = errorColor(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> IMPORT DATA?',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: error),
              ),
              const SizedBox(height: 16),
              Text(
                'This will REPLACE ALL of your current data.\n'
                'This action cannot be undone.',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(
                            color: textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: error,
                      foregroundColor: Colors.white,
                    ),
                    child:
                        Text('[IMPORT]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _importing = true);
    try {
      await HiveService.replaceAllPlans(importResult.plans!);
      await HiveService.replaceAllSessions(importResult.sessions!);

      if (!mounted) return;
      context.read<WorkoutPlanProvider>().loadPlans();
      context.read<WorkoutSessionProvider>().loadSessions();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> Data imported successfully',
              style: GoogleFonts.jetBrainsMono()),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('> Import failed: ${e.toString()}',
              style: GoogleFonts.jetBrainsMono()),
          backgroundColor: errorColor(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final accent = settings.accentColor;
    final bg = backgroundColor(context);
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(
          '> IMPORT SPREADSHEET',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 16, fontWeight: FontWeight.bold, color: accent),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(
          accent: accent,
          bg: bg,
          surface: surface,
          border: border,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),
      ),
    );
  }

  Widget _buildBody({
    required Color accent,
    required Color bg,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    switch (_state) {
      case _ImportState.connect:
        return _buildConnectState(
          accent: accent,
          surface: surface,
          border: border,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        );
      case _ImportState.upload:
        return _buildUploadState(
          accent: accent,
          surface: surface,
          border: border,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        );
      case _ImportState.preview:
        return _buildPreviewState(
          accent: accent,
          surface: surface,
          border: border,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        );
    }
  }

  Widget _buildConnectState({
    required Color accent,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> BACKEND URL',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 12, fontWeight: FontWeight.bold, color: accent),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlController,
          style: GoogleFonts.jetBrainsMono(color: textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'http://localhost:8000',
            labelStyle:
                GoogleFonts.jetBrainsMono(color: textSecondary, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _connecting ? null : _checkConnection,
                child: _connecting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Text('[CHECK CONNECTION]',
                        style: GoogleFonts.jetBrainsMono()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _connecting ? null : _connect,
                child: Text('[CONNECT]',
                    style: GoogleFonts.jetBrainsMono()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '> INSTRUCTIONS',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 12, fontWeight: FontWeight.bold, color: accent),
        ),
        const SizedBox(height: 8),
        Text(
          '1. Start the Python backend server\n'
          '2. Enter the server URL above\n'
          '3. Click "Check Connection" to verify\n'
          '4. Click "Connect" to proceed',
          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: textSecondary),
        ),
      ],
    );
  }

  Widget _buildUploadState({
    required Color accent,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> SELECT FILE',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 12, fontWeight: FontWeight.bold, color: accent),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a .xlsx or .csv spreadsheet to convert.',
          style: GoogleFonts.jetBrainsMono(fontSize: 12, color: textSecondary),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickFile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border, width: 1),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file, color: accent, size: 40),
                const SizedBox(height: 8),
                Text(
                  _selectedFileName ?? 'TAP TO BROWSE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: _selectedFileName != null
                        ? textPrimary
                        : textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                (_selectedFilePath != null && !_converting) ? _convert : null,
            child: _converting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : Text('[CONVERT]', style: GoogleFonts.jetBrainsMono()),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewState({
    required Color accent,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final jsonMap = _conversionResult?['json'] as Map<String, dynamic>?;
    final prettyJson = jsonMap != null
        ? const JsonEncoder.withIndent('  ').convert(jsonMap)
        : '{ }';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_warnings.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _warnings.map((w) => Chip(
              label: Text(w,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: Colors.black)),
              backgroundColor: Colors.amber,
              side: BorderSide.none,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          '> PREVIEW',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 12, fontWeight: FontWeight.bold, color: accent),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: border, width: 1),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                prettyJson,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _importing ? null : _importToApp,
                child: Text('[IMPORT TO APP]',
                    style: GoogleFonts.jetBrainsMono()),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _state = _ImportState.upload;
                  _conversionResult = null;
                  _warnings = [];
                });
              },
              child: Text('[BACK]', style: GoogleFonts.jetBrainsMono()),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('[DISCARD]', style: GoogleFonts.jetBrainsMono(color: textSecondary)),
            ),
          ],
        ),
      ],
    );
  }
}
