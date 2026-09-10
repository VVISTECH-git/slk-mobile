import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'core_auth.dart';

/// Everything still waiting to be photographed.
///
/// autoDispose for the same reason the catalogue is: somebody photographs a
/// saree, comes back, and the row must be gone. A provider that cached its
/// first answer would keep showing work already done, which on a list whose
/// whole purpose is to reach empty is the one failure that matters.
final coreShotListProvider =
    FutureProvider.autoDispose<List<CoreShotListRow>>((ref) async {
  final data = await ref.read(coreApiProvider).get('/photographs');

  return [
    for (final row in (data as List))
      CoreShotListRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// The shot list.
///
/// The one screen here with no counterpart in the portal. At a desk the two
/// acts happen in one place — you open a record and upload into it — so the
/// question never comes up. On a floor they are days and different people
/// apart, and somebody picking up a camera needs the list the desk does not:
/// which sarees to fetch, and what to shoot of each.
///
/// Tapping a row lands on that record's photographs, which is where the
/// camera actually opens. This screen only says where to point it.
class PhotographsScreen extends ConsumerStatefulWidget {
  const PhotographsScreen({super.key});

  @override
  ConsumerState<PhotographsScreen> createState() => _PhotographsScreenState();
}

class _PhotographsScreenState extends ConsumerState<PhotographsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shots = ref.watch(coreShotListProvider);
    final p = context.p;

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(title: const Text('Photographs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Consignment, name, colour, slot…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
          Expanded(
            child: AsyncView<List<CoreShotListRow>>(
              value: shots,
              onRetry: () => ref.invalidate(coreShotListProvider),
              // Emptiness handled inside the builder, not by AsyncView's own
              // empty state, so the message sits inside the RefreshIndicator
              // and can be pulled. Same as the catalogue.
              data: (rows) {
                final shown = _query.isEmpty
                    ? rows
                    : [for (final r in rows) if (r.haystack.contains(_query)) r];

                final pending = rows.fold<int>(
                  0,
                  (sum, r) => sum + r.pending.length,
                );

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(coreShotListProvider),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: shown.isEmpty ? 1 : shown.length + 1,
                    itemBuilder: (context, i) {
                      if (shown.isEmpty) {
                        return _Empty(
                          // Nothing left to shoot is a finished list, not an
                          // error, and it should read like one.
                          done: rows.isEmpty,
                          query: _search.text.trim(),
                        );
                      }

                      if (i == shown.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            shown.length == rows.length
                                ? '$pending photograph${pending == 1 ? '' : 's'} '
                                    'across ${rows.length} '
                                    'record${rows.length == 1 ? '' : 's'}'
                                : '${shown.length} of ${rows.length} records',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: p.textMuted),
                          ),
                        );
                      }

                      return _Row(row: shown[i]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.done, required this.query});

  /// True when the list itself is empty — the work is finished. False when a
  /// search hid everything, which is a different thing to say.
  final bool done;
  final String query;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            done ? Icons.check_circle_outline : Icons.search_off,
            size: 40,
            color: done ? p.success : p.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            done
                ? 'Nothing is waiting to be photographed.'
                : 'Nothing matches “$query”.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary),
          ),
          if (done) ...[
            const SizedBox(height: 6),
            Text(
              'Pull down to check again.',
              style: TextStyle(fontSize: 12, color: p.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.row});

  final CoreShotListRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.p;
    final swatch = row.swatch;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // The same screen the catalogue opens, and the same fallback: the
        // product code where one exists, the design code only where nothing
        // has arrived yet.
        //
        // Refetched on the way back. autoDispose alone never fires here:
        // this list keeps watching the provider underneath the pushed
        // screen, so a slot photographed there stayed listed until somebody
        // pulled to refresh — on the one screen whose job is reaching empty.
        onTap: () async {
          await context.push(
            '/core/records/${row.id}/photos'
            '?code=${Uri.encodeComponent(row.productCode ?? row.designCode)}',
          );
          if (context.mounted) ref.invalidate(coreShotListProvider);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: swatch ?? p.surface3,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.border),
                    ),
                    child: swatch == null
                        ? Icon(Icons.help_outline, size: 18, color: p.textMuted)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // The consignment leads, as it does everywhere else.
                        Row(
                          children: [
                            if (row.productCode != null) ...[
                              Text(
                                row.productCode!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: p.primary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (row.colour != null)
                                Text('  ·  ',
                                    style: TextStyle(
                                        fontSize: 12, color: p.textMuted)),
                            ] else
                              Text(
                                'No consignment yet  ·  ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: p.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                row.colour ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: p.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.photo_camera_outlined, color: p.textMuted),
                ],
              ),
              const SizedBox(height: 10),
              /*
                The slots, named.

                A count — "3 photographs" — would fit on one line and be
                useless: somebody carrying a saree to a light needs to know it
                is the pallu and the border, because that decides how they
                hold it. Naming them is the difference between a worklist and
                a tally.
              */
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final slot in row.pending)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.surface3,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.border),
                      ),
                      child: Text(
                        slot,
                        style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
