part of 'tasbih_page.dart';

class _CounterFace extends StatelessWidget {
  const _CounterFace({
    required this.counter,
    required this.increment,
    required this.undo,
    required this.onHold,
    required this.onRelease,
    required this.onReset,
  });
  final TasbihController counter;
  final VoidCallback increment, undo, onHold, onRelease, onReset;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), style = counter.definition.style;
    final number = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '${counter.current}',
        key: const ValueKey('tasbih-current'),
        style: TextStyle(
          fontSize: style == TasbihStyle.fullscreen ? 128 : 64,
          fontWeight: FontWeight.w700,
          color: p.tealHeading,
        ),
      ),
    );
    final dial = SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: counter.current / counter.definition.goal,
              strokeWidth: 7,
              color: const Color(0xFF2A8C82),
              backgroundColor: p.border,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 95, width: 130, child: number),
              Text(
                'من ${counter.definition.goal}',
                style: TextStyle(color: p.muted),
              ),
            ],
          ),
        ],
      ),
    );
    Widget face = switch (style) {
      TasbihStyle.classic => dial,
      TasbihStyle.fullscreen => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_outlined, color: p.gold, size: 40),
          const SizedBox(height: 8),
          Flexible(
            fit: FlexFit.loose,
            child: SizedBox(width: 270, height: 200, child: number),
          ),
        ],
      ),
      TasbihStyle.buttons => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: undo,
            icon: const Icon(Icons.remove),
            tooltip: 'نقصان',
          ),
          const SizedBox(width: 12),
          Flexible(child: SizedBox(width: 130, height: 120, child: number)),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: increment,
            icon: const Icon(Icons.add),
            tooltip: 'زيادة',
          ),
        ],
      ),
      TasbihStyle.circular => SizedBox(
        width: 250,
        height: 250,
        child: CustomPaint(
          painter: _BeadsPainter(p.gold, false, counter.current),
          child: Center(
            child: SizedBox(width: 110, height: 100, child: number),
          ),
        ),
      ),
      TasbihStyle.horizontal => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 150, height: 100, child: number),
          SizedBox(
            height: 70,
            width: double.infinity,
            child: CustomPaint(
              painter: _BeadsPainter(p.gold, true, counter.current),
            ),
          ),
        ],
      ),
      TasbihStyle.digital => Container(
        width: 208,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.gold,
          borderRadius: BorderRadius.circular(38),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 88,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: p.background,
                border: Border.all(color: const Color(0xFFA48640), width: 3),
                borderRadius: BorderRadius.circular(17),
              ),
              child: number,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt),
                  tooltip: 'تصفير الحالي',
                ),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.notice,
                  ),
                  child: Icon(
                    Icons.touch_app_outlined,
                    color: p.tealHeading,
                    size: 30,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    };
    // One interaction surface for every skin. Child buttons win their gesture
    // arena, so pressing + or the digital reset cannot also increment the face.
    face = Semantics(
      label:
          'المسبحة، العدّ الحالي ${counter.current} من ${counter.definition.goal}',
      button: true,
      child: Listener(
        onPointerUp: (_) => onRelease(),
        onPointerCancel: (_) => onRelease(),
        child: GestureDetector(
          key: const ValueKey('tasbih-face'),
          behavior: HitTestBehavior.opaque,
          onTap: increment,
          onLongPress: onHold,
          onHorizontalDragEnd:
              style == TasbihStyle.circular || style == TasbihStyle.horizontal
              ? (details) {
                  if (details.primaryVelocity! > 100) {
                    increment();
                  } else if (details.primaryVelocity! < -100) {
                    undo();
                  }
                }
              : null,
          child: SizedBox(
            height: style == TasbihStyle.fullscreen
                ? math.max(320, MediaQuery.sizeOf(context).height * .5)
                : 270,
            width: double.infinity,
            child: Center(
              child: Padding(padding: const EdgeInsets.all(12), child: face),
            ),
          ),
        ),
      ),
    );
    return _card(context, face);
  }
}

class _BeadsPainter extends CustomPainter {
  _BeadsPainter(this.color, this.horizontal, this.current);
  final Color color;
  final bool horizontal;
  final int current;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi * 2 / 12;
      final center = horizontal
          ? Offset(size.width * (i + .5) / 12, size.height / 2)
          : Offset(
              size.width / 2 + math.cos(angle) * (size.width / 2 - 17),
              size.height / 2 + math.sin(angle) * (size.height / 2 - 17),
            );
      final radius = horizontal ? math.min(11.0, size.width / 27) : 12.0;
      paint.shader = RadialGradient(
        colors: [Colors.white, color, const Color(0xFF795522)],
        stops: const [0, .4, 1],
        center: const Alignment(-.4, -.5),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, i == current % 12 ? radius + 2 : radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BeadsPainter oldDelegate) =>
      color != oldDelegate.color ||
      horizontal != oldDelegate.horizontal ||
      current != oldDelegate.current;
}
