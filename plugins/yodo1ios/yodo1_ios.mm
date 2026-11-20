#include "yodo1_ios.h"

#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Fala com o SDK do Yodo1 MAS (pod Yodo1MasFull) pelo runtime do Objective-C. Vive na thread principal.
// E o "adDelegate" do video premiado: o SDK chama os metodos onRewardAd... abaixo.
@interface Yodo1IosHost : NSObject
@property(nonatomic, assign) Yodo1Ios *owner;
- (void)iniciaComChave:(NSString *)chave coppa:(BOOL)coppa gdpr:(BOOL)gdpr ccpa:(BOOL)ccpa;
- (void)carrega;
- (BOOL)pronto;
- (void)mostra;
@end

static NSString *textoDe(const String &s) {
	return [NSString stringWithUTF8String:s.utf8().get_data()];
}

static String godotDe(NSString *s) {
	return String::utf8(s ? s.UTF8String : "");
}

// sharedInstance de uma classe do SDK, ou nil se o SDK nao entrou no app (Podfile esquecido).
static id instanciaDe(NSString *classe) {
	Class c = NSClassFromString(classe);
	if (c == nil || ![c respondsToSelector:@selector(sharedInstance)]) {
		return nil;
	}
	return ((id(*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance));
}

@implementation Yodo1IosHost

- (void)emite:(const char *)sinal {
	if (self.owner) {
		self.owner->_emite(String(sinal), String(), false);
	}
}

- (void)emite:(const char *)sinal texto:(NSString *)texto {
	if (self.owner) {
		self.owner->_emite(String(sinal), godotDe(texto ?: @"erro"), true);
	}
}

- (id)video {
	return instanciaDe(@"Yodo1MasRewardAd");
}

- (void)iniciaComChave:(NSString *)chave coppa:(BOOL)coppa gdpr:(BOOL)gdpr ccpa:(BOOL)ccpa {
	id mas = instanciaDe(@"Yodo1Mas");
	if (mas == nil) {
		[self emite:"falhou_iniciar" texto:@"SDK do Yodo1 ausente"];
		return;
	}
	[mas setValue:@(coppa) forKey:@"isCOPPAAgeRestricted"];
	[mas setValue:@(gdpr) forKey:@"isGDPRUserConsent"];
	[mas setValue:@(ccpa) forKey:@"isCCPADoNotSell"];
	// o SDK confere a conformidade do delegado: o protocolo existe em tempo de execucao quando o pod esta no app
	Protocol *protocolo = objc_getProtocol("Yodo1MasRewardAdDelegate");
	if (protocolo != NULL && !class_conformsToProtocol([Yodo1IosHost class], protocolo)) {
		class_addProtocol([Yodo1IosHost class], protocolo);
	}
	id video = [self video];
	if (video != nil) {
		[video setValue:self forKey:@"adDelegate"];
	}
	__weak Yodo1IosHost *eu = self;
	void (^ok)(void) = ^{
		[eu emite:"iniciou"];
	};
	void (^falhou)(NSError *) = ^(NSError *erro) {
		[eu emite:"falhou_iniciar" texto:erro.localizedDescription];
	};
	SEL inicia = NSSelectorFromString(@"initMasWithAppKey:successfulHandler:failHandler:");
	((void (*)(id, SEL, NSString *, id, id))objc_msgSend)(mas, inicia, chave, ok, falhou);
}

- (void)carrega {
	id video = [self video];
	if (video != nil) {
		((void (*)(id, SEL))objc_msgSend)(video, @selector(loadAd));
	}
}

- (BOOL)pronto {
	id video = [self video];
	if (video == nil) {
		return NO;
	}
	return ((BOOL(*)(id, SEL))objc_msgSend)(video, NSSelectorFromString(@"isLoaded"));
}

- (void)mostra {
	id video = [self video];
	if (video == nil) {
		[self emite:"video_nao_abriu" texto:@"SDK do Yodo1 ausente"];
		return;
	}
	if ([video respondsToSelector:@selector(showAd)]) {
		((void (*)(id, SEL))objc_msgSend)(video, @selector(showAd));
	} else {
		SEL comLugar = NSSelectorFromString(@"showAdWithPlacement:customData:");
		((void (*)(id, SEL, id, id))objc_msgSend)(video, comLugar, nil, nil);
	}
}

// ---- Yodo1MasRewardAdDelegate

- (void)onRewardAdLoaded:(id)ad {
	[self emite:"video_carregado"];
}

- (void)onRewardAdFailedToLoad:(id)ad withError:(NSError *)error {
	[self emite:"video_falhou" texto:error.localizedDescription];
}

- (void)onRewardAdOpened:(id)ad {
}

- (void)onRewardAdFailedToOpen:(id)ad withError:(NSError *)error {
	[self emite:"video_nao_abriu" texto:error.localizedDescription];
}

- (void)onRewardAdClosed:(id)ad {
	[self emite:"video_fechado"];
}

- (void)onRewardAdEarned:(id)ad {
	[self emite:"video_ganhou"];
}

@end

void Yodo1Ios::_bind_methods() {
	ClassDB::bind_method(D_METHOD("inicia", "app_key", "coppa", "gdpr", "ccpa"), &Yodo1Ios::inicia);
	ClassDB::bind_method(D_METHOD("carregaVideo"), &Yodo1Ios::carregaVideo);
	ClassDB::bind_method(D_METHOD("videoPronto"), &Yodo1Ios::videoPronto);
	ClassDB::bind_method(D_METHOD("mostraVideo"), &Yodo1Ios::mostraVideo);
	ClassDB::bind_method(D_METHOD("carregaIntersticial"), &Yodo1Ios::carregaIntersticial);
	ClassDB::bind_method(D_METHOD("intersticialPronto"), &Yodo1Ios::intersticialPronto);
	ClassDB::bind_method(D_METHOD("mostraIntersticial"), &Yodo1Ios::mostraIntersticial);

	ADD_SIGNAL(MethodInfo("iniciou"));
	ADD_SIGNAL(MethodInfo("falhou_iniciar", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("video_carregado"));
	ADD_SIGNAL(MethodInfo("video_falhou", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("video_nao_abriu", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("video_ganhou"));
	ADD_SIGNAL(MethodInfo("video_fechado"));
}

// O aviso vai para o laco do jogo (call_deferred): o SDK chama de qualquer thread.
void Yodo1Ios::_emite(const String &p_sinal, const String &p_texto, bool p_com_texto) {
	if (p_com_texto) {
		call_deferred("emit_signal", p_sinal, p_texto);
	} else {
		call_deferred("emit_signal", p_sinal);
	}
}

// Antes de iniciar, a pergunta de rastreamento da Apple (ATT): o anuncio funciona com sim ou com nao.
void Yodo1Ios::inicia(const String &p_app_key, bool p_coppa, bool p_gdpr, bool p_ccpa) {
	NSString *chave = textoDe(p_app_key);
	Yodo1IosHost *h = host;
	void (^comeca)(void) = ^{
		[h iniciaComChave:chave coppa:p_coppa gdpr:p_gdpr ccpa:p_ccpa];
	};
	dispatch_async(dispatch_get_main_queue(), ^{
		if (@available(iOS 14, *)) {
			[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
				dispatch_async(dispatch_get_main_queue(), comeca);
			}];
		} else {
			comeca();
		}
	});
}

void Yodo1Ios::carregaVideo() {
	Yodo1IosHost *h = host;
	dispatch_async(dispatch_get_main_queue(), ^{
		[h carrega];
	});
}

bool Yodo1Ios::videoPronto() {
	__block BOOL r = NO;
	Yodo1IosHost *h = host;
	if ([NSThread isMainThread]) {
		r = [h pronto];
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			r = [h pronto];
		});
	}
	return r;
}

void Yodo1Ios::mostraVideo() {
	Yodo1IosHost *h = host;
	dispatch_async(dispatch_get_main_queue(), ^{
		[h mostra];
	});
}

Yodo1Ios::Yodo1Ios() {
	host = [[Yodo1IosHost alloc] init];
	host.owner = this;
}

Yodo1Ios::~Yodo1Ios() {
	if (host) {
		host.owner = nullptr;
		host = nil;
	}
}
