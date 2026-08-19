import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A Tile tracker (key finder) attached to the account.
class _Tile {
  _Tile({
    required this.name,
    required this.batteryPercent,
    required this.lastSeen,
  });

  final String name;
  final int batteryPercent;
  final String lastSeen;
  bool ringing = false;
}

/// The Keys / Tile screen. Lists Tile trackers with battery and last-seen,
/// and lets the user ring one to find it.
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  final List<_Tile> _tiles = <_Tile>[
    _Tile(name: 'House keys', batteryPercent: 82, lastSeen: 'Just now'),
    _Tile(name: 'Car keys', batteryPercent: 45, lastSeen: '5m ago'),
    _Tile(name: 'Backpack', batteryPercent: 12, lastSeen: '1h ago'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keys')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final _Tile t in _tiles)
            _TileRow(
              tile: t,
              onRing: () => setState(() => t.ringing = !t.ringing),
            ),
          _AddTileRow(onTap: _addTile),
        ],
      ),
    );
  }

  void _addTile() {
    final TextEditingController name = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a Tile'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tile name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final String n = name.text.trim();
              if (n.isNotEmpty) {
                setState(() {
                  _tiles.add(
                    _Tile(name: n, batteryPercent: 100, lastSeen: 'Just now'),
                  );
                });
              }
              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.tile, required this.onRing});

  final _Tile tile;
  final VoidCallback onRing;

  @override
  Widget build(BuildContext context) {
    final Color batteryColor = tile.batteryPercent <= 20
        ? AppColors.statusRed
        : tile.batteryPercent <= 50
            ? AppColors.statusOrange
            : AppColors.statusGreen;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.purple.withValues(alpha: 0.12),
        ),
        child: const Icon(Icons.key, color: AppColors.purple, size: 22),
      ),
      title: Text(
        tile.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('${tile.batteryPercent}% · ${tile.lastSeen}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_std, color: batteryColor, size: 20),
          const SizedBox(width: 8),
          IconButton(
            tooltip: tile.ringing ? 'Stop ringing' : 'Ring',
            icon: Icon(
              tile.ringing ? Icons.volume_up : Icons.volume_up_outlined,
              color: tile.ringing ? AppColors.purple : AppColors.textMuted,
            ),
            onPressed: onRing,
          ),
        ],
      ),
    );
  }
}

class _AddTileRow extends StatelessWidget {
  const _AddTileRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.add_circle_outline, color: AppColors.purple),
      title: const Text(
        'Add a Tile',
        style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
