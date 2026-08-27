import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
import 'category_providers.dart';

/// One level of the category tree. `parentId == null` is the root (which, when
/// [kCategoryFocus] is set, shows just that top category — e.g. Sarees). Tapping
/// a node that has children drills deeper; tapping a leaf opens its edit form.
class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key, this.parentId});

  final String? parentId;

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CategoryRow c) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return c.name.toLowerCase().contains(q) || (c.code ?? '').toLowerCase().contains(q);
  }

  List<CategoryRow> _childrenOf(List<CategoryRow> all, String? pid) {
    var kids = all.where((c) => c.parentId == pid).toList();
    // At the root, honour the focus scope (show only e.g. Sarees).
    if (pid == null && kCategoryFocus != null) {
      kids = kids.where((c) => c.name == kCategoryFocus).toList();
    }
    kids.sort((a, b) => a.name.compareTo(b.name));
    return kids;
  }

  bool _hasChildren(List<CategoryRow> all, String id) => all.any((c) => c.parentId == id);

  // Direct children count and leaf-descendant count for a folder node.
  ({int direct, int leaves, bool childrenAreFolders}) _counts(List<CategoryRow> all, String id) {
    final direct = all.where((c) => c.parentId == id).toList();
    final childrenAreFolders = direct.any((c) => _hasChildren(all, c.id));
    int leaves = 0;
    final stack = <String>[id];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final kids = all.where((c) => c.parentId == cur).toList();
      if (kids.isEmpty) {
        if (cur != id) leaves++;
      } else {
        for (final k in kids) {
          stack.add(k.id);
        }
      }
    }
    return (direct: direct.length, leaves: leaves, childrenAreFolders: childrenAreFolders);
  }

  String _titleFor(List<CategoryRow>? all) {
    if (widget.parentId == null) return 'Catalogue';
    if (all != null) {
      for (final c in all) {
        if (c.id == widget.parentId) return c.name;
      }
    }
    return 'Catalogue';
  }

  // Depth of a node = number of ancestors above it (top-level = 0).
  int _depthOf(List<CategoryRow> all, String? id) {
    if (id == null) return -1;
    final byId = {for (final c in all) c.id: c};
    var d = 0;
    var cur = byId[id]?.parentId;
    final seen = <String>{};
    while (cur != null && byId.containsKey(cur) && !seen.contains(cur)) {
      seen.add(cur);
      d++;
      cur = byId[cur]!.parentId;
    }
    return d;
  }

  // What the items created/listed at THIS level are called.
  String _childWord(List<CategoryRow> all) {
    switch (_depthOf(all, widget.parentId) + 1) {
      case 0:
        return 'group';
      case 1:
        return 'sub-group';
      default:
        return 'design';
    }
  }

  // Lightweight create for a group / sub-group: just a name (+ optional code).
  Future<void> _quickAdd(BuildContext context, String word) async {
    final nameCtl = TextEditingController();
    final codeCtl = TextEditingController();
    final cap = '${word[0].toUpperCase()}${word.substring(1)}';
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.p.surface2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 14, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: context.p.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('New $word', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: '$cap name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Code (optional)',
                helperText: 'Leave blank to inherit the parent\'s code',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty) return;
                try {
                  await ref.read(categoryRepositoryProvider).create({
                    'name': name,
                    'parentId': widget.parentId,
                    'code': codeCtl.text.trim(),
                    'status': 'active',
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: context.p.primary,
                foregroundColor: Colors.white,
              ),
              child: Text('Create $word'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$cap created')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(async.valueOrNull)),
        actions: [
          const ThemeButton(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(categoriesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final all = async.valueOrNull ?? const <CategoryRow>[];
          final childDepth = _depthOf(all, widget.parentId) + 1;
          if (childDepth <= 1) {
            // Groups & sub-groups are just folders — quick name popup.
            await _quickAdd(context, _childWord(all));
          } else {
            // A design needs the full form.
            await context.push('/category/new', extra: {'parentId': widget.parentId});
          }
          ref.invalidate(categoriesProvider);
        },
        backgroundColor: context.p.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('New ${_childWord(async.valueOrNull ?? const [])}'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$e', style: TextStyle(color: context.p.danger)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(categoriesProvider),
              child: const Text('Try again'),
            ),
          ]),
        ),
        data: (all) => _body(context, all),
      ),
    );
  }

  Widget _body(BuildContext context, List<CategoryRow> all) {
    final kids = _childrenOf(all, widget.parentId).where(_matches).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${kids.length} ${kids.length == 1 ? 'item' : 'items'}',
                style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
          ),
        ),
        Expanded(
          child: kids.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty ? 'Nothing here yet. Tap ＋ to add.' : 'No matches.',
                    style: TextStyle(color: context.p.textSecondary),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(categoriesProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: kids.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = kids[i];
                      // Groups (0) & sub-groups (1) are folders — always enterable,
                      // even when empty. Designs (2+) open their detail form.
                      final isFolder = _depthOf(all, c.id) < 2;
                      if (isFolder) {
                        final n = _counts(all, c.id);
                        final subtitle = (n.direct == 0 && n.leaves == 0)
                            ? 'Empty — tap to open'
                            : n.childrenAreFolders
                                ? '${n.direct} sub-groups · ${n.leaves} designs'
                                : '${n.leaves} designs';
                        return _FolderCard(
                          row: c,
                          subtitle: subtitle,
                          onTap: () async {
                            await context.push('/category/browse/${c.id}');
                            ref.invalidate(categoriesProvider);
                          },
                          onEdit: () async {
                            await context.push('/category/${c.id}/edit');
                            ref.invalidate(categoriesProvider);
                          },
                        );
                      }
                      return _CategoryCard(
                        row: c,
                        onTap: () async {
                          await context.push('/category/${c.id}/edit');
                          ref.invalidate(categoriesProvider);
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// A drill-down node (has children) — folder row with counts and a chevron.
class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.row, required this.subtitle, required this.onTap, this.onEdit});
  final CategoryRow row;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: context.p.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.folder_outlined, color: context.p.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined, size: 20, color: context.p.textSecondary),
                ),
              Icon(Icons.chevron_right, color: context.p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.row, required this.onTap});
  final CategoryRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final attrs = [row.technique, row.fabric, row.borderStyle, row.dyeType]
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toList();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(row.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  _StatusChip(status: row.status),
                ],
              ),
              if ((row.code ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                _CodePill(text: row.code!),
              ],
              if (attrs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(attrs.join('  ·  '),
                    style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
              ],
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Pills wrap to a second line if they don't fit, so nothing
                  // is ever pushed off the card edge.
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _Pill(
                          icon: Icons.inventory_2_outlined,
                          text: '${row.pieceCount} piece${row.pieceCount == 1 ? '' : 's'}'
                              '${row.colourCount > 0 ? ' · ${row.colourCount} colour${row.colourCount == 1 ? '' : 's'}' : ''}',
                        ),
                        if (row.missingPhotos)
                          _Pill(
                            icon: Icons.warning_amber_rounded,
                            text: row.coloursWithPhotos == 0
                                ? 'No photos'
                                : 'Photos ${row.coloursWithPhotos}/${row.colourCount}',
                            warn: true,
                          ),
                        if ((row.hsnCode ?? '').isNotEmpty)
                          _Pill(icon: Icons.receipt_long_outlined, text: 'HSN ${row.hsnCode}'),
                        if ((row.gstRate ?? '').isNotEmpty)
                          _Pill(icon: Icons.percent, text: 'GST ${_gst(row.gstRate!)}%'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Photos menu (pinned right): actual per-colour product photos,
                  // or the photo-guide sample checklist.
                  PopupMenuButton<String>(
                    icon: Icon(Icons.photo_camera_outlined, size: 20, color: context.p.primary),
                    tooltip: 'Photos',
                    onSelected: (v) {
                      if (v == 'product') {
                        context.push('/category/${row.id}/product-photos', extra: {'name': row.name});
                      } else {
                        context.push('/category/${row.id}/photos', extra: {'name': row.name});
                      }
                    },
                    itemBuilder: (menuCtx) => [
                      PopupMenuItem(
                        value: 'product',
                        child: Row(children: [
                          Icon(Icons.checkroom_outlined, size: 20, color: menuCtx.p.primary),
                          const SizedBox(width: 12),
                          const Text('Product photos'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'guide',
                        child: Row(children: [
                          Icon(Icons.photo_library_outlined, size: 20, color: menuCtx.p.textSecondary),
                          const SizedBox(width: 12),
                          const Text('Photo guide (samples)'),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _gst(String v) {
    final d = double.tryParse(v);
    if (d == null) return v;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final active = status == 'active';
    final color = active ? context.p.success : context.p.textSecondary;
    final label = status.isEmpty ? 'Active' : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _CodePill extends StatelessWidget {
  const _CodePill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.p.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: context.p.primaryDark)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.warn = false});
  final IconData icon;
  final String text;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    final color = warn ? const Color(0xFFB45309) : context.p.textSecondary; // amber-700
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(fontSize: 12, color: color, fontWeight: warn ? FontWeight.w600 : FontWeight.normal)),
      ],
    );
  }
}
