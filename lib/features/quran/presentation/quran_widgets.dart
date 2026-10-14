import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app_appearance.dart';

const qTeal = Color(0xFF007D85);
const qNavy = Color(0xFF0C2057);
const qGold = Color(0xFFB38C42);
const qCream = Color(0xFFFFFCF7);

TextStyle qText(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color? color,
}) => TextStyle(
  fontFamily: 'QuranUI',
  fontSize: size,
  height: 1.55,
  fontWeight: weight,
  color:
      color ??
      (AppPalette.of(context).dark ? AppPalette.of(context).heading : qNavy),
);

class QuranHeader extends StatelessWidget {
  const QuranHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.dark = false,
    this.height = 150,
    this.onBack,
    this.actions = const [],
    this.center = false,
  });
  final String title, subtitle;
  final bool dark, center;
  final double height;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        height +
        (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 1) * 70,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/quran/header_${center
              ? 'home'
              : dark
              ? 'dark'
              : 'light'}.png',
          fit: BoxFit.cover,
        ),
        if (center)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x00FFFFFF),
                  Color(0x66FFFFFF),
                  Color(0x00FFFFFF),
                ],
              ),
            ),
          ),
        Positioned(
          left: 18,
          right: 18,
          top: 12,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                if (onBack != null)
                  QCircleButton(
                    icon: Icons.chevron_left,
                    label: 'رجوع',
                    onTap: onBack,
                  ),
                const Spacer(),
                ...actions.expand((w) => [w, const SizedBox(width: 8)]),
              ],
            ),
          ),
        ),
        Positioned(
          right: center ? 30 : 25,
          left: center
              ? 30
              : title.length > 24
              ? 90
              : 135,
          top: center ? 32 : null,
          bottom: center ? null : 21,
          child: Column(
            crossAxisAlignment: center
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: center ? TextAlign.center : TextAlign.right,
                style: qText(
                  context,
                  size: center
                      ? 24
                      : title.length > 24
                      ? 18
                      : 20,
                  weight: FontWeight.w800,
                  color: dark ? Colors.white : qNavy,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: center ? TextAlign.center : TextAlign.right,
                style: qText(
                  context,
                  size: 12,
                  color: dark ? Colors.white : const Color(0xFF607C91),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class QCircleButton extends StatelessWidget {
  const QCircleButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.size = 38,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: AppPalette.of(context).surface,
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: const Color(0x22000000),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: 23,
            color:
                color ??
                (AppPalette.of(context).dark
                    ? AppPalette.of(context).heading
                    : qNavy),
          ),
        ),
      ),
    ),
  );
}

class QCard extends StatelessWidget {
  const QCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppPalette.of(context).dark
            ? AppPalette.of(context).border
            : const Color(0xFFE8E9EC),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07000000),
          blurRadius: 9,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class QMedallion extends StatelessWidget {
  const QMedallion({
    super.key,
    required this.number,
    this.filled = false,
    this.size = 44,
    this.textColor,
  });
  final int number;
  final bool filled;
  final double size;
  final Color? textColor;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _MedallionPainter(filled),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(size * .17),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$number',
              textDirection: TextDirection.ltr,
              style: qText(
                context,
                size: size * .32,
                weight: FontWeight.w700,
                color:
                    textColor ??
                    (filled ? Colors.white : AppPalette.of(context).heading),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MedallionPainter extends CustomPainter {
  _MedallionPainter(this.filled);
  final bool filled;
  Path outline(Size size, double inset) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - inset;
    final path = Path();
    for (var i = 0; i <= 192; i++) {
      final angle = i / 192 * math.pi * 2 - math.pi / 2;
      final r = radius * (.91 + .09 * math.cos(8 * angle));
      final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (filled) {
      canvas.drawPath(
        outline(size, 3),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFD0A65A), Color(0xFF8B611D)],
          ).createShader(Offset.zero & size),
      );
    }
    final pen = Paint()
      ..color = qGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(outline(size, 1), pen);
    canvas.drawPath(outline(size, 3.8), pen..strokeWidth = .7);
    canvas.drawPath(outline(size, 6), pen..strokeWidth = .5);
  }

  @override
  bool shouldRepaint(_MedallionPainter oldDelegate) =>
      oldDelegate.filled != filled;
}

class QSearchField extends StatelessWidget {
  const QSearchField({
    super.key,
    this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmit,
    this.onTap,
    this.readOnly = false,
    this.trailing,
  });
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged, onSubmit;
  final VoidCallback? onTap;
  final bool readOnly;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => QCard(
    padding: EdgeInsets.zero,
    child: TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmit,
      style: qText(context, size: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: qText(
          context,
          size: 13,
          color: AppPalette.of(context).muted,
        ),
        suffixIcon: const Icon(Icons.search, color: qNavy),
        prefixIcon: trailing,
        border: InputBorder.none,
        isDense: true,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
  );
}

class QSegments extends StatelessWidget {
  const QSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppPalette.of(context).neutral,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: List.generate(
        labels.length,
        (index) => Expanded(
          child: Material(
            color: selected == index ? qTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              onTap: () => onSelect(index),
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: qText(
                    context,
                    size: 12,
                    color: selected == index ? Colors.white : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class QSectionTitle extends StatelessWidget {
  const QSectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: qText(context, size: 17, weight: FontWeight.w800),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: Text(action!, style: qText(context, size: 12, color: qTeal)),
        ),
    ],
  );
}

class QPrimaryButton extends StatelessWidget {
  const QPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.chevron_left,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData icon;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: qTeal,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    label: Text(
      label,
      style: qText(
        context,
        color: Colors.white,
        size: 13,
        weight: FontWeight.w700,
      ),
    ),
  );
}

void qNotice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontFamily: 'QuranUI'),
        ),
      ),
    );
