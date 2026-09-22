import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'core_auth.dart' show coreOptionsProvider;
import 'pipeline_providers.dart';
import 'records_list_screen.dart' show coreRecordsProvider;

/// Fill in what a record is: the motif, the craft, the border, its colours —
/// the details decided on the floor that the bale's cloth item couldn't
/// know. The record already exists (made at the door when its Thaans came
/// back from Print); every save here patches it.
///
/// Nothing is typed. What the item already settled (type, fibre, size) is
/// shown, not asked; what's to be decided is a picker each, from the same
/// Master Lists the web's record form uses; and the price, photos and
/// stock wait for Ironing, where they belong.
///
/// Route: `/core/records/:id/fill`.
class RecordFillScreen extends ConsumerStatefulWidget {
  const RecordFillScreen({super.key, required this.recordId});
  final String recordId;

  @override
  ConsumerState<RecordFillScreen> createState() => _RecordFillScreenState();
}

class _RecordFillScreenState extends ConsumerState<RecordFillScreen> {
  /// Every field's current pick, by key — seeded once from the draft, then
  /// the person's. Null is "not yet", and is sent as null.
  final _attrs = <String, String?>{};
  String? _colourId;
  String? _secondaryColourId;

  /// Seeded from the first draft that arrives; a refresh after a save must
  /// not wipe what is on screen.
  String? _seededFor;
  bool _busy = false;

  void _seed(CoreRecordFill d) {
    if (_seededFor == d.colourwayId) return;
    _seededFor = d.colourwayId;
    _attrs
      ..clear()
      ..addEntries([for (final f in d.fields) MapEntry(f.key, f.valueId)]);
    _colourId = d.colourId;
    _secondaryColourId = d.secondaryColourId;
  }

  /// The next record in the pipeline still waiting on something — the one
  /// "Save · next" would open. Null when this is the last.
  CorePipelineRecord? _nextOf(List<CorePipelineRecord>? rows) {
    for (final r in rows ?? const <CorePipelineRecord>[]) {
      if (r.id != widget.recordId && r.needs.isNotEmpty) return r;
    }
    return null;
  }

  Future<void> _save(CoreRecordFill draft) async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(pipelineRepositoryProvider).fill(
            widget.recordId,
            attributes: {for (final f in draft.fields) f.key: _attrs[f.key]},
            colourId: _colourId,
            secondaryColourId: _secondaryColourId,
          );
      if (!mounted) return;
      showOk(context, result.message);

      ref.invalidate(recordFillProvider(widget.recordId));
      ref.invalidate(pipelineRecordsProvider);
      ref.invalidate(coreRecordsProvider);

      // Freshly fetched, so the record just saved no longer counts if it is
      // now complete — and the next one offered really does need something.
      List<CorePipelineRecord>? rows;
      try {
        rows = await ref.read(pipelineRecordsProvider('in_pipeline').future);
      } catch (_) {
        rows = null;
      }
      if (!mounted) return;
      final next = _nextOf(rows);
      if (next == null) {
        context.pop();
        return;
      }
      final open = await showConfirmDialog(
        context,
        title: 'Next: ${next.name}?',
        message: [next.summary, 'needs ${next.needs.join(', ')}'].join(' · '),
        confirmLabel: 'Open',
        cancelLabel: 'Done',
      );
      if (!mounted) return;
      if (open) {
        context.pushReplacement('/core/records/${next.id}/fill');
      } else {
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(recordFillProvider(widget.recordId));
    final options = ref.watch(coreOptionsProvider);
    final rows = ref.watch(pipelineRecordsProvider('in_pipeline'));

    final d = draft.value;
    if (d != null) _seed(d);

    final subtitle = d == null
        ? null
        : [
            if (d.designCode != null) d.designCode!,
            if (d.thaanCount > 0) '${d.thaanCount} Thaan${d.thaanCount == 1 ? '' : 's'}',
            if (d.stage.isNotEmpty) 'at ${d.stage}',
          ].join(' · ');

    final hasNext = _nextOf(rows.value) != null;

    return AppPage(
      title: d?.recordName ?? 'Fill in details',
      subtitle: subtitle,
      actions: const [ThemeButton()],
      padded: false,
      bottomBar: d == null || !options.hasValue
          ? null
          : BottomActionBar(
              primary: AppButton.primary(
                label: hasNext ? 'Save · next' : 'Save',
                icon: Icons.check,
                busy: _busy,
                onPressed: () => _save(d),
              ),
            ),
      body: AsyncView<CoreRecordFill>(
        value: draft,
        onRetry: () => ref.invalidate(recordFillProvider(widget.recordId)),
        loading: const LoadingState(message: 'Reading the record…'),
        data: (d) => AsyncView<CoreOptions>(
          value: options,
          onRetry: () => ref.invalidate(coreOptionsProvider),
          loading: const LoadingState(message: 'Loading the lists…'),
          data: (o) => _buildForm(context, d, o),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, CoreRecordFill d, CoreOptions o) {
    final sareeSize = d.sareeSize;
    final colours = _pickOptions(o['colour']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Known already ──
        const InlineNotice("Already known from the bale's cloth item — nothing to type here."),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.recordLabel != null) ...[
                KeyValueRow('Record', d.recordLabel!, strong: true),
                const Divider(height: 16),
              ],
              for (final i in d.inherited) KeyValueRow(i.label, i.valueLabel),
              if (sareeSize != null) KeyValueRow('Saree size', sareeSize),
              if (d.inherited.isEmpty && sareeSize == null) const KeyValueRow('Inherited', 'Nothing from the item'),
            ],
          ),
        ),

        // ── Decided here ──
        SectionHeader(d.stage.isEmpty ? 'Fill in' : 'Decided at ${d.stage} — fill in'),
        if (d.needs.isNotEmpty) ...[
          InlineNotice('Still needs ${d.needs.join(', ')}.', icon: Icons.pending_outlined, warning: true),
          const SizedBox(height: 12),
        ],
        if (d.fields.isEmpty)
          const EmptyState(compact: true, title: 'Nothing to decide at this stage.', icon: Icons.check_circle_outline)
        else
          for (final f in d.fields) ...[
            PickerField(
              label: f.label,
              required: f.required,
              value: _attrs[f.key],
              options: _pickOptions(o[f.list]),
              allowClear: !f.required,
              hint: o[f.list] == null ? 'No "${f.list}" list on the server' : null,
              onChanged: (v) => setState(() => _attrs[f.key] = v),
            ),
            const SizedBox(height: 14),
          ],
        PickerField(
          label: 'Primary colour',
          required: true,
          value: _colourId,
          options: colours,
          onChanged: (v) => setState(() => _colourId = v),
        ),
        const SizedBox(height: 14),
        PickerField(
          label: 'Secondary colour',
          value: _secondaryColourId,
          options: colours,
          allowClear: true,
          hint: 'None',
          onChanged: (v) => setState(() => _secondaryColourId = v),
        ),
        const SizedBox(height: 16),
        const InlineNotice('Price, photos and stock come at the end, after Ironing.', icon: Icons.schedule),
        const SizedBox(height: 8),
      ],
    );
  }

  static List<PickerOption> _pickOptions(List<CoreOption>? values) => [
        for (final v in values ?? const <CoreOption>[]) PickerOption(v.id, v.label, color: v.swatch),
      ];
}
