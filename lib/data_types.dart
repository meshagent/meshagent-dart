// data_types.dart
/// We define a typedef for a constructor function that
/// takes JSON data and returns a [DataType] instance.
typedef DataTypeConstructor = DataType Function(Map<String, dynamic> data);

/// A global registry mapping a `type` string to a
/// factory constructor for the corresponding [DataType] subclass.
final Map<String, DataTypeConstructor> _dataTypes = {
  "int": (data) => IntDataType.fromJson(data),
  "date": (data) => DateDataType.fromJson(data),
  "text": (data) => TextDataType.fromJson(data),
  "json": (data) => JsonDataType.fromJson(data),
  "uuid": (data) => UuidDataType.fromJson(data),
  "vector": (data) => VectorDataType.fromJson(data),
  "float": (data) => FloatDataType.fromJson(data),
  "timestamp": (data) => TimestampDataType.fromJson(data),
  "binary": (data) => BinaryDataType.fromJson(data),
  "bool": (data) => BoolDataType.fromJson(data),
  "list": (data) => ListDataType.fromJson(data),
  "struct": (data) => StructDataType.fromJson(data),
};

/// Abstract base class for data types.
abstract class DataType {
  DataType({this.nullable, this.metadata});

  bool? nullable;
  Map<String, dynamic>? metadata;

  /// Convert this data type instance to a JSON object.
  Map<String, dynamic> toJson() {
    return {"nullable": nullable, "metadata": metadata};
  }

  /// Factory method: parse a JSON representation into a concrete [DataType].
  /// Looks up the correct subclass in [_dataTypes].
  static DataType fromJson(Map<String, dynamic> data) {
    final type = data['type'];
    final constructor = _dataTypes[type];
    if (constructor == null) {
      throw Exception("Unknown data type: $type");
    }
    return constructor(data);
  }
}

/// IntDataType
class BoolDataType extends DataType {
  BoolDataType({super.nullable, super.metadata}) : super();

  static BoolDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'bool') {
      throw Exception("Expected type 'bool', got '${data['type']}'");
    }
    return BoolDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'bool', ...super.toJson()};
  }

  @override
  String toString() {
    return "bool";
  }
}

/// IntDataType
class IntDataType extends DataType {
  IntDataType({super.nullable, super.metadata}) : super();

  static IntDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'int') {
      throw Exception("Expected type 'int', got '${data['type']}'");
    }
    return IntDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'int', ...super.toJson()};
  }

  @override
  String toString() {
    return "int";
  }
}

/// DateDataType
class DateDataType extends DataType {
  DateDataType({super.nullable, super.metadata}) : super();

  static DateDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'date') {
      throw Exception("Expected type 'date', got '${data['type']}'");
    }
    return DateDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'date', ...super.toJson()};
  }

  @override
  String toString() {
    return "date";
  }
}

/// JsonDataType
class JsonDataType extends DataType {
  JsonDataType({super.nullable, super.metadata}) : super();

  static JsonDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'json') {
      throw Exception("Expected type 'json', got '${data['type']}'");
    }
    return JsonDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'json', ...super.toJson()};
  }

  @override
  String toString() {
    return "json";
  }
}

/// FloatDataType
class FloatDataType extends DataType {
  FloatDataType({super.nullable, super.metadata}) : super();

  static FloatDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'float') {
      throw Exception("Expected type 'float', got '${data['type']}'");
    }
    return FloatDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'float', ...super.toJson()};
  }

  @override
  String toString() {
    return "float";
  }
}

/// FloatDataType
class TimestampDataType extends DataType {
  TimestampDataType({super.nullable, super.metadata}) : super();

  static TimestampDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'timestamp') {
      throw Exception("Expected type 'float', got '${data['type']}'");
    }
    return TimestampDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'timestamp', ...super.toJson()};
  }

  @override
  String toString() {
    return "timestamp";
  }
}

/// VectorDataType
class VectorDataType extends DataType {
  final int size;
  final DataType elementType;

  VectorDataType({required this.size, required this.elementType, super.nullable, super.metadata}) : super();

  static VectorDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'vector') {
      throw Exception("Expected type 'vector', got '${data['type']}'");
    }
    return VectorDataType(
      nullable: data["nullable"],
      metadata: data["metadata"],
      size: data['size'] as int,
      elementType: DataType.fromJson(data['element_type'] as Map<String, dynamic>),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'vector', 'size': size, 'element_type': elementType.toJson(), ...super.toJson()};
  }

  @override
  String toString() {
    return "vector<$elementType>[$size]";
  }
}

/// ListDataType
class ListDataType extends DataType {
  final DataType elementType;

  ListDataType({required this.elementType, super.nullable, super.metadata}) : super();

  static ListDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'list') {
      throw Exception("Expected type 'list', got '${data['type']}'");
    }
    return ListDataType(
      nullable: data["nullable"],
      metadata: data["metadata"],
      elementType: DataType.fromJson(data['element_type'] as Map<String, dynamic>),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'list', 'element_type': elementType.toJson(), ...super.toJson()};
  }

  @override
  String toString() {
    return "list<$elementType>";
  }
}

/// StructDataType
class StructDataType extends DataType {
  final Map<String, DataType> fields;

  StructDataType({required this.fields, super.nullable, super.metadata}) : super();

  static StructDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'struct') {
      throw Exception("Expected type 'struct', got '${data['type']}'");
    }
    final rawFields = data["fields"] as Map<String, dynamic>? ?? const {};
    return StructDataType(
      nullable: data["nullable"],
      metadata: data["metadata"],
      fields: rawFields.map((key, value) => MapEntry(key, DataType.fromJson(value as Map<String, dynamic>))),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'struct',
      'fields': {for (final entry in fields.entries) entry.key: entry.value.toJson()},
      ...super.toJson(),
    };
  }

  @override
  String toString() {
    return "struct{${fields.keys.join(", ")}}";
  }
}

/// TextDataType
class TextDataType extends DataType {
  TextDataType({super.nullable, super.metadata}) : super();

  static TextDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'text') {
      throw Exception("Expected type 'text', got '${data['type']}'");
    }
    return TextDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'text', ...super.toJson()};
  }

  @override
  String toString() {
    return "text";
  }
}

/// UuidDataType
class UuidDataType extends DataType {
  UuidDataType({super.nullable, super.metadata}) : super();

  static UuidDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'uuid') {
      throw Exception("Expected type 'uuid', got '${data['type']}'");
    }
    return UuidDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'uuid', ...super.toJson()};
  }

  @override
  String toString() {
    return "uuid";
  }
}

/// BinaryDataType
class BinaryDataType extends DataType {
  BinaryDataType({super.nullable, super.metadata}) : super();

  static BinaryDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'binary') {
      throw Exception("Expected type 'binary', got '${data['binary']}'");
    }
    return BinaryDataType(nullable: data["nullable"], metadata: data["metadata"]);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'binary', ...super.toJson()};
  }

  @override
  String toString() {
    return "binary";
  }
}
