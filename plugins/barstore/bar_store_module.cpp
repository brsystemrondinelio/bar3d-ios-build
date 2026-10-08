#include "bar_store_module.h"

#include "core/config/engine.h"

#include "bar_store.h"

BarStore *bar_store_singleton = nullptr;

void register_barstore_types() {
	bar_store_singleton = memnew(BarStore);
	Engine::get_singleton()->add_singleton(Engine::Singleton("BarStore", bar_store_singleton));
}

void unregister_barstore_types() {
	if (bar_store_singleton) {
		memdelete(bar_store_singleton);
		bar_store_singleton = nullptr;
	}
}
