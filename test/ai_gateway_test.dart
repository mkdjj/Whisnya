import 'package:flutter_test/flutter_test.dart';
import 'package:whisnya/services/ai/ai_gateway.dart';
import 'package:whisnya/services/ai_service.dart';

void main() {
  test('AiService implements the replaceable AI gateway', () {
    expect(AiService(), isA<AiGateway>());
  });
}
