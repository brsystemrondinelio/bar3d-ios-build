#ifndef BAR_APPLE_H
#define BAR_APPLE_H

#include "core/object/class_db.h"

#ifdef __OBJC__
@class BarAppleHost;
typedef BarAppleHost BarAppleHostRef;
#else
typedef void BarAppleHostRef;
#endif

// "Entrar com Apple" para o iPhone. Chama sign_in(); a resposta chega pelos
// sinais apple_ok(token, usuario, nome) ou apple_fail(mensagem). O token e' o
// JWT que o servidor confere (bar_apple_lib.php).
class BarApple : public Object {
	GDCLASS(BarApple, Object);

	static BarApple *instance;
	static void _bind_methods();

	BarAppleHostRef *host = nullptr;

public:
	void sign_in();
	// Pede a permissao de rastreamento (ATT). Resposta: sinal att_pronto(estado), estado = 0 nao perguntado, 1 restrito, 2 negado, 3 autorizado.
	void request_tracking();
	void _emit_att(int p_estado);

	void _emit_ok(const String &p_token, const String &p_user, const String &p_name);
	void _emit_fail(const String &p_message);

	static BarApple *get_singleton();

	BarApple();
	~BarApple();
};

#endif
