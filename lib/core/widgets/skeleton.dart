import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Lightweight shimmer: one AnimationController drives a gradient
/// ShaderMask over all skeleton children. Stops animating when the user
/// has requested reduced motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.shimmer);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerLow;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = _c.value;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-1 + 3 * t - 1, 0),
              end: Alignment(1 + 3 * t - 1, 0),
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(rect),
            child: child,
          );
        },
      ),
    );
  }
}

/// Placeholder block used inside a [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox(
      {super.key, this.width, this.height, this.radius = Radii.sm});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton matching the media grid layout.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.columns = 3, this.count = 18});

  final int columns;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Dimens.gridSpacing),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: Dimens.gridSpacing,
          crossAxisSpacing: Dimens.gridSpacing,
        ),
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonBox(radius: Radii.sm),
      ),
    );
  }
}

/// Skeleton matching the album card grid on the home screen.
class SkeletonAlbums extends StatelessWidget {
  const SkeletonAlbums({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: Space.lg,
          crossAxisSpacing: Space.lg,
          childAspectRatio: 0.82,
        ),
        itemCount: 6,
        itemBuilder: (_, __) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SkeletonBox(radius: Radii.lg)),
            SizedBox(height: Space.sm),
            SkeletonBox(width: 100, height: 14),
            SizedBox(height: Space.xs),
            SkeletonBox(width: 60, height: 12),
          ],
        ),
      ),
    );
  }
}
