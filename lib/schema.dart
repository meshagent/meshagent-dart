class MeshSchemaValidationException implements Exception {
  final String message;
  MeshSchemaValidationException(this.message);

  @override
  String toString() => '$message';
}

enum SimpleValue {
  number('number'),
  string('string'),
  nullValue('null'),
  boolean('boolean');

  final String value;
  const SimpleValue(this.value);

  static SimpleValue? fromString(String val) {
    for (var v in SimpleValue.values) {
      if (v.value == val) return v;
    }
    return null;
  }
}

class MeshSchema {
  final String _rootTagName;
  final List<ElementType> _elements;
  final Map<String, ElementType> elementsByTagName = {};

  MeshSchema({required String rootTagName, required List<ElementType> elements})
      : _rootTagName = rootTagName,
        _elements = elements {
    for (final t in elements) {
      if (elementsByTagName.containsKey(t.tagName)) {
        throw MeshSchemaValidationException(
            "${t.tagName} was found more than once in tags");
      }
      elementsByTagName[t.tagName] = t;
    }

    if (!elementsByTagName.containsKey(rootTagName)) {
      throw MeshSchemaValidationException("$rootTagName was not found in tags");
    }

    validate();
  }

  factory MeshSchema.fromJson(Map<String, dynamic> json) {
    final elements = <ElementType>[];

    String rootTagRef = json["\$root_tag_ref"];
    final prefix = "#/\$defs/";
    // emulate removeprefix
    String rootTagName = rootTagRef.startsWith(prefix)
        ? rootTagRef.substring(prefix.length)
        : rootTagRef;

    final defs = json["\$defs"] as Map;

    for (var elementJson in defs.values) {
      elements.add(ElementType.fromJson(elementJson));
    }

    return MeshSchema(rootTagName: rootTagName, elements: elements);
  }

  Map<String, dynamic> toJson() {
    final defs = {};
    for (final t in elements) {
      defs[t.tagName] = t.toJson();
    }

    final rootElementJson = root.toJson();
    // root.toJson() structure:
    // we want:
    // {
    //  "$root_tag_ref": "#/$defs/"+_rootTagName,
    //  **root,
    //  "$defs": defs
    // }

    final result = {"\$root_tag_ref": "#/\$defs/$_rootTagName", "\$defs": defs};

    // Merge root into result
    for (var entry in rootElementJson.entries) {
      result[entry.key] = entry.value;
    }

    return result;
  }

  ElementType element(String name) {
    return elementsByTagName[name]!;
  }

  void validate() {
    for (final e in _elements) {
      e.validate(this);
    }
  }

  ElementType get root => elementsByTagName[_rootTagName]!;

  List<ElementType> get elements => _elements;
}

abstract class ElementProperty {
  final String name;
  final String? description;

  ElementProperty({required this.name, this.description});

  void validate(MeshSchema schema);

  Map toJson();
}

class ValueProperty extends ElementProperty {
  final SimpleValue type;
  final List<dynamic>? enumValues;

  ValueProperty(
      {required super.name,
      super.description,
      required this.type,
      this.enumValues});

  @override
  void validate(MeshSchema schema) {
    // In Python it checked if type in SimpleValue members.
    // Here we already have an enum, so no real validation needed.
    // But we can ensure that _type is always a valid SimpleValue.
    // Just trust the enum for now.
  }

  @override
  Map toJson() {
    return {
      name: {
        "type": type.value,
        if (description != null) "description": description,
        if (enumValues != null) "enum": enumValues,
      }
    };
  }
}

class ChildProperty extends ElementProperty {
  final List<String> _childTagNames;

  ChildProperty(
      {required super.name,
      super.description,
      required List<String> childTagNames,
      this.ordered = false})
      : _childTagNames = childTagNames;
  final bool ordered;

  @override
  void validate(MeshSchema schema) {
    for (final item in _childTagNames) {
      // make sure there is an element that matches
      schema.element(item);
    }
  }

  bool isTagAllowed(String tagName) => _childTagNames.contains(tagName);

  List<String> get childTagNames => _childTagNames;

  @override
  Map<String, dynamic> toJson() {
    var base = {};
    if (description != null) {
      base["description"] = description;
    }
    if (ordered) {
      return {
        name: {
          ...base,
          "type": "array",
          "prefixItems":
              _childTagNames.map((p) => {"\$ref": "#/\$defs/$p"}).toList(),
          "items": false,
        }
      };
    } else {
      return {
        name: {
          ...base,
          "type": "array",
          "items": {
            "anyOf":
                _childTagNames.map((p) => {"\$ref": "#/\$defs/$p"}).toList()
          }
        }
      };
    }
  }
}

class ElementType {
  final String _tagName;
  final List<ElementProperty> _properties;
  final String? _description;
  final Map<String, ElementProperty> _propertyLookup = {};
  String? _childPropertyName;

  ElementType(
      {required String tagName,
      required String? description,
      required List<ElementProperty> properties})
      : _tagName = tagName,
        _description = description,
        _properties = List<ElementProperty>.from(properties) {
    for (final p in _properties) {
      if (p is ChildProperty) {
        if (_childPropertyName != null) {
          throw MeshSchemaValidationException(
              "Only one child property is allowed");
        }
        _childPropertyName = p.name;
      }

      if (_propertyLookup.containsKey(p.name)) {
        throw MeshSchemaValidationException("Duplicate property ${p.name}");
      }
      _propertyLookup[p.name] = p;
    }
  }

  factory ElementType.fromJson(Map<String, dynamic> json) {
    // Based on original code, it seems `description` and `properties` are at top level:
    // {
    //   "type": "object",
    //   "description": "...",
    //   "required": [...],
    //   "properties": {
    //     "tagName": {
    //       "type": "object",
    //       "required": [...],
    //       "properties": { ... }
    //     }
    //   }
    // }

    final description = json["description"] as String?;

    final propertiesMap = json["properties"] as Map;

    // The Python code picks up the first key in properties as the tagName and uses its properties
    // structure:
    // "properties": {
    //   "tagName": {
    //       "type": "object",
    //       ...
    //       "properties": {
    //          "prop_name": { "description":..., "type": ... or "array" ... }
    //       }
    //   }
    // }

    if (propertiesMap.isEmpty) {
      throw MeshSchemaValidationException(
          "Invalid schema json: no properties found");
    }

    // In Python code, it uses `for k, type_json in json["properties"].items()` then returns inside.
    // So effectively, we take the first entry as the element definition.
    final firstEntry = propertiesMap.entries.first;
    final tagName = firstEntry.key;
    final typeJson = firstEntry.value as Map;

    final propMap = typeJson["properties"] as Map;
    final properties = <ElementProperty>[];

    propMap.forEach((propName, p) {
      final pMap = p as Map;
      final propDescription = pMap["description"] as String?;
      final pType = pMap["type"];

      if (pType == "array") {
        if (pMap["items"] != null &&
            pMap["items"] is Map &&
            pMap["items"]["anyOf"] != null) {
          // handle ChildProperty
          final items = pMap["items"] as Map;

          final anyOf = items["anyOf"] as List<dynamic>;
          final childTagNames = <String>[];

          for (var refObj in anyOf) {
            final refMap = refObj as Map;
            final refStr = refMap["\$ref"] as String;
            const prefix = "#/\$defs/";
            final childTagName = refStr.startsWith(prefix)
                ? refStr.substring(prefix.length)
                : refStr;
            childTagNames.add(childTagName);
          }

          properties.add(
            ChildProperty(
              name: propName,
              description: propDescription,
              childTagNames: childTagNames,
            ),
          );
        } else if (pMap["prefixItems"] != null) {
          final anyOf = pMap["prefixItems"] as List<dynamic>;
          final childTagNames = <String>[];

          for (var refObj in anyOf) {
            final refMap = refObj as Map;
            final refStr = refMap["\$ref"] as String;
            const prefix = "#/\$defs/";
            final childTagName = refStr.startsWith(prefix)
                ? refStr.substring(prefix.length)
                : refStr;
            childTagNames.add(childTagName);
          }

          properties.add(
            ChildProperty(
              name: propName,
              description: propDescription,
              childTagNames: childTagNames,
              ordered: true,
            ),
          );
        } else {
          throw new MeshSchemaValidationException(
              "Invalid array type encountered");
        }
      } else {
        // handle ValueProperty
        // pType should be a string matching SimpleValue
        final valTypeStr = pType as String;
        final valType = SimpleValue.fromString(valTypeStr);
        if (valType == null) {
          throw MeshSchemaValidationException(
              "Invalid value type: $valTypeStr");
        }

        final enumValue = pMap["enum"] as List<dynamic>?;
        properties.add(
          ValueProperty(
            name: propName,
            description: propDescription,
            type: valType,
            enumValues: enumValue,
          ),
        );
      }
    });

    return ElementType(
        tagName: tagName, description: description, properties: properties);
  }

  Map<String, dynamic> toJson() {
    final props = {};
    final required = <String>[];

    for (final p in _properties) {
      required.add(p.name);
      if (props.containsKey(p.name)) {
        throw MeshSchemaValidationException(
            "duplicate key in schema: ${p.name}");
      }
      props[p.name] = p.toJson()[p.name];
    }

    return {
      "type": "object",
      "additionalProperties": false,
      "description": _description,
      "required": [_tagName],
      "properties": {
        _tagName: {
          "type": "object",
          "additionalProperties": false,
          "required": required,
          "properties": props,
        }
      }
    };
  }

  void validate(MeshSchema schema) {
    for (final p in _properties) {
      p.validate(schema);
    }
  }

  String? get childPropertyName => _childPropertyName;
  String get tagName => _tagName;
  String? get description => _description;
  List<ElementProperty> get properties => _properties;

  ElementProperty property(String name) {
    final prop = _propertyLookup[name];
    if (prop == null) {
      throw Exception("Property is not in schema: $name");
    }
    return prop;
  }
}
