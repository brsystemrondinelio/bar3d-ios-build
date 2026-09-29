#include "bar_apple.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <UIKit/UIKit.h>

@interface BarAppleHost : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>
@property(nonatomic, assign) BarApple *owner;
@property(nonatomic, strong) ASAuthorizationController *controle;
- (void)entrar;
@end

@implementation BarAppleHost

- (void)entrar {
	ASAuthorizationAppleIDProvider *provedor = [[ASAuthorizationAppleIDProvider alloc] init];
	ASAuthorizationAppleIDRequest *pedido = [provedor createRequest];
	pedido.requestedScopes = @[ ASAuthorizationScopeFullName, ASAuthorizationScopeEmail ];
	self.controle = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[ pedido ]];
	self.controle.delegate = self;
	self.controle.presentationContextProvider = self;
	[self.controle performRequests];
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
	for (UIScene *cena in UIApplication.sharedApplication.connectedScenes) {
		if ([cena isKindOfClass:[UIWindowScene class]]) {
			UIWindow *janela = ((UIWindowScene *)cena).windows.firstObject;
			if (janela) {
				return janela;
			}
		}
	}
	return [[UIWindow alloc] init];
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
	if (self.owner == nullptr) {
		return;
	}
	if (![authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
		self.owner->_emit_fail("credencial inesperada");
		return;
	}
	ASAuthorizationAppleIDCredential *credencial = (ASAuthorizationAppleIDCredential *)authorization.credential;
	NSString *token = credencial.identityToken ? [[NSString alloc] initWithData:credencial.identityToken encoding:NSUTF8StringEncoding] : @"";
	// A Apple so entrega o nome na primeira vez que a pessoa entra.
	NSString *nome = @"";
	if (credencial.fullName.givenName.length > 0) {
		nome = credencial.fullName.givenName;
	}
	self.owner->_emit_ok(String::utf8(token.UTF8String ?: ""), String::utf8(credencial.user.UTF8String ?: ""), String::utf8(nome.UTF8String ?: ""));
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
	if (self.owner == nullptr) {
		return;
	}
	// Cancelar a janela nao e' falha do jogo: o codigo 1001 e' "cancelado".
	String mensagem = (error.code == ASAuthorizationErrorCanceled) ? String("cancelado") : String::utf8(error.localizedDescription.UTF8String ?: "erro");
	self.owner->_emit_fail(mensagem);
}

@end

BarApple *BarApple::instance = nullptr;

void BarApple::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sign_in"), &BarApple::sign_in);

	ADD_SIGNAL(MethodInfo("apple_ok", PropertyInfo(Variant::STRING, "token"), PropertyInfo(Variant::STRING, "user"), PropertyInfo(Variant::STRING, "name")));
	ADD_SIGNAL(MethodInfo("apple_fail", PropertyInfo(Variant::STRING, "message")));
}

BarApple *BarApple::get_singleton() {
	return instance;
}

void BarApple::sign_in() {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (this->host == nil) {
			this->host = [[BarAppleHost alloc] init];
			this->host.owner = this;
		}
		[this->host entrar];
	});
}

void BarApple::_emit_ok(const String &p_token, const String &p_user, const String &p_name) {
	emit_signal("apple_ok", p_token, p_user, p_name);
}

void BarApple::_emit_fail(const String &p_message) {
	emit_signal("apple_fail", p_message);
}

BarApple::BarApple() {
	instance = this;
}

BarApple::~BarApple() {
	if (host) {
		host.owner = nullptr;
		host = nil;
	}
	instance = nullptr;
}
