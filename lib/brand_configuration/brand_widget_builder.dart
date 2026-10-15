import 'package:flutter_flavor_test/brand_configuration/app_brand.dart';

T brandMaybeWhen<T>({required T Function() orElse, T Function()? globex}) {
  return switch (AppBrand.current) {
    AppBrand.globex => globex?.call() ?? orElse(),
    _ => orElse(),
  };
}
