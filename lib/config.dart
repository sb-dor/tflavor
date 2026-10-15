abstract class Config {
  static const String brand = String.fromEnvironment(
    'BRAND',
    defaultValue: 'acme',
  );

  static const environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );
}
