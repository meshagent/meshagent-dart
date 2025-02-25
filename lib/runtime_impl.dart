import 'document.dart';
import 'runtime.dart';

Future<void> initializeDocumentRuntime() {
  throw new Exception("Not implemented");
}

class DocumentRuntimeImpl extends DocumentRuntime {
  DocumentRuntimeImpl() : super.base();

  @override
  void registerDocument(RuntimeDocument document) {
    throw new Exception("Not implemented");
  }

  @override
  void unregisterDocument(RuntimeDocument document) {
    throw new Exception("Not implemented");
  }

  @override
  void sendChanges(Map<String, dynamic> message) {
    throw new Exception("Not implemented");
  }

  @override
  void applyBackendChanges(
      {required String documentId, required String base64}) {
    throw new Exception("Not implemented");
  }
}
