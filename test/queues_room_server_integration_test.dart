import 'dart:async';

import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

import 'room_server_e2e_helpers.dart';

const int _queueNotFound = 5001;
const int _queueAlreadyExists = 5002;

void main() {
  group('queues room server integration parity', skip: roomServerE2eSkipReason, () {
    test('can_receive_last', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        await client1.queues.send('test_queue', {'hello': 'world'}, create: true);

        final message = await client2.queues.receive('test_queue', create: false, wait: true);

        expect(message, {'hello': 'world'});
      }, roomNamePrefix: 'dart-queues');
    });

    test('can_receive_first', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        final receive = client2.queues.receive('test_queue', create: true, wait: true);

        await Future<void>.delayed(const Duration(milliseconds: 200));
        await client1.queues.send('test_queue', {'hello': 'world'}, create: false);

        expect(await receive, {'hello': 'world'});
      }, roomNamePrefix: 'dart-queues');
    });

    test('can_receive_no_wait', () async {
      await withTwoRoomServerE2eClients((client1, client2) async {
        expect(await client2.queues.receive('test_queue', create: true, wait: false), isNull);

        await client1.queues.send('test_queue', {'hello': 'world'}, create: false);

        expect(await client2.queues.receive('test_queue', create: true, wait: false), {'hello': 'world'});
      }, roomNamePrefix: 'dart-queues');
    });

    test('receive_missing_queue_error_code', () async {
      await withTwoRoomServerE2eClients((_, client2) async {
        await expectLater(
          client2.queues.receive('missing_queue', create: false, wait: false),
          throwsA(isA<RoomServerException>().having((error) => error.code, 'code', _queueNotFound)),
        );
      }, roomNamePrefix: 'dart-queues');
    });

    test('open_existing_queue_error_code', () async {
      await withTwoRoomServerE2eClients((client1, _) async {
        await client1.queues.open('duplicate_queue');

        await expectLater(
          client1.queues.open('duplicate_queue'),
          throwsA(isA<RoomServerException>().having((error) => error.code, 'code', _queueAlreadyExists)),
        );
      }, roomNamePrefix: 'dart-queues');
    });
  });
}
