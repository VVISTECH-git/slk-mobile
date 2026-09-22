import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/ui/ui.dart';
import 'bale_providers.dart';
import 'thaan_labels_pdf.dart';

/// Printing a bale's QR-coded Thaan labels — its own screen, not a button
/// buried in Record Cutting's sheet. Ink or paper running out partway
/// through a real batch (500 Thaans is well within range here) needs a way
/// to pick up where it stopped — by the Thaan code on the last label that
/// actually printed, which is the only thing physically in front of
/// whoever's reloading the printer. Not a position number: nobody standing
/// at a printer knows "#50", they know "T00002120". Mirrors the same idea
/// slk-core's own `/thaans/print/[baleId]` page uses.
class ThaanLabelsScreen extends ConsumerStatefulWidget {
  const ThaanLabelsScreen({super.key, required this.baleId});
  final String baleId;

  @override
  ConsumerState<ThaanLabelsScreen> createState() => _ThaanLabelsScreenState();
}

class _ThaanLabelsScreenState extends ConsumerState<ThaanLabelsScreen> {
  String? _baleCode;
  List<String> _codes = [];
  bool _loading = true;

  final _from = TextEditingController();
  final _to = TextEditingController();
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (baleCode, codes) = await ref.read(baleRepositoryProvider).qrCodes(widget.baleId);
      if (!mounted) return;
      setState(() {
        _baleCode = baleCode;
        _codes = codes;
        if (codes.isNotEmpty) {
          _from.text = codes.first;
          _to.text = codes.last;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  /// -1 when what's typed doesn't match any Thaan on this bale — codes are
  /// typed by hand off a physical label, so a typo is the normal failure
  /// mode to guard against, not an edge case.
  int get _fromIndex => _codes.indexOf(_from.text.trim().toUpperCase());
  int get _toIndex => _codes.indexOf(_to.text.trim().toUpperCase());

  bool get _rangeValid => _fromIndex != -1 && _toIndex != -1 && _fromIndex <= _toIndex;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      await printThaanLabels(
        baleCode: _baleCode ?? '',
        codes: _codes.sublist(_fromIndex, _toIndex + 1),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _rangeValid ? _toIndex - _fromIndex + 1 : 0;
    final bothFound = _fromIndex != -1 && _toIndex != -1;

    final Widget body;
    if (_loading) {
      body = const LoadingState(message: 'Loading Thaan codes…');
    } else if (_codes.isEmpty) {
      body = const EmptyState(icon: Icons.qr_code_2, title: 'No Thaans here have a QR code yet.');
    } else {
      body = SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InlineNotice(
              '${_codes.length} Thaan${_codes.length == 1 ? '' : 's'} coded, '
              '${_codes.first} to ${_codes.last}.',
              icon: Icons.qr_code_2,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'From code',
                    controller: _from,
                    textCapitalization: TextCapitalization.characters,
                    error: _fromIndex == -1 ? 'Not on this bale' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'To code',
                    controller: _to,
                    textCapitalization: TextCapitalization.characters,
                    error: _toIndex == -1 ? 'Not on this bale' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_rangeValid && bothFound)
              const InlineNotice('From has to come before To — swap them.', icon: Icons.swap_horiz, warning: true)
            else if (count == _codes.length)
              const InlineNotice('Printing all of them.', icon: Icons.print_outlined)
            else
              const InlineNotice(
                'Printer ran out partway? Set From to the last label that actually printed — '
                'labels usually resume right after it.',
              ),
          ],
        ),
      );
    }

    return AppPage(
      title: 'Print QR codes',
      subtitle: _baleCode,
      actions: const [ThemeButton()],
      padded: false,
      body: body,
      bottomBar: _codes.isEmpty
          ? null
          : BottomActionBar(
              primary: AppButton.primary(
                label: 'Print $count label${count == 1 ? '' : 's'}',
                icon: Icons.print_outlined,
                busy: _printing,
                onPressed: _rangeValid ? _print : null,
              ),
            ),
    );
  }
}
