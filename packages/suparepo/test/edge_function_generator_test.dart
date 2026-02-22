import 'package:suparepo/src/edge_function_generator.dart';
import 'package:suparepo/src/edge_function_info.dart';
import 'package:suparepo/src/repository_generator.dart';
import 'package:test/test.dart';

void main() {
  late EdgeFunctionGenerator generator;

  setUp(() {
    generator = EdgeFunctionGenerator();
  });

  group('EdgeFunctionGenerator', () {
    test('型定義なしクライアント生成', () {
      final functions = [
        EdgeFunctionInfo(name: 'send-email'),
        EdgeFunctionInfo(
          name: 'process-payment',
          description: 'Process a payment',
        ),
      ];

      final output = generator.generateEdgeFunctionClient(
        functions,
      );

      expect(output, contains('class SupabaseEdgeFunctionClient'));
      expect(output, contains('SupabaseClient _client'));

      // send-email -> sendEmail method
      expect(output, contains('Future<FunctionResponse> sendEmail'));
      expect(output, contains('Map<String, dynamic>? body'));
      expect(output, contains('Map<String, String>? headers'));
      expect(
        output,
        contains("_client.functions.invoke('send-email'"),
      );

      // process-payment -> processPayment method
      expect(
        output,
        contains('Future<FunctionResponse> processPayment'),
      );
      expect(
        output,
        contains('/// Process a payment'),
      );
    });

    test('型定義ありクライアント生成（request + response）', () {
      final functions = [
        EdgeFunctionInfo(name: 'send-email'),
      ];
      final modelDefs = {
        'send-email': EdgeFunctionModelDef(
          request: [
            EdgeFunctionFieldDef(
              name: 'to',
              dataType: 'text',
              isRequired: true,
            ),
            EdgeFunctionFieldDef(
              name: 'subject',
              dataType: 'text',
              isRequired: true,
            ),
            EdgeFunctionFieldDef(
              name: 'body_html',
              dataType: 'text',
              isRequired: false,
            ),
          ],
          response: [
            EdgeFunctionFieldDef(
              name: 'success',
              dataType: 'bool',
              isRequired: true,
            ),
            EdgeFunctionFieldDef(
              name: 'message_id',
              dataType: 'text',
              isRequired: false,
            ),
          ],
        ),
      };

      final output = generator.generateEdgeFunctionClient(
        functions,
        modelDefs: modelDefs,
      );

      // Request model class
      expect(output, contains('class SendEmailRequest'));
      expect(output, contains('final String to;'));
      expect(output, contains('final String subject;'));
      expect(output, contains('final String? bodyHtml;'));
      expect(output, contains('required this.to'));
      expect(output, contains('required this.subject'));
      expect(output, contains('this.bodyHtml'));
      expect(output, contains('SendEmailRequest.fromJson'));
      expect(output, contains('toJson()'));

      // Response model class
      expect(output, contains('class SendEmailResponse'));
      expect(output, contains('final bool success;'));
      expect(output, contains('final String? messageId;'));

      // Typed method
      expect(
        output,
        contains('Future<SendEmailResponse> sendEmail'),
      );
      expect(
        output,
        contains('required SendEmailRequest request'),
      );
      expect(output, contains('request.toJson()'));
      expect(
        output,
        contains('SendEmailResponse.fromJson'),
      );
    });

    test('型定義あり（requestのみ）', () {
      final functions = [
        EdgeFunctionInfo(name: 'notify'),
      ];
      final modelDefs = {
        'notify': EdgeFunctionModelDef(
          request: [
            EdgeFunctionFieldDef(
              name: 'user_id',
              dataType: 'uuid',
              isRequired: true,
            ),
          ],
        ),
      };

      final output = generator.generateEdgeFunctionClient(
        functions,
        modelDefs: modelDefs,
      );

      expect(output, contains('class NotifyRequest'));
      // responseがないのでFunctionResponse返却
      expect(
        output,
        contains('Future<FunctionResponse> notify'),
      );
      expect(
        output,
        contains('required NotifyRequest request'),
      );
    });

    test('型定義なしと型定義ありの混在', () {
      final functions = [
        EdgeFunctionInfo(name: 'untyped-func'),
        EdgeFunctionInfo(name: 'typed-func'),
      ];
      final modelDefs = {
        'typed-func': EdgeFunctionModelDef(
          response: [
            EdgeFunctionFieldDef(
              name: 'result',
              dataType: 'text',
              isRequired: true,
            ),
          ],
        ),
      };

      final output = generator.generateEdgeFunctionClient(
        functions,
        modelDefs: modelDefs,
      );

      // untyped-func is untyped
      expect(
        output,
        contains('Future<FunctionResponse> untypedFunc'),
      );

      // typed-func has response model
      expect(output, contains('class TypedFuncResponse'));
      expect(
        output,
        contains('Future<TypedFuncResponse> typedFunc'),
      );
    });

    test('ヘッダーコメントが含まれる', () {
      final output = generator.generateEdgeFunctionClient([]);

      expect(
        output,
        contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
      );
      expect(output, contains('Generated by suparepo'));
      expect(
        output,
        contains(
          "import 'package:supabase_flutter/supabase_flutter.dart'",
        ),
      );
    });

    test('空の関数リストでも正常に生成', () {
      final output = generator.generateEdgeFunctionClient([]);

      expect(output, contains('class SupabaseEdgeFunctionClient'));
      expect(output, contains('const SupabaseEdgeFunctionClient'));
    });

    test('モデルのtoJsonでoptionalフィールドはifガード付き', () {
      final functions = [
        EdgeFunctionInfo(name: 'test-func'),
      ];
      final modelDefs = {
        'test-func': EdgeFunctionModelDef(
          request: [
            EdgeFunctionFieldDef(
              name: 'required_field',
              dataType: 'text',
              isRequired: true,
            ),
            EdgeFunctionFieldDef(
              name: 'optional_field',
              dataType: 'int4',
              isRequired: false,
            ),
          ],
        ),
      };

      final output = generator.generateEdgeFunctionClient(
        functions,
        modelDefs: modelDefs,
      );

      expect(
        output,
        contains("'required_field': requiredField,"),
      );
      expect(
        output,
        contains(
          "if (optionalField != null) "
          "'optional_field': optionalField",
        ),
      );
    });

    test('プロバイダーはインライン生成しない', () {
      final functions = [
        EdgeFunctionInfo(name: 'send-email'),
      ];

      final output = generator.generateEdgeFunctionClient(
        functions,
      );

      expect(output, isNot(contains('@Riverpod')));
      expect(
        output,
        isNot(contains('riverpod_annotation')),
      );
      expect(output, isNot(contains('part ')));
    });
  });

  group('RepositoryGenerator.generateSupabaseClientProvider', () {
    late RepositoryGenerator repoGenerator;

    setUp(() {
      repoGenerator = RepositoryGenerator();
    });

    test('EdgeFunctionClient プロバイダーが含まれる', () {
      final output = repoGenerator.generateSupabaseClientProvider(
        edgeFunctionClientImport: 'package:data/edge_function_client.dart',
      );

      expect(
        output,
        contains(
          "import 'package:data/edge_function_client.dart';",
        ),
      );
      expect(output, contains('@Riverpod(keepAlive: true)'));
      expect(
        output,
        contains(
          'SupabaseEdgeFunctionClient '
          'supabaseEdgeFunctionClient(Ref ref)',
        ),
      );
      expect(
        output,
        contains('ref.watch(supabaseClientProvider)'),
      );
      expect(
        output,
        contains('SupabaseEdgeFunctionClient(client)'),
      );
    });

    test('RpcClient プロバイダーが含まれる', () {
      final output = repoGenerator.generateSupabaseClientProvider(
        rpcClientImport: 'package:data/rpc_client.dart',
      );

      expect(
        output,
        contains("import 'package:data/rpc_client.dart';"),
      );
      expect(
        output,
        contains(
          'SupabaseRpcClient supabaseRpcClient(Ref ref)',
        ),
      );
    });

    test('RPC + EdgeFunction 両方のプロバイダーが含まれる', () {
      final output = repoGenerator.generateSupabaseClientProvider(
        rpcClientImport: 'package:data/rpc_client.dart',
        edgeFunctionClientImport: 'package:data/edge_function_client.dart',
      );

      expect(
        output,
        contains('supabaseClient(Ref ref)'),
      );
      expect(
        output,
        contains('supabaseRpcClient(Ref ref)'),
      );
      expect(
        output,
        contains('supabaseEdgeFunctionClient(Ref ref)'),
      );
    });

    test('引数なしの場合はsupabaseClientのみ', () {
      final output = repoGenerator.generateSupabaseClientProvider();

      expect(
        output,
        contains('supabaseClient(Ref ref)'),
      );
      expect(
        output,
        isNot(contains('supabaseRpcClient')),
      );
      expect(
        output,
        isNot(contains('supabaseEdgeFunctionClient')),
      );
    });
  });
}
