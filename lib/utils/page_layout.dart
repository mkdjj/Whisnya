import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const pageHorizontalPadding = 12.0;
const firstContentGap = 12.0;
const compactBreakpoint = 700.0;
const expandedBreakpoint = 1100.0;

bool isCompactWidth(double width) => width < compactBreakpoint;

bool isMediumWidth(double width) =>
    width >= compactBreakpoint && width < expandedBreakpoint;

bool isExpandedWidth(double width) => width >= expandedBreakpoint;

double responsiveHorizontalPadding(double width) {
  if (isCompactWidth(width)) return pageHorizontalPadding;
  if (isMediumWidth(width)) return 20;
  return 32;
}

double responsiveMaxContentWidth(double width) {
  if (isCompactWidth(width)) return width;
  if (isMediumWidth(width)) return 760;
  return 920;
}

double homeListTop(BuildContext context) {
  return MediaQuery.paddingOf(context).top + kToolbarHeight + firstContentGap;
}

SystemUiOverlayStyle appSystemOverlayStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
  );
}

class AdaptivePage extends StatelessWidget {
  const AdaptivePage({required this.child, this.maxWidth, super.key});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: responsiveHorizontalPadding(width),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? responsiveMaxContentWidth(width),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
