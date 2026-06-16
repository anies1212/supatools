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

/// A field in an Edge Function success-response DTO tree.
///
/// Models the shape of a single property in the success response, recovered
/// from a TypeScript `interface` (or, as a fallback, a `jsonResponse({...})`
/// call). Each field is either a scalar ([dartScalarType] set) or a nested
/// object ([objectFields] set). [isList] wraps the resolved type in
/// `List<...>`; [nullable] appends `?` (recovered from `T | null`).
class EdgeFunctionResponseField {
  final String jsonKey;
  final bool nullable;
  final bool isList;

  /// Set for scalar fields: e.g. `String`, `int`, `double`, `bool`,
  /// `Map<String, dynamic>`, `dynamic`.
  final String? dartScalarType;

  /// Set for object fields: the nested object's fields. A nested Freezed
  /// class is generated for these.
  final List<EdgeFunctionResponseField>? objectFields;

  const EdgeFunctionResponseField({
    required this.jsonKey,
    this.nullable = false,
    this.isList = false,
    this.dartScalarType,
    this.objectFields,
  }) : assert(
          (dartScalarType == null) != (objectFields == null),
          'exactly one of dartScalarType / objectFields must be set',
        );

  bool get isObject => objectFields != null;

  @override
  String toString() => 'EdgeFunctionResponseField($jsonKey, '
      'scalar: $dartScalarType, object: ${objectFields != null}, '
      'list: $isList, nullable: $nullable)';
}

/// Model definition for an Edge Function (request + response + errors)
class EdgeFunctionModelDef {
  final List<EdgeFunctionFieldDef>? request;
  final List<EdgeFunctionFieldDef>? response;
  final List<EdgeFunctionErrorDef>? errors;

  /// Rich success-response shape recovered from an exported TypeScript
  /// interface (preferred) or inferred from the `jsonResponse({...})` call.
  ///
  /// When set, a Freezed response DTO (`<function>_response.dart`) is generated
  /// and the typed client method returns that DTO. Supersedes the flat
  /// [response] heuristic, which is kept for backward compatibility.
  final List<EdgeFunctionResponseField>? responseObject;

  const EdgeFunctionModelDef({
    this.request,
    this.response,
    this.errors,
    this.responseObject,
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
      responseObject: yaml.responseObject ?? auto.responseObject,
    );
  }
}
