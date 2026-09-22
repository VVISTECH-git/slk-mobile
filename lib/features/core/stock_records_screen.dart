import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../pieces/piece_labels_pdf.dart';
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
    if (code.isEmpty) {
      // Nothing to look up — but the keypad that was open to type it is
      // the one thing on screen, and this is the only key that closes it.
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      return;
    }

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
      // Backing out of Stock Records mid-lookup disposes both of these —
      // touching them after that throws, so the guard has to cover them too,
      // not just the setState above.
      if (mounted) {
        setState(() => _busy = false);
        _field.clear();
        // Ready for the next scan without anybody tapping the field again:
        // a Bluetooth scanner types into whichever field has focus, so focus
        // stays here. The on-screen keyboard is a different matter — it
        // covered the very pieces just looked up, on a phone whose keypad
        // can't even submit — so it is put away. A scanner never needs it.
        _focus.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
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

  /// One sheet, whether the scan resolved a single saree or a whole
  /// consignment — a box of ten arriving is exactly when a dozen labels are
  /// wanted at once, not one screen visit per piece.
  Future<void> _printLabels(List<CorePiece> pieces) => printPieceLabels(
        codes: [for (final p in pieces) p.itemCode],
        productName: pieces.first.name,
        variantLabel: pieces.first.colour,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return AppPage(
      title: 'Stock Records',
      padded: false,
      // The page frame drops focus on any tap in its body, which is right
      // for every other screen and wrong for this one: the field keeps focus
      // on purpose so a Bluetooth scanner's keystrokes land in it, and a
      // stray tap on empty space must not take that away. An inner tap
      // handler wins the gesture and does nothing, so focus stays put.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ListView(
          // The field keeps focus on purpose (a scanner types into it), so a
          // tap on it re-opens the keypad over the results with nothing to
          // close it. Scrolling the results is the natural next move — that
          // now puts the keypad away.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Item or product code',
                    hint: '500066 or 300032',
                    controller: _field,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    // Guarded like the arrow: a scanner's Enter arriving while
                    // a lookup is in flight would start a second one and show
                    // whichever answered last under the other's heading.
                    onSubmitted: (v) {
                      if (!_busy) _lookup(v);
                    },
                    // iOS's numeric keypad has no return/search key, so typing
                    // a code by hand has no way to submit without this — the
                    // Bluetooth scanner's Enter keystroke reaches onSubmitted
                    // regardless of what the on-screen keyboard shows.
                    suffix: AppIconButton(
                      icon: Icons.arrow_forward,
                      tooltip: 'Search',
                      onPressed: _busy ? null : () => _lookup(_field.text),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AppButton.primary(
                  label: 'Scan',
                  icon: Icons.qr_code_scanner,
                  expand: false,
                  onPressed: _busy ? null : _scan,
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
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: LoadingState(message: 'Looking up ${_asked ?? ''}…'),
              )
            else if (_problem != null)
              _Problem(code: _asked ?? '', message: _problem!)
            else if (_found != null) ...[
              _Summary(code: _asked ?? '', pieces: _found!),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton.ghost(
                  label: _found!.length > 1 ? 'Print labels' : 'Print label',
                  icon: Icons.qr_code_2,
                  onPressed: () => _printLabels(_found!),
                ),
              ),
              const SizedBox(height: 2),
              for (final piece in _found!) _PieceCard(piece: piece),
            ] else
              const _Idle(),
          ],
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 32),
      child: EmptyState(
        icon: Icons.qr_code_2,
        title: 'Nothing scanned yet.',
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
    // What was actually read goes under the server's answer, because a
    // scanner that has picked up a stray character produces exactly this and
    // no other clue.
    return InlineNotice(
      '$message\nRead: $code',
      icon: Icons.error_outline,
      warning: true,
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

    return AppCard(
      emphasis: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The same QR the printed label carries — the bare item code,
                // which is what a scan of either resolves. On screen so a
                // piece can be identified or handed on without a label
                // printed, and another phone can scan it straight off this
                // one. White behind it with room around: a QR needs its quiet
                // zone to be read, whatever the theme, and the card is not
                // white.
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: p.border),
                  ),
                  child: QrImageView(
                    data: piece.itemCode,
                    size: 64,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
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
                piece.isHeld
                    ? const StatusBadge('In stock', tone: BadgeTone.success)
                    : const StatusBadge('Gone', tone: BadgeTone.danger),
              ],
            ),
            const SizedBox(height: 12),
            KeyValueRow(
              'Where',
              // Null once it has left us, which is not the same as unknown.
              piece.location ?? 'No longer with us',
              strong: piece.isHeld,
            ),
            KeyValueRow('Price', piece.price),
            if (piece.colour != null) KeyValueRow('Colour', piece.colour!),
            if (piece.productType != null)
              KeyValueRow('Type', piece.productType!),
            // Consignment before design, and that ordering is the point: the
            // product code is what the paperwork says, the design code is
            // internal and repeats. Kept only because a scan is also how
            // somebody finds their way back to the record.
            if (piece.productCode != null)
              KeyValueRow('Consignment', piece.productCode!, mono: true),
            KeyValueRow('Design', piece.designCode, mono: true),
            if (piece.receivedAt != null)
              KeyValueRow(
                'Received',
                piece.reference == null
                    ? piece.receivedAt!
                    : '${piece.receivedAt!} · ${piece.reference!}',
              ),
          ],
        ),
      ),
    );
  }
}
