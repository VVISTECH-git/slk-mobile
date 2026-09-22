import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import '../core/core_auth.dart' show coreOptionsProvider;
import 'pile_providers.dart';

/// Piles — Phase 2. Fill in what a pile is: the motif, the craft, the
/// border, its colours — the details decided at this stage that the bale's
/// cloth item couldn't know. The first save makes the Product Management
/// record (the colourway); every save after that patches it.
///
/// Nothing is typed. What the item already settled (type, fibre, size) is
/// shown, not asked; what's to be decided is a picker each, from the same
/// Master Lists the web's record form uses; and the price, photos and
/// stock wait for Ironing, where they belong.
///
/// Route: `/core/piles/:id/complete`.
class CompletePileScreen extends ConsumerStatefulWidget {
  const CompletePileScreen({super.key, required this.pileId});
  final String pileId;

  @override
  ConsumerState<CompletePileScreen> createState() => _CompletePileScreenState();
}

class _CompletePileScreenState extends ConsumerState<CompletePileScreen> {
  /// Every field's current pick, by key — seeded once from the draft, then
  /// the person's. Null is "not yet", and is sent as null.
  final _attrs = <String, String?>{};
  String? _colourId;
  String? _secondaryColourId;

  /// Seeded from the first draft that arrives; a refresh after a save must
  /// not wipe what is on screen.
  String? _seededFor;
  bool _busy = false;

  void _seed(CorePileDraft d) {
    if (_seededFor == d.pileId) return;
    _seededFor = d.pileId;
    _attrs
      ..clear()
      ..addEntries([for (final f in d.fields) MapEntry(f.key, f.valueId)]);
    _colourId = d.colourId;
    _secondaryColourId = d.secondaryColourId;
  }

  /// The next draft pile still waiting on something — the one "Save · next
  /// pile" would open. Null when this is the last.
  CorePile? _nextOf(List<CorePile>? drafts) {
    for (final p in drafts ?? const <CorePile>[]) {
      if (p.id != widget.pileId && p.needs.isNotEmpty) return p;
    }
    return null;
  }

  Future<void> _save(CorePileDraft draft) async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(pileRepositoryProvider).complete(
            widget.pileId,
            attributes: {for (final f in draft.fields) f.key: _attrs[f.key]},
            colourId: _colourId,
            secondaryColourId: _secondaryColourId,
          );
      if (!mounted) return;
      showOk(context, result.message);

      ref.invalidate(pileDetailProvider(widget.pileId));
      ref.invalidate(pileDraftProvider(widget.pileId));
      ref.invalidate(pilesProvider);

      // Freshly fetched, so the pile just saved no longer counts if it is
      // now complete — and the next one offered really does need something.
      List<CorePile>? drafts;
      try {
        drafts = await ref.read(pilesProvider('draft').future);
      } catch (_) {
        drafts = null;
      }
      if (!mounted) return;
      final next = _nextOf(drafts);
      if (next == null) {
        context.pop();
        return;
      }
      final open = await showConfirmDialog(
        context,
        title: 'Next: ${next.name}?',
        message: [
          next.code,
          '${next.thaanCount} Thaan${next.thaanCount == 1 ? '' : 's'}',
          'needs ${next.needs.join(', ')}',
        ].join(' · '),
        confirmLabel: 'Open',
        cancelLabel: 'Done',
      );
      if (!mounted) return;
      if (open) {
        context.pushReplacement('/core/piles/${next.id}/complete');
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
    final draft = ref.watch(pileDraftProvider(widget.pileId));
    final options = ref.watch(coreOptionsProvider);
    final pile = ref.watch(pileDetailProvider(widget.pileId));
    final drafts = ref.watch(pilesProvider('draft'));

    final d = draft.value;
    if (d != null) _seed(d);

    final thaanCount = pile.value?.thaanCount;
    final subtitle = d == null
        ? null
        : [
            d.pileCode,
            if (thaanCount != null) '$thaanCount Thaan${thaanCount == 1 ? '' : 's'}',
            if (d.stage.isNotEmpty) 'at ${d.stage}',
          ].join(' · ');

    final hasNext = _nextOf(drafts.value) != null;

    return AppPage(
      title: d?.pileName ?? 'Complete pile',
      subtitle: subtitle,
      actions: const [ThemeButton()],
      padded: false,
      bottomBar: d == null || !options.hasValue
          ? null
          : BottomActionBar(
              primary: AppButton.primary(
                label: hasNext ? 'Save · next pile' : 'Save',
                icon: Icons.check,
                busy: _busy,
                onPressed: () => _save(d),
              ),
            ),
      body: AsyncView<CorePileDraft>(
        value: draft,
        onRetry: () => ref.invalidate(pileDraftProvider(widget.pileId)),
        loading: const LoadingState(message: 'Reading the pile…'),
        data: (d) => AsyncView<CoreOptions>(
          value: options,
          onRetry: () => ref.invalidate(coreOptionsProvider),
          loading: const LoadingState(message: 'Loading the lists…'),
          data: (o) => _buildForm(context, d, o, pile.value),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, CorePileDraft d, CoreOptions o, CorePile? pile) {
    final photoUrl = pile?.photoUrl;
    final sareeSize = d.sareeSize;
    final colours = _pickOptions(o['colour']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Known already ──
        Row(
          children: [
            RowThumb(
              size: 64,
              image: photoUrl == null ? null : NetworkImage(photoUrl),
              icon: photoUrl == null ? Icons.layers_outlined : null,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: InlineNotice("Already known from the bale's cloth item — nothing to type here."),
            ),
          ],
        ),
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
