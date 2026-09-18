import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import '../../widgets/theme_button.dart';
import 'bale_providers.dart';
import 'thaan_labels_pdf.dart';

/// Printing a bale's QR-coded Thaan labels — its own screen, not a button
/// buried in Record Cutting's sheet. A thermal roll running out of ink
/// partway through a real batch (200 Thaans is an ordinary size here) needs
/// somewhere to pick a resume point, not just a print trigger — mirrors
/// slk-core's own `/thaans/print/[baleId]` page, including its "Resume
/// from" picker, since there's no signal from the printer itself saying
/// where it actually stopped.
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

  /// How many labels (from the top) are already printed and physically
  /// stuck to a bale — 0 means print everything.
  int _printedThrough = 0;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (baleCode, codes) = await ref.read(baleRepositoryProvider).qrCodes(widget.baleId);
      if (!mounted) return;
      setState(() {
        _baleCode = baleCode;
        _codes = codes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      await printThaanLabels(baleCode: _baleCode ?? '', codes: _codes.sublist(_printedThrough));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final visible = _codes.length - _printedThrough;

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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    if (_codes.length > 1)
                      PickerField(
                        label: 'Resume from',
                        value: '$_printedThrough',
                        options: [
                          PickerOption('0', 'Start — print all ${_codes.length}'),
                          for (var i = 0; i < _codes.length - 1; i++)
                            PickerOption('${i + 1}', 'After #${i + 1} · ${_codes[i]}'),
                        ],
                        onChanged: (v) => setState(() => _printedThrough = int.parse(v ?? '0')),
                        hint: 'Printer ran out partway? Pick the last label that actually printed.',
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _printedThrough == 0
                          ? '${_codes.length} Thaan${_codes.length == 1 ? '' : 's'} to print.'
                          : 'Printing $visible of ${_codes.length} — resuming after $_printedThrough already done.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    for (var i = _printedThrough; i < _codes.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '#${i + 1}   ${_codes[i]}',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: p.text),
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
                  onPressed: _printing || visible == 0 ? null : _print,
                  icon: _printing
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print_outlined),
                  label: Text(_printing ? 'Preparing…' : 'Print $visible label${visible == 1 ? '' : 's'}'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ),
    );
  }
}
