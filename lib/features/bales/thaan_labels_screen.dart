import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import 'bale_providers.dart';
import 'thaan_labels_pdf.dart';

/// Printing a bale's QR-coded Thaan labels — its own screen, not a button
/// buried in Record Cutting's sheet. A thermal roll running out of ink
/// partway through a real batch (500 Thaans is well within range here)
/// needs a way to pick up where it stopped — a plain From/To range, not a
/// list of every code on screen or a picker wheel scrolling through
/// hundreds of options. Mirrors the same From/To idea slk-core's own
/// `/thaans/print/[baleId]` page uses.
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

  final _from = TextEditingController(text: '1');
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
        _to.text = '${codes.length}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  /// 1-based, clamped into range — typing garbage or an out-of-range number
  /// never crashes the slice below, it just snaps back to something valid.
  int get _fromIndex {
    if (_codes.isEmpty) return 1;
    return (int.tryParse(_from.text) ?? 1).clamp(1, _codes.length);
  }

  int get _toIndex {
    if (_codes.isEmpty) return 1;
    return (int.tryParse(_to.text) ?? _codes.length).clamp(_fromIndex, _codes.length);
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      await printThaanLabels(
        baleCode: _baleCode ?? '',
        codes: _codes.sublist(_fromIndex - 1, _toIndex),
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
    final count = _codes.isEmpty ? 0 : _toIndex - _fromIndex + 1;

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
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _from,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'From #'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _to,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'To #'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        count == _codes.length
                            ? 'Printing all of them.'
                            : 'Printer ran out partway? Set From to where it stopped — '
                              '#$_fromIndex is ${_codes[_fromIndex - 1]}, #$_toIndex is ${_codes[_toIndex - 1]}.',
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
                  onPressed: _printing || count == 0 ? null : _print,
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
