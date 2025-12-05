import "dart:typed_data";

import "package:meshagent/protocol.dart";
import "package:livekit_client/livekit_client.dart" as lk;

class LivekitProtocolChannel extends ProtocolChannel {
  LivekitProtocolChannel({required this.room, required this.topic, required this.remote});

  final lk.RemoteParticipant remote;
  final lk.Room room;
  final String topic;

  lk.EventsListener<lk.RoomEvent>? listener;

  void Function(Uint8List data)? onDataReceived;

  @override
  void start(void Function(Uint8List data) onDataReceived, {void Function()? onDone, void Function(Object? error)? onError}) {
    this.onDataReceived = onDataReceived;
    listener = room.createListener();
    listener!.on<lk.DataReceivedEvent>(onDataPacket);
  }

  @override
  void dispose() {
    listener?.dispose();
    onDataReceived = null;
  }

  @override
  Future<void> sendData(Uint8List data) async {
    await room.localParticipant!.publishData(data, reliable: true, topic: topic, destinationIdentities: [remote.identity]);
  }

  void onDataPacket(lk.DataReceivedEvent evt) {
    if (evt.topic == topic && evt.participant == remote) {
      onDataReceived!(evt.data as Uint8List);
    }
  }
}
