import 'document.dart';

abstract class DocumentRuntime {
  DocumentRuntime.base();

  void registerDocument(RuntimeDocument document);
  void unregisterDocument(RuntimeDocument document);

  void sendChanges(Map<String, dynamic> message);
  void applyBackendChanges({required String documentId, required String base64});

  static DocumentRuntime? _instance;

  static DocumentRuntime? get instance {
    return _instance;
  }

  static set instance(DocumentRuntime value) {
    _instance = value;
  }
}
