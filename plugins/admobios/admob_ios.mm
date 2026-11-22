#include "admob_ios.h"

#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Fala com o SDK do AdMob (pod Google-Mobile-Ads-SDK) e com o formulario de privacidade do Google (pod
// GoogleUserMessagingPlatform) pelo runtime do Objective-C. Vive na thread principal.
// E o "fullScreenContentDelegate" do video e do intersticial e o "delegate" do banner: o SDK chama os metodos
// adDidDismissFullScreenContent:, bannerViewDidReceiveAd: etc. abaixo.

// Tamanho de anuncio do AdMob (o GADAdSize do SDK): largura x altura e um campo de opcoes.
typedef struct {
	CGSize size;
	NSUInteger flags;
} TamanhoDoAnuncio;

@interface AdMobIosHost : NSObject
@property(nonatomic, assign) AdMobIos *owner;
@property(nonatomic, strong) id video;
@property(nonatomic, strong) id intersticial;
@property(nonatomic, strong) UIView *banner;
@property(nonatomic, assign) BOOL carregandoBanner;
@property(nonatomic, assign) BOOL bannerFalhou;
@end

static NSString *textoDe(const String &s) {
	return [NSString stringWithUTF8String:s.utf8().get_data()];
}

static String godotDe(NSString *s) {
	return String::utf8(s ? s.UTF8String : "");
}

// A tela de cima de tudo: o controlador do Godot ou o que estiver aberto por cima dele.
static UIViewController *telaDeCima() {
	UIWindow *janela = nil;
	for (UIScene *cena in UIApplication.sharedApplication.connectedScenes) {
		if (![cena isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)cena).windows) {
			if (w.isKeyWindow) {
				janela = w;
			}
		}
		if (janela == nil && ((UIWindowScene *)cena).windows.count > 0) {
			janela = ((UIWindowScene *)cena).windows.firstObject;
		}
	}
	UIViewController *vc = janela.rootViewController;
	while (vc.presentedViewController != nil) {
		vc = vc.presentedViewController;
	}
	return vc;
}

// Um pedido de anuncio novo (GADRequest), ou nil se o SDK nao entrou no app.
static id pedidoNovo() {
	Class c = NSClassFromString(@"GADRequest");
	if (c == nil) {
		return nil;
	}
	return ((id(*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"request"));
}

// O app ganha a conformidade ao protocolo do SDK em tempo de execucao (o SDK confere antes de chamar).
static void conformaA(const char *protocolo) {
	Protocol *p = objc_getProtocol(protocolo);
	if (p != NULL && !class_conformsToProtocol([AdMobIosHost class], p)) {
		class_addProtocol([AdMobIosHost class], p);
	}
}

@implementation AdMobIosHost

- (void)emite:(const char *)sinal {
	if (self.owner) {
		self.owner->_emite(String(sinal), Variant(), false);
	}
}

- (void)emite:(const char *)sinal texto:(NSString *)texto {
	if (self.owner) {
		self.owner->_emite(String(sinal), Variant(godotDe(texto ?: @"erro")), true);
	}
}

- (void)emite:(const char *)sinal valor:(const Variant &)valor {
	if (self.owner) {
		self.owner->_emite(String(sinal), valor, true);
	}
}

// ---- formulario de privacidade do Google (UMP: Europa, Reino Unido e estados dos EUA com lei)

- (BOOL)podeAnunciar {
	Class c = NSClassFromString(@"UMPConsentInformation");
	if (c == nil) {
		return YES;  // sem o SDK do formulario: segue como fora dessas regioes
	}
	id info = ((id(*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedInstance"));
	return ((BOOL(*)(id, SEL))objc_msgSend)(info, NSSelectorFromString(@"canRequestAds"));
}

- (void)consentimento {
	Class cInfo = NSClassFromString(@"UMPConsentInformation");
	Class cParametros = NSClassFromString(@"UMPRequestParameters");
	Class cFormulario = NSClassFromString(@"UMPConsentForm");
	if (cInfo == nil || cParametros == nil || cFormulario == nil) {
		[self emite:"consentimento_pronto" valor:Variant(true)];
		return;
	}
	id info = ((id(*)(id, SEL))objc_msgSend)(cInfo, NSSelectorFromString(@"sharedInstance"));
	id parametros = [[cParametros alloc] init];
	__weak AdMobIosHost *eu = self;
	void (^fim)(void) = ^{
		[eu emite:"consentimento_pronto" valor:Variant((bool)[eu podeAnunciar])];
	};
	void (^depoisDoFormulario)(NSError *) = ^(NSError *erro) {
		if (erro != nil) {
			NSLog(@"[AdMobGodot] formulario UMP: %@", erro.localizedDescription);
		}
		dispatch_async(dispatch_get_main_queue(), fim);
	};
	void (^depoisDaAtualizacao)(NSError *) = ^(NSError *erro) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (erro != nil) {
				NSLog(@"[AdMobGodot] UMP: %@", erro.localizedDescription);
				fim();
				return;
			}
			SEL mostra = NSSelectorFromString(@"loadAndPresentIfRequiredFromViewController:completionHandler:");
			((void (*)(id, SEL, id, id))objc_msgSend)(cFormulario, mostra, telaDeCima(), depoisDoFormulario);
		});
	};
	SEL atualiza = NSSelectorFromString(@"requestConsentInfoUpdateWithParameters:completionHandler:");
	((void (*)(id, SEL, id, id))objc_msgSend)(info, atualiza, parametros, depoisDaAtualizacao);
}

// ---- inicio do AdMob

- (void)inicia {
	Class c = NSClassFromString(@"GADMobileAds");
	if (c == nil) {
		NSLog(@"[AdMobGodot] SDK do AdMob ausente no app");
		return;
	}
	conformaA("GADFullScreenContentDelegate");
	conformaA("GADBannerViewDelegate");
	id ads = ((id(*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedInstance"));
	__weak AdMobIosHost *eu = self;
	void (^pronto)(id) = ^(id estado) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[eu emite:"iniciou"];
		});
	};
	((void (*)(id, SEL, id))objc_msgSend)(ads, NSSelectorFromString(@"startWithCompletionHandler:"), pronto);
}

// ---- video premiado

- (void)carregaVideo:(NSString *)idBloco {
	Class c = NSClassFromString(@"GADRewardedAd");
	id pedido = pedidoNovo();
	if (c == nil || pedido == nil) {
		[self emite:"video_falhou" texto:@"SDK do AdMob ausente"];
		return;
	}
	self.video = nil;
	__weak AdMobIosHost *eu = self;
	void (^chegou)(id, NSError *) = ^(id anuncio, NSError *erro) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (erro != nil || anuncio == nil) {
				[eu emite:"video_falhou" texto:erro.localizedDescription];
				return;
			}
			[anuncio setValue:eu forKey:@"fullScreenContentDelegate"];
			eu.video = anuncio;
			[eu emite:"video_carregado"];
		});
	};
	SEL carrega = NSSelectorFromString(@"loadWithAdUnitID:request:completionHandler:");
	((void (*)(id, SEL, NSString *, id, id))objc_msgSend)(c, carrega, idBloco, pedido, chegou);
}

- (void)mostraVideo {
	id anuncio = self.video;
	if (anuncio == nil) {
		[self emite:"video_nao_abriu" texto:@"nenhum video carregado"];
		return;
	}
	__weak AdMobIosHost *eu = self;
	void (^ganhou)(void) = ^{
		[eu emite:"video_ganhou"];
	};
	SEL mostra = NSSelectorFromString(@"presentFromRootViewController:userDidEarnRewardHandler:");
	((void (*)(id, SEL, id, id))objc_msgSend)(anuncio, mostra, telaDeCima(), ganhou);
}

// ---- intersticial

- (void)carregaIntersticial:(NSString *)idBloco {
	Class c = NSClassFromString(@"GADInterstitialAd");
	id pedido = pedidoNovo();
	if (c == nil || pedido == nil) {
		[self emite:"intersticial_falhou" texto:@"SDK do AdMob ausente"];
		return;
	}
	self.intersticial = nil;
	__weak AdMobIosHost *eu = self;
	void (^chegou)(id, NSError *) = ^(id anuncio, NSError *erro) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (erro != nil || anuncio == nil) {
				[eu emite:"intersticial_falhou" texto:erro.localizedDescription];
				return;
			}
			[anuncio setValue:eu forKey:@"fullScreenContentDelegate"];
			eu.intersticial = anuncio;
			[eu emite:"intersticial_carregado"];
		});
	};
	SEL carrega = NSSelectorFromString(@"loadWithAdUnitID:request:completionHandler:");
	((void (*)(id, SEL, NSString *, id, id))objc_msgSend)(c, carrega, idBloco, pedido, chegou);
}

- (void)mostraIntersticial {
	id anuncio = self.intersticial;
	if (anuncio == nil) {
		[self emite:"intersticial_falhou" texto:@"nenhum intersticial carregado"];
		[self emite:"intersticial_fechado"];
		return;
	}
	((void (*)(id, SEL, id))objc_msgSend)(anuncio, NSSelectorFromString(@"presentFromRootViewController:"), telaDeCima());
}

// ---- GADFullScreenContentDelegate (video e intersticial)

- (void)adDidDismissFullScreenContent:(id)anuncio {
	if (anuncio == self.video) {
		self.video = nil;  // cada video so passa uma vez: o jogo carrega o proximo
		[self emite:"video_fechado"];
	} else if (anuncio == self.intersticial) {
		self.intersticial = nil;
		[self emite:"intersticial_fechado"];
	}
}

- (void)ad:(id)anuncio didFailToPresentFullScreenContentWithError:(NSError *)erro {
	if (anuncio == self.video) {
		self.video = nil;
		[self emite:"video_nao_abriu" texto:erro.localizedDescription];
	} else if (anuncio == self.intersticial) {
		self.intersticial = nil;
		[self emite:"intersticial_falhou" texto:erro.localizedDescription];
		[self emite:"intersticial_fechado"];
	}
}

// ---- banner (320x50 no alto, no meio, logo abaixo da area segura)

- (void)carregaBanner {
	if (self.carregandoBanner) {
		return;
	}
	id pedido = pedidoNovo();
	if (pedido == nil) {
		return;
	}
	self.carregandoBanner = YES;
	self.bannerFalhou = NO;
	((void (*)(id, SEL, id))objc_msgSend)(self.banner, NSSelectorFromString(@"loadRequest:"), pedido);
}

- (void)mostraBanner:(NSString *)idBloco {
	if (self.banner == nil) {
		Class c = NSClassFromString(@"GADBannerView");
		UIViewController *tela = telaDeCima();
		if (c == nil || tela == nil) {
			[self emite:"banner_falhou" texto:@"SDK do AdMob ausente"];
			return;
		}
		TamanhoDoAnuncio tamanho = { CGSizeMake(320, 50), 0 };  // o GADAdSizeBanner do SDK
		TamanhoDoAnuncio *doSdk = (TamanhoDoAnuncio *)dlsym(RTLD_DEFAULT, "GADAdSizeBanner");
		if (doSdk != NULL) {
			tamanho = *doSdk;
		}
		id banner = ((id(*)(id, SEL, TamanhoDoAnuncio))objc_msgSend)([c alloc], NSSelectorFromString(@"initWithAdSize:"), tamanho);
		[banner setValue:idBloco forKey:@"adUnitID"];
		[banner setValue:tela forKey:@"rootViewController"];
		[banner setValue:self forKey:@"delegate"];
		UIView *v = (UIView *)banner;
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[tela.view addSubview:v];
		[NSLayoutConstraint activateConstraints:@[
			[v.topAnchor constraintEqualToAnchor:tela.view.safeAreaLayoutGuide.topAnchor],
			[v.centerXAnchor constraintEqualToAnchor:tela.view.centerXAnchor],
			[v.widthAnchor constraintEqualToConstant:tamanho.size.width],
			[v.heightAnchor constraintEqualToConstant:tamanho.size.height],
		]];
		self.banner = v;
		[self carregaBanner];
	} else if (self.bannerFalhou) {
		[self carregaBanner];  // a ultima tentativa falhou: tenta de novo agora que o jogo pediu
	}
	self.banner.hidden = NO;
	[self.banner.superview bringSubviewToFront:self.banner];
}

- (void)escondeBanner {
	self.banner.hidden = YES;
}

// ---- GADBannerViewDelegate

- (void)bannerViewDidReceiveAd:(id)banner {
	self.carregandoBanner = NO;
	[self emite:"banner_carregado"];
}

- (void)bannerView:(id)banner didFailToReceiveAdWithError:(NSError *)erro {
	self.carregandoBanner = NO;
	self.bannerFalhou = YES;
	[self emite:"banner_falhou" texto:erro.localizedDescription];
}

@end

void AdMobIos::_bind_methods() {
	ClassDB::bind_method(D_METHOD("consentimento"), &AdMobIos::consentimento);
	ClassDB::bind_method(D_METHOD("rastreamentoStatus"), &AdMobIos::rastreamentoStatus);
	ClassDB::bind_method(D_METHOD("pedeRastreamento"), &AdMobIos::pedeRastreamento);
	ClassDB::bind_method(D_METHOD("inicia"), &AdMobIos::inicia);
	ClassDB::bind_method(D_METHOD("carregaVideo", "id"), &AdMobIos::carregaVideo);
	ClassDB::bind_method(D_METHOD("videoPronto"), &AdMobIos::videoPronto);
	ClassDB::bind_method(D_METHOD("mostraVideo"), &AdMobIos::mostraVideo);
	ClassDB::bind_method(D_METHOD("carregaIntersticial", "id"), &AdMobIos::carregaIntersticial);
	ClassDB::bind_method(D_METHOD("intersticialPronto"), &AdMobIos::intersticialPronto);
	ClassDB::bind_method(D_METHOD("mostraIntersticial"), &AdMobIos::mostraIntersticial);
	ClassDB::bind_method(D_METHOD("mostraBanner", "id"), &AdMobIos::mostraBanner);
	ClassDB::bind_method(D_METHOD("escondeBanner"), &AdMobIos::escondeBanner);

	ADD_SIGNAL(MethodInfo("consentimento_pronto", PropertyInfo(Variant::BOOL, "pode_anunciar")));
	ADD_SIGNAL(MethodInfo("rastreamento_respondeu", PropertyInfo(Variant::INT, "status")));
	ADD_SIGNAL(MethodInfo("iniciou"));
	ADD_SIGNAL(MethodInfo("video_carregado"));
	ADD_SIGNAL(MethodInfo("video_falhou", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("video_nao_abriu", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("video_ganhou"));
	ADD_SIGNAL(MethodInfo("video_fechado"));
	ADD_SIGNAL(MethodInfo("intersticial_carregado"));
	ADD_SIGNAL(MethodInfo("intersticial_falhou", PropertyInfo(Variant::STRING, "mensagem")));
	ADD_SIGNAL(MethodInfo("intersticial_fechado"));
	ADD_SIGNAL(MethodInfo("banner_carregado"));
	ADD_SIGNAL(MethodInfo("banner_falhou", PropertyInfo(Variant::STRING, "mensagem")));
}

// O aviso vai para o laco do jogo (call_deferred): o SDK chama de qualquer thread.
void AdMobIos::_emite(const String &p_sinal, const Variant &p_valor, bool p_com_valor) {
	if (p_com_valor) {
		call_deferred("emit_signal", p_sinal, p_valor);
	} else {
		call_deferred("emit_signal", p_sinal);
	}
}

// Roda um bloco na thread principal: na hora, se ja estiver nela; senao, na fila dela.
static void naThreadPrincipal(void (^bloco)(void)) {
	if ([NSThread isMainThread]) {
		bloco();
	} else {
		dispatch_async(dispatch_get_main_queue(), bloco);
	}
}

void AdMobIos::consentimento() {
	AdMobIosHost *h = host;
	naThreadPrincipal(^{
		[h consentimento];
	});
}

// 0 = ainda nao perguntado, 1 = restrito, 2 = negado, 3 = permitido. iPhone antigo (sem a pergunta): 3.
int AdMobIos::rastreamentoStatus() {
	if (@available(iOS 14, *)) {
		return (int)ATTrackingManager.trackingAuthorizationStatus;
	}
	return 3;
}

void AdMobIos::pedeRastreamento() {
	AdMobIosHost *h = host;
	naThreadPrincipal(^{
		if (@available(iOS 14, *)) {
			[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[h emite:"rastreamento_respondeu" valor:Variant((int)status)];
				});
			}];
		} else {
			[h emite:"rastreamento_respondeu" valor:Variant(3)];
		}
	});
}

void AdMobIos::inicia() {
	AdMobIosHost *h = host;
	naThreadPrincipal(^{
		[h inicia];
	});
}

void AdMobIos::carregaVideo(const String &p_id) {
	AdMobIosHost *h = host;
	NSString *id_bloco = textoDe(p_id);
	naThreadPrincipal(^{
		[h carregaVideo:id_bloco];
	});
}

bool AdMobIos::videoPronto() {
	return host.video != nil;
}

void AdMobIos::mostraVideo() {
	AdMobIosHost *h = host;
	naThreadPrincipal(^{
		[h mostraVideo];
	});
}

void AdMobIos::carregaIntersticial(const String &p_id) {
	AdMobIosHost *h = host;
	NSString *id_bloco = textoDe(p_id);
	naThreadPrincipal(^{
		[h carregaIntersticial:id_bloco];
	});
}

bool AdMobIos::intersticialPronto() {
	return host.intersticial != nil;
}

void AdMobIos::mostraIntersticial() {
	AdMobIosHost *h = host;
	naThreadPrincipal(^{
		[h mostraIntersticial];
	});
}

void AdMobIos::mostraBanner(const String &p_id) {
	AdMobIosHost *h = host;
	NSString *id_bloco = textoDe(p_id);
	naThreadPrincipal(^{
		[h mostraBanner:id_bloco];
	});
}

void AdMobIos::escondeBanner() {
	AdMobIosHost *h = host;
	naThreadPrincipal(^{
		[h escondeBanner];
	});
}

AdMobIos::AdMobIos() {
	host = [[AdMobIosHost alloc] init];
	host.owner = this;
}

AdMobIos::~AdMobIos() {
	if (host) {
		host.owner = nullptr;
		[host.banner removeFromSuperview];
		host = nil;
	}
}
