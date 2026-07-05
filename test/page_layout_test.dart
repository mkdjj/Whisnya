import 'package:ai_role_chat/utils/page_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies responsive widths', () {
    expect(isCompactWidth(699), isTrue);
    expect(isMediumWidth(700), isTrue);
    expect(isMediumWidth(1099), isTrue);
    expect(isExpandedWidth(1100), isTrue);
  });

  test('keeps mobile tight and desktop bounded', () {
    expect(responsiveHorizontalPadding(360), pageHorizontalPadding);
    expect(responsiveMaxContentWidth(360), 360);
    expect(responsiveMaxContentWidth(900), 760);
    expect(responsiveMaxContentWidth(1400), 920);
  });
}
