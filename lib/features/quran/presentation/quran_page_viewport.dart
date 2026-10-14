import 'package:flutter/material.dart';

/// A single finger turns pages or scrolls a tall sheet at its normal scale.
/// Pinch zoom and panning a magnified sheet stay inside the page.
class QuranPageViewport extends StatefulWidget {
  const QuranPageViewport({
    super.key,
    required this.page,
    required this.child,
    required this.onSwipe,
    this.onZoomChanged,
  });

  final int page;
  final Widget child;
  final ValueChanged<int> onSwipe;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<QuranPageViewport> createState() => _QuranPageViewportState();
}

class _QuranPageViewportState extends State<QuranPageViewport> {
  final transform = TransformationController();
  final scroll = ScrollController();
  Offset drag = Offset.zero;
  bool pinching = false;
  bool startedAtNormalScale = true;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    transform.addListener(_onTransform);
  }

  void _onTransform() {
    final value = transform.value.getMaxScaleOnAxis() > 1.01;
    if (value == zoomed) return;
    zoomed = value;
    widget.onZoomChanged?.call(value);
  }

  void _start(ScaleStartDetails details) {
    drag = Offset.zero;
    pinching = details.pointerCount > 1;
    startedAtNormalScale = !zoomed;
  }

  void _update(ScaleUpdateDetails details) {
    pinching |= details.pointerCount > 1 || (details.scale - 1).abs() > .01;
    if (!startedAtNormalScale || pinching) return;
    drag += details.focalPointDelta;
    // InteractiveViewer's scale recognizer can own a one-finger pan even at
    // scale 1. Forward that vertical movement to the actual sheet scroll.
    if (drag.dy.abs() > drag.dx.abs() && scroll.hasClients) {
      scroll.jumpTo(
        (scroll.offset - details.focalPointDelta.dy).clamp(
          scroll.position.minScrollExtent,
          scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  void _end(ScaleEndDetails details) {
    if (!startedAtNormalScale || pinching || zoomed) return;
    final velocity = details.velocity.pixelsPerSecond;
    if (drag.dx.abs() <= drag.dy.abs()) return;
    if (drag.dx.abs() < 48 && (drag.dx.abs() < 18 || velocity.dx.abs() < 350)) {
      return;
    }
    widget.onSwipe(drag.dx > 0 ? 1 : -1);
  }

  @override
  void dispose() {
    transform.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(0.0, 560.0);
      return SingleChildScrollView(
        key: PageStorageKey('mushaf-scroll-${widget.page}'),
        controller: scroll,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: InteractiveViewer(
              transformationController: transform,
              minScale: 1,
              maxScale: 5,
              onInteractionStart: _start,
              onInteractionUpdate: _update,
              onInteractionEnd: _end,
              child: SizedBox(width: width, child: widget.child),
            ),
          ),
        ),
      );
    },
  );
}
