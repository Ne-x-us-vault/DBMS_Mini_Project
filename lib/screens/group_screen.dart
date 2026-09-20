import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/group_repository.dart';

/// After confirming a group code: pick your "Managing as" name from the
/// existing members or add your own name.
class JoinSetupScreen extends StatefulWidget {
  const JoinSetupScreen({
    super.key,
    required this.group,
    required this.repository,
  });

  final GroupInfo group;
  final GroupRepository repository;

  @override
  State<JoinSetupScreen> createState() => _JoinSetupScreenState();
}

class _JoinSetupScreenState extends State<JoinSetupScreen> {
  String? _selected;
  bool _addMine = false;
  final TextEditingController _mine = TextEditingController();

  @override
  void dispose() {
    _mine.dispose();
    super.dispose();
  }

  String? get _pick =>
      _addMine ? (_mine.text.trim().isEmpty ? null : _mine.text.trim()) : _selected;

  Future<void> _continue() async {
    final name = _pick;
    if (name == null) return;
    if (_addMine && !widget.group.members.contains(name)) {
      await widget.repository.setMembers(
        widget.group.id,
        [...widget.group.members, name],
      );
    }
    if (!mounted) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = widget.group.members;
    return Scaffold(
      appBar: AppBar(title: const Text('Joining group')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '“${widget.group.name}” · You’ll manage expenses, history and chat as one of the members below.',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          for (final m in members)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(m[0].toUpperCase())),
                title: Text(m),
                trailing: _addMine
                    ? null
                    : Icon(
                        _selected == m
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _selected == m
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                onTap: () => setState(() {
                  _addMine = false;
                  _selected = m;
                }),
              ),
            ),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: const Icon(Icons.person_add_alt)),
              title: const Text("Add my own name"),
              trailing: Icon(
                _addMine ? Icons.check_circle : Icons.radio_button_unchecked,
                color: _addMine
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              onTap: () => setState(() => _addMine = true),
            ),
          ),
          if (_addMine) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _mine,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'Will be added as a new member',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _pick == null ? null : _continue,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}