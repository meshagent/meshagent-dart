import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshagent/meshagent.dart';
import 'package:test/test.dart';

void main() {
  test('listMailboxDeliveries sends mailbox-only filters and parses status', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'deliveries': [
            {
              'id': 'delivery-1',
              'submission_id': 'submission-1',
              'recipient': 'person@example.net',
              'message_id': '<message@example.test>',
              'status': 'delivered',
              'submitted_at': '2026-08-21T12:00:00Z',
              'status_at': '2026-08-21T12:01:00Z',
              'attempt_count': 1,
              'smtp_code': 250,
            },
          ],
          'total': 1,
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'token', client: client);

    final page = await meshagent.listMailboxDeliveries(
      projectId: 'project-1',
      address: 'alerts@example.test',
      count: 25,
      offset: 50,
      status: 'delivered',
      recipient: 'person',
      messageId: '<message@example.test>',
    );

    expect(requestedUri.path, '/accounts/projects/project-1/mailboxes/alerts%40example.test/deliveries');
    expect(requestedUri.queryParameters['count'], '25');
    expect(requestedUri.queryParameters['offset'], '50');
    expect(requestedUri.queryParameters['status'], 'delivered');
    expect(page.total, 1);
    expect(page.deliveries.single.messageId, '<message@example.test>');
    expect(page.deliveries.single.smtpCode, 250);
  });

  test('listMailboxDeliveryEvents parses chronological event page', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/accounts/projects/project-1/mailboxes/alerts%40example.test/deliveries/delivery-1/events');
      return http.Response(
        jsonEncode({
          'events': [
            {
              'id': 'event-1',
              'delivery_id': 'delivery-1',
              'provider': 'mailgun',
              'provider_event_id': 'mailgun-event-1',
              'event_type': 'accepted',
              'status': 'accepted',
              'occurred_at': '2026-08-21T12:00:00Z',
              'received_at': '2026-08-21T12:00:01Z',
              'attempt_no': 0,
            },
            {
              'id': 'event-2',
              'delivery_id': 'delivery-1',
              'provider': 'mailgun',
              'provider_event_id': 'mailgun-event-2',
              'event_type': 'delivered',
              'status': 'delivered',
              'occurred_at': '2026-08-21T12:01:00Z',
              'received_at': '2026-08-21T12:01:01Z',
              'attempt_no': 1,
              'smtp_code': 250,
            },
          ],
          'total': 2,
        }),
        200,
      );
    });
    final meshagent = Meshagent(baseUrl: 'http://example.test', token: 'token', client: client);

    final page = await meshagent.listMailboxDeliveryEvents(
      projectId: 'project-1',
      address: 'alerts@example.test',
      deliveryId: 'delivery-1',
    );

    expect(page.total, 2);
    expect(page.events.map((event) => event.eventType), ['accepted', 'delivered']);
  });
}
