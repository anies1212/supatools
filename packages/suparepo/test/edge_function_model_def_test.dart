import 'package:suparepo/src/edge_function_info.dart';
import 'package:test/test.dart';

void main() {
  group('EdgeFunctionModelDef.merge', () {
    final request = [
      const EdgeFunctionFieldDef(name: 'birth_year', dataType: 'int4'),
    ];
    final response = [
      const EdgeFunctionFieldDef(name: 'ok', dataType: 'bool'),
    ];
    final errors = [
      const EdgeFunctionErrorDef(code: 'rate_limited', statusCode: 429),
    ];

    test('returns null when both are null', () {
      expect(EdgeFunctionModelDef.merge(null, null), isNull);
    });

    test('returns auto when yaml is null', () {
      final auto = EdgeFunctionModelDef(request: request, errors: errors);
      final merged = EdgeFunctionModelDef.merge(null, auto);
      expect(merged, same(auto));
    });

    test('returns yaml when auto is null', () {
      final yaml = EdgeFunctionModelDef(request: request);
      final merged = EdgeFunctionModelDef.merge(yaml, null);
      expect(merged, same(yaml));
    });

    test('yaml request wins, auto fills errors/response', () {
      final yamlRequest = [
        const EdgeFunctionFieldDef(name: 'birth_year', dataType: 'int4'),
      ];
      final yaml = EdgeFunctionModelDef(request: yamlRequest);
      final auto = EdgeFunctionModelDef(
        request: request,
        response: response,
        errors: errors,
      );

      final merged = EdgeFunctionModelDef.merge(yaml, auto)!;
      // YAML-specified request takes precedence.
      expect(merged.request, same(yamlRequest));
      // Groups omitted by YAML are filled from auto-detection.
      expect(merged.response, same(response));
      expect(merged.errors, same(errors));
    });

    test('auto request used when yaml omits it', () {
      final yaml = EdgeFunctionModelDef(errors: errors);
      final auto = EdgeFunctionModelDef(request: request);
      final merged = EdgeFunctionModelDef.merge(yaml, auto)!;
      expect(merged.request, same(request));
      expect(merged.errors, same(errors));
    });
  });
}
