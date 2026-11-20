#ifndef YODO1_IOS_H
#define YODO1_IOS_H

#include "core/object/class_db.h"

#ifdef __OBJC__
@class Yodo1IosHost;
typedef Yodo1IosHost Yodo1IosHostRef;
#else
typedef void Yodo1IosHostRef;
#endif

// Video premiado do Yodo1 MAS no iPhone, com os MESMOS metodos e sinais do plugin Android (Yodo1Godot.kt):
//   inicia(appKey, coppa, gdpr, ccpa) ; carregaVideo() ; videoPronto() ; mostraVideo()
//   sinais: iniciou, falhou_iniciar(msg), video_carregado, video_falhou(msg), video_nao_abriu(msg), video_ganhou,
//           video_fechado
// O SDK (pod Yodo1MasFull) e chamado pelo runtime do Objective-C (NSClassFromString): o plugin compila sem os
// cabecalhos do Yodo1 e o SDK entra no app pelo Podfile do projeto Xcode.
class Yodo1Ios : public Object {
	GDCLASS(Yodo1Ios, Object);

	static void _bind_methods();

	Yodo1IosHostRef *host = nullptr;

public:
	void inicia(const String &p_app_key, bool p_coppa, bool p_gdpr, bool p_ccpa);
	void carregaVideo();
	bool videoPronto();
	void mostraVideo();
	// os dois metodos de intersticial existem no Android; aqui ficam vazios (o jogo nao usa)
	void carregaIntersticial() {}
	bool intersticialPronto() { return false; }
	void mostraIntersticial() {}

	void _emite(const String &p_sinal, const String &p_texto, bool p_com_texto);

	Yodo1Ios();
	~Yodo1Ios();
};

#endif
