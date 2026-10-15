import 'package:flutter_flavor_test/brand_configuration/app_brand.dart';

class BrandConfig {
  const BrandConfig._({required this.appName, required this.logoAsset});

  static const _acme = BrandConfig._(
    appName: 'Acme',
    logoAsset: 'assets/brands/acme/logo.png',
  );
  static const _globex = BrandConfig._(
    appName: 'Globex',
    logoAsset: 'assets/brands/globex/logo.png',
  );

  static BrandConfig current = switch (AppBrand.current) {
    AppBrand.acme => _acme,
    AppBrand.globex => _globex,
  };

  final String appName;
  final String logoAsset;
}
