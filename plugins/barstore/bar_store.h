#ifndef BAR_STORE_H
#define BAR_STORE_H

#include "core/object/class_db.h"

#ifdef __OBJC__
@class BarStoreHost;
typedef BarStoreHost BarStoreHostRef;
#else
typedef void BarStoreHostRef;
#endif

// Compras dentro do app pela Apple (StoreKit): assinatura do Clube VIP e pacotes
// de credito. O jogo chama buscar() / comprar() / restaurar() / pendentes() /
// finalizar(); as respostas chegam por sinais. A compra so e "finalizada" (a Apple
// para de reenviar) depois que o SERVIDOR conferiu o comprovante: o jogo chama
// finalizar(transacao) so nessa hora.
class BarStore : public Object {
	GDCLASS(BarStore, Object);

	static BarStore *instance;
	static void _bind_methods();

	BarStoreHostRef *host = nullptr;

public:
	void buscar(const PackedStringArray &p_ids);
	void comprar(const String &p_id, const String &p_usuario);
	void restaurar();
	String pendentes();
	void finalizar(const String &p_transacao);

	void _emit_produtos(const String &p_json);
	void _emit_compra_ok(const String &p_produto, const String &p_transacao, const String &p_original);
	void _emit_compra_falhou(const String &p_mensagem);
	void _emit_compra_cancelada();
	void _emit_restauracao_pronta();

	static BarStore *get_singleton();

	BarStore();
	~BarStore();
};

#endif
