import '../widgets/aura_controls.dart';

import 'package:aura/theme/aura_theme.dart';

import 'dart:io';

import 'package:flutter/material.dart';

import 'layout_draft.dart';
import 'layout_template.dart';

class LayoutIcon extends StatelessWidget {
  const LayoutIcon({
    super.key,
    required this.template,
    this.size = 26,
    this.color = Colors.white,
  });
  final LayoutTemplate template;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _LayoutIconPainter(template, color),
  );
}

class _LayoutIconPainter extends CustomPainter {
  _LayoutIconPainter(this.template, this.color);
  final LayoutTemplate template;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    for (final r in template.cells) {
      final bounds = Rect.fromLTRB(
        r.left * (size.width - 2) + 1,
        r.top * (size.height - 2) + 1,
        r.right * (size.width - 2) + 1,
        r.bottom * (size.height - 2) + 1,
      );
      canvas.drawPath(template.cellPath(bounds.deflate(.35)), paint);
    }
  }

  @override
  bool shouldRepaint(_LayoutIconPainter old) =>
      old.template != template || old.color != color;
}

/// The same even pixel rectangles as the exporter, scaled to the display.
class LayoutGrid extends StatelessWidget {
  const LayoutGrid({
    super.key,
    required this.draft,
    this.livePreview,
    this.onSelect,
    this.showSelection = true,
    this.retaking = false,
  });
  final LayoutDraft draft;
  final Widget? livePreview;
  final ValueChanged<int>? onSelect;
  final bool showSelection;
  final bool retaking;
  @override
  Widget build(BuildContext context) {
    final output = layoutOutputSize(
      draft.ratio,
      longEdge: draft.isVideo || draft.kinds.contains(CellKind.video)
          ? 1920
          : 2160,
    );
    final cells = draft.template.pixelRects(output);
    return AspectRatio(
      aspectRatio: output.aspectRatio,
      child: LayoutBuilder(
        builder: (context, bounds) => Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            for (int i = 0; i < cells.length; i++)
              Positioned.fromRect(
                rect: Rect.fromLTRB(
                  cells[i].left / output.width * bounds.maxWidth,
                  cells[i].top / output.height * bounds.maxHeight,
                  cells[i].right / output.width * bounds.maxWidth,
                  cells[i].bottom / output.height * bounds.maxHeight,
                ),
                child: Semantics(
                  label:
                      'Cell ${i + 1}, ${draft.media[i] == null ? 'empty' : draft.media[i]!.kind.name}',
                  selected: showSelection && draft.selected == i,
                  button: onSelect != null,
                  child: GestureDetector(
                    key: ValueKey('layout-cell-$i'),
                    onTap: onSelect == null ? null : () => onSelect!(i),
                    child: ClipPath(
                      clipper: LayoutCellClipper(draft.template),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Color(i.isEven ? 0xFF222226 : 0xFF29292E),
                          ),
                          if (i == draft.selected &&
                              (draft.media[i] == null || retaking) &&
                              livePreview != null)
                            livePreview!
                          else if (draft.media[i] case final media?)
                            Transform.flip(
                              flipX: media.mirror,
                              child: Image.file(
                                File(media.thumbnail ?? media.path),
                                fit: BoxFit.cover,
                                cacheWidth: 800,
                                gaplessPlayback: true,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            )
                          else
                            Center(
                              child: Icon(
                                draft.kinds[i] == CellKind.video
                                    ? Icons.videocam_outlined
                                    : Icons.add_a_photo_outlined,
                                color: AuraColors.muted,
                              ),
                            ),
                          if (showSelection) ...[
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _CellOutlinePainter(
                                  draft.template,
                                  draft.selected == i,
                                ),
                              ),
                            ),
                            Align(
                              alignment: draft.template.isDiamond
                                  ? const Alignment(0, -.4)
                                  : Alignment.topLeft,
                              child: FractionallySizedBox(
                                widthFactor: draft.template.isDiamond ? .5 : 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      color: Colors.black54,
                                      child: Text(
                                        '${i + 1}${draft.media[i]?.kind == CellKind.video ? ' • ${draft.media[i]!.seconds.toStringAsFixed(1)}s' : ''}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LayoutCellClipper extends CustomClipper<Path> {
  const LayoutCellClipper(this.template);
  final LayoutTemplate template;
  @override
  Path getClip(Size size) => template.cellPath(Offset.zero & size);
  @override
  bool shouldReclip(LayoutCellClipper old) => old.template != template;
}

/// An accessible alternative to tapping narrow strips in portrait canvases.
class LayoutCellSelector extends StatelessWidget {
  const LayoutCellSelector({super.key, required this.draft, this.onSelect});
  final LayoutDraft draft;
  final ValueChanged<int>? onSelect;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: draft.media.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, i) => Tooltip(
        message:
            'Cell ${i + 1} · ${draft.kinds[i].name} · ${draft.media[i] == null ? 'empty' : 'filled'}',
        child: ChoiceChip(
          key: ValueKey('layout-select-$i'),
          label: Text('${i + 1}'),
          avatar: Icon(
            draft.media[i] != null
                ? Icons.check
                : draft.kinds[i] == CellKind.video
                ? Icons.videocam_outlined
                : Icons.photo_camera_outlined,
            size: 15,
            color: draft.selected == i ? Colors.black : AuraColors.muted,
          ),
          selected: draft.selected == i,
          selectedColor: AuraColors.primary,
          labelStyle: TextStyle(
            color: draft.selected == i ? Colors.black : Colors.white,
          ),
          showCheckmark: false,
          onSelected: onSelect == null ? null : (_) => onSelect!(i),
        ),
      ),
    ),
  );
}

class _CellOutlinePainter extends CustomPainter {
  _CellOutlinePainter(this.template, this.selected);
  final LayoutTemplate template;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      template.cellPath((Offset.zero & size).deflate(selected ? 1 : .25)),
      Paint()
        ..color = selected ? AuraColors.primary : AuraColors.muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : .5,
    );
  }

  @override
  bool shouldRepaint(_CellOutlinePainter old) =>
      old.template != template || old.selected != selected;
}

Future<({LayoutTemplate template, LayoutMode mode})?> showLayoutPicker(
  BuildContext context,
  LayoutDraft draft,
) {
  var selected = draft.template;
  var mode = draft.mode;
  return showModalBottomSheet<({LayoutTemplate template, LayoutMode mode})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose your layout',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SegmentedButton<LayoutMode>(
                  segments: const [
                    ButtonSegment(
                      value: LayoutMode.photos,
                      label: Text('Photos'),
                    ),
                    ButtonSegment(
                      value: LayoutMode.videos,
                      label: Text('Videos'),
                    ),
                    ButtonSegment(
                      value: LayoutMode.hybrid,
                      label: Text('Hybrid'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => update(() => mode = s.first),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in LayoutTemplate.values)
                      SizedBox(
                        width: 98,
                        child: OutlinedButton(
                          key: ValueKey('template-${t.name}'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: selected == t
                                ? AuraColors.primary.withValues(alpha: .16)
                                : null,
                            side: BorderSide(
                              color: selected == t
                                  ? AuraColors.primary
                                  : Colors.white24,
                            ),
                          ),
                          onPressed: () => update(() => selected = t),
                          child: Column(
                            children: [
                              LayoutIcon(
                                template: t,
                                size: 36,
                                color: selected == t
                                    ? AuraColors.primary
                                    : Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  mode == LayoutMode.hybrid
                      ? 'Choose a photo or video for each cell.'
                      : mode == LayoutMode.videos
                      ? 'Record a separate video in every cell.'
                      : 'Take a separate photo in every cell.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                AuraButton(
                  onPressed: () =>
                      Navigator.pop(context, (template: selected, mode: mode)),
                  label: 'Use layout',
                  icon: Icons.check_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
