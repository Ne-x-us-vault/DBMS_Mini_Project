import 'package:flutter/material.dart';

import '../services/group_repository.dart';
import '../services/local_session.dart';
import '../store/app_store.dart';
import 'chat_screen.dart';
import 'splits_screen.dart';

/// The tabbed view for one opened group (Splits + Chat), pushed from Home.
/// A floating back button returns to the home group list without leaving the
/// group; "Leave group" removes the membership and then pops back.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.repository,
    required this.local,
  });

  final String groupId;
  final GroupRepository repository;
  final LocalSession local;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late final AppStore _store = AppStore(
    repo: widget.repository,
    session: widget.local,
    groupId: widget.groupId,
  );
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _store.init();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  Future<void> _leaveGroup() async {
    final actingName = _store.managingAs.isEmpty
        ? widget.local.displayName
        : _store.managingAs;
    try {
      await widget.repository.leaveGroup(widget.groupId, name: actingName);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Could not leave "$_store.groupName". Try again.'),
        ));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        if (!_store.groupExists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Group')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'This group no longer exists.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'It may have been deleted.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back to my groups'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back to my groups',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(_store.groupName),
            actions: [
              IconButton(
                tooltip: 'Leave group',
                icon: const Icon(Icons.logout),
                onPressed: () => _confirmLeave(context),
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              SplitsScreen(store: _store, onLeave: () => _confirmLeave(context)),
              ChatScreen(store: _store),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Splits',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chat',
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmLeave(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text(
          'This phone will stop seeing the group. The group itself stays for '
          'everyone else.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx, true);
              _leaveGroup();
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }
}