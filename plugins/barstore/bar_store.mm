#include "bar_store.h"

#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

// Fala com a fila de pagamentos da Apple. Vive na thread principal.
@interface BarStoreHost : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@property(nonatomic, assign) BarStore *owner;
@property(nonatomic, strong) SKProductsRequest *pedido;
@property(nonatomic, strong) NSMutableDictionary<NSString *, SKProduct *> *produtos;
// Compras ja pagas que o servidor ainda nao confirmou (a Apple as reenvia a cada abertura).
@property(nonatomic, strong) NSMutableDictionary<NSString *, SKPaymentTransaction *> *aguardando;
- (void)iniciar;
- (void)buscar:(NSArray<NSString *> *)ids;
- (void)comprar:(NSString *)codigo usuario:(NSString *)usuario;
- (void)restaurar;
- (NSString *)listaPendentes;
- (void)finalizar:(NSString *)transacao;
@end

static NSString *textoDe(const String &s) {
	return [NSString stringWithUTF8String:s.utf8().get_data()];
}

static String godotDe(NSString *s) {
	return String::utf8(s ? s.UTF8String : "");
}

@implementation BarStoreHost

- (void)iniciar {
	self.produtos = [NSMutableDictionary dictionary];
	self.aguardando = [NSMutableDictionary dictionary];
	[[SKPaymentQueue defaultQueue] addTransactionObserver:self];
}

- (void)buscar:(NSArray<NSString *> *)ids {
	self.pedido = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:ids]];
	self.pedido.delegate = self;
	[self.pedido start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
	NSMutableArray *lista = [NSMutableArray array];
	NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
	fmt.numberStyle = NSNumberFormatterCurrencyStyle;
	for (SKProduct *p in response.products) {
		self.produtos[p.productIdentifier] = p;
		fmt.locale = p.priceLocale;
		[lista addObject:@{
			@"id" : p.productIdentifier,
			@"titulo" : p.localizedTitle ?: @"",
			@"preco" : [fmt stringFromNumber:p.price] ?: @"",
			@"valor" : p.price.stringValue ?: @""
		}];
	}
	NSData *dados = [NSJSONSerialization dataWithJSONObject:lista options:0 error:nil];
	NSString *json = dados ? [[NSString alloc] initWithData:dados encoding:NSUTF8StringEncoding] : @"[]";
	if (self.owner) {
		self.owner->_emit_produtos(godotDe(json));
	}
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
	if (self.owner) {
		self.owner->_emit_produtos(String("[]"));
	}
}

- (void)comprar:(NSString *)codigo usuario:(NSString *)usuario {
	SKProduct *p = self.produtos[codigo];
	if (p == nil) {
		if (self.owner) {
			self.owner->_emit_compra_falhou(String("produto_nao_encontrado"));
		}
		return;
	}
	if (![SKPaymentQueue canMakePayments]) {
		if (self.owner) {
			self.owner->_emit_compra_falhou(String("compras_desligadas"));
		}
		return;
	}
	SKMutablePayment *pagamento = [SKMutablePayment paymentWithProduct:p];
	if (usuario.length > 0) {
		pagamento.applicationUsername = usuario;
	}
	[[SKPaymentQueue defaultQueue] addPayment:pagamento];
}

- (void)restaurar {
	[[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
	for (SKPaymentTransaction *t in transactions) {
		switch (t.transactionState) {
			case SKPaymentTransactionStatePurchased:
			case SKPaymentTransactionStateRestored: {
				NSString *codigo = t.transactionIdentifier;
				if (codigo.length == 0) {
					[queue finishTransaction:t];
					break;
				}
				self.aguardando[codigo] = t;
				SKPaymentTransaction *orig = t.originalTransaction ?: t;
				if (self.owner) {
					self.owner->_emit_compra_ok(godotDe(t.payment.productIdentifier), godotDe(codigo), godotDe(orig.transactionIdentifier ?: codigo));
				}
				break;
			}
			case SKPaymentTransactionStateFailed: {
				BOOL cancelou = (t.error.code == SKErrorPaymentCancelled);
				[queue finishTransaction:t];
				if (self.owner) {
					if (cancelou) {
						self.owner->_emit_compra_cancelada();
					} else {
						self.owner->_emit_compra_falhou(godotDe(t.error.localizedDescription ?: @"erro"));
					}
				}
				break;
			}
			default:
				break; // comprando / adiada: espera
		}
	}
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
	if (self.owner) {
		self.owner->_emit_restauracao_pronta();
	}
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
	if (self.owner) {
		if (error.code == SKErrorPaymentCancelled) {
			self.owner->_emit_compra_cancelada();
		} else {
			self.owner->_emit_compra_falhou(godotDe(error.localizedDescription ?: @"erro"));
		}
	}
}

- (NSString *)listaPendentes {
	NSMutableArray *lista = [NSMutableArray array];
	for (NSString *codigo in self.aguardando) {
		SKPaymentTransaction *t = self.aguardando[codigo];
		SKPaymentTransaction *orig = t.originalTransaction ?: t;
		[lista addObject:@{ @"produto" : t.payment.productIdentifier ?: @"", @"transacao" : codigo, @"original" : orig.transactionIdentifier ?: codigo }];
	}
	NSData *dados = [NSJSONSerialization dataWithJSONObject:lista options:0 error:nil];
	return dados ? [[NSString alloc] initWithData:dados encoding:NSUTF8StringEncoding] : @"[]";
}

- (void)finalizar:(NSString *)transacao {
	SKPaymentTransaction *t = self.aguardando[transacao];
	if (t != nil) {
		[[SKPaymentQueue defaultQueue] finishTransaction:t];
		[self.aguardando removeObjectForKey:transacao];
	}
}

@end

BarStore *BarStore::instance = nullptr;

void BarStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("buscar", "ids"), &BarStore::buscar);
	ClassDB::bind_method(D_METHOD("comprar", "id", "usuario"), &BarStore::comprar);
	ClassDB::bind_method(D_METHOD("restaurar"), &BarStore::restaurar);
	ClassDB::bind_method(D_METHOD("pendentes"), &BarStore::pendentes);
	ClassDB::bind_method(D_METHOD("finalizar", "transacao"), &BarStore::finalizar);

	ADD_SIGNAL(MethodInfo("produtos", PropertyInfo(Variant::STRING, "json")));
	ADD_SIGNAL(MethodInfo("compra_ok", PropertyInfo(Variant::STRING, "produto"), PropertyInfo(Variant::STRING, "transacao"), PropertyInfo(Variant::STRING, "original")));
	ADD_SIGNAL(MethodInfo("compra_falhou", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("compra_cancelada"));
	ADD_SIGNAL(MethodInfo("restauracao_pronta"));
}

BarStore *BarStore::get_singleton() {
	return instance;
}

void BarStore::buscar(const PackedStringArray &p_ids) {
	NSMutableArray *ids = [NSMutableArray array];
	for (int i = 0; i < p_ids.size(); i++) {
		[ids addObject:textoDe(p_ids[i])];
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host buscar:ids];
	});
}

void BarStore::comprar(const String &p_id, const String &p_usuario) {
	NSString *codigo = textoDe(p_id);
	NSString *usuario = textoDe(p_usuario);
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host comprar:codigo usuario:usuario];
	});
}

void BarStore::restaurar() {
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host restaurar];
	});
}

String BarStore::pendentes() {
	__block NSString *r = @"[]";
	if ([NSThread isMainThread]) {
		r = [host listaPendentes];
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			r = [this->host listaPendentes];
		});
	}
	return godotDe(r);
}

void BarStore::finalizar(const String &p_transacao) {
	NSString *codigo = textoDe(p_transacao);
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host finalizar:codigo];
	});
}

void BarStore::_emit_produtos(const String &p_json) {
	emit_signal("produtos", p_json);
}

void BarStore::_emit_compra_ok(const String &p_produto, const String &p_transacao, const String &p_original) {
	emit_signal("compra_ok", p_produto, p_transacao, p_original);
}

void BarStore::_emit_compra_falhou(const String &p_mensagem) {
	emit_signal("compra_falhou", p_mensagem);
}

void BarStore::_emit_compra_cancelada() {
	emit_signal("compra_cancelada");
}

void BarStore::_emit_restauracao_pronta() {
	emit_signal("restauracao_pronta");
}

BarStore::BarStore() {
	instance = this;
	host = [[BarStoreHost alloc] init];
	host.owner = this;
	[host iniciar];
}

BarStore::~BarStore() {
	if (host) {
		host.owner = nullptr;
		host = nil;
	}
	instance = nullptr;
}
