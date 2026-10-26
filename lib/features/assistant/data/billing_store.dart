import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

enum BillingState { pending, canceled, error, purchased, restored }

class BillingProduct {
  const BillingProduct(
    this.id,
    this.title,
    this.description,
    this.price, {
    this.native,
  });
  final String id, title, description, price;
  final Object? native;
}

class BillingPurchase {
  const BillingPurchase({
    required this.id,
    required this.product,
    required this.proof,
    required this.state,
    this.ownerToken,
    this.needsCompletion = false,
    this.native,
  });
  final String id, product, proof;
  final BillingState state;
  final String? ownerToken;
  final bool needsCompletion;
  final Object? native;
}

abstract class BillingStore {
  String? get platform;
  Stream<List<BillingPurchase>> get updates;
  Future<BillingProduct?> product(String id);
  Future<bool> buy(BillingProduct product, String ownerToken);
  Future<void> restore(String ownerToken);
  Future<void> complete(BillingPurchase purchase);
}

class NativeBillingStore implements BillingStore {
  @override
  String? get platform => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
      ? 'ios'
      : null;
  @override
  Stream<List<BillingPurchase>> get updates => platform == null
      ? const Stream.empty()
      : InAppPurchase.instance.purchaseStream.map(
          (rows) => rows
              .map(
                (p) => BillingPurchase(
                  id: p.purchaseID ?? p.productID,
                  product: p.productID,
                  proof: platform == 'ios'
                      ? p.purchaseID ?? ''
                      : p.verificationData.serverVerificationData,
                  state: BillingState.values.byName(p.status.name),
                  ownerToken: p is GooglePlayPurchaseDetails
                      ? p.billingClientPurchase.obfuscatedAccountId
                      : p is SK2PurchaseDetails
                      ? p.appAccountToken
                      : null,
                  needsCompletion: p.pendingCompletePurchase,
                  native: p,
                ),
              )
              .toList(),
        );
  @override
  Future<BillingProduct?> product(String id) async {
    if (platform == null || !await InAppPurchase.instance.isAvailable()) {
      return null;
    }
    final result = await InAppPurchase.instance.queryProductDetails({id});
    if (result.error != null || result.notFoundIDs.contains(id)) return null;
    final matches = result.productDetails.where((p) => p.id == id);
    if (matches.length != 1) return null;
    final p = matches.single;
    return BillingProduct(p.id, p.title, p.description, p.price, native: p);
  }

  @override
  Future<bool> buy(BillingProduct product, String ownerToken) =>
      InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product.native! as ProductDetails,
          applicationUserName: ownerToken,
        ),
      );
  @override
  Future<void> restore(String ownerToken) =>
      InAppPurchase.instance.restorePurchases(applicationUserName: ownerToken);
  @override
  Future<void> complete(BillingPurchase purchase) => InAppPurchase.instance
      .completePurchase(purchase.native! as PurchaseDetails);
}
