#include "bar_web_view_module.h"

#include "core/config/engine.h"

#include "bar_web_view.h"

BarWebView *bar_web_view_singleton = nullptr;

void register_barwebview_types() {
	bar_web_view_singleton = memnew(BarWebView);
	Engine::get_singleton()->add_singleton(Engine::Singleton("BarWebView", bar_web_view_singleton));
}

void unregister_barwebview_types() {
	if (bar_web_view_singleton) {
		memdelete(bar_web_view_singleton);
		bar_web_view_singleton = nullptr;
	}
}
