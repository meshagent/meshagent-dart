import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import "dart:convert";

import 'document.dart';
import 'runtime.dart';

Future<void> initializeDocumentRuntime() async {
  await DocumentRuntimeImpl._init;
}

class DocumentRuntimeImpl extends DocumentRuntime {
  DocumentRuntimeImpl() : super.base();

  static final _entrypointCode = rootBundle
      .loadString("packages/meshagent/js/entrypoint.txt", cache: false)
      .catchError((onError) => rootBundle.loadString("js/entrypoint.txt", cache: false));
  static final _jsRuntime = getJavascriptRuntime(xhr: false);

  static final _init =
      (() async {
        _jsRuntime.executeSafe(
          '''
        function onSendUpdateToBackend(msg) {
          sendMessage('onSendUpdateToBackend', msg);
        }

        function onSendUpdateToClient(msg) {
          sendMessage('onSendUpdateToClient', msg);
        }

        const module = {
          exports: {
          }
        };

        const crypto = {
          getRandomValues(v) {
              const rands = sendMessage('getRandomValues', JSON.stringify([v.length, v.BYTES_PER_ELEMENT]));
              for(let i = 0; i < v.length; i++) {
                  v[i] = rands[i];
              }
              return v;
          }
        };

      ''' +
              await _entrypointCode,
        );

        _jsRuntime.onMessage("getRandomValues", (p) {
          var length = p[0];
          var width = p[1];
          var random = Random.secure();
          if (width == 1) {
            return List.generate(length, (_) => random.nextInt(255));
          } else if (width == 2) {
            return List.generate(length, (_) => random.nextInt(0xffff));
          } else if (width == 4) {
            return List.generate(length, (_) => random.nextInt(0xffffffff));
          } else if (width == 8) {
            return List.generate(length, (_) => random.nextInt(0xffffffffffffffff));
          } else {
            throw Exception("Unexpected width $width");
          }
        });

        _jsRuntime.onMessage("onSendUpdateToBackend", (parsed) {
          print("send to server $parsed");
          onDocumentSync(documentId: parsed["documentID"], base64: parsed["data"]);
        });

        _jsRuntime.onMessage("onSendUpdateToClient", (data) {
          try {
            final documentID = data["documentID"];
            print(documentID);

            final doc = _documents[documentID];
            if (doc != null) {
              doc.receiveChanges(data["data"]);
            } else {
              throw Exception("Document is not registered $documentID");
            }
          } catch (err, stack) {
            print("error: $err $stack");
          }
        });

        print("runtime initialized");
      })();

  static void onDocumentSync({required String documentId, required String base64}) {
    final doc = _documents[documentId]!;
    if (doc.sendChangesToBackend != null) {
      doc.sendChangesToBackend!(base64);
    } else {
      print("Document sync handler is not attached");
    }
  }

  static final Map<String, RuntimeDocument> _documents = {};

  @override
  void registerDocument(RuntimeDocument document) {
    print("Registering document ${document.id}");
    _documents[document.id] = document;
    _jsRuntime.executeSafe('''
          module.exports.registerDocument(${jsonEncode(document.id)});
      ''');
  }

  @override
  void unregisterDocument(RuntimeDocument document) {
    print("Unregistering document ${document.id}");
    _documents.remove(document.id);
    _jsRuntime.executeSafe('''
        module.exports.unregisterDocument(${jsonEncode(document.id)});
    ''');
  }

  @override
  void sendChanges(Map<String, dynamic> message) {
    final jsonChanges = jsonEncode(message);
    _jsRuntime.executeSafe('''
    module.exports.applyChanges($jsonChanges);
''');
  }

  @override
  void applyBackendChanges({required String documentId, required String base64}) {
    _jsRuntime.executeSafe("module.exports.applyBackendChanges(${jsonEncode(documentId)},${jsonEncode(base64)})");
  }
}

extension _Execute on JavascriptRuntime {
  dynamic executeSafe(String code) {
    final result = evaluate(code);
    if (result.isError) {
      throw Exception(result.stringResult);
    }
    return result.rawResult;
  }
}
