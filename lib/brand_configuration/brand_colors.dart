import 'dart:ui';

import 'package:flutter_flavor_test/brand_configuration/app_brand.dart';

abstract final class BrandColors {
  static Color primary = switch (AppBrand.current) {
    AppBrand.acme => Color(0xFF2C6B4F),
    AppBrand.globex => Color(0xFF02505A),
  };

  static Color seed = primary;
}
