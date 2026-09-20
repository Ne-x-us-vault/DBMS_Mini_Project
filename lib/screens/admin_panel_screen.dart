import 'package:flutter/material.dart';

import '../models/models.dart';
import '../store/app_store.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key, required this.store});

  final AppStore store;

  Future<void> _confirmRemoveUser(BuildContext context, UserProfile u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove user?'),
        content: Text(
          '${u.name} will no longer be a group member. Their expenses stay in the history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) store.removeUser(u.uid);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = store.users;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage users & roles')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Users are the people who sign up. The admin can change roles or remove a member. Admins can edit and delete any expense; members only their own.',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (users.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No users yet.'),
              ),
            )
          else
            for (final u in users)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text(u.name[0].toUpperCase())),
                  title: Text(u.name),
                  subtitle: Text(u.email),
                  trailing: u.uid == store.myUid
                      ? const Chip(
                          avatar: Icon(Icons.shield_outlined, size: 16),
                          label: Text('You'),
                          visualDensity: VisualDensity.compact,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              avatar: Icon(
                                u.isAdmin
                                    ? Icons.shield_outlined
                                    : Icons.person_outline,
                                size: 16,
                              ),
                              label: Text(u.isAdmin ? 'Admin' : 'Member'),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: u.isAdmin ? 'Make member' : 'Make admin',
                              icon: Icon(
                                u.isAdmin
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                              ),
                              onPressed: () =>
                                  store.setRole(u.uid, u.isAdmin ? 'member' : 'admin'),
                            ),
                            IconButton(
                              tooltip: 'Remove user',
                              icon: const Icon(Icons.person_remove_outlined),
                              color: Colors.red,
                              onPressed: () => _confirmRemoveUser(context, u),
                            ),
                          ],
                        ),
                ),
              ),
          if (store.isAdmin &&
              users.where((u) => u.isAdmin).length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'There are multiple admins. Keep at least one admin.',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}