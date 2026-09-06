import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/async_view.dart';
import '../production/production_providers.dart';
import '../pieces/piece_providers.dart';
import 'business_edit_screen.dart';
import 'master_data_screen.dart';
import 'settings_providers.dart';
import 'staff_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          const ThemeButton(),
          IconButton(onPressed: () => ref.invalidate(settingsProvider), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncView<Map<String, dynamic>>(
        value: settings,
        onRetry: () => ref.invalidate(settingsProvider),
        data: (d) {
          final business = (d['business'] as Map?)?.cast<String, dynamic>() ?? {};
          final staff = (d['staff'] as List?) ?? [];
          final stores = ((d['stores'] as List?) ?? []).cast<dynamic>();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ---- Appearance ----
              _SectionHeader('Appearance'),
              const _ThemePicker(),
              const SizedBox(height: 20),

              // ---- Business profile ----
              _SectionHeader('Business profile'),
              Card(
                child: ListTile(
                  title: Text('${business['legalName'] ?? 'Set business details'}'),
                  subtitle: Text(
                    'GSTIN: ${business['gstin']?.toString().isNotEmpty == true ? business['gstin'] : '— not set —'}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => BusinessEditScreen(business: business)),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Staff ----
              _SectionHeader('Staff & PINs', onAdd: () async {
                final res = await showStaffDialog(context, stores: stores);
                if (res != null) {
                  // ignore: use_build_context_synchronously — _guard checks context.mounted itself
                  await _guard(context, ref, () => _repo(ref).addStaff(
                        name: res.name, pin: res.pin ?? '', storeId: res.storeId, role: res.role));
                }
              }),
              ...staff.map((s) {
                final m = (s as Map);
                return Card(
                  child: ListTile(
                    title: Text('${m['name']}'),
                    subtitle: Text('${m['role']}${m['storeName'] != null ? ' · ${m['storeName']}' : ''} · PIN ${m['pin']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          final res = await showStaffDialog(context, stores: stores, existing: m.cast<String, dynamic>());
                          if (res != null) {
                            // ignore: use_build_context_synchronously — _guard checks context.mounted itself
                            await _guard(context, ref, () => _repo(ref).updateStaff(m['id'] as String,
                                name: res.name, storeId: res.storeId, role: res.role, pin: res.pin));
                          }
                        } else if (v == 'delete') {
                          await _guard(context, ref, () => _repo(ref).deleteStaff(m['id'] as String));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),

              // ---- Master data (locations + attribute lists) ----
              _SectionHeader('Master data'),
              Card(
                child: ListTile(
                  leading: Icon(Icons.dataset_outlined, color: context.p.primary),
                  title: const Text('Locations, Fabrics, Techniques…'),
                  subtitle: const Text(
                    'Stores/warehouses & the lists designs pick from',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MasterDataScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Serialized stock ----
              const _SerializeStockTile(),
              const SizedBox(height: 20),

              // ---- Production config ----
              const _VendorsSection(),
              const SizedBox(height: 20),
              const _StagesSection(),
            ],
          );
        },
      ),
    );
  }
}

/// Vendors (external job-work processors) — add / rename / delete.
class _VendorsSection extends ConsumerWidget {
  const _VendorsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(prodVendorsProvider);
    final repo = ref.read(productionRepositoryProvider);
    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(prodVendorsProvider);
        if (context.mounted) showOk(context, 'Saved.');
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Column(
      children: [
        _SectionHeader('Vendors', onAdd: () async {
          final res = await _vendorDialog(context);
          if (res != null) await guard(() => repo.saveVendor(name: res.name, phone: res.phone, address: res.address));
        }),
        ...vendors.maybeWhen(
          data: (list) => [
            for (final v in list)
              _NamedRow(
                name: '${(v as Map)['name']}',
                sub: '${v['phone'] ?? 'no phone'} · holding ${v['holding']} pcs',
                onDelete: (v['holding'] as num?) == 0
                    ? () => guard(() => repo.deleteVendor(v['id'] as String))
                    : null,
                onEdit: () async {
                  final res = await _vendorDialog(context, existing: v.cast<String, dynamic>());
                  if (res != null) {
                    await guard(() => repo.saveVendor(
                        id: v['id'] as String, name: res.name, phone: res.phone, address: res.address));
                  }
                },
              ),
          ],
          orElse: () => [const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())],
        ),
      ],
    );
  }

  Future<({String name, String phone, String address})?> _vendorDialog(
    BuildContext context, {
    Map<String, dynamic>? existing,
  }) {
    final name = TextEditingController(text: existing?['name'] as String? ?? '');
    final phone = TextEditingController(text: existing?['phone'] as String? ?? '');
    final address = TextEditingController(text: existing?['address'] as String? ?? '');
    return showDialog<({String name, String phone, String address})>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'New vendor' : 'Edit vendor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
            const SizedBox(height: 10),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (name: name.text.trim(), phone: phone.text.trim(), address: address.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Job stages — the ordered processing pipeline (Prep, Screen Print, …).
class _StagesSection extends ConsumerWidget {
  const _StagesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = ref.watch(prodStagesProvider);
    final repo = ref.read(productionRepositoryProvider);
    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
        ref.invalidate(prodStagesProvider);
        if (context.mounted) showOk(context, 'Saved.');
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Column(
      children: [
        _SectionHeader('Job stages', onAdd: () async {
          final res = await _stageDialog(context);
          if (res != null) await guard(() => repo.saveStage(name: res.name, sequence: res.sequence));
        }),
        ...stages.maybeWhen(
          data: (list) => [
            for (final s in list)
              _NamedRow(
                name: '${(s as Map)['sequence']}. ${s['name']}',
                sub: 'Processing stage',
                onDelete: () => guard(() => repo.deleteStage(s['id'] as String)),
                onEdit: () async {
                  final res = await _stageDialog(context, existing: s.cast<String, dynamic>());
                  if (res != null) {
                    await guard(() => repo.saveStage(id: s['id'] as String, name: res.name, sequence: res.sequence));
                  }
                },
              ),
          ],
          orElse: () => [const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())],
        ),
      ],
    );
  }

  Future<({String name, int sequence})?> _stageDialog(BuildContext context, {Map<String, dynamic>? existing}) {
    final name = TextEditingController(text: existing?['name'] as String? ?? '');
    final seq = TextEditingController(text: '${existing?['sequence'] ?? ''}');
    return showDialog<({String name, int sequence})>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'New stage' : 'Edit stage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Stage name')),
            const SizedBox(height: 10),
            TextField(
              controller: seq,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Order (1, 2, 3…)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (name: name.text.trim(), sequence: int.tryParse(seq.text.trim()) ?? 0)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Swatch-tile theme picker, LEAP-style: tap a card to switch the whole app's
/// look instantly. The choice persists across launches.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeControllerProvider);
    return Column(
      children: [
        for (final t in SlkThemes.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ThemeTile(
              theme: t,
              selected: t.id == current.id,
              onTap: () => ref.read(themeControllerProvider.notifier).select(t),
            ),
          ),
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.theme, required this.selected, required this.onTap});
  final SlkTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? context.p.primary : context.p.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Swatch preview
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.p.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(child: Container(color: theme.palette.appBar)),
                    Row(
                      children: [
                        Expanded(child: Container(height: 14, color: theme.palette.primary)),
                        Expanded(child: Container(height: 14, color: theme.palette.accent)),
                        Expanded(child: Container(height: 14, color: theme.palette.surface1)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(theme.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(theme.description, style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: context.p.primary)
              else
                Icon(Icons.circle_outlined, color: context.p.border),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.onAdd});
  final String title;
  final VoidCallback? onAdd;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          if (onAdd != null)
            TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: const Text('Add')),
        ],
      ),
    );
  }
}

class _NamedRow extends StatelessWidget {
  const _NamedRow({required this.name, required this.sub, this.onDelete, this.onEdit});
  final String name;
  final String sub;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        title: Text(name),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(onPressed: onEdit, icon: Icon(Icons.edit_outlined, size: 20, color: context.p.textSecondary)),
            if (onDelete != null)
              IconButton(onPressed: onDelete, icon: Icon(Icons.delete_outline, color: context.p.danger))
            else if (onEdit == null)
              Icon(Icons.lock_outline, size: 16, color: context.p.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// One-time: serialize existing quantity stock into individually-tagged pieces.
class _SerializeStockTile extends ConsumerStatefulWidget {
  const _SerializeStockTile();
  @override
  ConsumerState<_SerializeStockTile> createState() => _SerializeStockTileState();
}

class _SerializeStockTileState extends ConsumerState<_SerializeStockTile> {
  bool _busy = false;

  Future<void> _run() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Serialize existing stock?'),
        content: const Text(
            'Creates one tagged piece for every unit currently on hand that isn\'t tagged yet. '
            'On-hand quantities do not change. Safe to run more than once.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Serialize')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final created = await ref.read(pieceRepositoryProvider).backfill();
      if (mounted) showOk(context, 'Serialized $created existing pieces.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.qr_code_2, color: context.p.primary),
        title: const Text('Serialize existing stock'),
        subtitle: const Text('Tag every on-hand unit (one-time)', style: TextStyle(fontSize: 12)),
        trailing: _busy
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _busy ? null : _run,
      ),
    );
  }
}
