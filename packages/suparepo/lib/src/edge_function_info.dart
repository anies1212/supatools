/// Represents a detected Edge Function
class EdgeFunctionInfo {
  final String name;
  final String? description;

  const EdgeFunctionInfo({
    required this.name,
    this.description,
  });

  @override
  String toString() => 'EdgeFunctionInfo($name)';
}

/// Field definition for Edge Function request/response models
class EdgeFunctionFieldDef {
  final String name;
  final String dataType;
  final bool isRequired;

  const EdgeFunctionFieldDef({
    required this.name,
    required this.dataType,
    this.isRequired = true,
  });

  @override
  String toString() => 'EdgeFunctionFieldDef($name: $dataType, '
      'required: $isRequired)';
}

/// Error code definition for an Edge Function
class EdgeFunctionErrorDef {
  final String code;
  final int? statusCode;

  const EdgeFunctionErrorDef({required this.code, this.statusCode});

  @override
  String toString() => 'EdgeFunctionErrorDef($code, status: $statusCode)';
}

/// Model definition for an Edge Function (request + response + errors)
class EdgeFunctionModelDef {
  final List<EdgeFunctionFieldDef>? request;
  final List<EdgeFunctionFieldDef>? response;
  final List<EdgeFunctionErrorDef>? errors;

  const EdgeFunctionModelDef({
    this.request,
    this.response,
    this.errors,
  });

  /// Merges a YAML-defined model with an auto-detected one.
  ///
  /// YAML wins per field group (request/response/errors); auto-detection fills
  /// any group the YAML omits. This keeps auto-detected error/response classes
  /// even when the YAML overrides only `request`. Returns null when both are
  /// null.
  static EdgeFunctionModelDef? merge(
    EdgeFunctionModelDef? yaml,
    EdgeFunctionModelDef? auto,
  ) {
    if (yaml == null) return auto;
    if (auto == null) return yaml;
    return EdgeFunctionModelDef(
      request: yaml.request ?? auto.request,
      response: yaml.response ?? auto.response,
      errors: yaml.errors ?? auto.errors,
    );
  }
}
