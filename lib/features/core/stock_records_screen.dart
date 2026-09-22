import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../pieces/piece_labels_pdf.dart';
import '../pos/barcode_scan_screen.dart';
import '../thaans/thaan_providers.dart';

/// What did I just scan?
///
/// The floor's question, asked with a saree in one hand and a phone in the
/// other. Product Management answers "what do we sell and how much is there";
/// this answers "which one is this, which record is it under, is it still
/// ours, and where does the ledger think it is" — a different question,
/// asked in a different posture, so it gets its own screen rather than a
/// tab on the catalogue.
///
/// One label, either way. The QR stitched onto a Thaan at Label Stitching
/// is the same code it keeps as a piece once it goes on the shelf, so
/// `GET /thaans/lookup?code=` answers for both: where it is in the
/// pipeline while it is a Thaan, and where it sits in stock once it is a
/// piece.
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
  CoreThaan? _found;
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
      final thaan = await ref.read(thaanRepositoryProvider).lookupByCode(code);
      if (mounted) setState(() => _found = thaan);
    } on ApiException catch (e) {
      /*
        The server's own words, shown as they are.

        "That is not an SLK label" and "No Thaan carries that code" are
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
        // covered the very answer just looked up, on a phone whose keypad
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

  /// A fresh label for a piece whose own got torn or faded — the same code,
  /// reprinted. Only once it is a piece: a Thaan's label is printed from
  /// its bale, in a sheet, and reprinting one on its own is not a thing
  /// the floor does.
  Future<void> _printLabel(CoreThaan t) => printPieceLabels(
        codes: [t.pieceCode!],
        productName: t.recordName ?? t.itemName,
        variantLabel: t.recordColour,
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
                    label: 'Thaan or piece code',
                    hint: 'T00002048',
                    controller: _field,
                    focusNode: _focus,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    // Guarded like the arrow: a scanner's Enter arriving while
                    // a lookup is in flight would start a second one and show
                    // whichever answered last under the other's heading.
                    onSubmitted: (v) {
                      if (!_busy) _lookup(v);
                    },
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
              'Scan the label on a saree — the same one it has carried since Label Stitching.',
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
              if (_found!.pieceCode != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton.ghost(
                    label: 'Print label',
                    icon: Icons.qr_code_2,
                    onPressed: () => _printLabel(_found!),
                  ),
                ),
                const SizedBox(height: 2),
              ],
              _ThaanCard(thaan: _found!),
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

/// One Thaan, answered: which record it is under, where it is in the
/// pipeline, and — once it is a piece — whether it is still ours and where.
class _ThaanCard extends StatelessWidget {
  const _ThaanCard({required this.thaan});

  final CoreThaan thaan;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final t = thaan;
    final code = t.pieceCode ?? t.code ?? '—';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The same QR the label carries — the bare code, which is what
              // a scan of either resolves. On screen so a piece can be
              // identified or handed on without a label printed, and another
              // phone can scan it straight off this one. White behind it with
              // room around: a QR needs its quiet zone to be read, whatever
              // the theme, and the card is not white.
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.border),
                ),
                child: QrImageView(
                  data: code,
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
                      code,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: p.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.recordLabel ?? t.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              /*
                Where it stands, said first and said loudly.

                It is the first thing a scan should answer. The ledger
                decides it for a piece — sold, written off or sent on all
                make it "Gone" — and a saree that reads "Warehouse" when it
                left six weeks ago is the bug this screen exists to not have.
              */
              _stockBadge(t),
            ],
          ),
          const SizedBox(height: 12),
          KeyValueRow('Record', t.recordLabel ?? 'Not in a record'),
          KeyValueRow('Pipeline', t.pipelineStatus),
          KeyValueRow('Stock', t.stockStatus ?? (t.pieceCode == null ? 'In pipeline' : 'On shelf')),
          if (t.pieceCode != null) KeyValueRow('Piece', t.pieceCode!, mono: true),
          if (t.productCode != null) KeyValueRow('Product', t.productCode!, mono: true),
          KeyValueRow(
            'Where',
            // Null once it has left us, which is not the same as unknown;
            // and not a place at all while it is still a Thaan.
            t.locationName ?? (t.isHeld == false ? 'No longer with us' : 'Not on a shelf yet'),
            strong: t.isHeld == true,
          ),
          if (t.isHeld != null) KeyValueRow('Held', t.isHeld! ? 'Yes' : 'No'),
          if (t.priceMinor != null) KeyValueRow('Price', t.price),
          const Divider(height: 20),
          KeyValueRow('Bale', t.baleCode, mono: true),
          KeyValueRow('Item', '${t.itemName} · ${t.baleType}'),
          KeyValueRow('Supplier', t.supplierName),
          if (t.lastStage != null)
            KeyValueRow(
              'Last stage',
              t.lastVendorName == null ? t.lastStage! : '${t.lastStage} · ${t.lastVendorName}',
            ),
          if (t.voidedAt != null) ...[
            const SizedBox(height: 10),
            InlineNotice('Voided on ${t.voidedAt}', icon: Icons.block, warning: true),
          ],
        ],
      ),
    );
  }

  static Widget _stockBadge(CoreThaan t) {
    if (t.voidedAt != null) return const StatusBadge('Voided', tone: BadgeTone.danger);
    return switch (t.stockStatus) {
      'On shelf' => const StatusBadge('On shelf', tone: BadgeTone.success),
      'Gone' => const StatusBadge('Gone', tone: BadgeTone.danger),
      'Voided' => const StatusBadge('Voided', tone: BadgeTone.danger),
      'In pipeline' => const StatusBadge('In pipeline', tone: BadgeTone.brand),
      _ => StatusBadge.pipeline(t.pipelineStatus),
    };
  }
}
