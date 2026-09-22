import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../pos/barcode_scan_screen.dart';
import 'core_auth.dart';

/// The whole catalogue, fetched once per visit.
///
/// Filtered on the phone rather than by asking the server again. The API sends
/// it whole (about 150 rows at SLK's size), so typing is instant and keeps
/// working with no signal once the list has arrived — which on a warehouse
/// floor is worth more than pagination. When the catalogue outgrows that, the
/// filter belongs in the SQL, not in a longer list.
///
/// autoDispose, and that matters more than it looks.
///
/// A plain FutureProvider caches its first answer for the life of the app. The
/// catalogue was empty when this screen first opened, a record was filed a
/// minute later, and re-entering the screen kept showing "The catalogue is
/// empty" — the fetch never ran again. On a floor where somebody files a
/// record and then goes looking for it, that is the whole feature broken.
///
/// Disposing when the screen is left means the next visit fetches afresh.
final coreRecordsProvider =
    FutureProvider.autoDispose<List<CoreRecordRow>>((ref) async {
  final data = await ref.read(coreApiProvider).get('/records');

  return [
    for (final row in (data as List))
      CoreRecordRow.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

/// Which row a scanned piece belongs to, if the catalogue's own idea of
/// "the newest consignment" happens to be the one on the label.
///
/// A row only remembers its newest product code — see [CoreRecordRow] —
/// so a piece from an older consignment of the same colourway won't match
/// here even though it is, in fact, that row's. That's a known, accepted
/// gap: it fails safe into [fallbackSearchFor] rather than guessing.
CoreRecordRow? matchingRowForPiece(List<CoreRecordRow> rows, CorePiece piece) {
  for (final r in rows) {
    if (r.productCode != null && r.productCode == piece.productCode) {
      return r;
    }
  }
  return null;
}

/// What to search for when a scan resolved a piece but not to a specific
/// row — the product code if the piece has one (300001 and up, on every
/// piece that arrived in a consignment), the design code otherwise.
String fallbackSearchFor(CorePiece piece) => piece.productCode ?? piece.designCode;

/// Whether what somebody typed is a number off a label — an item code
/// (500066) or a product code (300032), six digits either way — rather than
/// a word or a design code. Those never appear in [CoreRecordRow.haystack]
/// (a row carries only its newest consignment's code, and no item codes at
/// all), so typing one used to read "Nothing matches" while scanning the
/// same label worked. This is what lets the typed path resolve the same way.
bool looksLikeLabelCode(String query) => RegExp(r'^\d{6}$').hasMatch(query.trim());

/// The catalogue, on a phone.
///
/// One row per colourway — the sellable line — which is the same grain the web
/// table uses and the same grain a record has. Two colours of one saree are two
/// rows here, because they are two things to price and two things to count.
///
/// A row leads with the **product code**, not the design code. The design code
/// repeats and is internal; the product code is the consignment, and it is what
/// is written on the paperwork somebody is holding.
class RecordsListScreen extends ConsumerStatefulWidget {
  const RecordsListScreen({super.key});

  @override
  ConsumerState<RecordsListScreen> createState() => _RecordsListScreenState();
}

/// The chip row under the search — All, or one slice of the production
/// pipeline, decided on the phone from the counts each row already carries.
enum _PipelineFilter {
  all('All'),
  inPipeline('In pipeline'),
  ready('Ready for shelf'),
  shelved('On shelf');

  const _PipelineFilter(this.label);
  final String label;

  bool keeps(CoreRecordRow r) => switch (this) {
        all => true,
        // Thaans behind it, and not every one of them on the shelf yet.
        inPipeline => r.thaanCount > 0 && r.shelvedCount < r.thaanCount,
        ready => r.finishedCount > 0,
        shelved => r.shelvedCount > 0,
      };

  String get emptyMessage => switch (this) {
        all => 'The catalogue is empty.',
        inPipeline => 'Nothing in the pipeline — no record has Thaans still out.',
        ready => 'Nothing back from Ironing yet.',
        shelved => 'Nothing put on the shelf from the pipeline yet.',
      };
}

class _RecordsListScreenState extends ConsumerState<RecordsListScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _resolving = false;
  _PipelineFilter _filter = _PipelineFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A scanned label names a piece, not a row — the item code on it (500001
  /// and up) appears nowhere in [CoreRecordRow.haystack], only the product
  /// code does. So a scan resolves through the same piece lookup Stock
  /// Records uses, then either jumps straight to the row that consignment
  /// belongs to, or — when the row list doesn't have that exact consignment
  /// as its newest one — falls back to searching by the code the scan
  /// actually found, rather than silently landing on "nothing matches".
  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScanScreen(title: 'Scan an SLK label'),
      ),
    );
    if (code == null || !mounted) return;

    await _resolveCode(code);
  }

  /// A six-digit code typed into the search box, submitted with the
  /// keyboard's search key. The phone-side filter cannot answer it (see
  /// [looksLikeLabelCode]), so it goes the way a scan goes — but only when
  /// the filter really came up empty, so a product code that *is* a row's
  /// newest consignment still just filters like any other search.
  void _lookUpTyped() {
    final typed = _search.text.trim();
    if (!looksLikeLabelCode(typed)) return;

    final rows = ref.read(coreRecordsProvider).valueOrNull ?? const [];
    if (rows.any((r) => r.haystack.contains(typed.toLowerCase()))) return;

    _resolveCode(typed);
  }

  Future<void> _resolveCode(String code) async {
    setState(() => _resolving = true);
    try {
      final data = await ref.read(coreApiProvider).get('/pieces/$code');
      final pieces = [
        for (final row in (data as List))
          CorePiece.fromJson((row as Map).cast<String, dynamic>()),
      ];

      if (pieces.isEmpty) {
        if (mounted) showOk(context, 'Nothing on file for $code.');
        return;
      }

      final piece = pieces.first;
      final rows = await ref.read(coreRecordsProvider.future);
      final match = matchingRowForPiece(rows, piece);

      if (!mounted) return;

      if (match != null) {
        await context.push('/core/records/${match.id}');
        if (mounted) ref.invalidate(coreRecordsProvider);
      } else {
        final fallback = fallbackSearchFor(piece);
        setState(() {
          _search.text = fallback;
          _query = fallback.toLowerCase();
        });
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(coreRecordsProvider);
    final p = context.p;

    return AppPage(
      title: 'Products List',
      padded: false,
      actions: [
        if (_resolving)
          // A scan or a typed code is being looked up — said in the place
          // the scan button was, small enough to live in an app bar.
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.onAppBar),
            ),
          )
        else
          AppIconButton(
            icon: Icons.qr_code_scanner,
            tooltip: 'Scan an SLK label',
            color: p.onAppBar,
            onPressed: _scan,
          ),
        AppIconButton(
          icon: Icons.add,
          tooltip: 'New record',
          color: p.onAppBar,
          // Refetched on the way back — see _Row for why autoDispose alone
          // never does this here. Filing a record and then not finding it
          // in the list you filed it from was the whole bug.
          onPressed: () async {
            await context.push('/core/records/new');
            if (mounted) ref.invalidate(coreRecordsProvider);
          },
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchField(
              hint: 'Code, name, colour, consignment…',
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              onSubmitted: (_) => _lookUpTyped(),
            ),
          ),
          // Where a record's Thaans are — the same counts the row's
          // subtitle reads, as a filter. Client-side: the list is already
          // whole, and a chip that asked the server again would lose the
          // typed search with it.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _PipelineFilter.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<CoreRecordRow>>(
              value: records,
              onRetry: () => ref.invalidate(coreRecordsProvider),
              /*
                Emptiness is handled here, not by AsyncView's own empty state.

                That one replaces the whole builder, which put the message
                outside the RefreshIndicator — so a list that came back empty
                could not be pulled to refresh, and somebody who had just filed
                a record had no way to ask again. The empty case is a list with
                nothing in it, and it scrolls like one.
              */
              data: (rows) {
                final sliced = [for (final r in rows) if (_filter.keeps(r)) r];
                final shown = _query.isEmpty
                    ? sliced
                    : [for (final r in sliced) if (r.haystack.contains(_query)) r];
                final typed = _search.text.trim();

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(coreRecordsProvider),
                  child: ListView(
                    // Pullable even with nothing in it, which is exactly when
                    // somebody most wants to try again.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: sliced.isEmpty
                              ? EmptyState(
                                  title: _filter.emptyMessage,
                                  message: 'Pull down to check again.',
                                )
                              : EmptyState(
                                  icon: Icons.search_off,
                                  title: 'Nothing matches “$typed”.',
                                  // A label's number, not a word — the filter
                                  // was never going to find it. Offer the
                                  // lookup a scan would have done.
                                  actionLabel: looksLikeLabelCode(typed)
                                      ? 'Look up $typed as a label code'
                                      : null,
                                  onAction: _resolving
                                      ? null
                                      : () => _resolveCode(typed),
                                ),
                        )
                      else ...[
                        AppListGroup(
                          children: [for (final r in shown) _Row(record: r)],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            // "1 records" is the kind of thing that makes a
                            // screen look unfinished for the sake of one 's'.
                            shown.length == rows.length
                                ? '${rows.length} record${rows.length == 1 ? '' : 's'}'
                                : '${shown.length} of ${rows.length} records',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: p.textMuted),
                          ),
                        ),
                      ],
                    ],
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

class _Row extends ConsumerWidget {
  const _Row({required this.record});

  final CoreRecordRow record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.p;
    final swatch = record.swatch;
    final syncIcon = _syncIcon(record.syncStatus);

    /*
      The product code leads, not the design code.

      The design code — SAR-GEN-COT-0001 — describes what somebody entered
      and repeats; the schema calls it internal, and two people filing the
      same saree will write different ones. The product code is the
      consignment: what arrived, on a day, against an invoice, and what the
      floor reads off the paperwork in its hands. No consignment yet is said
      rather than left blank.
    */
    final subtitle = [
      record.productCode ?? 'No consignment yet',
      if (record.colour != null) record.colour!,
    ].join('  ·  ');

    // "6 Thaans · Nellateeta · needs craft" — only for a record that came
    // through the pipeline; a record filed at a desk has no Thaans to speak of.
    final pipelineLine = record.pipeline.line;

    return AppListRow(
      title: record.name,
      subtitle: pipelineLine == null ? subtitle : '$subtitle\n$pipelineLine',
      // The colour, as a colour. On a hand-painted saree it is the first
      // thing anyone says about the piece.
      leading: RowThumb(
        color: swatch,
        icon: swatch == null ? Icons.help_outline : null,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nothing drawn for "none" — a record with no consignment
              // yet, or one nobody has tried to publish, has nothing here
              // worth a person's attention.
              if (syncIcon != null) ...[
                Icon(syncIcon, size: 13, color: _syncColor(record.syncStatus, p)),
                const SizedBox(width: 4),
              ],
              Text(
                record.price,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: p.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            // "6 Piece" reads oddly; "6 in stock" is what is meant, and
            // the unit only earns its place where it is not the Piece.
            // Sold trails on only once there is one to report — a
            // record that has never sold says nothing extra.
            [
              record.uom == null || record.uom == 'Piece'
                  ? '${record.quantity} in stock'
                  : '${record.quantity} ${record.uom}',
              if (record.sold > 0) '${record.sold} sold',
            ].join(' · '),
            style: TextStyle(
              fontSize: 12,
              color: record.quantity > 0 ? p.success : p.textMuted,
            ),
          ),
        ],
      ),
      // The record, whole — every field the create form asks, seeded and
      // open to correction. Photographs are one tap from there, not
      // the destination in themselves.
      //
      // Refetched on the way back. The provider is autoDispose, but that
      // only fires once nothing is listening — and this list goes on
      // listening underneath the pushed screen, so a price or count saved
      // there came back to a row still showing the old one. Pull-to-refresh
      // was the only way out, and nobody knew to.
      onTap: () async {
        await context.push('/core/records/${record.id}');
        if (context.mounted) ref.invalidate(coreRecordsProvider);
      },
    );
  }

  /// Null for [CoreSyncStatus.none] — nothing to draw, not a placeholder.
  IconData? _syncIcon(CoreSyncStatus status) => switch (status) {
        CoreSyncStatus.none => null,
        CoreSyncStatus.pending => Icons.cloud_upload_outlined,
        CoreSyncStatus.synced => Icons.cloud_done_outlined,
        CoreSyncStatus.error => Icons.cloud_off_outlined,
      };

  // No amber in the palette yet — primary stands in for "in progress" the
  // same way it already does for the product code text above.
  Color _syncColor(CoreSyncStatus status, AppPalette p) => switch (status) {
        CoreSyncStatus.error => p.danger,
        CoreSyncStatus.pending => p.primary,
        _ => p.success,
      };
}
