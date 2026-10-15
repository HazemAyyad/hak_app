import 'package:flutter/material.dart';
import '../../../app_appearance.dart';

const rTeal = Color(0xFF075158);
const rGold = Color(0xFF94601D);
const rCream = Color(0xFFFFFCF6);

class ReligiousColors {
  ReligiousColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background =>
      dark ? const Color(0xFF0C2028) : const Color(0xFFFFFDF9);
  Color get card => dark ? const Color(0xFF142D33) : const Color(0xFFFFFDF9);
  Color get heading => dark ? const Color(0xFFB6DEE0) : rTeal;
  Color get text => dark ? const Color(0xFFE2ECEE) : const Color(0xFF293845);
  Color get muted => dark ? const Color(0xFFABBDC4) : const Color(0xFF65717F);
  Color get subtle => dark ? const Color(0xFF203A3E) : const Color(0xFFF6F2E9);
  Color get border => dark ? const Color(0xFF294348) : const Color(0xFFF2EFE7);
}

TextStyle rText(
  BuildContext context,
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w500,
  double height = 1.55,
}) => TextStyle(
  fontFamily: AppearanceScope.of(context).font.family,
  fontFamilyFallback: const ['AmiriQuran'],
  fontSize: size,
  height: height,
  fontWeight: weight,
  color: color ?? ReligiousColors(context).heading,
);

String rAsset(String name) => 'assets/religious/$name.png';

class ReligiousCard extends StatelessWidget {
  const ReligiousCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.ornament = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding, margin;
  final VoidCallback? onTap;
  final bool ornament;
  @override
  Widget build(BuildContext context) {
    final colors = ReligiousColors(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: .7),
        boxShadow: colors.dark
            ? []
            : [
                const BoxShadow(
                  color: Color(0x0C645132),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            foregroundPainter: ornament ? _VerseOrnament() : null,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _VerseOrnament extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = rGold.withValues(alpha: .32)
      ..strokeWidth = .6
      ..style = PaintingStyle.stroke;
    for (final (x, y, sx, sy) in [
      (7.0, 7.0, 1.0, 1.0),
      (size.width - 7, 7.0, -1.0, 1.0),
      (7.0, size.height - 7, 1.0, -1.0),
      (size.width - 7, size.height - 7, -1.0, -1.0),
    ]) {
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(sx, sy);
      canvas.drawPath(
        Path()
          ..moveTo(0, 37)
          ..lineTo(0, 11)
          ..quadraticBezierTo(0, 0, 11, 0)
          ..lineTo(37, 0),
        paint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(3, 26)
          ..cubicTo(26, 26, 26, 3, 3, 3)
          ..cubicTo(3, 26, 26, 26, 26, 3)
          ..moveTo(9, 9)
          ..lineTo(31, 31),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ReligiousRoundButton extends StatelessWidget {
  const ReligiousRoundButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.filled = false,
    this.size = 34,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool filled;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: SizedBox(
        width: size + 8,
        height: size + 8,
        child: Center(
          child: Material(
            color: filled ? rTeal : ReligiousColors(context).subtle,
            shape: const CircleBorder(),
            child: InkResponse(
              onTap: onTap,
              radius: (size + 8) / 2,
              child: SizedBox.square(
                dimension: size,
                child: Icon(
                  icon,
                  textDirection: TextDirection.ltr,
                  size: size * .55,
                  color: filled
                      ? Colors.white
                      : color ?? ReligiousColors(context).heading,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ReligiousHeader extends StatelessWidget {
  const ReligiousHeader({
    super.key,
    required this.title,
    this.subtitle = '',
    this.image = 'sunnah',
    this.light = false,
    this.onBack,
    this.onSaved,
    this.onShare,
    this.breadcrumb,
    this.tall = false,
  });
  final String title, subtitle, image;
  final String? breadcrumb;
  final bool light, tall;
  final VoidCallback? onBack, onSaved, onShare;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final color = light ? rTeal : Colors.white;
    final width = MediaQuery.sizeOf(context).width;
    double measured(
      String text,
      double size,
      double maxWidth, {
      FontWeight weight = FontWeight.w500,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: rText(context, size, weight: weight),
        ),
        textDirection: TextDirection.rtl,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: maxWidth);
      return painter.height;
    }

    final requiredHeight =
        top +
        29 +
        (onBack != null || onSaved != null ? 44 : 8) +
        measured(title, light ? 18 : 20, width * .75, weight: FontWeight.w800) +
        (subtitle.isEmpty ? 0 : 5 + measured(subtitle, 11, width * .65)) +
        (breadcrumb == null ? 0 : measured(breadcrumb!, 9, width - 32));
    final baseHeight =
        (tall
            ? 205
            : light
            ? 167
            : 185) +
        top +
        (scale - 1) * 85;
    return Container(
      height: requiredHeight > baseHeight ? requiredHeight : baseHeight,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(rAsset('header_$image')),
          fit: BoxFit.cover,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: light
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    rCream.withValues(alpha: .12),
                    rCream.withValues(alpha: .94),
                  ],
                  stops: const [0, .38, 1],
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, top + 9, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null || onSaved != null)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      if (onBack != null)
                        _whiteButton(
                          context,
                          Icons.chevron_left,
                          'رجوع',
                          onBack!,
                        ),
                      const Spacer(),
                      if (onSaved != null)
                        _whiteButton(
                          context,
                          Icons.bookmark_border,
                          'المفضلة',
                          onSaved!,
                        ),
                      if (onShare != null) ...[
                        const SizedBox(width: 6),
                        _whiteButton(
                          context,
                          Icons.share_outlined,
                          'مشاركة',
                          onShare!,
                        ),
                      ],
                    ],
                  ),
                ),
              const Spacer(),
              if (breadcrumb != null)
                Text(
                  breadcrumb!,
                  textAlign: TextAlign.right,
                  style: rText(context, 9, color: color.withValues(alpha: .9)),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .75,
                  ),
                  child: Text(
                    title,
                    textAlign: TextAlign.right,
                    style: rText(
                      context,
                      light ? 18 : 20,
                      color: color,
                      weight: FontWeight.w800,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * .65,
                    ),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: rText(context, 11, color: color, height: 1.6),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _whiteButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback action,
  ) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: Material(
        shape: const CircleBorder(),
        color: const Color(0xFFFFFEFA),
        child: InkResponse(
          onTap: action,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(
              icon,
              color: icon == Icons.chevron_left ? rTeal : rGold,
              size: 22,
            ),
          ),
        ),
      ),
    ),
  );
}

class ReligiousSearch extends StatelessWidget {
  const ReligiousSearch({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onFilter,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilter;
  @override
  Widget build(BuildContext context) => ReligiousCard(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Row(
      children: [
        if (onFilter != null)
          IconButton(
            onPressed: onFilter,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            iconSize: 21,
            icon: const Icon(Icons.tune),
            tooltip: 'تصفية النتائج',
            color: ReligiousColors(context).heading,
          ),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: rText(context, 12, color: ReligiousColors(context).text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: rText(
                context,
                11,
                color: ReligiousColors(context).muted,
              ),
              filled: true,
              fillColor: ReligiousColors(context).subtle.withValues(alpha: .6),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
        controller.text.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.search, color: rTeal),
              )
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
                tooltip: 'مسح البحث',
              ),
      ],
    ),
  );
}

class ReligiousPill extends StatelessWidget {
  const ReligiousPill({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });
  final String text;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: Material(
      color: selected ? rTeal : ReligiousColors(context).subtle,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            text,
            style: rText(
              context,
              10,
              color: selected ? Colors.white : ReligiousColors(context).heading,
            ),
          ),
        ),
      ),
    ),
  );
}

class ReligiousEmpty extends StatelessWidget {
  const ReligiousEmpty({
    super.key,
    required this.text,
    this.icon = Icons.search_off,
    this.action,
    this.onAction,
  });
  final String text;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(icon, size: 38, color: rGold),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: rText(context, 14)),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class ReligiousSectionCard extends StatelessWidget {
  const ReligiousSectionCard({
    super.key,
    required this.title,
    required this.text,
    this.source,
    this.icon = Icons.menu_book_outlined,
  });
  final String title, text;
  final String? source;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ReligiousCard(
    margin: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: ReligiousColors(context).subtle,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: rGold, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: rText(context, 14, weight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SelectableText(
          text,
          textAlign: TextAlign.right,
          style: rText(
            context,
            14,
            color: ReligiousColors(context).text,
            height: 1.85,
          ),
        ),
        if (source != null && source!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              source!,
              style: rText(context, 9, color: ReligiousColors(context).muted),
            ),
          ),
      ],
    ),
  );
}

/// Uses the app's existing destinations, with this section's reference palette.
class ReligiousNavigationBar extends StatelessWidget {
  const ReligiousNavigationBar({super.key, required this.onSelected});
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final colors = ReligiousColors(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12665533),
            blurRadius: 14,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: Row(
            children: [
              for (final (index, entry) in const [
                (Icons.home_outlined, 'الرئيسية'),
                (Icons.menu_book_outlined, 'القرآن'),
                (Icons.eco_outlined, 'الأذكار'),
                (Icons.explore_outlined, 'القبلة'),
                (Icons.more_horiz, 'المزيد'),
              ].indexed)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: index == 4,
                    label: entry.$2,
                    child: Material(
                      color: index == 4 ? colors.subtle : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () => onSelected(index),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                entry.$1,
                                color: index == 4 ? rGold : colors.heading,
                                size: 26,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.$2,
                                style: rText(
                                  context,
                                  10,
                                  color: index == 4 ? rGold : colors.heading,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
