import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haq_app/features/assistant/data/assistant_controller.dart';
import 'package:haq_app/features/assistant/data/billing_store.dart';
import 'package:haq_app/features/quran/data/quran_controller.dart';
import 'package:haq_app/features/quran/data/quran_repository.dart';
import 'package:haq_app/features/quran/data/quran_sync.dart';

Map<String, dynamic> assistantQuota({int used = 0}) => {
  'month': '2026-10',
  'day': '2026-10-26',
  'monthly_limit': 25,
  'daily_limit': 3,
  'monthly_used': used,
  'daily_used': used,
};
Map<String, dynamic> assistantReceipt({
  int id = 1,
  String? operation,
  String question = 'سؤال اختبار',
  String status = 'completed',
}) => {
  'id': id,
  'operation_id': operation ?? '00000000-0000-4000-8000-000000000001',
  'status': status,
  'question': question,
  'answer': status == 'completed'
      ? 'شرح آلي للاختبار، وليس نصًا دينيًا.'
      : null,
  'sources': [
    {'id': 'fixture', 'text': 'نص مصدر للاختبار', 'source': 'مصدر الاختبار'},
  ],
  'error_code': null,
  'quota': assistantQuota(used: 1),
};

class AssistantCloud implements HttpClientAdapter {
  bool enabled = true,
      active = true,
      schemaReady = true,
      loseAnswer = false,
      rejectPurchase = false,
      unauthorized = false;
  int generations = 0, verified = 0;
  Completer<void>? answerGate, profileGate, historyGate;
  final requests = <RequestOptions>[];
  final receipts = <String, Map<String, dynamic>>{};
  FlutterSecureStorage? storage;
  String token(int id) =>
      '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}';
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;
    final owner =
        (options.headers['Authorization'] as String? ?? 'token-1').endsWith('2')
        ? 2
        : 1;
    var status = 200;
    Map<String, dynamic> data;
    if (path == '/assistant/capabilities') {
      data = {
        'schema': 1,
        'schema_ready': schemaReady,
        'enabled': enabled,
        'monthly_limit': 25,
        'daily_limit': 3,
        'question_limit': 600,
        'stores': {
          'android': {'enabled': enabled, 'product': 'synthetic.monthly'},
          'ios': {'enabled': false, 'product': null},
        },
        'policy': {'terms': '', 'privacy': ''},
      };
    } else if (unauthorized && path.startsWith('/assistant/')) {
      status = 401;
      data = {};
    } else if (path == '/billing/profile') {
      data = {
        'store_token': token(owner),
        'subscription': {
          'active': active,
          'expires_at': null,
          'state': active ? 'ACTIVE' : 'NONE',
        },
        'quota': assistantQuota(used: receipts.length),
      };
      if (profileGate != null) await profileGate!.future;
    } else if (path == '/billing/verify') {
      verified++;
      status = rejectPurchase ? 503 : 200;
      if (!rejectPurchase) active = true;
      data = {
        'active': !rejectPurchase,
        'state': 'ACTIVE',
        'expires_at': '2026-11-26T00:00:00Z',
        'platform': 'android',
      };
    } else if (path == '/assistant/requests' && options.method == 'POST') {
      final input = Map<String, dynamic>.from(options.data as Map),
          operation = input['operation_id'] as String;
      if (storage != null) {
        expect(
          await storage!.read(key: 'assistant.pending.v1.account.$owner'),
          contains(operation),
        );
      }
      data = receipts.putIfAbsent(operation, () {
        generations++;
        return assistantReceipt(
          id: receipts.length + 1,
          operation: operation,
          question: input['question'] as String,
        );
      });
      if (answerGate != null) await answerGate!.future;
      if (loseAnswer) {
        loseAnswer = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
    } else if (path.startsWith('/assistant/requests/')) {
      final operation = path.split('/').last;
      data = receipts[operation] ?? {};
      if (data.isEmpty) status = 404;
    } else if (path == '/assistant/history') {
      data = {
        'items': receipts.values.toList().reversed.toList(),
        'next_cursor': null,
      };
      if (historyGate != null) await historyGate!.future;
    } else if (path.startsWith('/assistant/history/') &&
        options.method == 'DELETE') {
      final id = int.parse(path.split('/').last);
      receipts.removeWhere((k, v) => v['id'] == id);
      data = {'deleted': true};
    } else {
      data = {};
    }
    return ResponseBody.fromString(
      jsonEncode({'data': data}),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class TestBillingStore implements BillingStore {
  final events = StreamController<List<BillingPurchase>>.broadcast(sync: true);
  bool available = true;
  int queried = 0, bought = 0, restored = 0, completed = 0;
  String? boughtOwner;
  @override
  String? platform = 'android';
  @override
  Stream<List<BillingPurchase>> get updates => events.stream;
  @override
  Future<BillingProduct?> product(String id) async {
    queried++;
    return available
        ? BillingProduct(id, 'باكج اختبار', 'اشتراك شهري للاختبار', r'$5.00')
        : null;
  }

  @override
  Future<bool> buy(BillingProduct product, String ownerToken) async {
    bought++;
    boughtOwner = ownerToken;
    return true;
  }

  @override
  Future<void> restore(String ownerToken) async {
    restored++;
  }

  @override
  Future<void> complete(BillingPurchase purchase) async {
    completed++;
  }

  void emit(BillingState state, {String? owner, String id = 'purchase-1'}) =>
      events.add([
        BillingPurchase(
          id: id,
          product: 'synthetic.monthly',
          proof: 'synthetic-proof',
          state: state,
          ownerToken: owner,
          needsCompletion:
              state == BillingState.purchased || state == BillingState.restored,
        ),
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranController quran;
  late AssistantController c;
  late AssistantCloud cloud;
  late TestBillingStore store;
  AssistantController open({Future<void> Function(String, String?)? writer}) =>
      AssistantController(
        quran,
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = cloud,
        store: store,
        draftWriter: writer,
      );
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
  }

  Future<void> switchOwner() async {
    quran.account.profile = {
      'id': 2,
      'email': 'two@example.test',
      'name': 'Two',
    };
    quran.account.token = 'token-2';
    await quran.account.capabilities();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    cloud = AssistantCloud();
    store = TestBillingStore();
    quran = QuranController(
      preferences: await SharedPreferences.getInstance(),
      initialRepository: QuranRepository.fromJson(
        jsonDecode(File('assets/quran/quran.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
      accountFactory: (q) => QuranAccount(
        q,
        dio: Dio(BaseOptions(baseUrl: 'https://backend.test'))
          ..httpClientAdapter = cloud,
      ),
    );
    await quran.load();
    quran.account.profile = {
      'id': 1,
      'name': 'One',
      'email': 'one@example.test',
    };
    quran.account.token = 'token-1';
    cloud.storage = quran.account.storage;
    c = open();
  });
  tearDown(() async {
    await c.flush();
    c.dispose();
    quran.dispose();
    await store.events.close();
  });
  test(
    'disabled or missing store product never queries a price or initiates purchase',
    () async {
      cloud.enabled = false;
      await c.load();
      await c.buy();
      expect(store.queried, 0);
      expect(store.bought, 0);
      expect(c.product, isNull);
      cloud.enabled = true;
      store.available = false;
      await c.load();
      await c.buy();
      expect(c.product, isNull);
      expect(store.bought, 0);
      expect(c.purchaseError, isNotNull);
    },
  );
  test(
    'secure draft precedes paid HTTP and a lost answer resumes the same receipt after reopen',
    () async {
      await c.load();
      cloud.loseAnswer = true;
      await c.send('سؤال اختبار');
      expect(c.pending, isNotNull);
      expect(cloud.generations, 1);
      final operation = c.pending!['operation_id'];
      c.dispose();
      c = open();
      await c.load();
      expect(c.pending!['operation_id'], operation);
      await c.checkPending();
      expect(c.pending, isNull);
      expect(c.replies.single.answer, isNotNull);
      expect(cloud.generations, 1);
      expect(
        await quran.account.storage.read(key: 'assistant.pending.v1.account.1'),
        isNull,
      );
    },
  );
  test(
    'late old-account answer cannot populate a different account or clear its draft',
    () async {
      await c.load();
      cloud.answerGate = Completer<void>();
      final sending = c.send('سؤال خاص بالأول');
      for (var i = 0; i < 50 && cloud.generations == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      await switchOwner();
      cloud.answerGate!.complete();
      await sending;
      expect(c.scope, 'account.2');
      expect(c.replies, isEmpty);
      expect(c.pending, isNull);
      expect(c.active, false);
      expect(
        await quran.account.storage.read(key: 'assistant.pending.v1.account.1'),
        isNotNull,
      );
      expect(
        await quran.account.storage.read(key: 'assistant.pending.v1.account.2'),
        isNull,
      );
    },
  );
  test(
    'late subscription profile does not grant access to the newly selected account',
    () async {
      cloud.profileGate = Completer<void>();
      final load = c.load();
      for (
        var i = 0;
        i < 50 && !cloud.requests.any((r) => r.path == '/billing/profile');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      await switchOwner();
      cloud.profileGate!.complete();
      await load;
      expect(c.active, false);
      expect(c.storeToken, isNull);
      expect(c.product, isNull);
    },
  );
  test(
    'late history snapshot never replaces a newly confirmed answer',
    () async {
      await c.load();
      cloud.historyGate = Completer<void>();
      final history = c.history();
      for (
        var i = 0;
        i < 50 &&
            cloud.requests.where((r) => r.path == '/assistant/history').length <
                2;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      await c.send('سؤال اختبار');
      cloud.historyGate!.complete();
      await history;
      expect(c.replies.single.answer, isNotNull);
      expect(c.quota!['monthly_used'], 1);
    },
  );
  test(
    'pending and canceled native purchases never grant access or complete a transaction',
    () async {
      cloud.active = false;
      await c.load();
      await c.buy();
      expect(store.boughtOwner, cloud.token(1));
      expect(c.active, false);
      store.emit(BillingState.pending, owner: cloud.token(1));
      await settle();
      expect(c.buying, true);
      expect(cloud.verified, 0);
      store.emit(BillingState.canceled, owner: cloud.token(1));
      await settle();
      expect(c.active, false);
      expect(c.buying, false);
      expect(store.completed, 0);
      expect(cloud.verified, 0);
    },
  );
  test(
    'verified restored or purchased event grants access only after server and finishes once',
    () async {
      cloud.active = false;
      await c.load();
      cloud.rejectPurchase = true;
      store.emit(BillingState.purchased, owner: cloud.token(1));
      await settle();
      expect(c.active, false);
      expect(store.completed, 0);
      expect(c.purchaseError, isNotNull);
      cloud.rejectPurchase = false;
      await c.retryPurchases();
      expect(c.active, true);
      expect(store.completed, 1);
      store.emit(BillingState.restored, owner: cloud.token(1));
      await settle();
      expect(store.completed, 1);
    },
  );
  test(
    'purchase of a different account is not verified or completed under the current account',
    () async {
      cloud.active = false;
      await c.load();
      await switchOwner();
      await c.load();
      store.emit(BillingState.purchased, owner: cloud.token(1));
      await settle();
      expect(c.active, false);
      expect(cloud.verified, 0);
      expect(store.completed, 0);
    },
  );
  test(
    'failure to persist draft prevents charging and preserves the same operation for retry',
    () async {
      c.dispose();
      var writable = false;
      c = open(
        writer: (key, value) async {
          if (!writable) throw StateError('disk failure');
          if (value == null) {
            await quran.account.storage.delete(key: key);
          } else {
            await quran.account.storage.write(key: key, value: value);
          }
        },
      );
      await c.load();
      await c.send('سؤال اختبار');
      expect(cloud.generations, 0);
      final operation = c.pending!['operation_id'];
      writable = true;
      await c.send('سؤال اختبار');
      expect(cloud.generations, 1);
      expect(cloud.receipts.keys, [operation]);
    },
  );
  test(
    'failure clearing a confirmed draft never resends a paid generation',
    () async {
      c.dispose();
      var writes = 0;
      c = open(
        writer: (key, value) async {
          if (++writes == 2) throw StateError('cleanup failure');
          if (value == null) {
            await quran.account.storage.delete(key: key);
          } else {
            await quran.account.storage.write(key: key, value: value);
          }
        },
      );
      await c.load();
      await c.send('سؤال اختبار');
      expect(c.pending, isNotNull);
      expect(cloud.generations, 1);
      await c.checkPending();
      expect(c.pending, isNull);
      expect(cloud.generations, 1);
    },
  );
  test(
    'server-confirmed uncertain receipt leaves history and quota without fabricated answer',
    () async {
      await c.load();
      cloud.loseAnswer = true;
      await c.send('سؤال اختبار');
      final operation = c.pending!['operation_id'] as String;
      cloud.receipts[operation] = assistantReceipt(
        operation: operation,
        status: 'uncertain',
      );
      await c.checkPending();
      expect(c.pending, isNull);
      expect(c.replies.single.answer, isNull);
      expect(c.quota!['monthly_used'], 1);
      expect(cloud.generations, 1);
    },
  );
  test(
    'HTTP401 expires session while preserving private draft for that account',
    () async {
      await c.load();
      cloud.unauthorized = true;
      await c.send('سؤال خاص');
      expect(quran.account.sessionExpired, true);
      expect(c.active, false);
      expect(c.replies, isEmpty);
      expect(
        await quran.account.storage.read(key: 'assistant.pending.v1.account.1'),
        isNotNull,
      );
    },
  );
  test(
    'forgetting local retry preserves server receipt and authoritative consumed quota',
    () async {
      await c.load();
      cloud.loseAnswer = true;
      await c.send('سؤال اختبار');
      await c.forgetPending();
      expect(c.pending, isNull);
      expect(
        await quran.account.storage.read(key: 'assistant.pending.v1.account.1'),
        isNull,
      );
      expect(cloud.generations, 1);
      expect(cloud.receipts.length, 1);
      expect(c.quota!['monthly_used'], 1);
    },
  );
  test(
    'invalid source payload is rejected before presenting an assistant response',
    () {
      expect(
        () => AssistantReply.parse({
          ...assistantReceipt(),
          'sources': [
            {'id': 'fake', 'text': 7, 'source': 'bad'},
          ],
        }),
        throwsFormatException,
      );
    },
  );
}
