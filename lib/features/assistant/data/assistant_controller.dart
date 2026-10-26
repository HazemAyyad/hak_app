import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../quran/data/haq_api.dart';
import '../../quran/data/quran_controller.dart';
import '../../quran/data/quran_sync.dart';
import 'billing_store.dart';

class AssistantReply {
  AssistantReply(this.data);
  final Map<String, dynamic> data;
  int get id => data['id'] as int;
  String get operation => data['operation_id'] as String;
  String get status => data['status'] as String;
  String? get question => data['question'] as String?;
  String? get answer => data['answer'] as String?;
  List<Map<String, dynamic>> get sources => List<Map<String, dynamic>>.from(
    (data['sources'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
  );
  factory AssistantReply.parse(Map<String, dynamic> row) {
    if (row['id'] is! int ||
        row['operation_id'] is! String ||
        !{
          'reserved',
          'completed',
          'uncertain',
          'failed',
          'failed_billed',
        }.contains(row['status']) ||
        row['question'] != null && row['question'] is! String ||
        row['answer'] != null && row['answer'] is! String ||
        row['sources'] is! List) {
      throw const FormatException('Invalid assistant receipt');
    }
    for (final source in row['sources'] as List) {
      if (source is! Map ||
          source['text'] is! String ||
          source['source'] is! String ||
          source['id'] is! String) {
        throw const FormatException('Invalid source');
      }
    }
    return AssistantReply(row);
  }
}

class AssistantController extends ChangeNotifier {
  AssistantController(
    this.quran, {
    Dio? dio,
    BillingStore? store,
    this.draftWriter,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$haqApiBase/v1/religious',
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 85),
             ),
           ),
       store = store ?? NativeBillingStore() {
    scope = _scope;
    _credential = quran.account.token;
    quran.account.addListener(_accountChanged);
    _purchases = this.store.updates.listen(
      _purchased,
      onError: (Object _) {
        purchaseError = 'تعذّر متابعة عمليات المتجر؛ أعد فتح القسم';
        _emit();
      },
    );
  }
  final QuranController quran;
  final Dio dio;
  final BillingStore store;
  final Future<void> Function(String key, String? value)? draftWriter;
  StreamSubscription<List<BillingPurchase>>? _purchases;
  late String scope;
  String? _credential, storeToken, error, purchaseError, notice;
  bool enabled = false,
      loading = false,
      sending = false,
      buying = false,
      active = false,
      disposed = false;
  int _generation = 0, _loadVersion = 0, _dataVersion = 0, _historyVersion = 0;
  int? next;
  BillingProduct? product;
  Map<String, dynamic>? capabilities, quota, pending;
  final replies = <AssistantReply>[];
  final _purchaseQueue = <String, BillingPurchase>{};
  final _completedPurchases = <String>{};
  bool _processingPurchase = false;
  Future<void> _writes = Future.value();
  String get _scope => quran.account.profile == null
      ? 'guest'
      : 'account.${quran.account.profile!['id']}';
  bool get signedIn =>
      quran.account.profile != null && quran.account.token != null;
  String get _draftKey => 'assistant.pending.v1.$scope';
  bool _current(int generation) => !disposed && generation == _generation;
  void _emit() {
    if (!disposed) notifyListeners();
  }

  void _accountChanged() {
    if (scope == _scope && _credential == quran.account.token) return;
    scope = _scope;
    _credential = quran.account.token;
    _generation++;
    _dataVersion++;
    replies.clear();
    pending = null;
    product = null;
    storeToken = null;
    quota = null;
    capabilities = null;
    active = enabled = loading = sending = buying = false;
    error = purchaseError = notice = null;
    _purchaseQueue.clear();
    _completedPurchases.clear();
    _emit();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    bool private = true,
  }) async {
    final generation = _generation, token = _credential;
    if (private && !signedIn) throw StateError('سجّل الدخول للمتابعة');
    try {
      final response = await dio.request<Map<String, dynamic>>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {if (private) 'Authorization': 'Bearer $token'},
        ),
      );
      if (!_current(generation) || token != _credential) {
        throw StateError('تغير الحساب؛ أعد فتح القسم');
      }
      return Map<String, dynamic>.from(response.data!['data'] as Map);
    } on DioException catch (e) {
      if (_current(generation) && private && e.response?.statusCode == 401) {
        await quran.account.expireSession();
      }
      rethrow;
    }
  }

  String message(Object e) {
    if (e is StateError) return e.message.toString();
    if (e is DioException) {
      switch (e.response?.statusCode) {
        case 401:
          return 'انتهت الجلسة؛ جدّد تسجيل الدخول';
        case 402:
          return 'المساعد يحتاج اشتراكًا موثقًا وساريًا';
        case 403:
          return 'العملية غير متاحة لهذا الحساب؛ الشراء قد يكون مرتبطًا بحساب حق آخر';
        case 409:
          return 'يوجد سؤال مختلف بالمعرّف نفسه؛ تحقق من سجل الأسئلة';
        case 429:
          return 'وصلت حد الاستخدام؛ راجع رصيد الأسئلة وموعد تجديده';
        case 422:
          return 'تعذّر توثيق الطلب أو العثور على مصدر مناسب؛ راجع السؤال أو حالة الشراء';
        case 503:
          return 'الخدمة غير متاحة حاليًا؛ قد تحتاج إعدادًا أو بلغت حد الاستهلاك العام';
      }
    }
    return 'تعذّر الاتصال. تحقق من حالة العملية قبل إرسال طلب جديد.';
  }

  Future<void> _writeDraft(Map<String, dynamic>? value) async {
    final key = _draftKey, json = value == null ? null : jsonEncode(value);
    final job = _writes.catchError((Object _) {}).then((_) async {
      if (draftWriter != null) {
        await draftWriter!(key, json);
        return;
      }
      if (json == null) {
        await quran.account.storage.delete(key: key);
      } else {
        await quran.account.storage.write(key: key, value: json);
      }
    });
    _writes = job;
    await job;
  }

  Future<void> load() async {
    final generation = _generation,
        version = ++_loadVersion,
        key = _draftKey,
        dataVersion = _dataVersion;
    loading = true;
    error = null;
    _emit();
    try {
      final draft = signedIn
          ? await quran.account.storage.read(key: key)
          : null;
      if (!_current(generation) || version != _loadVersion) return;
      if (draft != null) {
        final data = Map<String, dynamic>.from(jsonDecode(draft) as Map);
        if (data['operation_id'] is! String || data['question'] is! String) {
          throw const FormatException('Invalid pending question');
        }
        if (dataVersion == _dataVersion) pending = data;
      }
      final caps = await request(
        'GET',
        '/assistant/capabilities',
        private: false,
      );
      if (!_current(generation) || version != _loadVersion) return;
      if (caps['schema'] != 1 || caps['enabled'] is! bool) {
        throw const FormatException('Unsupported service');
      }
      capabilities = caps;
      enabled = caps['enabled'] == true;
      if (signedIn && caps['schema_ready'] == true) {
        final profile = await request('GET', '/billing/profile');
        if (!_current(generation) || version != _loadVersion) return;
        storeToken = profile['store_token'] as String;
        if (dataVersion == _dataVersion) {
          active = (profile['subscription'] as Map)['active'] == true;
          quota = Map<String, dynamic>.from(profile['quota'] as Map);
        }
        await history();
        if (!_current(generation) || version != _loadVersion) return;
        final platform = store.platform;
        final configuration = platform == null
            ? null
            : (caps['stores'] as Map? ?? {})[platform] as Map?;
        product = null;
        if (configuration?['enabled'] == true &&
            configuration?['product'] is String) {
          try {
            final found = await store.product(
              configuration!['product'] as String,
            );
            if (_current(generation) && version == _loadVersion) {
              product = found;
              if (found == null) {
                purchaseError = 'تعذّر تحميل الباكج من المتجر؛ لم يُنفّذ شراء';
              }
            }
          } catch (_) {
            if (_current(generation)) purchaseError = 'تعذّر تحميل باكج المتجر';
          }
        }
      }
    } catch (e) {
      if (_current(generation) && version == _loadVersion) error = message(e);
    } finally {
      if (_current(generation) && version == _loadVersion) {
        loading = false;
        _emit();
        unawaited(_processPurchases());
      }
    }
  }

  Future<void> history({bool more = false}) async {
    final generation = _generation,
        dataVersion = _dataVersion,
        version = ++_historyVersion;
    final data = await request(
      'GET',
      '/assistant/history',
      query: {if (more && next != null) 'cursor': next},
    );
    final rows = (data['items'] as List)
        .map((e) => AssistantReply.parse(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (!_current(generation) ||
        dataVersion != _dataVersion ||
        version != _historyVersion) {
      return;
    }
    if (!more) replies.clear();
    for (final row in rows) {
      if (!replies.any((e) => e.id == row.id)) replies.add(row);
    }
    replies.sort((a, b) => b.id.compareTo(a.id));
    next = data['next_cursor'] as int?;
    _emit();
  }

  Future<void> send(String question) async {
    if (sending || loading || !signedIn || !active || !enabled) return;
    final generation = _generation;
    sending = true;
    error = null;
    _emit();
    try {
      if (pending != null && pending!['question'] != question.trim()) {
        throw StateError('يوجد سؤال بانتظار التأكيد؛ تحقق منه أولًا');
      }
      pending ??= {'operation_id': operationId(), 'question': question.trim()};
      final draft = Map<String, dynamic>.from(pending!);
      await _writeDraft(draft);
      if (!_current(generation)) return;
      final result = await request('POST', '/assistant/requests', data: draft);
      await _accept(result, generation);
    } catch (e) {
      if (_current(generation)) error = message(e);
    } finally {
      if (_current(generation)) {
        sending = false;
        _emit();
      }
    }
  }

  Future<void> checkPending() async {
    if (sending || pending == null || !signedIn) return;
    final generation = _generation, draft = Map<String, dynamic>.from(pending!);
    sending = true;
    error = null;
    _emit();
    try {
      Map<String, dynamic> data;
      try {
        data = await request(
          'GET',
          '/assistant/requests/${draft['operation_id']}',
        );
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        if (!_current(generation)) return;
        data = await request('POST', '/assistant/requests', data: draft);
      }
      await _accept(data, generation);
    } catch (e) {
      if (_current(generation)) error = message(e);
    } finally {
      if (_current(generation)) {
        sending = false;
        _emit();
      }
    }
  }

  Future<void> _accept(Map<String, dynamic> data, int generation) async {
    final reply = AssistantReply.parse(data);
    if (!_current(generation)) return;
    if (pending != null && pending!['operation_id'] != reply.operation) {
      throw const FormatException('Receipt does not match pending operation');
    }
    _dataVersion++;
    replies.removeWhere((e) => e.id == reply.id);
    replies.insert(0, reply);
    quota = Map<String, dynamic>.from(data['quota'] as Map);
    if (reply.status != 'reserved') {
      await _writeDraft(null);
      if (_current(generation)) pending = null;
    }
  }

  Future<void> erase(int id) async {
    final generation = _generation;
    await request('DELETE', '/assistant/history/$id');
    if (_current(generation)) {
      _dataVersion++;
      replies.removeWhere((e) => e.id == id);
      _emit();
    }
  }

  Future<void> forgetPending() async {
    if (sending || pending == null) return;
    final generation = _generation;
    try {
      await _writeDraft(null);
      if (_current(generation)) {
        pending = null;
        _dataVersion++;
        error = null;
        await load();
      }
    } catch (e) {
      if (_current(generation)) error = message(e);
    }
    _emit();
  }

  Future<void> buy() async {
    if (buying ||
        loading ||
        active ||
        product == null ||
        storeToken == null ||
        !signedIn ||
        !enabled) {
      return;
    }
    final generation = _generation;
    buying = true;
    purchaseError = null;
    notice = 'بانتظار المتجر؛ الدفع لا يفتح المساعد قبل التحقق الخادمي';
    _emit();
    try {
      if (!await store.buy(product!, storeToken!)) {
        throw StateError('لم يبدأ الشراء؛ أعد المحاولة من المتجر');
      }
    } catch (e) {
      if (_current(generation)) {
        purchaseError = message(e);
        buying = false;
      }
    }
    _emit();
  }

  Future<void> restore() async {
    if (storeToken == null || !signedIn || store.platform == null) return;
    final generation = _generation;
    purchaseError = null;
    notice = 'جارٍ التحقق من مشتريات المتجر؛ لا تظهر صلاحية قبل توثيقها';
    _emit();
    try {
      await store.restore(storeToken!);
      if (_current(generation)) await load();
    } catch (e) {
      if (_current(generation)) purchaseError = message(e);
    }
    _emit();
  }

  void _purchased(List<BillingPurchase> purchases) {
    for (final purchase in purchases) {
      _purchaseQueue['${purchase.id}:${purchase.product}'] = purchase;
    }
    unawaited(_processPurchases());
  }

  Future<void> _processPurchases() async {
    if (_processingPurchase ||
        disposed ||
        loading ||
        !signedIn ||
        storeToken == null ||
        store.platform == null) {
      return;
    }
    _processingPurchase = true;
    final generation = _generation;
    try {
      for (final entry in _purchaseQueue.entries.toList()) {
        if (!_current(generation)) return;
        final purchase = entry.value;
        if (purchase.ownerToken != null && purchase.ownerToken != storeToken) {
          _purchaseQueue.remove(entry.key);
          continue;
        }
        if (purchase.state == BillingState.pending) {
          notice = 'الشراء معلّق في المتجر؛ لم يُمنح اشتراك بعد';
          buying = true;
          _purchaseQueue.remove(entry.key);
          continue;
        }
        if (purchase.state == BillingState.canceled ||
            purchase.state == BillingState.error) {
          notice = purchase.state == BillingState.canceled
              ? 'أُلغي الشراء؛ لم يتفعّل اشتراك'
              : 'تعذّر الشراء في المتجر';
          buying = false;
          _purchaseQueue.remove(entry.key);
          continue;
        }
        try {
          final checked = await request(
            'POST',
            '/billing/verify',
            data: {'platform': store.platform, 'proof': purchase.proof},
          );
          if (!_current(generation)) return;
          active = checked['active'] == true;
          _dataVersion++;
          if (purchase.needsCompletion &&
              !_completedPurchases.contains(entry.key)) {
            await store.complete(purchase);
            if (_current(generation)) _completedPurchases.add(entry.key);
          }
          if (!_current(generation)) return;
          buying = false;
          purchaseError = null;
          notice = active
              ? 'تم توثيق الاشتراك من الخادم'
              : 'تم فحص الشراء؛ لا يوجد اشتراك سارٍ';
          _purchaseQueue.remove(entry.key);
        } catch (e) {
          if (_current(generation)) {
            buying = false;
            purchaseError = message(e);
          }
        }
      }
    } finally {
      _processingPurchase = false;
      _emit();
    }
  }

  Future<void> retryPurchases() => _processPurchases();
  Future<void> flush() => _writes;
  @override
  void dispose() {
    disposed = true;
    quran.account.removeListener(_accountChanged);
    unawaited(_purchases?.cancel());
    dio.close(force: true);
    super.dispose();
  }
}
