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
  String toString() =>
      'EdgeFunctionFieldDef($name: $dataType, '
      'required: $isRequired)';
}

/// Model definition for an Edge Function (request + response)
class EdgeFunctionModelDef {
  final List<EdgeFunctionFieldDef>? request;
  final List<EdgeFunctionFieldDef>? response;

  const EdgeFunctionModelDef({this.request, this.response});
}
