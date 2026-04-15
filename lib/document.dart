import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/schema.dart';
import "package:uuid/uuid.dart";

import 'runtime.dart';

class ChangeEmitter {
  final List<void Function()> _listeners = [];

  void notifyListeners() {
    for (var l in _listeners) {
      l();
    }
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

class MeshNode extends ChangeEmitter {
  MeshNode({this.parent, required this.doc});

  final MeshElement? parent;
  final RuntimeDocument doc;
}

class MeshElement extends MeshNode {
  MeshElement({
    super.parent,
    required super.doc,
    required this.tagName,
    required Map<String, dynamic> attributes,
    required this.elementType,
  }) : _attributes = attributes;

  final ElementType elementType;
  final List<MeshNode> _children = [];
  final String tagName;
  final Map<String, dynamic> _attributes;

  MeshElement? getNodeByID(String id) {
    if (id == this.id) {
      return this;
    }

    for (final child in getChildren()) {
      if (child is MeshElement) {
        final n = child.getNodeByID(id);
        if (n != null) {
          return n;
        }
      }
    }
    return null;
  }

  String? get id {
    return getAttribute("\$id");
  }

  dynamic getAttribute(String name) {
    return _attributes[name];
  }

  void setAttribute(String name, dynamic value) {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": id,
          "setAttributes": {name: value},
        },
      ],
    });
  }

  void removeAttribute(String name) {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": id,
          "removeAttributes": [name],
        },
      ],
    });
  }

  ElementType _ensureChildValid(String tagName) {
    final childName = elementType.childPropertyName;
    if (childName == null) {
      throw Exception("Children are not allowed on this element: $this.tagName");
    }

    final childProp = elementType.property(childName);
    final cp = childProp as ChildProperty;

    if (!cp.isTagAllowed(tagName)) {
      throw Exception("Cannot add $tagName to ${this.tagName}");
    }

    return doc.schema.element(tagName);
  }

  void _validateElementAttributes(ElementType elType, Map<String, dynamic> attributes) {
    // Just ensure each attribute is defined in schema
    for (final k in attributes.keys) {
      // If this property doesn't exist, schema validation will fail later
      elType.property(k); // Will throw if not found
    }
  }

  MeshElement createChildElement(String tagName, Map<String, dynamic> attributes, {String? id}) {
    final childElementType = _ensureChildValid(tagName);
    _validateElementAttributes(childElementType, attributes);
    final elementData = <String, dynamic>{
      "name": tagName,
      "attributes": {"\$id": id ?? const Uuid().v4(), ...attributes},
      "children": _defaultChildren(tagName),
    };
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": this.id,
          "insertChildren": {
            "children": [
              {"element": elementData},
            ],
          },
        },
      ],
    });
    return getNodeByID(elementData["attributes"]["\$id"])!;
  }

  MeshElement createChildElementAt(int index, String tagName, Map<String, dynamic> attributes, {String? id}) {
    final childElementType = _ensureChildValid(tagName);
    _validateElementAttributes(childElementType, attributes);

    final elementData = <String, dynamic>{
      "name": tagName,
      "attributes": {"\$id": id ?? const Uuid().v4(), ...attributes},
      "children": _defaultChildren(tagName),
    };
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": this.id,
          "insertChildren": {
            "index": index,
            "children": [
              {"element": elementData},
            ],
          },
        },
      ],
    });
    return getNodeByID(elementData["attributes"]["\$id"])!;
  }

  MeshElement createChildElementAfter(MeshElement element, String tagName, Map<String, dynamic> attributes, {String? id}) {
    final childElementType = _ensureChildValid(tagName);
    _validateElementAttributes(childElementType, attributes);

    if (element.parent?.id != this.id) {
      throw Exception("Element does not belong to this node");
    }
    final elementData = <String, dynamic>{
      "name": tagName,
      "attributes": {"\$id": id ?? const Uuid().v4(), ...attributes},
      "children": _defaultChildren(tagName),
    };
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": this.id,
          "insertChildren": {
            "after": element.id,
            "children": [
              {"element": elementData},
            ],
          },
        },
      ],
    });
    return getNodeByID(elementData["attributes"]!["\$id"])!;
  }

  List<Map<String, dynamic>> _defaultChildren(String tagName) {
    if (tagName == "text") {
      return [
        {
          "text": {"delta": []},
        },
      ];
    }
    return [];
  }

  void delete() {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {"nodeID": id, "delete": {}},
      ],
    });
  }

  void undo() {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {"undo": {}},
      ],
    });
  }

  void redo() {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {"redo": {}},
      ],
    });
  }

  List<MeshNode> getChildren() {
    return _children;
  }

  List<MeshElement> getElementsByTagName(String tagName) {
    return getChildren().whereType<MeshElement>().where((t) => t.tagName == tagName).toList();
  }

  // Equivalent of the Python append_json
  MeshElement appendJson(Map<String, dynamic> json) {
    final tagName = tagNameFromJson(json);
    final attributes = attributesFromJson(json);
    final elementType = doc.schema.element(tagName);

    if (elementType.childPropertyName != null) {
      final element = createChildElement(tagName, attributes);

      if (attributes.containsKey(elementType.childPropertyName!)) {
        // Extract children
        final children = attributes.remove(elementType.childPropertyName!) as List;
        // Create the element

        // Append each child
        for (final child in children) {
          element.appendJson(child as Map<String, dynamic>);
        }
      }
      return element;
    } else {
      // Just create the child element with given attributes
      return createChildElement(tagName, attributes);
    }
  }

  Map<String, dynamic> toJson({bool includeIds = false}) {
    final props = <String, dynamic>{};

    for (final k in _attributes.keys) {
      if (k != "\$id" || includeIds) {
        props[k] = _attributes[k];
      }
    }

    final schema = doc.schema.elementsByTagName[tagName];
    if (schema!.childPropertyName != null) {
      props[schema.childPropertyName!] = getChildren().whereType<MeshElement>().map((x) => x.toJson(includeIds: includeIds)).toList();
    }
    return {tagName: props};
  }
}

class TextElement extends MeshNode {
  TextElement({required super.parent, required this.delta, required super.doc});

  final List<Map<String, dynamic>> delta;

  void insert(int index, String text, {Map<String, dynamic>? attributes}) {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": parent!.id,
          "insertText": {"index": index, "text": text, "attributes": attributes ?? {}},
        },
      ],
    });
  }

  void format(int from, int length, Map<String, dynamic> attributes) {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": parent!.id,
          "formatText": {"from": from, "length": length, "attributes": attributes},
        },
      ],
    });
  }

  void delete(int index, int length) {
    doc.sendChanges({
      "documentID": doc.id,
      "changes": [
        {
          "nodeID": parent!.id,
          "deleteText": {"index": index, "length": length},
        },
      ],
    });
  }
}

class RuntimeDocument extends ChangeEmitter {
  RuntimeDocument({required this.id, required this.sendChanges, this.sendChangesToBackend, required this.schema});

  final _changes = StreamController<Map<String, dynamic>>.broadcast(sync: true);

  StreamSubscription<Map<String, dynamic>> listen(void Function(Map<String, dynamic>)? onData) {
    return _changes.stream.listen(onData);
  }

  final MeshSchema schema;

  final void Function(String)? sendChangesToBackend;

  final String id;

  final void Function(Map<String, dynamic>) sendChanges;

  late final root = MeshElement(parent: null, tagName: schema.root.tagName, attributes: {}, doc: this, elementType: schema.root);

  Uint8List getState({Uint8List? vector}) {
    final runtime = DocumentRuntime.instance;
    if (runtime == null) {
      throw StateError('DocumentRuntime is not initialized');
    }
    final stateBase64 = runtime.getState(documentId: id, vectorBase64: vector == null ? null : base64Encode(vector));
    return Uint8List.fromList(base64Decode(stateBase64));
  }

  Uint8List getStateVector() {
    final runtime = DocumentRuntime.instance;
    if (runtime == null) {
      throw StateError('DocumentRuntime is not initialized');
    }
    return Uint8List.fromList(base64Decode(runtime.getStateVector(documentId: id)));
  }

  MeshNode _createNode(MeshElement? parent, Map<String, dynamic> data) {
    if (data["element"] != null) {
      final elementData = data["element"];
      final tagName = elementData["tagName"] as String;
      final elementType = schema.element(tagName); // get schema type

      final element = MeshElement(
        doc: this,
        parent: parent,
        tagName: tagName,
        attributes: (elementData["attributes"] as Map?)?.cast<String, dynamic>() ?? {},
        elementType: elementType,
      );

      if (elementData["children"] != null) {
        for (final child in elementData["children"]) {
          element._children.add(_createNode(element, child));
        }
      }

      return element;
    } else if (data["text"] != null) {
      // text node
      final delta = (data["text"]["delta"] as List).whereType<Map<String, dynamic>>().toList();
      return TextElement(parent: parent, delta: delta, doc: this);
    } else {
      throw Exception("Unsupported node type");
    }
  }

  void receiveChanges(Map<String, dynamic> message) {
    final nodeID = message["target"] as String?;
    final target = message["root"] == true ? root : root.getNodeByID(nodeID!);
    // process element deltas

    num retain = 0;
    for (final delta in message["elements"]) {
      if (delta["retain"] != null) {
        retain += delta["retain"];
      }
      if (delta["insert"] != null) {
        for (final insert in delta["insert"] as List) {
          if (insert["element"] != null) {
            target!._children.insert(retain.toInt(), _createNode(target, insert));
            retain++;
          } else if (insert["text"] != null) {
            target!._children.insert(retain.toInt(), _createNode(target, insert));
            retain++;
          } else {
            throw Exception("Unsupported element delta");
          }
        }
      } else if (delta["delete"] != null) {
        target!._children.removeRange(retain.toInt(), (retain + (delta["delete"] as num)).toInt());
        retain -= delta["delete"];
      }
    }

    // process text deltas
    List? text = message["text"];
    if (text != null && text.isNotEmpty) {
      if (target!.tagName != "text") {
        throw Exception('Node is not a text node: $target.tagName');
      }

      final textNode = target._children[0] as TextElement;
      num retain = 0;
      int i = 0;
      num offset = 0;
      var targetDelta = textNode.delta;

      for (final delta in text) {
        if (delta["insert"] != null) {
          if (i == targetDelta.length) {
            targetDelta.add({"insert": delta["insert"], "attributes": delta["attributes"] ?? {}});
            i++;
            offset += (delta["insert"] as String).length;
            retain += (delta["insert"] as String).length;
          } else {
            final str = targetDelta[i]["insert"] as String;
            targetDelta[i]["insert"] =
                str.substring(0, (retain - offset).toInt()) + delta["insert"] + str.substring((retain - offset).toInt());
            retain += (delta["insert"] as String).length;
          }
        } else if (delta["delete"] != null) {
          num deleted = 0;
          while (delta["delete"] > deleted) {
            num remaining = delta["delete"] - deleted;

            // delete ends after item
            if (retain > offset) {
              // delete end
              final str = targetDelta[i]["insert"] as String;
              final start = str.substring(0, (retain - offset).toInt());
              final end = str.substring((retain - offset).toInt());

              if (remaining >= end.length) {
                targetDelta[i]["insert"] = start;
                deleted += end.length;
                i++;
                offset += str.length;
              } else {
                targetDelta[i]["insert"] = start + end.substring(remaining.toInt());
                deleted += (targetDelta[i]["insert"] as String).length;
              }
            } else if (delta["delete"] - deleted >= (targetDelta[i]["insert"] as String).length) {
              // delete segment
              deleted += (targetDelta[i]["insert"] as String).length;
              targetDelta.removeAt(i);
              //offset += targetDelta.splice(i, 1);
            } else {
              // delete ends inside item, delete front
              final str = targetDelta[i]["insert"] as String;
              final start = str.substring(0, remaining.toInt());
              final end = str.substring(remaining.toInt());
              targetDelta[i]["insert"] = end;
              deleted += start.length;
            }
          }
        } else if (delta["attributes"] != null) {
          num formatted = 0;
          while (delta["retain"] as num > formatted) {
            // format ends after item
            num remaining = delta["retain"] - formatted;

            if (targetDelta[i]["attributes"] == null) {
              targetDelta[i]["attributes"] = <String, dynamic>{};
            }

            if (retain > offset) {
              // format end
              final str = targetDelta[i]["insert"] as String;
              final start = str.substring(0, (retain - offset).toInt());
              final end = str.substring((retain - offset).toInt());

              if (remaining >= end.length) {
                targetDelta[i]["insert"] = start;
                targetDelta.insert(i + 1, {
                  "insert": end,
                  "attributes": {...targetDelta[i]["attributes"] as Map, ...delta["attributes"] as Map},
                });

                formatted += end.length;
                // move to next item
                i++;
                i++;
                offset += str.length;
              } else {
                targetDelta[i]["insert"] = start;
                targetDelta.insert(i + 1, {
                  "insert": end.substring(0, remaining.toInt()),
                  "attributes": {...targetDelta[i]["attributes"] as Map, ...delta["attributes"] as Map},
                });
                targetDelta.insert(i + 2, {
                  "insert": end.substring(remaining.toInt()),
                  "attributes": {...targetDelta[i]["attributes"] as Map},
                });

                formatted += remaining;
                i++;
                i++;
                i++;
                offset += start.length + remaining;
              }
            } else if (delta["retain"] - formatted >= (targetDelta[i]["insert"] as String).length) {
              formatted += (targetDelta[i]["insert"] as String).length;

              // format whole item
              for (final k in (delta["attributes"] as Map<String, dynamic>).keys) {
                targetDelta[i]["attributes"][k] = delta["attributes"][k];
              }
              offset += (targetDelta[i]["insert"] as String).length;
              i++;
            } else {
              // format ends inside item, format front
              final str = targetDelta[i]["insert"] as String;
              final start = str.substring(0, remaining.toInt());
              final end = str.substring(remaining.toInt());
              targetDelta[i]["insert"] = start;
              targetDelta.add({
                "insert": end,
                "attributes": {...targetDelta[i]["attributes"] as Map},
              });
              for (final k in (delta["attributes"] as Map).keys) {
                targetDelta[i]["attributes"][k] = delta["attributes"][k];
              }
              formatted += (delta["retain"] - formatted);
            }
          }
          retain += delta["retain"];
        } else if (delta["retain"] != null) {
          if (delta["retain"] != null) {
            retain += delta["retain"];
          }

          while (retain > (offset + ((targetDelta[i]["insert"] as String?)?.length ?? 0)).toInt()) {
            offset += (targetDelta[i]["insert"] as String).length;
            i++;
          }
        }
      }
    }

    for (final change in message["attributes"]["set"] as List) {
      target!._attributes[change["name"]] = change["value"];
      target.notifyListeners();
    }

    for (final name in message["attributes"]["delete"] as List) {
      target!._attributes.remove(name);
      target.notifyListeners();
    }

    notifyListeners();
    _changes.add(message);
  }
}

String tagNameFromJson(Map<String, dynamic> json) {
  if (json.length != 1) {
    throw Exception("JSON element must have a single key");
  }
  return json.keys.first;
}

Map<String, dynamic> attributesFromJson(Map<String, dynamic> json) {
  if (json.length != 1) {
    throw Exception("JSON element must have a single key");
  }
  final key = json.keys.first;
  final val = json[key];
  if (val is Map<String, dynamic>) {
    return Map<String, dynamic>.from(val);
  } else {
    throw Exception("JSON element value must be an object");
  }
}
