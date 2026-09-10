import 'package:flutter/material.dart';

/// A small, code-drawn body cue for exercise-category navigation.
///
/// The figure is intentionally diagrammatic rather than anatomical. The muted
/// silhouette provides orientation while the theme accent identifies the body
/// area associated with [group].
class MuscleGroupIllustration extends StatelessWidget {
  final String group;
  final Color silhouetteColor;
  final Color highlightColor;

  const MuscleGroupIllustration({
    super.key,
    required this.group,
    required this.silhouetteColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        painter: _MuscleGroupPainter(
          group: group,
          silhouetteColor: silhouetteColor,
          highlightColor: highlightColor,
        ),
        size: const Size(76, 88),
      ),
    );
  }
}

class _MuscleGroupPainter extends CustomPainter {
  final String group;
  final Color silhouetteColor;
  final Color highlightColor;

  const _MuscleGroupPainter({
    required this.group,
    required this.silhouetteColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 76;
    final scaleY = size.height / 88;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final body =
        Paint()
          ..color = silhouetteColor
          ..style = PaintingStyle.fill;
    final highlight =
        Paint()
          ..color = highlightColor
          ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(38, 9), 7, body);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(26, 18, 24, 38),
        const Radius.circular(10),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(17, 21, 8, 38),
        const Radius.circular(4),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(51, 21, 8, 38),
        const Radius.circular(4),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(27, 53, 10, 32),
        const Radius.circular(5),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(39, 53, 10, 32),
        const Radius.circular(5),
      ),
      body,
    );

    switch (group) {
      case 'Chest':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(29, 23, 18, 12),
            const Radius.circular(5),
          ),
          highlight,
        );
      case 'Back':
        final back =
            Path()
              ..moveTo(27, 23)
              ..lineTo(49, 23)
              ..lineTo(45, 43)
              ..lineTo(31, 43)
              ..close();
        canvas.drawPath(back, highlight);
      case 'Shoulders':
        canvas.drawCircle(const Offset(25, 24), 6, highlight);
        canvas.drawCircle(const Offset(51, 24), 6, highlight);
      case 'Arms':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(17, 27, 8, 25),
            const Radius.circular(4),
          ),
          highlight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(51, 27, 8, 25),
            const Radius.circular(4),
          ),
          highlight,
        );
      case 'Legs':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(27, 56, 10, 25),
            const Radius.circular(5),
          ),
          highlight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(39, 56, 10, 25),
            const Radius.circular(5),
          ),
          highlight,
        );
      case 'Core':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(32, 36, 12, 16),
            const Radius.circular(4),
          ),
          highlight,
        );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MuscleGroupPainter oldDelegate) {
    return group != oldDelegate.group ||
        silhouetteColor != oldDelegate.silhouetteColor ||
        highlightColor != oldDelegate.highlightColor;
  }
}
