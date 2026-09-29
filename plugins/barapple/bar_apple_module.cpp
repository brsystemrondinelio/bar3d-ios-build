#include "bar_apple_module.h"

#include "core/config/engine.h"

#include "bar_apple.h"

BarApple *bar_apple_singleton = nullptr;

void register_barapple_types() {
	bar_apple_singleton = memnew(BarApple);
	Engine::get_singleton()->add_singleton(Engine::Singleton("BarApple", bar_apple_singleton));
}

void unregister_barapple_types() {
	if (bar_apple_singleton) {
		memdelete(bar_apple_singleton);
		bar_apple_singleton = nullptr;
	}
}
