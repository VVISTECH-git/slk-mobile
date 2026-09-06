import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'settings_providers.dart';

/// One place to manage the shop's reference lists — Locations, Fabrics,
/// Techniques, Dye types, Border styles. Pulled out of the long Settings page
/// so master-data lives somewhere obvious and is quick to add to.
class MasterDataScreen extends ConsumerWidget {
  const MasterDataScreen({super.key});

  SettingsRepository _repo(WidgetRef ref) => ref.read(settingsRepositoryProvider);

  Future<void> _guard(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(settingsProvider);
      if (context.mounted) showOk(context, 'Saved.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<String?> _promptName(BuildContext context, String title) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => Navigator.pop(context, c.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Master data'),
        actions: [
          IconButton(onPressed: () => ref.invalidate(settingsProvider), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<Map<String, dynamic>>(
        value: settings,
        onRetry: () => ref.invalidate(settingsProvider),
        data: (d) {
          final locations = (d['locations'] as List?) ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  'The reference lists your designs and stock pick from. '
                  'Add here and they show up everywhere in the app.',
                  style: TextStyle(fontSize: 13, color: context.p.textSecondary),
                ),
              ),

              // Locations — add/delete (delete only when nothing is stored there).
              _MasterGroup(
                icon: Icons.store_mall_directory_outlined,
                title: 'Locations',
                subtitle: 'Stores & warehouses',
                rows: locations
                    .map((l) => (l as Map))
                    .map((m) => _Row(
                          name: '${m['name']}',
                          sub: '${m['type']} · ${m['inUse']} in use',
                          canDelete: (m['inUse'] as num?) == 0,
                          onDelete: () => _guard(context, ref, () => _repo(ref).deleteLocation(m['id'] as String)),
                        ))
                    .toList(),
                onAdd: () async {
                  final name = await _promptName(context, 'New location');
                  if (name != null && name.isNotEmpty) {
                    // ignore: use_build_context_synchronously — _guard checks context.mounted itself
                    await _guard(context, ref, () => _repo(ref).addLocation(name, 'retail'));
                  }
                },
              ),

              _attr(context, ref, d, icon: Icons.texture_outlined, title: 'Fabrics', kind: 'fabric', key: 'fabrics'),
              _attr(context, ref, d, icon: Icons.brush_outlined, title: 'Techniques', kind: 'technique', key: 'techniques'),
              _attr(context, ref, d, icon: Icons.water_drop_outlined, title: 'Dye types', kind: 'dye', key: 'dyeTypes'),
              _attr(context, ref, d, icon: Icons.border_style_outlined, title: 'Border styles', kind: 'border', key: 'borderStyles'),
            ],
          );
        },
      ),
    );
  }

  Widget _attr(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> d, {
    required IconData icon,
    required String title,
    required String kind,
    required String key,
  }) {
    final rows = (d[key] as List?) ?? [];
    return _MasterGroup(
      icon: icon,
      title: title,
      subtitle: 'Used on designs',
      rows: rows
          .map((r) => (r as Map))
          .map((m) => _Row(
                name: '${m['name']}',
                sub: '${m['inUse']} in use',
                canDelete: (m['inUse'] as num?) == 0,
                onDelete: () => _guard(context, ref, () => _repo(ref).deleteAttribute(kind, m['id'] as String)),
              ))
          .toList(),
      onAdd: () async {
        final name = await _promptName(context, 'New ${title.toLowerCase().replaceAll(RegExp(r's$'), '')}');
        if (name != null && name.isNotEmpty) {
          // ignore: use_build_context_synchronously — _guard checks context.mounted itself
          await _guard(context, ref, () => _repo(ref).addAttribute(kind, name));
        }
      },
    );
  }
}

class _Row {
  const _Row({required this.name, required this.sub, required this.canDelete, required this.onDelete});
  final String name;
  final String sub;
  final bool canDelete;
  final VoidCallback onDelete;
}

/// A collapsible card for one master-data list, with a prominent Add button.
class _MasterGroup extends StatelessWidget {
  const _MasterGroup({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.onAdd,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<_Row> rows;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Kill the default divider lines so the card reads as one clean block.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: rows.isEmpty,
          leading: CircleAvatar(
            backgroundColor: context.p.primary.withValues(alpha: 0.12),
            child: Icon(icon, color: context.p.primary, size: 20),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${rows.length} item${rows.length == 1 ? '' : 's'} · $subtitle',
            style: const TextStyle(fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('None yet.', style: TextStyle(fontSize: 13, color: context.p.textSecondary)),
                ),
              ),
            ...rows.map((r) => ListTile(
                  dense: true,
                  title: Text(r.name),
                  subtitle: Text(r.sub, style: const TextStyle(fontSize: 12)),
                  trailing: r.canDelete
                      ? IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline, color: context.p.danger),
                          onPressed: r.onDelete,
                        )
                      : Icon(Icons.lock_outline, size: 16, color: context.p.textSecondary),
                )),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add ${title.toLowerCase().replaceAll(RegExp(r's$'), '')}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
