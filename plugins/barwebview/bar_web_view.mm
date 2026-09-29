#include "bar_web_view.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// Igual ao DESKTOP_UA do Android: com agente de celular o cliente da PG acha
// que o aparelho esta de lado e bloqueia com "gire para retrato". A marca no
// fim e' a que o servidor reconhece para travar a tela cheia.
static NSString *const kUserAgent = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 Bar3DCabinet/1";

// Toque da tela do gabinete: a Apple nao deixa fabricar um toque nativo num
// WKWebView, entao o plugin entrega os mesmos eventos por JavaScript.
static NSString *const kToqueJS = @"function(a,x,y){"
	"var e=document.elementFromPoint(x,y)||document.body;"
	"var o={bubbles:true,cancelable:true,composed:true,clientX:x,clientY:y,screenX:x,screenY:y,view:window,button:0,buttons:(a==1?0:1)};"
	"var p=Object.assign({pointerId:1,pointerType:'touch',isPrimary:true,width:1,height:1},o);"
	"function pe(t){try{e.dispatchEvent(new PointerEvent(t,p));}catch(_){}}"
	"function me(t){e.dispatchEvent(new MouseEvent(t,o));}"
	"if(a==0){pe('pointerdown');me('mousedown');}"
	"else if(a==2){pe('pointermove');me('mousemove');}"
	"else{pe('pointerup');me('mouseup');me('click');}"
	"}";

@interface BarWebHost : NSObject <WKNavigationDelegate>
@property(nonatomic, assign) BarWebView *owner;
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, assign) BOOL emVoo;
@property(nonatomic, assign) int quadros;
@property(nonatomic, assign) int quedas;
@property(nonatomic, assign) int largura;
@property(nonatomic, assign) int altura;
- (void)abrir:(NSString *)url largura:(int)w altura:(int)h;
- (void)cadencia:(int)fps;
- (void)abrirSobreposto:(NSString *)url;
- (void)retanguloX:(int)x y:(int)y largura:(int)w altura:(int)h;
- (void)visivel:(BOOL)v;
- (void)fechar;
@end

@implementation BarWebHost

- (void)abrir:(NSString *)url largura:(int)w altura:(int)h {
	[self fechar];
	self.largura = w;
	self.altura = h;
	self.quadros = 0;

	WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
	cfg.allowsInlineMediaPlayback = YES;
	// Os jogos tocam o som sem um toque na propria pagina.
	cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
	WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, w, h) configuration:cfg];
	wv.customUserAgent = kUserAgent;
	wv.navigationDelegate = self;
	wv.opaque = YES;
	wv.backgroundColor = UIColor.blackColor;
	wv.scrollView.scrollEnabled = NO;
	wv.scrollView.bounces = NO;
	wv.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	self.web = wv;

	// O WKWebView precisa estar numa janela para desenhar; fica ATRAS da vista
	// do Godot (que cobre a tela toda), entao o jogador nunca o ve.
	UIWindow *janela = nil;
	for (UIScene *cena in UIApplication.sharedApplication.connectedScenes) {
		if ([cena isKindOfClass:[UIWindowScene class]]) {
			janela = ((UIWindowScene *)cena).windows.firstObject;
			break;
		}
	}
	UIView *pai = janela.rootViewController.view ?: janela;
	[pai insertSubview:wv atIndex:0];

	NSURL *alvo = [NSURL URLWithString:url];
	if (alvo) {
		[wv loadRequest:[NSURLRequest requestWithURL:alvo]];
	}
}

- (UIView *)vistaDoJogo {
	UIWindow *janela = nil;
	for (UIScene *cena in UIApplication.sharedApplication.connectedScenes) {
		if ([cena isKindOfClass:[UIWindowScene class]]) {
			janela = ((UIWindowScene *)cena).windows.firstObject;
			break;
		}
	}
	return janela.rootViewController.view ?: janela;
}

// SOBREPOSTO: o WKWebView vive POR CIMA da vista do Godot, escondido, e o jogo
// o posiciona sobre o vidro do gabinete. Desenha na GPU (60 quadros) e recebe o
// toque nativo -- ao contrario do modo de quadros, que fotografa a pagina.
- (void)abrirSobreposto:(NSString *)url {
	[self fechar];
	self.quadros = 0;
	self.quedas = 0;
	WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
	cfg.allowsInlineMediaPlayback = YES;
	cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
	WKWebView *wv = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 480) configuration:cfg];
	wv.customUserAgent = kUserAgent;
	wv.navigationDelegate = self;
	wv.opaque = YES;
	wv.backgroundColor = UIColor.blackColor;
	wv.scrollView.scrollEnabled = NO;
	wv.scrollView.bounces = NO;
	wv.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	wv.hidden = YES;
	self.web = wv;
	[[self vistaDoJogo] addSubview:wv];
	NSURL *alvo = [NSURL URLWithString:url];
	if (alvo) {
		[wv loadRequest:[NSURLRequest requestWithURL:alvo]];
	}
}

// O jogo fala em PIXELS da janela; o UIKit, em pontos.
- (void)retanguloX:(int)x y:(int)y largura:(int)w altura:(int)h {
	if (self.web == nil) {
		return;
	}
	// O jogo entrega PIXEIS da janela; o UIKit trabalha em pontos. A vista raiz do
	// Godot e' um UIView comum (contentScaleFactor = 1): usar o fator DELA dava a
	// janela do jogo 2x maior e deslocada (foto do dono no iPhone, 29/09). O certo
	// e' o fator da TELA.
	CGFloat escala = UIScreen.mainScreen.nativeScale;
	if (escala < 1) {
		escala = 1;
	}
	self.web.frame = CGRectMake(x / escala, y / escala, w / escala, h / escala);
}

- (void)visivel:(BOOL)v {
	self.web.hidden = !v;
}

- (void)cadencia:(int)fps {
	[self.timer invalidate];
	self.timer = nil;
	if (fps <= 0 || self.web == nil) {
		return;
	}
	self.timer = [NSTimer timerWithTimeInterval:1.0 / fps
										 target:self
									   selector:@selector(fotografar)
									   userInfo:nil
										repeats:YES];
	[[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)fotografar {
	// Um quadro por vez: se a foto anterior nao voltou, pula este.
	if (self.emVoo || self.web == nil) {
		return;
	}
	self.emVoo = YES;
	WKSnapshotConfiguration *conf = [[WKSnapshotConfiguration alloc] init];
	conf.snapshotWidth = @(self.largura);
	__weak BarWebHost *fraco = self;
	[self.web takeSnapshotWithConfiguration:conf
						  completionHandler:^(UIImage *imagem, NSError *erro) {
							  BarWebHost *eu = fraco;
							  if (eu == nil) {
								  return;
							  }
							  eu.emVoo = NO;
							  if (imagem == nil || eu.owner == nullptr) {
								  return;
							  }
							  NSData *jpeg = UIImageJPEGRepresentation(imagem, 0.7);
							  if (jpeg.length == 0) {
								  return;
							  }
							  eu.quadros += 1;
							  eu.owner->_emit_frame((const uint8_t *)jpeg.bytes, (int)jpeg.length);
						  }];
}

- (void)fechar {
	[self.timer invalidate];
	self.timer = nil;
	self.emVoo = NO;
	if (self.web) {
		// Esconde e manda para uma pagina vazia ANTES de remover: o WebGL do jogo
		// para de desenhar na hora e a janela nao fica visivel enquanto morre.
		self.web.hidden = YES;
		self.web.navigationDelegate = nil;
		[self.web stopLoading];
		[self.web loadHTMLString:@"" baseURL:nil];
		[self.web removeFromSuperview];
		self.web = nil;
	}
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	if (self.owner) {
		self.owner->_emit_page_loaded(String::utf8(webView.URL.absoluteString.UTF8String ?: ""));
	}
}

// O iOS MATA O PROCESSO DA PAGINA quando falta memoria (jogos Unity pesados). Sem
// tratar isto, o WebKit recarrega a pagina sozinho -- e o jogo ficava num LOOP:
// carregando, janela preta, some, carregando (TV Milionario, 29/09). Aqui: uma
// tentativa de recarregar; na segunda queda, esconde a janela e avisa o jogo.
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
	self.quedas += 1;
	if (self.owner) {
		self.owner->_emit_page_failed(String("processo_encerrado_") + String::num_int64(self.quedas));
	}
	if (self.quedas <= 1) {
		[webView reload];
	} else {
		webView.hidden = YES;
		[webView stopLoading];
	}
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	if (self.owner) {
		self.owner->_emit_page_failed(String::utf8(error.localizedDescription.UTF8String ?: ""));
	}
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	if (self.owner) {
		self.owner->_emit_page_failed(String::utf8(error.localizedDescription.UTF8String ?: ""));
	}
}

@end

BarWebView *BarWebView::instance = nullptr;

void BarWebView::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open_texture", "url", "id", "width", "height"), &BarWebView::open_texture);
	ClassDB::bind_method(D_METHOD("set_frame_rate", "fps"), &BarWebView::set_frame_rate);
	ClassDB::bind_method(D_METHOD("texture_frames"), &BarWebView::texture_frames);
	ClassDB::bind_method(D_METHOD("touch", "action", "x", "y"), &BarWebView::touch);
	ClassDB::bind_method(D_METHOD("eval_js", "code"), &BarWebView::eval_js);
	ClassDB::bind_method(D_METHOD("close"), &BarWebView::close);
	ClassDB::bind_method(D_METHOD("open", "url"), &BarWebView::open);
	ClassDB::bind_method(D_METHOD("set_rect", "x", "y", "width", "height"), &BarWebView::set_rect);
	ClassDB::bind_method(D_METHOD("set_visible", "visible"), &BarWebView::set_visible);

	ADD_SIGNAL(MethodInfo("page_loaded", PropertyInfo(Variant::STRING, "url")));
	ADD_SIGNAL(MethodInfo("page_failed", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("quadro", PropertyInfo(Variant::PACKED_BYTE_ARRAY, "jpeg")));
	// Declarado so para o GDScript ligar os dois sinais como no Android; no iPhone
	// quem alimenta o vidro e' o "quadro".
	ADD_SIGNAL(MethodInfo("frame_jpeg", PropertyInfo(Variant::PACKED_BYTE_ARRAY, "jpeg")));
}

BarWebView *BarWebView::get_singleton() {
	return instance;
}

void BarWebView::open_texture(String p_url, int p_id, int p_width, int p_height) {
	// O id da textura externa e' coisa do Android; aqui o quadro chega por sinal.
	NSString *url = [NSString stringWithUTF8String:p_url.utf8().get_data()];
	dispatch_async(dispatch_get_main_queue(), ^{
		if (this->host == nil) {
			this->host = [[BarWebHost alloc] init];
			this->host.owner = this;
		}
		[this->host abrir:url largura:p_width altura:p_height];
	});
}

void BarWebView::set_frame_rate(int p_fps) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host cadencia:p_fps];
	});
}

int BarWebView::texture_frames() {
	return host ? host.quadros : 0;
}

void BarWebView::touch(int p_action, float p_x, float p_y) {
	NSString *js = [NSString stringWithFormat:@"(%@)(%d,%f,%f);", kToqueJS, p_action, p_x, p_y];
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host.web evaluateJavaScript:js completionHandler:nil];
	});
}

void BarWebView::eval_js(String p_code) {
	NSString *js = [NSString stringWithUTF8String:p_code.utf8().get_data()];
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host.web evaluateJavaScript:js completionHandler:nil];
	});
}

void BarWebView::close() {
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host fechar];
	});
}

void BarWebView::open(String p_url) {
	NSString *url = [NSString stringWithUTF8String:p_url.utf8().get_data()];
	dispatch_async(dispatch_get_main_queue(), ^{
		if (this->host == nil) {
			this->host = [[BarWebHost alloc] init];
			this->host.owner = this;
		}
		[this->host abrirSobreposto:url];
	});
}

void BarWebView::set_rect(int p_x, int p_y, int p_width, int p_height) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host retanguloX:p_x y:p_y largura:p_width altura:p_height];
	});
}

void BarWebView::set_visible(bool p_visible) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[this->host visivel:p_visible];
	});
}

void BarWebView::_emit_page_loaded(const String &p_url) {
	emit_signal("page_loaded", p_url);
}

void BarWebView::_emit_page_failed(const String &p_message) {
	emit_signal("page_failed", p_message);
}

void BarWebView::_emit_frame(const uint8_t *p_data, int p_size) {
	PackedByteArray bytes;
	bytes.resize(p_size);
	memcpy(bytes.ptrw(), p_data, p_size);
	emit_signal("quadro", bytes);
}

BarWebView::BarWebView() {
	instance = this;
}

BarWebView::~BarWebView() {
	if (host) {
		host.owner = nullptr;
		[host fechar];
		host = nil;
	}
	instance = nullptr;
}
