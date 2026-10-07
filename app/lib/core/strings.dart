class Strings {
  const Strings(this.language);
  final String language;
  bool get es => language == 'es';
  String t(String spanish, String english) => es ? spanish : english;
  String status(String status) => switch (status) {
    'exact' => t('Exacto', 'Exact'),
    'approximate' => t('Aproximación', 'Approximation'),
    'empty' => t('Sin solución real', 'No real solution'),
    'unresolved' => t('No resuelto', 'Unresolved'),
    'domainError' => t('Fuera del dominio', 'Outside domain'),
    'timeout' => t('Tiempo agotado', 'Timed out'),
    'unsupported' => t('Operación no soportada', 'Unsupported operation'),
    _ => t('No se pudo completar', 'Could not complete'),
  };
  String operation(String op) => switch (op) {
    'evaluate' => t('Calcular', 'Calculate'),
    'exact' => t('Exacto', 'Exact'),
    'simplify' => t('Simplificar', 'Simplify'),
    'expand' => t('Expandir', 'Expand'),
    'factor' => t('Factorizar', 'Factor'),
    'solve' => t('Resolver', 'Solve'),
    'differentiate' => t('Derivar', 'Differentiate'),
    'integrate' => t('Integrar', 'Integrate'),
    'limit' => t('Límite', 'Limit'),
    _ => op,
  };
}
