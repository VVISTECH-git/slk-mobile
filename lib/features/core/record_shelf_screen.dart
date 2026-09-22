import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'pipeline_providers.dart';
import 'records_list_screen.dart' show coreRecordsProvider;

/// From the pipeline to the shelf: a record's Thaans back from Ironing
/// become pieces, each with its own code (the QR label already on it), as
/// stock at a location under the record's product. A retail price is the
/// one thing the server insists on; the rest can wait.
///
/// Repeatable — a record whose later Thaans come back from Ironing is
/// shelved again from the same screen, and only the new ones go.
///
/// Route: `/core/records/:id/shelf`.
class RecordShelfScreen extends ConsumerStatefulWidget {
  const RecordShelfScreen({super.key, required this.recordId});
  final String recordId;

  @override
  ConsumerState<RecordShelfScreen> createState() => _RecordShelfScreenState();
}

class _RecordShelfScreenState extends ConsumerState<RecordShelfScreen> {
  final _retail = TextEditingController();
  final _cost = TextEditingController();
  final _making = TextEditingController();
  final _wholesale = TextEditingController();
  final _mrp = TextEditingController();
  String? _locationId;
  bool _morePrices = false;

  /// Seeded from the first draft that arrives; a refresh after a save must
  /// not wipe what is on screen.
  String? _seededFor;
  bool _busy = false;

  /// Set once the shelve went through — the body becomes the success state.
  ({int count, String productCode})? _done;

  /// Digits and at most one dot — a rupee amount, nothing else.
  static final _money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  @override
  void dispose() {
    _retail.dispose();
    _cost.dispose();
    _making.dispose();
    _wholesale.dispose();
    _mrp.dispose();
    super.dispose();
  }

  void _seed(CoreRecordShelf d) {
    if (_seededFor == d.colourwayId) return;
    _seededFor = d.colourwayId;
    _retail.text = d.prices.retail;
    _cost.text = d.prices.cost;
    _making.text = d.prices.making;
    _wholesale.text = d.prices.wholesale;
    _mrp.text = d.prices.mrp;
    // The other prices only open by themselves when one is already set.
    _morePrices = [d.prices.cost, d.prices.making, d.prices.wholesale, d.prices.mrp].any((v) => v.isNotEmpty);
    _locationId = d.locations.isEmpty ? null : d.locations.first.id;
  }

  Future<void> _shelve(CoreRecordShelf d) async {
    final locationId = _locationId;
    if (locationId == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(pipelineRepositoryProvider).shelve(
            widget.recordId,
            prices: CoreShelfPrices(
              cost: _cost.text.trim(),
              making: _making.text.trim(),
              wholesale: _wholesale.text.trim(),
              retail: _retail.text.trim(),
              mrp: _mrp.text.trim(),
            ),
            locationId: locationId,
          );
      if (!mounted) return;
      ref.invalidate(pipelineRecordsProvider);
      ref.invalidate(recordThaansProvider(widget.recordId));
      ref.invalidate(recordShelfProvider(widget.recordId));
      ref.invalidate(coreRecordsProvider);
      setState(() {
        _done = (
          count: result.pieceCodes.isEmpty ? d.finished.length : result.pieceCodes.length,
          productCode: result.productCode,
        );
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(recordShelfProvider(widget.recordId));
    final d = draft.value;
    if (d != null) _seed(d);

    final done = _done;
    if (done != null) return _buildDone(context, d, done);

    final canGo = d != null && d.blockers.isEmpty && d.finished.isNotEmpty && _locationId != null;

    return AppPage(
      title: d?.recordName ?? 'Put on shelf',
      subtitle: d?.designCode,
      actions: const [ThemeButton()],
      padded: false,
      bottomBar: !canGo
          ? null
          : ListenableBuilder(
              listenable: _retail,
              builder: (_, _) => BottomActionBar(
                primary: AppButton.primary(
                  label: 'Put ${d.finished.length} on the shelf',
                  icon: Icons.inventory_2_outlined,
                  busy: _busy,
                  onPressed: _retail.text.trim().isEmpty ? null : () => _shelve(d),
                ),
              ),
            ),
      body: AsyncView<CoreRecordShelf>(
        value: draft,
        onRetry: () => ref.invalidate(recordShelfProvider(widget.recordId)),
        loading: const LoadingState(message: 'Reading the record…'),
        data: (d) => _buildBody(context, d),
      ),
    );
  }

  Widget _buildBody(BuildContext context, CoreRecordShelf d) {
    final n = d.finished.length;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: [
        // ── What goes ──
        AppCard(
          emphasis: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.recordLabel != null) ...[
                CardTitle(d.recordLabel!),
                const Divider(height: 20),
              ],
              Row(
                children: [
                  Expanded(child: StatTile(value: '$n', label: 'Back from Ironing', tone: BadgeTone.success)),
                  Expanded(child: StatTile(value: '${d.shelved.length}', label: 'On shelf')),
                  Expanded(child: StatTile(value: '${d.inPipeline}', label: 'In pipeline')),
                ],
              ),
            ],
          ),
        ),
        if (d.needs.isNotEmpty) ...[
          const SizedBox(height: 12),
          InlineNotice(
            'The record still needs ${d.needs.join(', ')} — fill those in before or after, but the listing will say less until you do.',
            icon: Icons.pending_outlined,
            warning: true,
          ),
        ],
        SectionHeader('Going on the shelf', trailing: Text('$n')),
        if (d.finished.isEmpty)
          const EmptyState(compact: true, title: 'Nothing back from Ironing yet.', icon: Icons.iron_outlined)
        else
          AppListGroup(
            children: [
              for (final t in d.finished) AppListRow(title: t.code, titleMono: true, dense: true),
            ],
          ),

        // ── In the way ──
        if (d.blockers.isNotEmpty) ...[
          const SizedBox(height: 16),
          InlineNotice(
            "Can't go on the shelf yet: ${d.blockers.join('; ')}",
            icon: Icons.block_outlined,
            warning: true,
          ),
          const SizedBox(height: 8),
        ] else if (d.finished.isNotEmpty) ...[
          // ── Price ──
          const SectionHeader('Price'),
          AppTextField(
            label: 'Retail',
            controller: _retail,
            required: true,
            prefixText: '₹ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _money,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),
          if (!_morePrices)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton.ghost(
                label: 'More prices',
                icon: Icons.expand_more,
                onPressed: () => setState(() => _morePrices = true),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            _price('Cost', _cost),
            const SizedBox(height: 14),
            _price('Making', _making),
            const SizedBox(height: 14),
            _price('Wholesale', _wholesale),
            const SizedBox(height: 14),
            _price('MRP', _mrp),
          ],

          // ── Where ──
          const SectionHeader('Where'),
          PickerField(
            label: 'Location',
            required: true,
            value: _locationId,
            options: [for (final l in d.locations) PickerOption(l.id, l.name, subtitle: l.code)],
            hint: d.locations.isEmpty ? 'No location to shelve at' : null,
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 16),
          const InlineNotice(
            'Each Thaan becomes a piece with its own code — the QR label already on it is the shelf label.',
            icon: Icons.qr_code_2,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _price(String label, TextEditingController c) => AppTextField(
        label: label,
        controller: c,
        prefixText: '₹ ',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _money,
        textInputAction: TextInputAction.next,
      );

  Widget _buildDone(BuildContext context, CoreRecordShelf? d, ({int count, String productCode}) done) {
    final n = done.count;
    final code = done.productCode;
    return AppPage(
      title: d?.recordName ?? 'On the shelf',
      subtitle: d?.designCode,
      actions: const [ThemeButton()],
      body: SuccessState(
        title: '$n Thaan${n == 1 ? '' : 's'} on the shelf',
        message: code.isEmpty
            ? 'Photograph it next so it can be listed.'
            : 'Product $code. Photograph it next so it can be listed.',
        actionLabel: 'Photograph it',
        onAction: () => context.push(
          '/core/records/${widget.recordId}/photos'
          '${code.isEmpty ? '' : '?code=${Uri.encodeComponent(code)}'}',
        ),
        secondaryLabel: 'Back to records',
        onSecondary: () => context.pop(),
      ),
    );
  }
}
