import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
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

class _RecordsListScreenState extends ConsumerState<RecordsListScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _resolving = false;

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
        context.push('/core/records/${match.id}');
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

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(
        title: const Text('Products List'),
        actions: [
          _resolving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Scan an SLK label',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scan,
                ),
          IconButton(
            tooltip: 'New record',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/core/records/new'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Code, name, colour, consignment…',
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
                final shown = _query.isEmpty
                    ? rows
                    : [for (final r in rows) if (r.haystack.contains(_query)) r];

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(coreRecordsProvider),
                  child: ListView.builder(
                    // Pullable even with nothing in it, which is exactly when
                    // somebody most wants to try again.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: shown.isEmpty ? 1 : shown.length + 1,
                    itemBuilder: (context, i) {
                      if (shown.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Column(
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 40, color: p.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                rows.isEmpty
                                    ? 'The catalogue is empty.'
                                    : 'Nothing matches “${_search.text.trim()}”.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: p.textSecondary),
                              ),
                              if (rows.isEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Pull down to check again.',
                                  style: TextStyle(
                                      fontSize: 12, color: p.textMuted),
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      if (i == shown.length) {
                        return Padding(
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
                        );
                      }

                      return _Row(record: shown[i]);
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

class _Row extends StatelessWidget {
  const _Row({required this.record});

  final CoreRecordRow record;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final swatch = record.swatch;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // The record, whole — every field the create form asks, seeded and
        // open to correction. Photographs are one tap from there, not
        // the destination in themselves.
        onTap: () => context.push('/core/records/${record.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // The colour, as a colour. On a hand-painted saree it is the
              // first thing anyone says about the piece.
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
                      record.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    /*
                      The product code leads, not the design code.

                      The design code — SAR-GEN-COT-0001 — describes what
                      somebody entered and repeats; the schema calls it
                      internal, and two people filing the same saree will
                      write different ones. The product code is the
                      consignment: what arrived, on a day, against an invoice,
                      and what the floor reads off the paperwork in its hands.
                    */
                    Row(
                      children: [
                        if (record.productCode != null) ...[
                          Text(
                            record.productCode!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: p.primary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (record.colour != null)
                            Text('  ·  ',
                                style: TextStyle(
                                    fontSize: 12, color: p.textMuted)),
                        ] else
                          Text(
                            // No consignment has arrived against this record
                            // yet, so there is no product code to show. Said
                            // rather than left blank.
                            'No consignment yet  ·  ',
                            style: TextStyle(
                                fontSize: 12,
                                color: p.textMuted,
                                fontStyle: FontStyle.italic),
                          ),
                        Flexible(
                          child: Text(
                            record.colour ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: p.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    record.price,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // "6 Piece" reads oddly; "6 in stock" is what is meant, and
                    // the unit only earns its place where it is not the Piece.
                    record.uom == null || record.uom == 'Piece'
                        ? '${record.quantity} in stock'
                        : '${record.quantity} ${record.uom}',
                    style: TextStyle(
                      fontSize: 12,
                      color: record.quantity > 0 ? p.success : p.textMuted,
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
