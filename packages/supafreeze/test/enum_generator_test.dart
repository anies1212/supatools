import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/config_loader.dart';
import 'package:supafreeze/src/enum_generator.dart';

void main() {
  late EnumGenerator generator;

  setUp(() {
    generator = EnumGenerator();
    TypeMapper.clearEnums();
  });

  group('EnumGenerator', () {
    group('getEnumClassName', () {
      test('converts snake_case to PascalCase', () {
        expect(generator.getEnumClassName('campaign_type'), 'CampaignType');
      });

      test('handles single word', () {
        expect(generator.getEnumClassName('status'), 'Status');
      });

      test('handles multiple underscores', () {
        expect(
          generator.getEnumClassName('user_account_status'),
          'UserAccountStatus',
        );
      });
    });

    group('getEnumFileName', () {
      test('generates correct file name', () {
        expect(
          generator.getEnumFileName('campaign_type'),
          'campaign_type.supafreeze.dart',
        );
      });

      test('converts PascalCase to snake_case', () {
        expect(
          generator.getEnumFileName('CampaignType'),
          'campaign_type.supafreeze.dart',
        );
      });
    });

    group('generateEnumFile', () {
      test('generates basic enum correctly', () {
        final enumInfo = EnumInfo(
          name: 'campaign_type',
          values: ['normal', 'trial'],
        );

        final result = generator.generateEnumFile(enumInfo);

        expect(result, contains('enum CampaignType {'));
        expect(result, contains("  normal('normal'),"));
        expect(result, contains("  trial('trial');"));
        expect(result, contains('const CampaignType(this.value);'));
        expect(result, contains('final String value;'));
        expect(result, contains('String toJson() => value;'));
        expect(result, contains('static CampaignType fromJson'));
      });

      test('generates enum with many values', () {
        final enumInfo = EnumInfo(
          name: 'order_status',
          values: ['pending', 'processing', 'shipped', 'delivered'],
        );

        final result = generator.generateEnumFile(enumInfo);

        expect(result, contains('enum OrderStatus {'));
        expect(result, contains("  pending('pending'),"));
        expect(result, contains("  processing('processing'),"));
        expect(result, contains("  shipped('shipped'),"));
        expect(result, contains("  delivered('delivered');"));
      });

      test('sanitizes hyphenated enum values', () {
        final enumInfo = EnumInfo(
          name: 'status',
          values: ['in-progress', 'not-started'],
        );

        final result = generator.generateEnumFile(enumInfo);

        expect(result, contains("  inProgress('in-progress'),"));
        expect(result, contains("  notStarted('not-started');"));
      });

      test('sanitizes enum values starting with digit', () {
        final enumInfo = EnumInfo(
          name: 'priority',
          values: ['1_high', '2_medium', '3_low'],
        );

        final result = generator.generateEnumFile(enumInfo);

        expect(result, contains(r"  $1High('1_high'),"));
        expect(result, contains(r"  $2Medium('2_medium'),"));
        expect(result, contains(r"  $3Low('3_low');"));
      });

      test('sanitizes reserved word enum values', () {
        final enumInfo = EnumInfo(
          name: 'keyword_type',
          values: ['class', 'default', 'void'],
        );

        final result = generator.generateEnumFile(enumInfo);

        expect(result, contains(r"  class$('class'),"));
        expect(result, contains(r"  default$('default'),"));
        expect(result, contains(r"  void$('void');"));
      });

      test('contains GENERATED CODE header', () {
        final enumInfo = EnumInfo(
          name: 'status',
          values: ['active'],
        );

        final result = generator.generateEnumFile(enumInfo);

        expect(result, contains('// GENERATED CODE - DO NOT MODIFY BY HAND'));
        expect(result, contains('// coverage:ignore-file'));
      });
    });

    group('generateAllEnumFiles', () {
      test('generates files for all enums', () {
        final enums = [
          EnumInfo(name: 'campaign_type', values: ['normal', 'trial']),
          EnumInfo(name: 'order_status', values: ['pending', 'shipped']),
        ];

        final result = generator.generateAllEnumFiles(enums);

        expect(result.length, 2);
        expect(result.keys, contains('campaign_type.supafreeze.dart'));
        expect(result.keys, contains('order_status.supafreeze.dart'));
      });
    });

    group('generateBarrelFile', () {
      test('exports all enum files', () {
        final enums = [
          EnumInfo(name: 'campaign_type', values: ['normal', 'trial']),
          EnumInfo(name: 'order_status', values: ['pending', 'shipped']),
        ];

        final result = generator.generateBarrelFile(enums);

        expect(
          result,
          contains("export 'campaign_type.supafreeze.dart';"),
        );
        expect(
          result,
          contains("export 'order_status.supafreeze.dart';"),
        );
        expect(result, contains('// GENERATED CODE'));
      });
    });

    group('dart_mappable format', () {
      late EnumGenerator mappableGen;

      setUp(() {
        mappableGen = EnumGenerator(format: ModelFormat.dartMappable);
      });

      test('generates a @MappableEnum with mapper part', () {
        final result = mappableGen.generateEnumFile(
          EnumInfo(name: 'campaign_type', values: ['normal', 'trial']),
        );

        expect(
          result,
          contains("import 'package:dart_mappable/dart_mappable.dart';"),
        );
        expect(
          result,
          contains("part 'campaign_type.supafreeze.mapper.dart';"),
        );
        expect(result, contains('@MappableEnum()'));
        expect(result, contains('enum CampaignType {'));
        expect(result, contains('normal,'));
        expect(result, contains('trial;'));
      });

      test('adds @MappableValue when the identifier differs', () {
        final result = mappableGen.generateEnumFile(
          EnumInfo(name: 'state', values: ['in-progress', 'done']),
        );

        expect(result, contains("@MappableValue('in-progress')"));
        expect(result, contains('inProgress,'));
        expect(result, contains('done;'));
      });
    });
  });
}
