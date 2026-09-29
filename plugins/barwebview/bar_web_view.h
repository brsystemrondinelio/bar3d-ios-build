#ifndef BAR_WEB_VIEW_H
#define BAR_WEB_VIEW_H

#include "core/object/class_db.h"

#ifdef __OBJC__
@class BarWebHost;
typedef BarWebHost BarWebHostRef;
#else
typedef void BarWebHostRef;
#endif

// A janela web das maquinas no iPhone (equivalente ao BarWebView do Android).
// A pagina do jogo roda num WKWebView fora da tela e o plugin devolve quadros
// JPEG pelo sinal "quadro"; o GDScript os poe numa ImageTexture no vidro do
// gabinete. Toque e JS entram pelas mesmas chamadas do Android.
class BarWebView : public Object {
	GDCLASS(BarWebView, Object);

	static BarWebView *instance;
	static void _bind_methods();

	BarWebHostRef *host = nullptr;

public:
	void open_texture(String p_url, int p_id, int p_width, int p_height);
	void set_frame_rate(int p_fps);
	int texture_frames();
	void touch(int p_action, float p_x, float p_y);
	void eval_js(String p_code);
	void close();
	// Modo SOBREPOSTO (o do PC e do Android antigo): o WKWebView nativo fica por
	// cima da vista do Godot, no retangulo do vidro, e desenha a 60 quadros.
	void open(String p_url);
	void set_rect(int p_x, int p_y, int p_width, int p_height);
	void set_visible(bool p_visible);

	// Chamados pelo lado Objective-C.
	void _emit_page_loaded(const String &p_url);
	void _emit_page_failed(const String &p_message);
	void _emit_frame(const uint8_t *p_data, int p_size);

	static BarWebView *get_singleton();

	BarWebView();
	~BarWebView();
};

#endif
