import 'package:flutter/material.dart';

enum AppBreakpoint { compact, mobile, tablet }

class AppSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
}

class AppResponsiveData {
  final double width;
  final double textScale;
  final Orientation orientation;

  const AppResponsiveData({
    required this.width,
    required this.textScale,
    required this.orientation,
  });

  AppBreakpoint get breakpoint {
    if (width < 360) return AppBreakpoint.compact;
    if (width <= 600) return AppBreakpoint.mobile;
    return AppBreakpoint.tablet;
  }

  bool get isCompact => breakpoint == AppBreakpoint.compact;
  bool get isMobile => breakpoint != AppBreakpoint.tablet;
  bool get isTablet => breakpoint == AppBreakpoint.tablet;

  EdgeInsets get pagePadding {
    if (isCompact) return const EdgeInsets.all(AppSpacing.sm);
    if (isTablet) return const EdgeInsets.all(AppSpacing.lg);
    return const EdgeInsets.all(AppSpacing.md);
  }

  int gridColumns({
    int compact = 1,
    int mobile = 2,
    int tablet = 4,
  }) {
    switch (breakpoint) {
      case AppBreakpoint.compact:
        return compact;
      case AppBreakpoint.mobile:
        return mobile;
      case AppBreakpoint.tablet:
        return tablet;
    }
  }
}

class AppResponsive {
  static AppResponsiveData of(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return AppResponsiveData(
      width: mediaQuery.size.width,
      textScale: mediaQuery.textScaler.scale(1),
      orientation: mediaQuery.orientation,
    );
  }
}

class AppConstrainedContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;

  const AppConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? responsive.pagePadding,
          child: child,
        ),
      ),
    );
  }
}

class AdaptiveActionGroup extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double compactBreakpoint;

  const AdaptiveActionGroup({
    super.key,
    required this.children,
    this.spacing = AppSpacing.sm,
    this.compactBreakpoint = 420,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < compactBreakpoint;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int? compactColumns;
  final int? mobileColumns;
  final int? tabletColumns;
  final double spacing;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.compactColumns,
    this.mobileColumns,
    this.tabletColumns,
    this.spacing = AppSpacing.sm,
  });

  @override
  Widget build(BuildContext context) {
    final responsive = AppResponsive.of(context);
    final columns = responsive.gridColumns(
      compact: compactColumns ?? 1,
      mobile: mobileColumns ?? 2,
      tablet: tabletColumns ?? 4,
    );

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: responsive.isTablet ? 1.4 : 1.25,
      ),
      itemBuilder: (context, index) => children[index],
    );
  }
}
