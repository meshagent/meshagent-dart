import 'dart:async';
import 'dart:typed_data';

import 'package:meshagent/helpers.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

import 'room_server_e2e_helpers.dart';

const int _permissionDenied = 1001;
const int _storageRecursiveRequired = 3002;
const int _storageInvalidPath = 3004;

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);

Future<T> _nextEvent<T extends RoomEvent>(RoomClient client) {
  return client.events.where((event) => event is T).cast<T>().first.timeout(const Duration(seconds: 3));
}

void main() {
  group('storage room server integration parity', skip: roomServerE2eSkipReason, () {
    test('storage_exists_when_non_existent', () async {
      await withRoomServerE2eClient((client) async {
        expect(await client.storage.exists('non_existent_file.txt'), isFalse);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_upload_and_exists', () async {
      await withRoomServerE2eClient((client) async {
        const path = 'test_folder/test_file.txt';
        expect(await client.storage.exists(path), isFalse);

        await client.storage.upload(path, _bytes('Hello, Storage!'));

        expect(await client.storage.exists(path), isTrue);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_download', () async {
      await withRoomServerE2eClient((client) async {
        const path = 'download_test.txt';
        final content = _bytes('Check download content');

        await client.storage.upload(path, content);
        final downloaded = await client.storage.download(path);

        expect(downloaded.data, content);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_stream_write_and_download', () async {
      await withRoomServerE2eClient((client) async {
        const path = 'stream_test.bin';
        final content = Uint8List.fromList([...List.filled(64 * 1024, 97), ...List.filled(64 * 1024, 98), ...'tail'.codeUnits]);

        await client.storage.uploadStream(
          path,
          Stream.fromIterable([content.sublist(0, 64 * 1024), content.sublist(64 * 1024, 128 * 1024), content.sublist(128 * 1024)]),
          size: content.length,
        );

        final chunks = await (await client.storage.downloadStream(path)).toList();
        final metadata = chunks.first;
        final dataChunks = chunks.skip(1).toList(growable: false);
        final builder = BytesBuilder(copy: false);
        for (final chunk in dataChunks) {
          builder.add(chunk.data);
        }

        expect(metadata.headers, {
          'kind': 'start',
          'name': 'stream_test.bin',
          'mime_type': 'application/octet-stream',
          'size': content.length,
        });
        expect(dataChunks.every((chunk) => chunk.headers['kind'] == 'data'), isTrue);
        expect(builder.takeBytes(), content);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_move', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('folder/source.txt', _bytes('moved content'));

        await client.storage.move('folder/source.txt', 'folder/destination.txt');

        expect(await client.storage.exists('folder/source.txt'), isFalse);
        expect(await client.storage.exists('folder/destination.txt'), isTrue);
        expect((await client.storage.download('folder/destination.txt')).data, _bytes('moved content'));
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_download_url', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('download_url_test.bin', _bytes('Some binary content'));

        final url = await client.storage.downloadUrl('download_url_test.bin');

        expect(url, anyOf(startsWith('http'), startsWith('ws')));
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_list', () async {
      await withRoomServerE2eClient((client) async {
        const folder = 'my_test_folder';
        const files = ['a.txt', 'b.txt', 'c.txt'];
        for (final file in files) {
          await client.storage.upload('$folder/$file', _bytes('some content'), overwrite: true);
        }

        final listing = await client.storage.list(folder);

        expect(listing.map((entry) => entry.name).toList(), files);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_stat_folder', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('my_stat_folder/a.txt', _bytes('some content'), overwrite: true);

        final entry = await client.storage.stat('my_stat_folder');

        expect(entry, isNotNull);
        expect(entry!.name, 'my_stat_folder');
        expect(entry.isFolder, isTrue);
        expect(entry.size, isNull);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_delete', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('delete_me.txt', _bytes('Delete this content'));
        expect(await client.storage.exists('delete_me.txt'), isTrue);

        await client.storage.delete('delete_me.txt');

        expect(await client.storage.exists('delete_me.txt'), isFalse);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_delete_folder_requires_recursive_error_code', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('folder_without_recursive/a.txt', _bytes('content'));

        await expectLater(
          client.storage.delete('folder_without_recursive'),
          throwsA(isA<RoomServerException>().having((error) => error.code, 'code', _storageRecursiveRequired)),
        );
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_delete_file_allows_recursive_true', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('delete_me_recursive.txt', _bytes('Delete this content'));

        await client.storage.delete('delete_me_recursive.txt', recursive: true);

        expect(await client.storage.exists('delete_me_recursive.txt'), isFalse);
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_invalid_path_error_code', () async {
      await withRoomServerE2eClient((client) async {
        await expectLater(
          client.storage.exists('../invalid.txt'),
          throwsA(isA<RoomServerException>().having((error) => error.code, 'code', _storageInvalidPath)),
        );
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_read_operations_require_permission', () async {
      final restricted = ApiScope(
        storage: StorageGrant(paths: [StoragePathGrant(path: 'allowed/', readOnly: true)]),
      );
      await withRoomServerE2eClient(
        (client) async {
          final operations = <Future<void> Function()>[
            () async => client.storage.exists('restricted.txt'),
            () async => client.storage.stat('restricted.txt'),
            () async => client.storage.list('restricted-folder'),
            () async => client.storage.download('restricted.txt'),
            () async => client.storage.downloadUrl('restricted.txt'),
          ];
          for (final operation in operations) {
            await expectLater(operation(), throwsA(isA<RoomServerException>().having((error) => error.code, 'code', _permissionDenied)));
          }
        },
        apiScope: restricted,
        roomNamePrefix: 'dart-storage',
      );
    });

    test('storage_write_operations_require_permission', () async {
      final restricted = ApiScope(
        storage: StorageGrant(paths: [StoragePathGrant(path: 'allowed/', readOnly: true)]),
      );
      await withRoomServerE2eClient(
        (client) async {
          final operations = <Future<void> Function()>[
            () => client.storage.upload('restricted.txt', _bytes('blocked')),
            () => client.storage.delete('restricted.txt'),
          ];
          for (final operation in operations) {
            await expectLater(operation(), throwsA(isA<RoomServerException>().having((error) => error.code, 'code', _permissionDenied)));
          }
        },
        apiScope: restricted,
        roomNamePrefix: 'dart-storage',
      );
    });

    test('storage_file_update_and_delete_events', () async {
      await withRoomServerE2eClient((client) async {
        final updated = _nextEvent<FileUpdatedEvent>(client);
        await client.storage.upload('event_test.txt', _bytes('Testing events'));
        expect((await updated).path, 'event_test.txt');

        final updatedAgain = _nextEvent<FileUpdatedEvent>(client);
        await client.storage.upload('event_test.txt', _bytes('Changed content'), overwrite: true);
        expect((await updatedAgain).path, 'event_test.txt');

        final deleted = _nextEvent<FileDeletedEvent>(client);
        await client.storage.delete('event_test.txt');
        expect((await deleted).path, 'event_test.txt');
      }, roomNamePrefix: 'dart-storage');
    });

    test('storage_file_moved_event', () async {
      await withRoomServerE2eClient((client) async {
        await client.storage.upload('events/source.txt', _bytes('event payload'));
        final moved = _nextEvent<FileMovedEvent>(client);

        await client.storage.move('events/source.txt', 'events/destination.txt');

        final event = await moved;
        expect(event.sourcePath, 'events/source.txt');
        expect(event.destinationPath, 'events/destination.txt');
        expect(event.participantId, client.localParticipant!.id);
      }, roomNamePrefix: 'dart-storage');
    });

    test('deploy_schema', () async {
      await withRoomServerE2eClient((client) async {
        final schema = MeshSchema(
          rootTagName: 'sample',
          elements: [
            ElementType(
              tagName: 'sample',
              description: 'test',
              properties: [
                ChildProperty(name: 'children', description: 'desc', childTagNames: ['child']),
              ],
            ),
            ElementType(
              tagName: 'child',
              description: 'child',
              properties: [ValueProperty(name: 'prop', description: 'desc', type: SimpleValue.number)],
            ),
          ],
        );

        await deploySchema(room: client, schema: schema, name: 'sample_test_schema', overwrite: true);

        expect(await client.storage.exists('.schemas/sample_test_schema.json'), isTrue);
      }, roomNamePrefix: 'dart-storage');
    });
  });
}
