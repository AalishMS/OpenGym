import 'package:flutter/material.dart';

import '../../models/training_block.dart';
import '../../models/training_week.dart';
import '../../theme/radii.dart';

abstract final class TrainingBlockDialogs {
  static Future<String?> startingWeek(
    BuildContext context, {
    required List<TrainingBlock> blocks,
    required Map<String, List<TrainingWeek>> weeksByBlock,
    String? selectedWeekId,
  }) => showDialog<String>(
    context: context,
    builder:
        (_) => _StartingWeek(
          blocks: blocks,
          weeksByBlock: weeksByBlock,
          selectedWeekId: selectedWeekId,
        ),
  );

  static Future<TrainingBlock?> create(
    BuildContext context, {
    required Future<TrainingBlock> Function(String name, int count) onSave,
  }) => showDialog<TrainingBlock>(
    context: context,
    builder: (_) => _BlockForm(onCreate: onSave),
  );

  static Future<void> rename(
    BuildContext context,
    TrainingBlock block, {
    required Future<void> Function(String name) onSave,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _BlockForm(initialName: block.name, onRename: onSave),
  );

  static Future<void> reorder(
    BuildContext context,
    List<TrainingBlock> blocks, {
    required Future<void> Function(List<String> ids) onSave,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _BlockOrder(blocks: blocks, onSave: onSave),
  );
}

class _BlockForm extends StatefulWidget {
  final String? initialName;
  final Future<TrainingBlock> Function(String, int)? onCreate;
  final Future<void> Function(String)? onRename;
  const _BlockForm({this.initialName, this.onCreate, this.onRename});
  @override
  State<_BlockForm> createState() => _BlockFormState();
}

class _BlockFormState extends State<_BlockForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName ?? '');
  final _count = TextEditingController(text: '1');
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.onCreate case final create?) {
        final result = await create(_name.text.trim(), int.parse(_count.text));
        if (mounted) Navigator.pop(context, result);
      } else {
        await widget.onRename!(_name.text.trim());
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      title: Text(widget.onCreate != null ? 'Create block' : 'Rename block'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_saving,
                maxLength: 40,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Block name'),
                validator:
                    (value) =>
                        (value ?? '').trim().isEmpty
                            ? 'Enter a block name.'
                            : null,
              ),
              if (widget.onCreate != null)
                TextFormField(
                  controller: _count,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weeks'),
                  validator: (value) {
                    final count = int.tryParse(value ?? '');
                    return count == null || count < 1 || count > 52
                        ? 'Choose 1–52 weeks.'
                        : null;
                  },
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!),
                ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _BlockOrder extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Future<void> Function(List<String>) onSave;
  const _BlockOrder({required this.blocks, required this.onSave});
  @override
  State<_BlockOrder> createState() => _BlockOrderState();
}

class _BlockOrderState extends State<_BlockOrder> {
  late final _blocks = List<TrainingBlock>.of(widget.blocks);
  bool _saving = false;
  String? _error;
  void _move(int from, int to) {
    if (_saving || to < 0 || to >= _blocks.length) return;
    setState(() => _blocks.insert(to, _blocks.removeAt(from)));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_blocks.map((b) => b.id).toList());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Blocks changed. Close and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Reorder blocks'),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .45,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (index, block) in _blocks.indexed)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            block.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Move ${block.name} up',
                          onPressed:
                              _saving || index == 0
                                  ? null
                                  : () => _move(index, index - 1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Move ${block.name} down',
                          onPressed:
                              _saving || index == _blocks.length - 1
                                  ? null
                                  : () => _move(index, index + 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _StartingWeek extends StatefulWidget {
  final List<TrainingBlock> blocks;
  final Map<String, List<TrainingWeek>> weeksByBlock;
  final String? selectedWeekId;
  const _StartingWeek({
    required this.blocks,
    required this.weeksByBlock,
    this.selectedWeekId,
  });
  @override
  State<_StartingWeek> createState() => _StartingWeekState();
}

class _StartingWeekState extends State<_StartingWeek> {
  String? _block;
  String? _week;
  @override
  void initState() {
    super.initState();
    final choices =
        widget.blocks
            .where((b) => (widget.weeksByBlock[b.id] ?? []).isNotEmpty)
            .toList();
    final chosen =
        choices
            .where(
              (b) => widget.weeksByBlock[b.id]!.any(
                (w) => w.id == widget.selectedWeekId,
              ),
            )
            .firstOrNull ??
        choices.firstOrNull;
    _block = chosen?.id;
    _week =
        widget.selectedWeekId ??
        (_block == null ? null : widget.weeksByBlock[_block]!.first.id);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose starting week'),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _block,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Block'),
            items: [
              for (final b in widget.blocks.where(
                (b) => (widget.weeksByBlock[b.id] ?? []).isNotEmpty,
              ))
                DropdownMenuItem(
                  value: b.id,
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged:
                (value) => setState(() {
                  _block = value;
                  _week =
                      value == null
                          ? null
                          : widget.weeksByBlock[value]!.first.id;
                }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_block),
            initialValue: _week,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Week'),
            items: [
              for (final w in widget.weeksByBlock[_block] ?? <TrainingWeek>[])
                DropdownMenuItem(value: w.id, child: Text('Week ${w.number}')),
            ],
            onChanged: (value) => setState(() => _week = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _week == null ? null : () => Navigator.pop(context, _week),
        child: const Text('Use this week'),
      ),
    ],
  );
}
