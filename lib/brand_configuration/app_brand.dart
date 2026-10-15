import 'package:flutter/services.dart' show appFlavor;

const String _kBrandFlavor = appFlavor ?? 'acme';

enum AppBrand {
  acme._('acme'),
  globex._('globex');

  const AppBrand._(this.flavor);
  final String flavor;

  static AppBrand get current => isGlobex ? AppBrand.globex : AppBrand.acme;

  static bool get isGlobex => _kBrandFlavor == 'globex';

  static bool get isAcme => _kBrandFlavor == 'acme';
}
