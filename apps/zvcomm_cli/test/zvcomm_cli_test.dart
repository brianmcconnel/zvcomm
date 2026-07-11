import 'package:test/test.dart';
import 'package:zvcomm_cli/zvcomm_cli.dart';

void main() {
  test('cli version is set', () {
    expect(cliVersion, isNotEmpty);
  });
}
