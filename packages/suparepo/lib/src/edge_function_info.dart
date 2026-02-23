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

/// Edge Functionのエラーコード定義
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
}
