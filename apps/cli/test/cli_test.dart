import 'package:test/test.dart';
import 'package:cli/cli.dart';

void main() {
  test('cli version is set', () {
    expect(cliVersion, isNotEmpty);
  });
}
