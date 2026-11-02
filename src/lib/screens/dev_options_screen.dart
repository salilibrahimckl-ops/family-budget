import 'package:flutter/material.dart';

import '../categories.dart';
import '../repo.dart';

/// Developer options: create your own spending categories, rename, recolour
/// or hide the built-in ones, and add auto-detect keywords.
class DevOptionsScreen extends StatelessWidget {
  const DevOptionsScreen({super.key, required this.repo});
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: repo.familyStream(),
      builder: (context, snap) {
        if (snap.hasData) CatStore.apply(snap.data!.data());
        final cats = CatStore.all;
        final tt = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Developer options')),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'newCat',
            icon: const Icon(Icons.add),
            label: const Text('New category'),
            onPressed: () => _edit(context, null, cats.length),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Spending categories. Add your own (e.g. Medical, School fees), rename or hide the '
                  'built-in ones, and add keywords so matching UPI payments are sorted automatically. '
                  'Changes apply to both phones.',
                  style: tt.bodySmall,
                ),
              ),
              for (final c in cats)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: c.color.withValues(alpha: c.hidden ? 0.06 : 0.15),
                    child: Icon(c.icon, color: c.hidden ? Colors.grey : c.color),
                  ),
                  title: Text(c.label,
                      style: TextStyle(
                          color: c.hidden ? Colors.grey : null,
                          decoration: c.hidden ? TextDecoration.lineThrough : null)),
                  subtitle: Text([
                    c.custom ? 'Your category' : 'Built-in',
                    if (c.goal) 'target (set aside)',
                    if (c.hidden) 'hidden',
                    if (c.keywords.isNotEmpty) 'keywords: ${c.keywords.join(', ')}',
                  ].join(' · ')),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(context, c, cats.indexOf(c)),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Cat? existing, int order) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CatEditor(repo: repo, existing: existing, order: order),
    );
  }
}

class _CatEditor extends StatefulWidget {
  const _CatEditor({required this.repo, required this.existing, required this.order});
  final Repo repo;
  final Cat? existing;
  final int order;
  @override
  State<_CatEditor> createState() => _CatEditorState();
}

class _CatEditorState extends State<_CatEditor> {
  late final _name = TextEditingController(text: widget.existing?.label ?? '');
  late final _kw = TextEditingController(text: widget.existing?.keywords.join(', ') ?? '');
  late String _icon = widget.existing?.iconKey ?? 'label';
  late Color _color = widget.existing?.color ?? kColorChoices[widget.order % kColorChoices.length];
  late bool _goal = widget.existing?.goal ?? false;
  late bool _hidden = widget.existing?.hidden ?? false;
  bool _busy = false;

  bool get _isNew => widget.existing == null;
  bool get _builtIn => widget.existing != null && !widget.existing!.custom;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final id = widget.existing?.id ?? 'c_${DateTime.now().millisecondsSinceEpoch}';
    final kws = _kw.text.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    final cat = Cat(id, name, _icon, _color,
        goal: _builtIn ? widget.existing!.goal : _goal,
        custom: widget.existing?.custom ?? true,
        hidden: _hidden,
        keywords: kws);
    await widget.repo.saveCat(cat, order: _isNew ? 100 + widget.order : null);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_isNew ? 'New category' : 'Edit category', style: tt.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _kw,
            decoration: const InputDecoration(
              labelText: 'Auto-detect keywords (optional)',
              hintText: 'e.g. apollo, pharmacy, hospital',
              helperText: 'Payments whose payee contains any of these go here automatically',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Icon', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in kIconChoices.entries)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _icon = e.key),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: _icon == e.key ? _color : _color.withValues(alpha: 0.10),
                  child: Icon(e.value, size: 20, color: _icon == e.key ? Colors.white : _color),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Colour', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kColorChoices)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _color.toARGB32() == c.toARGB32()
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          if (!_builtIn)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _goal,
              onChanged: (v) => setState(() => _goal = v),
              title: const Text('Money set aside (like Savings)'),
              subtitle: const Text('Shows progress to a target instead of money left to spend'),
            ),
          if (!_isNew)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
              title: const Text('Hide this category'),
            ),
          const SizedBox(height: 8),
          Row(children: [
            if (widget.existing?.custom == true)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text('Delete ${widget.existing!.label}?'),
                            content: const Text('Its payments will move to "To tag".'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await widget.repo.deleteCat(widget.existing!);
                        if (context.mounted) Navigator.pop(context);
                      },
              ),
            if (_builtIn)
              TextButton(
                onPressed: () async {
                  await widget.repo.resetCat(widget.existing!);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Reset to default'),
              ),
            const Spacer(),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_isNew ? 'Add' : 'Save')),
          ]),
        ]),
      ),
    );
  }
}
