import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
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
    final p = context.p;
    final count = _rangeValid ? _toIndex - _fromIndex + 1 : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_baleCode == null ? 'Print QR codes' : 'Print QR codes — $_baleCode'),
        actions: [const ThemeButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _codes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No Thaans here have a QR code yet.',
                      style: TextStyle(color: p.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${_codes.length} Thaan${_codes.length == 1 ? '' : 's'} coded, '
                      '${_codes.first} to ${_codes.last}.',
                      style: TextStyle(fontSize: 13, color: p.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _from,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'From code',
                              errorText: _fromIndex == -1 ? 'Not on this bale' : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _to,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'To code',
                              errorText: _toIndex == -1 ? 'Not on this bale' : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        !_rangeValid && _fromIndex != -1 && _toIndex != -1
                            ? 'From has to come before To — swap them.'
                            : count == _codes.length
                                ? 'Printing all of them.'
                                : "Printer ran out partway? Set From to the last label that actually printed — "
                                  'labels usually resume right after it.',
                        style: TextStyle(fontSize: 12, color: p.textMuted),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _codes.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _printing || !_rangeValid ? null : _print,
                  icon: _printing
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print_outlined),
                  label: Text(_printing ? 'Preparing…' : 'Print $count label${count == 1 ? '' : 's'}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ),
    );
  }
}
