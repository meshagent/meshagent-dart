import 'dart:convert';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('RequiredTable round-trips full Arrow schema fidelity', () {
    final schema = ArrowSchema(
      [
        ArrowField(
          name: 'annotations',
          type: ArrowListType(
            ArrowField(
              name: 'item',
              type: ArrowStructType([
                ArrowField(name: 'key', type: ArrowUtf8Type(), nullable: false, metadata: {'role': 'key'}),
                ArrowField(name: 'value', type: ArrowUtf8Type(large: true), metadata: {'role': 'value'}),
              ]),
            ),
          ),
          metadata: {'field': 'annotations'},
        ),
        ArrowField(
          name: 'labels',
          type: ArrowDictionaryType(id: 1, indexType: ArrowIntType(bitWidth: 32, signed: true), valueType: ArrowUtf8Type()),
        ),
        ArrowField(name: 'amount', type: ArrowDecimalType(bitWidth: 128, precision: 20, scale: 4)),
      ],
      metadata: {'schema': 'required-table'},
    );
    final requirement = RequiredTable(
      name: 'records',
      namespace: ['team'],
      schema: schema,
      scalarIndexes: ['amount'],
      fullTextSearchIndexes: ['annotations'],
      vectorIndexes: ['embedding'],
    );

    final encoded = requirement.toJson();
    final decoded = Requirement.fromJson(encoded);
    final encodedSchema = ArrowIpcSchema(base64Decode(encoded['schema'] as String)).schema;

    expect(decoded, isA<RequiredTable>());
    final decodedTable = decoded as RequiredTable;
    expect(decodedTable.name, 'records');
    expect(decodedTable.namespace, ['team']);
    expect(decodedTable.scalarIndexes, ['amount']);
    expect(decodedTable.fullTextSearchIndexes, ['annotations']);
    expect(decodedTable.vectorIndexes, ['embedding']);
    expect(decodedTable.schema.metadata, {'schema': 'required-table'});
    expect(encodedSchema.metadata, {'schema': 'required-table'});

    final annotations = decodedTable.schema.fields[0];
    expect(annotations.name, 'annotations');
    expect(annotations.metadata, {'field': 'annotations'});
    expect(annotations.type, isA<ArrowListType>());
    final item = (annotations.type as ArrowListType).valueField;
    final itemType = item.type as ArrowStructType;
    expect(itemType.fields[0].nullable, isFalse);
    expect(itemType.fields[0].metadata, {'role': 'key'});
    final valueType = itemType.fields[1].type as ArrowUtf8Type;
    expect(valueType.large, isTrue);

    final labelsType = decodedTable.schema.fields[1].type as ArrowDictionaryType;
    expect(labelsType.indexType.bitWidth, 32);
    expect(labelsType.valueType, isA<ArrowUtf8Type>());

    final amountType = decodedTable.schema.fields[2].type as ArrowDecimalType;
    expect(amountType.bitWidth, 128);
    expect(amountType.precision, 20);
    expect(amountType.scale, 4);
  });
}
