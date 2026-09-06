import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../pos/barcode_scan_screen.dart';
import 'core_auth.dart';

/// What did I just scan?
///
/// The floor's question, asked with a saree in one hand and a phone in the
/// other. Product Management answers "what do we sell and how much is there";
/// this answers "which one is this, is it still ours, and where does the
/// ledger think it is" — a different question, asked in a different posture,
/// so it gets its own screen rather than a tab on the catalogue.
///
/// Either code on the label works. The item code — 500001 and up — is one
/// saree; the product code — 300001 and up — is the consignment it arrived
/// in, and scanning that returns the whole delivery, which is what makes
/// counting a box possible. Refusing a code because it named a delivery
/// rather than a piece would be a strange thing to explain to somebody
/// holding it.
class StockRecordsScreen extends ConsumerStatefulWidget {
  const StockRecordsScreen({super.key});

  @override
  ConsumerState<StockRecordsScreen> createState() => _StockRecordsScreenState();
}

class _StockRecordsScreenState extends ConsumerState<StockRecordsScreen> {
  final _field = TextEditingController();

  /// Kept focused so a Bluetooth scanner's keystrokes land here and submit on
  /// its trailing Enter. The camera is the fallback, not the assumption — a
  /// warehouse that has a HID scanner will use it, and it is faster.
  final _focus = FocusNode();

  bool _busy = false;

  /// The last code looked up, so the answer can name what it is answering.
  String? _asked;
  List<CorePiece>? _found;
  String? _problem;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;

    setState(() {
      _busy = true;
      _asked = code;
      _found = null;
      _problem = null;
    });

    try {
      final data = await ref.read(coreApiProvider).get('/pieces/$code');

      final pieces = [
        for (final row in (data as List))
          CorePiece.fromJson((row as Map).cast<String, dynamic>()),
      ];

      if (mounted) setState(() => _found = pieces);
    } on ApiException catch (e) {
      /*
        The server's own words, shown as they are.

        "That is not an SLK label" and "No piece carries that code" are
        different answers to a scan and the difference matters — the first is
        a QR from somewhere else, the second is one of ours that nobody has
        entered. Restating them here would mean two places to keep honest.
      */
      if (mounted) setState(() => _problem = e.message);
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _field.clear();
      // Ready for the next scan without anybody tapping the field again.
      _focus.requestFocus();
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScanScreen(title: 'Scan an SLK label'),
      ),
    );

    if (code != null) await _lookup(code);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(title: const Text('Stock Records')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _field,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _lookup,
                  decoration: InputDecoration(
                    labelText: 'Item or product code',
                    hintText: '500066 or 300032',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    // iOS's numeric keypad has no return/search key, so typing
                    // a code by hand has no way to submit without this — the
                    // Bluetooth scanner's Enter keystroke reaches onSubmitted
                    // regardless of what the on-screen keyboard shows.
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      tooltip: 'Search',
                      onPressed: _busy ? null : () => _lookup(_field.text),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  label: const Text('Scan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Scan the label on a saree, or the one on the box it arrived in.',
            style: TextStyle(fontSize: 12, color: p.textMuted),
          ),
          const SizedBox(height: 20),

          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_problem != null)
            _Problem(code: _asked ?? '', message: _problem!)
          else if (_found != null) ...[
            _Summary(code: _asked ?? '', pieces: _found!),
            const SizedBox(height: 12),
            for (final piece in _found!) _PieceCard(piece: piece),
          ] else
            const _Idle(),
        ],
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle();

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.qr_code_2, size: 44, color: p.textMuted),
          const SizedBox(height: 12),
          Text(
            'Nothing scanned yet.',
            style: TextStyle(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.code, required this.message});

  final String code;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: p.danger,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // What was actually read, because a scanner that has picked up a
            // stray character produces exactly this and no other clue.
            'Read: $code',
            style: TextStyle(
              fontSize: 12.5,
              color: p.danger,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.code, required this.pieces});

  final String code;
  final List<CorePiece> pieces;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    final held = pieces.where((piece) => piece.isHeld).length;
    final consignment = pieces.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(
            consignment ? Icons.inventory_2_outlined : Icons.label_outline,
            size: 20,
            color: p.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: p.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // A consignment is counted; a single piece is not, because
                  // "1 of 1 still held" is a strange way to say "yes".
                  consignment
                      ? '${pieces.length} pieces · $held still held'
                      : 'One piece',
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({required this.piece});

  final CorePiece piece;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      piece.itemCode,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: p.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      piece.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              /*
                Held or gone, said first and said loudly.

                It is the first thing a scan should answer. The ledger decides
                it — sold, written off or sent on all make it false — and a
                saree that reads "Warehouse" when it left six weeks ago is the
                bug this screen exists to not have.
              */
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (piece.isHeld ? p.success : p.danger)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  piece.isHeld ? 'In stock' : 'Gone',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: piece.isHeld ? p.success : p.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Fact(
            label: 'Where',
            // Null once it has left us, which is not the same as unknown.
            value: piece.location ?? 'No longer with us',
            emphasise: piece.isHeld,
          ),
          _Fact(label: 'Price', value: piece.price),
          if (piece.colour != null) _Fact(label: 'Colour', value: piece.colour!),
          if (piece.productType != null)
            _Fact(label: 'Type', value: piece.productType!),
          // Consignment before design, and that ordering is the point: the
          // product code is what the paperwork says, the design code is
          // internal and repeats. Kept only because a scan is also how
          // somebody finds their way back to the record.
          if (piece.productCode != null)
            _Fact(label: 'Consignment', value: piece.productCode!),
          _Fact(label: 'Design', value: piece.designCode),
          if (piece.receivedAt != null)
            _Fact(
              label: 'Received',
              value: piece.reference == null
                  ? piece.receivedAt!
                  : '${piece.receivedAt!} · ${piece.reference!}',
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: p.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: emphasise ? p.text : p.textSecondary,
                fontWeight: emphasise ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
