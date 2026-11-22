import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;

/// Adds the bundled fonts' OFL texts to Flutter's license page.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, asset) in const [
      ('Inter (font)', 'assets/fonts/OFL-Inter.txt'),
      ('JetBrains Mono (font)', 'assets/fonts/OFL-JetBrainsMono.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        pkg,
      ], await rootBundle.loadString(asset));
    }
  });
}
