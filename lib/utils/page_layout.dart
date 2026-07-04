import 'package:flutter/material.dart';

const pageHorizontalPadding = 12.0;
const firstContentGap = 12.0;

double homeListTop(BuildContext context) {
  return MediaQuery.paddingOf(context).top + kToolbarHeight + firstContentGap;
}
