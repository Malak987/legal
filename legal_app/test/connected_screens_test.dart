import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:legalserviceapp/services/auth_service.dart';
import 'package:legalserviceapp/state/session_controller.dart';
import 'package:legalserviceapp/state/session_scope.dart';
import 'package:legalserviceapp/views/earnings/earnings.dart';
import 'package:legalserviceapp/views/cases/act.dart';
import 'package:legalserviceapp/views/home/details.dart';
import 'package:legalserviceapp/views/messages/chat_screen.dart';
import 'package:legalserviceapp/views/messages/chatdetailsscreen.dart';
import 'package:legalserviceapp/views/order/OrdersHistory/active_orders.dart';
import 'package:legalserviceapp/views/order/OrdersHistory/cancelled_orders.dart';
import 'package:legalserviceapp/views/order/OrdersHistory/completed_orders.dart';
import 'package:legalserviceapp/views/order/OrdersHistory/order_history_screen.dart';
import 'package:legalserviceapp/views/reviews/reviews.dart';
import 'package:legalserviceapp/views/reviews/writereview.dart';
import 'package:legalserviceapp/views/settings/views/notifications.dart';
import 'package:legalserviceapp/views/subscription/subscription.dart';
import 'package:legalserviceapp/views/tasks/tasks.dart';
import 'package:legalserviceapp/views/wallet/toppup.dart';
import 'package:legalserviceapp/views/wallet/walletscreen.dart';

import 'support/fakes.dart';

Future<void> _drain(WidgetTester tester, {int frames = 4}) async {
  for (var f = 0; f < frames; f++) {
    await tester.runAsync(() async {
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    });
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<SessionController> _pumpSignedIn(
  WidgetTester tester,
  Widget child, {
  required Future<http.Response> Function(http.Request request, int attempt)
      handler,
  String role = 'client',
}) async {
  final gateway = FakeAuthGateway();
  final session = SessionController(
    auth: AuthService(
      gateway: gateway,
      api: testApiClient(
        userProfile: profileJson(role: role),
        handler: (request, attempt) async {
          return handler(request, attempt);
        },
      ),
    ),
  );
  addTearDown(session.dispose);

  session.start();
  gateway.emit(const AuthUser(uid: 'uid-1', email: 'sara@example.com'));
  await _drain(tester);

  await tester.pumpWidget(
    SessionScope(
      controller: session,
      child: MaterialApp(home: child),
    ),
  );
  await _drain(tester);
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaseDetailsScreen', () {
    testWidgets('loads a caller-authorized case by its stable ID',
        (tester) async {
      final requests = <String>[];
      await _pumpSignedIn(
        tester,
        const CaseDetailsScreen(caseId: 'case-1'),
        handler: (req, _) async {
          requests.add('${req.method} ${req.url.path}');
          if (req.url.path.contains('/cases') &&
              req.method == 'GET') {
            return jsonOk({
              'id': 'case-1',
              'title': 'Contract dispute',
              'clientName': 'Nour Hassan',
              'categoryName': 'Commercial Law',
              'lawyerName': 'Mona Fahmy',
              'status': 'In Progress',
              'priority': 'High',
              'dueDate': '2026-12-02',
              'description': 'Review disputed termination terms.',
            });
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(requests, contains('GET /rest/v1/cases'));
      expect(find.textContaining('Contract dispute'), findsOneWidget);
      expect(find.textContaining('Commercial Law'), findsOneWidget);
      expect(find.textContaining('Mona Fahmy'), findsOneWidget);
      expect(find.textContaining('Review disputed termination terms.'), findsOneWidget);
      expect(find.text('Evidence'), findsNothing);
      expect(find.text('Last Hearing'), findsNothing);
    });
  });

  group('Booking history screens', () {
    testWidgets('OrdersHistory builds sections from GET /api/bookings',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const OrdersHistory(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/bookings') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'booking-active',
                  'lawyerName': 'Mona Fahmy',
                  'date': '2026-11-10',
                  'time': '09:00',
                  'status': 'Pending',
                  'totalPrice': 150,
                },
                {
                  'id': 'booking-done',
                  'lawyerName': 'Karim Nassar',
                  'date': '2026-10-01',
                  'time': '11:00',
                  'status': 'Completed',
                  'totalPrice': 200,
                },
              ],
              'total': 2,
            });
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Active Bookings (1)'), findsOneWidget);
      expect(find.textContaining('Completed Bookings (1)'), findsOneWidget);
      expect(find.textContaining('Mona Fahmy'), findsOneWidget);
      expect(find.text('Karim Nassar'), findsOneWidget);
    });

    testWidgets('ActiveOrders cancels an existing booking via PUT /api/bookings/:id',
        (tester) async {
      var status = 'Pending';
      final calls = <String>[];
      await _pumpSignedIn(
        tester,
        const ActiveOrders(),
        handler: (req, _) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.url.path.contains('/bookings') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'booking-1',
                  'lawyerName': 'Mona Fahmy',
                  'date': '2026-11-10',
                  'time': '09:00',
                  'hours': 1,
                  'totalPrice': 150,
                  'status': status,
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.contains('/bookings') &&
              req.method == 'PUT') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            status = body['status']?.toString() ?? status;
            return jsonOk({'id': 'booking-1', 'status': status});
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Mona Fahmy'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await _drain(tester);

      expect(status, 'Cancelled');
      expect(calls, contains('PUT /api/bookings/booking-1'));
      expect(find.textContaining('No active bookings'), findsOneWidget);
    });
  });

  group('TasksScreen', () {
    testWidgets('loads tasks from GET /api/tasks and creates a new task',
        (tester) async {
      final createdBodies = <Map<String, dynamic>>[];
      await _pumpSignedIn(
        tester,
        const TasksScreen(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/tasks') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'task-1',
                  'title': 'File contract addendum',
                  'description': 'Prepare exhibit B',
                  'dueDate': '2026-11-10',
                  'priority': 'High',
                  'status': 'Pending',
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.endsWith('/tasks') && req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            createdBodies.add(body);
            return jsonOk({'id': 'task-2', ...body}, status: 201);
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.text('File contract addendum'), findsOneWidget);
      expect(find.text('Prepare exhibit B'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Task Title'),
        'Review settlement draft',
      );
      await tester.tap(find.text('Add Task'));
      await _drain(tester);

      expect(createdBodies, hasLength(1));
      expect(createdBodies.single['title'], 'Review settlement draft');
    });
  });

  group('ChatScreen and ChatDetailsScreen', () {
    testWidgets('ChatScreen lists conversations from GET /api/chats',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const ChatScreen(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/chats') && req.method == 'GET') {
            return jsonOk([
              {
                'id': 'chat-1',
                'participants': ['uid-1', 'lawyer-u1'],
                'participantNames': {
                  'uid-1': 'Sara Ali',
                  'lawyer-u1': 'Counsel Karim',
                },
                'lastMessage': 'Please bring the signed affidavit.',
              },
            ]);
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.text('Counsel Karim'), findsOneWidget);
      expect(
        find.text('Please bring the signed affidavit.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'ChatDetailsScreen loads messages and posts replies via POST /api/chats/:id/messages',
        (tester) async {
      final sentBodies = <Map<String, dynamic>>[];
      await _pumpSignedIn(
        tester,
        const ChatDetailsScreen(chatId: 'chat-1', userName: 'Counsel Karim'),
        handler: (req, _) async {
          if (req.url.path.endsWith('/chats/chat-1') && req.method == 'GET') {
            return jsonOk({
              'id': 'chat-1',
              'participantNames': {
                'uid-1': 'Sara Ali',
                'lawyer-u1': 'Counsel Karim',
              },
              'messages': [
                {
                  'id': 'm-1',
                  'senderId': 'lawyer-u1',
                  'senderName': 'Counsel Karim',
                  'text': 'Hello Sara, I reviewed your case.',
                },
              ],
            });
          }
          if (req.url.path.endsWith('/chats/chat-1/messages') &&
              req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            sentBodies.add(body);
            return jsonOk({'id': 'm-2', ...body}, status: 201);
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Hello Sara, I reviewed your case.'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'Thank you, sending the documents now.',
      );
      await tester.tap(find.byIcon(Icons.send));
      await _drain(tester);

      expect(sentBodies, hasLength(1));
      expect(
        sentBodies.single['text'],
        'Thank you, sending the documents now.',
      );
    });
  });

  group('ReviewsScreen and WriteReviewScreen', () {
    testWidgets('ReviewsScreen renders live reviews and average rating',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const ReviewsScreen(lawyerId: 'lawyer-1', lawyerName: 'Mona Fahmy'),
        handler: (req, _) async {
          if (req.url.path.endsWith('/reviews') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'rev-1',
                  'lawyerId': 'lawyer-1',
                  'userId': 'uid-2',
                  'userName': 'Nour Hassan',
                  'rating': 5,
                  'comment': 'Thorough and responsive representation.',
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.endsWith('/lawyers') && req.method == 'GET') {
            return jsonOk({'items': const <Object>[], 'total': 0});
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Nour Hassan'), findsOneWidget);
      expect(
        find.text('Thorough and responsive representation.'),
        findsOneWidget,
      );
      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('WriteReviewScreen submits rating and comment to POST /api/reviews',
        (tester) async {
      final submitted = <Map<String, dynamic>>[];
      await _pumpSignedIn(
        tester,
        const WriteReviewScreen(
          initialLawyerId: 'lawyer-1',
          initialLawyerName: 'Mona Fahmy',
        ),
        handler: (req, _) async {
          if (req.url.path.endsWith('/reviews') && req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            submitted.add(body);
            return jsonOk({'id': 'rev-new', ...body}, status: 201);
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      await tester.enterText(
        find.byType(TextField),
        'Great legal advice on our contract.',
      );
      await tester.tap(find.text('Submit Review'));
      await _drain(tester);

      expect(submitted, hasLength(1));
      expect(submitted.single['lawyerId'], 'lawyer-1');
      expect(submitted.single['rating'], 5.0);
      expect(submitted.single['comment'], 'Great legal advice on our contract.');
    });
  });

  group('WalletScreen and TopUpScreen', () {
    testWidgets('WalletScreen renders live balance and transactions',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const WalletScreen(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/wallet/uid-1') && req.method == 'GET') {
            return jsonOk({
              'id': 'uid-1',
              'userId': 'uid-1',
              'balance': 340.5,
              'transactions': [
                {
                  'id': 'tx-1',
                  'type': 'debit',
                  'amount': 50,
                  'description': 'Retainer payment',
                },
              ],
            });
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('\$340.50'), findsOneWidget);
      expect(find.text('Retainer payment'), findsOneWidget);
      expect(find.text('-\$50.00'), findsOneWidget);
    });

    testWidgets(
        'TopUpScreen surfaces server 403 error on client credit attempt without faking success',
        (tester) async {
      var callbackCalled = false;
      await _pumpSignedIn(
        tester,
        TopUpScreen(onTopUp: (_) => callbackCalled = true),
        handler: (req, _) async {
          if (req.url.path.endsWith('/wallet/transactions') &&
              req.method == 'POST') {
            return jsonError(403, 'Only admins can credit wallets');
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      await tester.enterText(find.byType(TextField).first, '100');
      await tester.tap(find.text('Submit Transaction'));
      await _drain(tester);

      expect(callbackCalled, isFalse);
      expect(find.textContaining('Only admins can credit wallets'), findsWidgets);
    });
  });

  group('SubscriptionScreen', () {
    testWidgets(
        'loads plans from GET /api/plans and submits subscription request via POST /api/subscriptions',
        (tester) async {
      final subPosts = <Map<String, dynamic>>[];
      await _pumpSignedIn(
        tester,
        const SubscriptionScreen(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/plans') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'plan-pro',
                  'title': 'Professional Counsel',
                  'price': '\$49/mo',
                  'features': ['Unlimited Case Tracking', 'Priority Booking'],
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.endsWith('/subscriptions') && req.method == 'GET') {
            return jsonOk({'items': const <Object>[], 'total': 0});
          }
          if (req.url.path.endsWith('/subscriptions') && req.method == 'POST') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            subPosts.add(body);
            return jsonOk(
              {
                'id': 'sub-1',
                'planId': body['planId'],
                'planTitle': 'Professional Counsel',
                'status': 'Pending',
              },
              status: 201,
            );
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.text('Professional Counsel'), findsOneWidget);
      expect(find.text('\$49/mo'), findsOneWidget);

      await tester.tap(find.text('Subscribe to Professional Counsel'));
      await _drain(tester);

      expect(subPosts, hasLength(1));
      expect(subPosts.single['planId'], 'plan-pro');
    });
  });

  group('EarningsScreen', () {
    testWidgets('renders live earnings for a lawyer account', (tester) async {
      await _pumpSignedIn(
        tester,
        const EarningsScreen(),
        role: 'lawyer',
        handler: (req, _) async {
          if (req.url.path.endsWith('/earnings/uid-1') && req.method == 'GET') {
            return jsonOk({
              'totalEarnings': 1250,
              'pendingPayout': 300,
              'monthly': {'2026-10': 1250},
              'history': [
                {
                  'id': 'earn-1',
                  'amount': 1250,
                  'status': 'paid',
                  'description': 'Commercial Arbitration Consultation',
                },
              ],
            });
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('\$1250.00'), findsWidgets);
      expect(
        find.text('Commercial Arbitration Consultation'),
        findsOneWidget,
      );
    });

    testWidgets('shows authorization notice when server returns 403 for client',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const EarningsScreen(),
        role: 'client',
        handler: (req, _) async {
          if (req.url.path.endsWith('/earnings/uid-1') && req.method == 'GET') {
            return jsonError(403, 'Forbidden');
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Lawyer Account Required'), findsOneWidget);
    });
  });

  group('CompletedOrders, CancelledOrders, and GroceryNotifications', () {
    testWidgets('CompletedOrders renders completed bookings from the API',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const CompletedOrders(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/bookings') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'bk-done',
                  'lawyerId': 'lawyer-1',
                  'lawyerName': 'Mona Fahmy',
                  'date': '2026-10-15',
                  'time': '10:00',
                  'hours': 2,
                  'totalPrice': 500,
                  'status': 'Completed',
                },
              ],
              'total': 1,
            });
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Mona Fahmy'), findsOneWidget);
      expect(find.text('\$500'), findsOneWidget);
    });

    testWidgets('CancelledOrders renders cancelled bookings from the API',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const CancelledOrders(),
        handler: (req, _) async {
          if (req.url.path.endsWith('/bookings') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'bk-canc',
                  'lawyerId': 'lawyer-2',
                  'lawyerName': 'Ahmed Hassan',
                  'date': '2026-10-12',
                  'time': '14:00',
                  'hours': 1,
                  'totalPrice': 250,
                  'status': 'Cancelled',
                },
              ],
              'total': 1,
            });
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Ahmed Hassan'), findsOneWidget);
      expect(find.textContaining('\$250'), findsOneWidget);
    });

    testWidgets(
        'GroceryNotifications renders notifications and marks them read',
        (tester) async {
      var markReadCalled = false;
      await _pumpSignedIn(
        tester,
        const GroceryNotifications(),
        handler: (req, _) async {
          if (req.url.path.contains('/notifications') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'notif-1',
                  'userId': 'uid-1',
                  'title': 'Booking Confirmed',
                  'content': 'Your appointment with Mona Fahmy is confirmed.',
                  'type': 'booking',
                  'read': false,
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.contains('/notifications') && req.method == 'PUT') {
            markReadCalled = true;
            return jsonOk({'id': 'notif-1', 'read': true});
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Booking Confirmed'), findsOneWidget);
      expect(
        find.text('Your appointment with Mona Fahmy is confirmed.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Booking Confirmed'));
      await _drain(tester);
      expect(markReadCalled, isTrue);
    });
  });

  group('LegalServiceDetailsScreen', () {
    testWidgets('loads lawyer details, availability count, and reviews',
        (tester) async {
      await _pumpSignedIn(
        tester,
        const LegalServiceDetailsScreen(lawyerId: 'lawyer-1'),
        handler: (req, _) async {
          if (req.url.path.contains('/lawyers') && req.method == 'GET') {
            return jsonOk({
              'id': 'lawyer-1',
              'name': 'Mona Fahmy',
              'specialty': 'Family Law',
              'location': 'Cairo',
              'price': '\$200/hr',
              'priceValue': 200,
              'rating': 4.9,
              'experience': '12 years',
              'bio': 'Senior family law counsel.',
            });
          }
          if (req.url.path.contains('/reviews') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'rev-1',
                  'userName': 'Layla',
                  'rating': 5,
                  'comment': 'Very helpful consultation.',
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.contains('/availability') && req.method == 'GET') {
            return jsonOk({
              'items': [
                {
                  'id': 'av-1',
                  'lawyerId': 'lawyer-1',
                  'date': '2026-11-15',
                  'slots': ['09:00', '10:00'],
                },
              ],
              'total': 1,
            });
          }
          if (req.url.path.contains('/favorites') && req.method == 'GET') {
            return jsonOk(const <Object>[]);
          }
          return jsonOk(<String, dynamic>{});
        },
      );

      expect(find.textContaining('Mona Fahmy'), findsOneWidget);
      expect(find.textContaining('Senior family law counsel.'), findsOneWidget);
      expect(find.textContaining('Experience: 12 years'), findsOneWidget);
      expect(find.textContaining('Very helpful consultation.'), findsOneWidget);
    });
  });
}
