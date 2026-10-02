import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Deterministic test typography for behavior/semantics tests. These tests do
/// not certify the production fonts' layout or fetch fonts from the network.
Future<void> loadTestFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final flutterPackage = (config['packages'] as List).cast<Map>().singleWhere(
    (package) => package['name'] == 'flutter',
  );
  final flutterRoot = configFile.absolute.uri.resolve(
    '${flutterPackage['rootUri']}/',
  );
  final font = ByteData.sublistView(
    File.fromUri(
      flutterRoot.resolve('../flutter_tools/static/Ahem.ttf'),
    ).readAsBytesSync(),
  );
  final manifest = const StandardMessageCodec().encodeMessage({
    for (final family in ['Manrope', 'JetBrainsMono'])
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ])
        '$family-$weight.ttf': [
          {'asset': '$family-$weight.ttf'},
        ],
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final asset = utf8.decode(message!.buffer.asUint8List());
        if (asset == 'AssetManifest.bin') return manifest;
        if (asset.startsWith('Manrope-') || asset.startsWith('JetBrainsMono-')) {
          return font;
        }
        return null;
      });
  for (final weight in [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  ]) {
    GoogleFonts.manrope(fontWeight: weight);
    GoogleFonts.jetBrainsMono(fontWeight: weight);
  }
  await GoogleFonts.pendingFonts();
}
