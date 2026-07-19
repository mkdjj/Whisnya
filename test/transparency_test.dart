import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/utils/transparency.dart';

void main() {
  test('converts between stored opacity and displayed transparency', () {
    expect(opacityToTransparency(1), 0);
    expect(opacityToTransparency(0), 1);
    expect(transparencyToOpacity(0), 1);
    expect(transparencyToOpacity(1), 0);
    expect(opacityToTransparency(2), 0);
    expect(transparencyToOpacity(-1), 1);
  });
}
