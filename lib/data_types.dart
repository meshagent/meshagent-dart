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
  "vector": (data) => VectorDataType.fromJson(data),
  "float": (data) => FloatDataType.fromJson(data),
  "timestamp": (data) => TimestampDataType.fromJson(data),
  "binary": (data) => BinaryDataType.fromJson(data),
};

/// Abstract base class for data types.
abstract class DataType {
  DataType();

  /// Convert this data type instance to a JSON object.
  Map<String, dynamic> toJson();

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
class IntDataType extends DataType {
  IntDataType() : super();

  static IntDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'int') {
      throw Exception("Expected type 'int', got '${data['type']}'");
    }
    return IntDataType();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'int'};
  }

  @override
  String toString() {
    return "int";
  }
}

/// DateDataType
class DateDataType extends DataType {
  DateDataType() : super();

  static DateDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'date') {
      throw Exception("Expected type 'date', got '${data['type']}'");
    }
    return DateDataType();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'date'};
  }

  @override
  String toString() {
    return "date";
  }
}

/// FloatDataType
class FloatDataType extends DataType {
  FloatDataType() : super();

  static FloatDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'float') {
      throw Exception("Expected type 'float', got '${data['type']}'");
    }
    return FloatDataType();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'float'};
  }

  @override
  String toString() {
    return "float";
  }
}

/// FloatDataType
class TimestampDataType extends DataType {
  TimestampDataType() : super();

  static TimestampDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'timestamp') {
      throw Exception("Expected type 'float', got '${data['type']}'");
    }
    return TimestampDataType();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'timestamp'};
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

  VectorDataType({required this.size, required this.elementType}) : super();

  static VectorDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'vector') {
      throw Exception("Expected type 'vector', got '${data['type']}'");
    }
    return VectorDataType(size: data['size'] as int, elementType: DataType.fromJson(data['element_type'] as Map<String, dynamic>));
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'vector', 'size': size, 'element_type': elementType.toJson()};
  }

  @override
  String toString() {
    return "vector<$elementType>[$size]";
  }
}

/// TextDataType
class TextDataType extends DataType {
  TextDataType() : super();

  static TextDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'text') {
      throw Exception("Expected type 'text', got '${data['type']}'");
    }
    return TextDataType();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'text'};
  }

  @override
  String toString() {
    return "text";
  }
}

/// BinaryDataType
class BinaryDataType extends DataType {
  BinaryDataType() : super();

  static BinaryDataType fromJson(Map<String, dynamic> data) {
    if (data['type'] != 'binary') {
      throw Exception("Expected type 'binary', got '${data['binary']}'");
    }
    return BinaryDataType();
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'binary'};
  }

  @override
  String toString() {
    return "binary";
  }
}
