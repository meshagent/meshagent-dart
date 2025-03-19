import 'dart:convert';

import 'package:flutter/services.dart';
import "package:logging/logging.dart";
import 'document.dart';
import 'runtime.dart';

import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS("meshagent.registerDocument")
external void _runtimeRegisterDocument(JSString id, JSString? data, JSFunction sendUpdateToBackend, JSFunction sendUpdateToClient);

@JS("meshagent.unregisterDocument")
external void _runtimeUnregisterDocument(JSString id);

@JS("meshagent.applyChanges")
external void _runtimeApplyChanges(JSObject changes);

@JS("meshagent.applyBackendChanges")
external void _runtimeApplyBackendChanges(JSString documentID, JSString base64);

Future<void> initializeDocumentRuntime() async {
  await DocumentRuntimeImpl._init;
}

class DocumentRuntimeImpl extends DocumentRuntime {
  DocumentRuntimeImpl() : super.base();

  static final _entrypointCode = rootBundle.loadString("packages/meshagent/js/entrypoint.txt", cache: false);

  static final _init = (() async {
    final element = web.document.createElement("script")
      ..innerHTML = (await _entrypointCode).toJS;

    web.document.body!.appendChild(element);
  }());

  static void onDocumentSync({required String documentId, required String base64}) {
    final doc = _documents[documentId]!;
    if (doc.sendChangesToBackend != null) {
      doc.sendChangesToBackend!(base64);
    } else {
      Logger.root.log(Level.WARNING, "Document sync handler is not attached");
    }
  }

  static final Map<String, RuntimeDocument> _documents = {};

  void onSendUpdateToBackend(String js) {
    final parsed = jsonDecode(js) as Map;
    onDocumentSync(documentId: parsed["documentID"], base64: parsed["data"]);
  }

  void onSendUpdateToClient(String js) {
    final parsed = jsonDecode(js) as Map;
    try {
      final documentID = parsed["documentID"];

      final doc = _documents[documentID];
      if (doc != null) {
        doc.receiveChanges(parsed["data"]);
      } else {
        throw Exception("Document is not registered $documentID");
      }
    } catch (err, stack) {
      Logger.root.log(Level.WARNING, "error: $err $stack");
    }
  }

  @override
  void registerDocument(RuntimeDocument document) {
    _documents[document.id] = document;
    void Function(String) onSendUpdateToBackend = this.onSendUpdateToBackend;
    void Function(String) onSendUpdateToClient = this.onSendUpdateToClient;

    _runtimeRegisterDocument(document.id.toJS, null, onSendUpdateToBackend.toJS, onSendUpdateToClient.toJS);
  }

  @override
  void unregisterDocument(RuntimeDocument document) {
    _documents.remove(document.id);
    _runtimeUnregisterDocument(document.id.toJS);
  }

  @override
  void sendChanges(Map<String, dynamic> message) {
    _runtimeApplyChanges(message.jsify() as JSObject);
  }

  @override
  void applyBackendChanges({required String documentId, required String base64}) {
    _runtimeApplyBackendChanges(documentId.toJS, base64.toJS);
  }
}
