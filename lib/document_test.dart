import 'package:meshagent/room_server_client.dart';
import 'package:meshagent/runtime.dart';
import 'package:test/test.dart';

import 'package:meshagent/schema.dart';
import 'package:meshagent/document.dart';

final MeshSchema testSchema = MeshSchema(
  rootTagName: "root",
  elements: [
    // <root> type
    ElementType(
      tagName: "root",
      // Typically you'd keep metadata/description if needed
      description: "",
      properties: [
        ValueProperty(name: "hello", description: "", type: SimpleValue.string),
        ValueProperty(name: "hi", description: "", type: SimpleValue.string),
        ValueProperty(name: "test", description: "", type: SimpleValue.string),
        ChildProperty(name: "children", description: "", childTagNames: ["child", "text"]),
      ],
    ),
    // <child> type
    ElementType(
      tagName: "child",
      description: "",
      properties: [
        ValueProperty(name: "hello", description: "", type: SimpleValue.string),
        ValueProperty(name: "hi", description: "", type: SimpleValue.string),
        ValueProperty(name: "test", description: "", type: SimpleValue.string),
        ChildProperty(name: "children", description: "", childTagNames: ["child"]),
      ],
    ),
    // <text> type
    ElementType(
      tagName: "text",
      description: "",
      properties: [
        // "children" -> can contain <child> if needed, or just text in your schema
        ChildProperty(name: "children", description: "", childTagNames: ["child"]),
        ValueProperty(name: "hello", description: "", type: SimpleValue.string),
      ],
    ),
  ],
);

// -----------------------------------------------------------------------------
// 3) Unit tests that mirror the Python tests
// -----------------------------------------------------------------------------
void main() async {
  await DocumentRuntime.initialize();

  MeshDocument createNewDoc() {
    final doc = MeshDocument(schema: testSchema, sendChangesToBackend: (base64) {});

    return doc;
  }

  group('DocumentRuntime (Dart) tests mirrored from Python', () {
    // A simple helper to create a new doc

    test('test_runtime', () {
      final doc = createNewDoc();

      // root.append_child("child", {"hello": "world"})
      final element = doc.root.createChildElement("child", {"hello": "world"});
      expect(element.tagName, equals("child"));
      expect(element.getAttribute("hello"), equals("world"));

      // e2 = element.append_child("child", {"hi": "there"})
      final e2 = element.createChildElement("child", {"hi": "there"});
      expect(e2.getAttribute("hi"), equals("there"));

      // e2.append_child("child", {"hello": "hi"})
      final e3 = e2.createChildElement("child", {"hello": "hi"});
      expect(e3.getAttribute("hello"), equals("hi"));

      // element["test"] = "test2"
      element.setAttribute("test", "test2");
      expect(element.getAttribute("test"), equals("test2"));

      // element._remove_attribute("test")
      element.removeAttribute("test");
      expect(element.getAttribute("test"), isNull);
    });

    test('test_set_attribute', () {
      final doc = createNewDoc();
      doc.root.setAttribute("test", "v1");
      expect(doc.root.getAttribute("test"), equals("v1"));
    });

    test('test_insert_and_delete_element', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("child", {"hello": "world"});
      expect(child.tagName, equals("child"));
      expect(child.getAttribute("hello"), equals("world"));

      // child.delete()
      child.delete();
      expect(doc.root.getChildren(), isEmpty);
    });

    test('test_update_attribute', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("child", {"hello": "world"});
      child.setAttribute("hello", "mod");
      expect(child.getAttribute("hello"), equals("mod"));
    });

    test('test_remove_attribute', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("child", {"hello": "world"});
      child.setAttribute("hello", "mod");
      child.removeAttribute("hello");
      expect(child.getAttribute("hello"), isNull);
    });

    test('test_insert_extend_and_shrink_text_delta', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("text", {"hello": "world"});
      expect(child.tagName, equals("text"));
      expect(child.getAttribute("hello"), equals("world"));

      // The text node is the first child of <text>
      final text = child.getChildren()[0] as TextElement;
      expect(text.delta, isEmpty);

      // text.insert(0, "hello world")
      text.insert(0, "hello world");
      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], equals("hello world"));

      // Insert again at 0
      text.insert(0, "hello world");
      expect(text.delta.length, 1);
      // combined into a single run
      expect(text.delta[0]["insert"], equals("hello worldhello world"));

      // text.delete(len("hello world"), len("hello world"))
      final lengthHelloWorld = "hello world".length;
      text.delete(lengthHelloWorld, lengthHelloWorld);
      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], equals("hello world"));
    });

    test('test_format_text_deltas', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("text", {"hello": "world"});
      final text = child.getChildren()[0] as TextElement;

      // Insert "hello world"
      text.insert(0, "hello world");
      // Format entire text with {"bold": true}
      text.format(0, "hello world".length, {"bold": true});

      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], equals("hello world"));
      expect(text.delta[0]["attributes"]["bold"], isTrue);

      // format(0, len("hello"), {"italic": true})
      text.format(0, 5, {"italic": true});

      // We expect text to split: ["hello", " world"] with different attributes
      expect(text.delta.length, 2);
      expect(text.delta[0]["insert"], equals("hello"));
      expect(text.delta[0]["attributes"]["bold"], isTrue);
      expect(text.delta[0]["attributes"]["italic"], isTrue);

      expect(text.delta[1]["insert"], equals(" world"));
      expect(text.delta[1]["attributes"]["bold"], isTrue);
      expect(text.delta[1]["attributes"].containsKey("italic"), isFalse);

      // format(3,2, {"underline": true})
      text.format(3, 2, {"underline": true}); // from=3, to=5 => length=2

      expect(text.delta.length, 3);
      // "hel", "lo", " world"
      expect(text.delta[0]["insert"], equals("hel"));
      expect(text.delta[1]["insert"], equals("lo"));
      expect(text.delta[2]["insert"], equals(" world"));

      expect(text.delta[0]["attributes"]["bold"], isTrue);
      expect(text.delta[0]["attributes"]["italic"], isTrue);
      expect(text.delta[0]["attributes"]["underline"], isNull);
      expect(text.delta[1]["attributes"]["underline"], isTrue);

      // format entire range with "strikethrough: true"
      text.format(0, "hello world".length, {"strikethrough": true});

      // Should keep 3 segments
      expect(text.delta.length, 3);
      expect(text.delta[0]["insert"], equals("hel"));
      expect(text.delta[1]["insert"], equals("lo"));
      expect(text.delta[2]["insert"], equals(" world"));

      expect(text.delta[0]["attributes"]["bold"], isTrue);
      expect(text.delta[0]["attributes"]["italic"], isTrue);
      expect(text.delta[0]["attributes"].containsKey("underline"), isFalse);
      expect(text.delta[0]["attributes"]["strikethrough"], isTrue);

      expect(text.delta[1]["attributes"]["bold"], isTrue);
      expect(text.delta[1]["attributes"]["italic"], isTrue);
      expect(text.delta[1]["attributes"]["underline"], isTrue);
      expect(text.delta[1]["attributes"]["strikethrough"], isTrue);

      expect(text.delta[2]["attributes"]["bold"], isTrue);
      expect(text.delta[2]["attributes"].containsKey("italic"), isFalse);
      expect(text.delta[2]["attributes"].containsKey("underline"), isFalse);
      expect(text.delta[2]["attributes"]["strikethrough"], isTrue);

      // format(1,1, {"dot": true}) across the splitted runs
      text.format(1, 1, {"dot": true});
      expect(text.delta.length, 5);

      expect(text.delta[0]["insert"], equals("h"));
      expect(text.delta[1]["insert"], equals("e"));
      expect(text.delta[2]["insert"], equals("l"));
    });

    test('test_delete_start_of_delta_text', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("text", {"hello": "world"});
      final text = child.getChildren()[0] as TextElement;

      text.insert(0, "hello world");
      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], "hello world");

      // delete(0, len("hello "))
      text.delete(0, "hello ".length);
      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], "world");
    });

    test('test_delete_end_of_delta_text', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("text", {"hello": "world"});
      final text = child.getChildren()[0] as TextElement;

      text.insert(0, "world");
      // delete last 1
      text.delete("world".length - 1, 1);
      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], "worl");
    });

    test('test_delete_center_of_delta_text', () {
      final doc = createNewDoc();
      final child = doc.root.createChildElement("text", {"hello": "world"});
      final text = child.getChildren()[0] as TextElement;

      text.insert(0, "worl");
      text.delete(2, 1); // remove the 'r'
      expect(text.delta.length, 1);
      expect(text.delta[0]["insert"], "wol");
    });

    test('test_insert_elements_at_positions', () {
      final doc = createNewDoc();

      // Insert at end
      final child1 = doc.root.createChildElement("child", {"hello": "world2"});
      expect(child1.tagName, "child");
      expect(child1.getAttribute("hello"), "world2");

      // Insert deep
      final child2 = child1.createChildElement("child", {"hello": "world3"});
      expect(child2.tagName, "child");
      expect(child2.getAttribute("hello"), "world3");

      // Insert after deep
      final child3 = child1.createChildElement("child", {"hello": "world4"});
      expect(child3.tagName, "child");
      expect(child3.getAttribute("hello"), "world4");

      // insert_child_after in Python => createChildElementAfter in Dart
      final child5 = child1.createChildElementAfter(child2, "child", {"hello": "world5"});
      // child2 is index 0, child5 is inserted after => index 1, child3 is now index 2
      final childrenOfChild1 = child1.getChildren().whereType<Element>().toList();
      expect(childrenOfChild1[1], equals(child5));
      expect(child5.getAttribute("hello"), "world5");

      // insert_child_at(2, "child", {"hello":"world6"})
      final child6 = child1.createChildElementAt(2, "child", {"hello": "world6"});
      // Now the order is:
      //   index=0 => child2
      //   index=1 => child5
      //   index=2 => child6
      //   index=3 => child3
      final updatedChildren = child1.getChildren().whereType<Element>().toList();
      expect(updatedChildren[2], equals(child6));
      expect(child6.getAttribute("hello"), "world6");
    });
  });
}
