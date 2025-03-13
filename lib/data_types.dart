// data_types.dart
/// We define a typedef for a constructor function that
/// takes JSON data and returns a [DataType] instance.
typedef DataTypeConstructor = DataType Function(Map<String, dynamic> data);

/// A global registry mapping a `type` string to a
/// factory constructor for the corresponding [DataType] subclass.
final Map<String, DataTypeConstructor> _dataTypes = {};

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
}

/// Register in the global registry
void _registerIntDataType() {
  _dataTypes["int"] = (data) => IntDataType.fromJson(data);
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
}

/// Register
void _registerDateDataType() {
  _dataTypes["date"] = (data) => DateDataType.fromJson(data);
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
}

/// Register
void _registerFloatDataType() {
  _dataTypes["float"] = (data) => FloatDataType.fromJson(data);
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
}

/// Register
void _registerVectorDataType() {
  _dataTypes["vector"] = (data) => VectorDataType.fromJson(data);
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
}

/// Register
void _registerTextDataType() {
  _dataTypes["text"] = (data) => TextDataType.fromJson(data);
}

/// Helper to register all data types at once.
void registerAllDataTypes() {
  _registerIntDataType();
  _registerDateDataType();
  _registerFloatDataType();
  _registerVectorDataType();
  _registerTextDataType();
}
