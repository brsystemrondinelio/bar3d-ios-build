#ifndef ADMOB_IOS_H
#define ADMOB_IOS_H

#include "core/object/class_db.h"

#ifdef __OBJC__
@class AdMobIosHost;
typedef AdMobIosHost AdMobIosHostRef;
#else
typedef void AdMobIosHostRef;
#endif

// Anuncios do AdMob (Google Mobile Ads) no iPhone, com os MESMOS metodos e sinais do plugin Android:
//   consentimento()                      -> sinal consentimento_pronto(pode_anunciar)   (formulario UMP do Google)
//   rastreamentoStatus() / pedeRastreamento() -> sinal rastreamento_respondeu(status)  (pergunta ATT da Apple)
//   inicia()                             -> sinal iniciou
//   carregaVideo(id) ; videoPronto() ; mostraVideo()
//       sinais video_carregado, video_falhou(msg), video_nao_abriu(msg), video_ganhou, video_fechado
//   carregaIntersticial(id) ; intersticialPronto() ; mostraIntersticial()
//       sinais intersticial_carregado, intersticial_falhou(msg), intersticial_fechado
//   mostraBanner(id) ; escondeBanner()   -> sinais banner_carregado, banner_falhou(msg)
// O SDK (pods Google-Mobile-Ads-SDK e GoogleUserMessagingPlatform) e chamado pelo runtime do Objective-C
// (NSClassFromString): o plugin compila sem os cabecalhos do Google e o SDK entra no app pelo Podfile.
class AdMobIos : public Object {
	GDCLASS(AdMobIos, Object);

	static void _bind_methods();

	AdMobIosHostRef *host = nullptr;

public:
	void consentimento();
	int rastreamentoStatus();
	void pedeRastreamento();
	void inicia();

	void carregaVideo(const String &p_id);
	bool videoPronto();
	void mostraVideo();

	void carregaIntersticial(const String &p_id);
	bool intersticialPronto();
	void mostraIntersticial();

	void mostraBanner(const String &p_id);
	void escondeBanner();

	// Leva o sinal para o laco do jogo (call_deferred). com_valor = false: sinal sem argumento.
	void _emite(const String &p_sinal, const Variant &p_valor, bool p_com_valor);

	AdMobIos();
	~AdMobIos();
};

#endif
