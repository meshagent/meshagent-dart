import 'package:flutter/material.dart';
import 'document.dart';
import 'runtime_impl.dart'
    if (dart.library.io) 'runtime_native.dart'
    if (dart.library.js_interop) 'runtime_web.dart';

abstract class DocumentRuntime {
  DocumentRuntime.base();

  factory DocumentRuntime._() {
    return DocumentRuntimeImpl();
  }

  void registerDocument(RuntimeDocument document);
  void unregisterDocument(RuntimeDocument document);

  void sendChanges(Map<String, dynamic> message);
  void applyBackendChanges(
      {required String documentId, required String base64});

  static DocumentRuntime? _instance;

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDocumentRuntime();
    _instance = DocumentRuntime._();
  }

  static DocumentRuntime get instance {
    if (_instance == null) {
      throw Exception(
          "You must initialize the document runtime. Add 'await DocumentRuntime.initialize()' to your main function to initialize the DocumentRuntime.");
    }
    return _instance!;
  }
}
