import 'package:test/test.dart';
import 'package:json_schema/json_schema.dart';
import '../lib/schema.dart'; // This should contain the translated MeshSchema, ElementType, etc.

void main() {
  test('test_schema_validates_tag_names', () {
    expect(() {
      MeshSchema(
        rootTagName: "sample2",
        elements: [
          ElementType(tagName: "sample", description: "test", properties: [])
        ],
      );
    }, throwsA(TypeMatcher<MeshSchemaValidationException>()));
  });

  test('test_schema_validates_value_names', () {
    // Here we pass an invalid value type "bad"
    expect(() {
      MeshSchema(
        rootTagName: "sample2",
        elements: [
          ElementType(tagName: "sample", description: "test", properties: [
            ValueProperty(
                name: "string",
                description: "",
                type: SimpleValue.fromString("bad") ??
                    (throw MeshSchemaValidationException("bad")))
          ])
        ],
      );
    }, throwsA(TypeMatcher<MeshSchemaValidationException>()));
  });

  test('test_schema_validates_child_tag_names', () {
    // child_tag_names=["blah"] but "blah" element is not defined
    expect(() {
      MeshSchema(
        rootTagName: "sample2",
        elements: [
          ElementType(tagName: "sample", description: "test", properties: [
            ChildProperty(
                name: "children", description: "", childTagNames: ["blah"])
          ])
        ],
      );
    }, throwsA(TypeMatcher<MeshSchemaValidationException>()));
  });

  test('test_schema_requires_properties', () {
    final s = MeshSchema(rootTagName: "sample", elements: [
      ElementType(tagName: "sample", description: "test", properties: [
        ValueProperty(name: "prop", description: "desc", type: SimpleValue.number)
      ])
    ]);

    final schemaMap = s.toJson();
    final schema = JsonSchema.create(schemaMap);

    // Valid object
    var result = schema.validate({
      "sample": {"prop": 1}
    });
    expect(result.isValid, isTrue);

    // extra prop at top-level or invalid structure
    result = schema.validate({
      "smple": {"test": 1},
      "sample": 1
    });
    expect(result.isValid, isFalse);

    // missing required property
    result = schema.validate({});
    expect(result.isValid, isFalse);
  });

  test('test_nested_schema_object', () {
    final s = MeshSchema(rootTagName: "sample", elements: [
      ElementType(tagName: "sample", description: "test", properties: [
        ValueProperty(
            name: "sample2", description: "desc", type: SimpleValue.number)
      ])
    ]);

    final schema = JsonSchema.create(s.toJson());

    // Valid
    var result = schema.validate({
      "sample": {"sample2": 1}
    });
    expect(result.isValid, isTrue);

    // Invalid type
    result = schema.validate({
      "sample": {"sample2": "test"}
    });
    expect(result.isValid, isFalse);
  });

  test('test_nested_array_values', () {
    final s = MeshSchema(rootTagName: "sample", elements: [
      ElementType(tagName: "sample", description: "test", properties: [
        ChildProperty(
            name: "children",
            description: "desc",
            childTagNames: ["string_tag"])
      ]),
      ElementType(tagName: "string_tag", description: "", properties: [
        ValueProperty(name: "value", description: "", type: SimpleValue.string)
      ])
    ]);

    final schema = JsonSchema.create(s.toJson());

    // Valid
    var result = schema.validate({
      "sample": {
        "children": [
          {
            "string_tag": {"value": "test"}
          }
        ]
      }
    });
    expect(result.isValid, isTrue);

    // Invalid: children is an object instead of array or invalid structure
    result = schema.validate({
      "sample": {"children": {}}
    });
    expect(result.isValid, isFalse);
  });

  test('test_nested_array_objects', () {
    final s = MeshSchema(rootTagName: "sample", elements: [
      ElementType(tagName: "sample", description: "test", properties: [
        ChildProperty(
            name: "children", description: "desc", childTagNames: ["sample2"])
      ]),
      ElementType(tagName: "sample2", description: "desc2", properties: [
        ValueProperty(
            name: "prop", description: "desc", type: SimpleValue.number)
      ])
    ]);

    final schema = JsonSchema.create(s.toJson());

    // Valid
    var result = schema.validate({
      "sample": {
        "children": [
          {
            "sample2": {"prop": 1}
          }
        ]
      }
    });
    expect(result.isValid, isTrue);

    // Invalid: empty object in array
    result = schema.validate({
      "sample": {
        "children": [{}]
      }
    });
    expect(result.isValid, isFalse);

    // Missing required property
    result = schema.validate({"sample": {}});
    expect(result.isValid, isFalse);
  });

  test('test_nested_array_multi_objects', () {
    final s = MeshSchema(rootTagName: "sample", elements: [
      ElementType(tagName: "sample", description: "test", properties: [
        ChildProperty(
            name: "children",
            description: "desc",
            childTagNames: ["child1", "child2"])
      ]),
      ElementType(tagName: "child1", description: "child", properties: [
        ValueProperty(
            name: "prop", description: "desc", type: SimpleValue.number)
      ]),
      ElementType(tagName: "child2", description: "child", properties: [
        ValueProperty(
            name: "prop", description: "desc", type: SimpleValue.string)
      ]),
    ]);

    final schema = JsonSchema.create(s.toJson());

    // Valid
    var result = schema.validate({
      "sample": {
        "children": [
          {
            "child1": {"prop": 1}
          },
          {
            "child2": {"prop": "test"}
          }
        ]
      }
    });
    expect(result.isValid, isTrue);

    // Invalid: wrong structure for child1
    result = schema.validate({
      "sample": {
        "children": [
          {"child1": "test"}
        ]
      }
    });
    expect(result.isValid, isFalse);

    // Missing required property
    result = schema.validate({"sample": {}});
    expect(result.isValid, isFalse);
  });

  test('test_roundtrip_schema_json', () {
    final s = MeshSchema(rootTagName: "sample", elements: [
      ElementType(description: "test", tagName: "sample", properties: [
        ChildProperty(
            name: "children",
            description: "desc",
            childTagNames: ["child1", "child2"])
      ]),
      ElementType(tagName: "child1", description: "child", properties: [
        ValueProperty(
            name: "prop", description: "desc", type: SimpleValue.number)
      ]),
      ElementType(tagName: "child2", description: "child", properties: [
        ValueProperty(
            name: "prop", description: "desc", type: SimpleValue.string)
      ]),
    ]);

    final json1 = s.toJson();
    final s2 = MeshSchema.fromJson(json1);
    final json2 = s2.toJson();

    // Compare the two JSON structures as strings for equality
    expect(json2.toString(), equals(json1.toString()));
  });
}
