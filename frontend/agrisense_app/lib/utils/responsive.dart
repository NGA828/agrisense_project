import 'package:flutter/material.dart';

/// Responsive utility helper for AgriSense AI.
/// Provides breakpoint checks, dynamic value pickers, layout wrappers, and dynamic grid calculators.
class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  static const double mobileMax = 600.0;
  static const double tabletMax = 1024.0;

  const Responsive({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  /// Check screen categories
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileMax;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileMax &&
      MediaQuery.of(context).size.width < tabletMax;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletMax;

  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= 900.0;

  /// Pick responsive value according to current screen width
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    if (width >= tabletMax && desktop != null) {
      return desktop;
    }
    if (width >= mobileMax && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  /// Calculate responsive grid columns
  static int gridColumns(
    BuildContext context, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 4,
  }) {
    return value<int>(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= tabletMax && desktop != null) {
          return desktop!;
        }
        if (constraints.maxWidth >= mobileMax && tablet != null) {
          return tablet!;
        }
        return mobile;
      },
    );
  }
}

/// A wrapper widget that caps content width on wide screens (tablet/desktop)
/// and centers it with comfortable responsive padding.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxContentWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxContentWidth = 1200.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    EdgeInsets resolvedPadding;

    if (padding != null) {
      resolvedPadding = padding!.resolve(Directionality.of(context));
    } else {
      resolvedPadding = EdgeInsets.symmetric(
        horizontal: width >= Responsive.mobileMax ? 24.0 : 16.0,
        vertical: 12.0,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(
          padding: resolvedPadding,
          child: child,
        ),
      ),
    );
  }
}
