import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<LicenseEntry>> interEntries() async {
    final entries = await LicenseRegistry.licenses.toList();
    return entries.where((e) => e.packages.contains('Inter')).toList();
  }

  test(
    'registers the Inter licence exactly once, even when called repeatedly',
    () async {
      registerDesignLicenses();
      registerDesignLicenses();
      registerDesignLicenses();

      final entries = await interEntries();
      expect(entries, hasLength(1));
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(text, contains('The Inter Project Authors'));
    },
  );

  test('the licence asset is the one referenced by the constant', () {
    expect(interLicenseAsset, 'assets/fonts/OFL.txt');
  });
}
