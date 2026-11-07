import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/incident.dart';
import '../theme/app_theme.dart';

/// Unified iOS icon widget that guarantees fixed bounds, zero layout shift,
/// and crisp rendering of CupertinoIcons glyphs.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 18,
    this.color = AppColors.textPrimary,
    this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          icon,
          size: size,
          color: color,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

/// Unified Apple Home / Settings style rounded icon container.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.boxSize = 36,
    this.iconSize = 18,
    this.borderRadius = 11,
    this.circular = false,
    this.showBorder = false,
  });

  final IconData icon;
  final Color color;
  final double boxSize;
  final double iconSize;
  final double borderRadius;
  final bool circular;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(color: color.withValues(alpha: 0.32), width: 0.6)
            : null,
      ),
      alignment: Alignment.center,
      child: AppIcon(
        icon,
        size: iconSize,
        color: color,
      ),
    );
  }
}

/// Native iOS pressable wrapper with subtle scale + opacity animation and haptics.
class IosPressable extends StatefulWidget {
  const IosPressable({
    super.key,
    required this.child,
    this.onTap,
    this.enableHaptics = true,
    this.scaleDown = 0.98,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enableHaptics;
  final double scaleDown;

  @override
  State<IosPressable> createState() => _IosPressableState();
}

class _IosPressableState extends State<IosPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        if (widget.enableHaptics) {
          HapticFeedback.lightImpact();
        }
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Elevated iOS hero / overlay card.
/// Uses a clean matte surface by default for 60/120fps scrolling performance;
/// pass [enableBlur] = true only for floating HUD overlays over the map.
class IosGlassCard extends StatelessWidget {
  const IosGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.color,
    this.borderColor,
    this.blurSigma = 20,
    this.enableBlur = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;
  final double blurSigma;
  final bool enableBlur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final bg = color ?? AppColors.card;
    final border = borderColor ?? AppColors.cardBorder;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: border, width: 0.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    if (enableBlur) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    }

    if (onTap != null) {
      return IosPressable(onTap: onTap, child: content);
    }
    return content;
  }
}

/// Calm, solid iOS surface card (Apple Home / Settings grouped inset style).
class IosSurfaceCard extends StatelessWidget {
  const IosSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
    this.color = AppColors.card,
    this.borderColor = AppColors.cardBorder,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: child,
    );
    if (onTap != null) {
      return IosPressable(onTap: onTap, child: box);
    }
    return box;
  }
}

/// Capsule status / severity / mode pill.
class IosStatusPill extends StatelessWidget {
  const IosStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.pulsingDot = false,
    this.solid = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool pulsingDot;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    final bg = solid ? color : color.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: solid
            ? null
            : Border.all(color: color.withValues(alpha: 0.34), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsingDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            AppIcon(icon!, size: 11.5, color: fg),
            const SizedBox(width: 4.5),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.25,
            ),
          ),
        ],
      ),
    );
  }
}

/// Apple Home / Weather section header with optional right action button.
class IosSectionHeader extends StatelessWidget {
  const IosSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.35,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              onPressed: () {
                HapticFeedback.selectionClick();
                onAction!();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const AppIcon(
                    CupertinoIcons.chevron_right,
                    size: 12,
                    color: AppColors.primaryGreen,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Finite entrance fade + slide animation (safe for WidgetTester.pumpAndSettle).
class IosFadeIn extends StatelessWidget {
  const IosFadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 220),
    this.offsetY = 8,
  });

  final Widget child;
  final Duration duration;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * offsetY),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Clean iOS skeleton placeholder card for loading states.
class IosSkeletonCard extends StatelessWidget {
  const IosSkeletonCard({
    super.key,
    this.height = 110,
    this.borderRadius = 18,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 120,
            height: 11,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Container(
            width: 190,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Container(
            width: 150,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter overlay that renders sleek iOS Vision-style YOLO bounding boxes.
class YoloBoxPainter extends CustomPainter {
  YoloBoxPainter(this.boxes);

  final List<DetectionBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final isFire = box.label.toLowerCase().contains('fire');
      final color = isFire ? AppColors.dangerRed : AppColors.warningOrange;

      final bool isNormalized =
          box.x2 <= 1.05 && box.y2 <= 1.05 && box.x1 <= 1.05 && box.y1 <= 1.05;
      final left = (isNormalized ? box.x1 * size.width : box.x1)
          .clamp(4.0, size.width - 20.0);
      final top = (isNormalized ? box.y1 * size.height : box.y1)
          .clamp(4.0, size.height - 20.0);
      final right = (isNormalized ? box.x2 * size.width : box.x2)
          .clamp(left + 16.0, size.width - 4.0);
      final bottom = (isNormalized ? box.y2 * size.height : box.y2)
          .clamp(top + 16.0, size.height - 4.0);

      final rect = Rect.fromLTRB(left, top, right, bottom);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.14)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, fillPaint);

      final strokePaint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(rrect, strokePaint);

      final textSpan = TextSpan(
        text:
            ' ${box.label.toUpperCase()} ${(box.confidence * 100).toStringAsFixed(0)}% ',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          (top - tp.height - 6).clamp(2.0, size.height - tp.height - 4),
          tp.width + 8,
          tp.height + 4,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(badgeRect, Paint()..color = color);
      tp.paint(
        canvas,
        Offset(badgeRect.left + 4, badgeRect.top + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant YoloBoxPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}

String formatRelativeOrShortTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60 && diff.inSeconds >= 0) {
    return 'Just now';
  }
  if (diff.inMinutes < 60 && diff.inMinutes >= 0) {
    return '${diff.inMinutes}m ago';
  }
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$dd.$mm · $hh:$min';
}
