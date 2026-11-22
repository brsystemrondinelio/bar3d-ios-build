#include "admob_ios_module.h"

#include "core/config/engine.h"

#include "admob_ios.h"

static AdMobIos *admob_ios_singleton = nullptr;

// O nome do singleton e o MESMO do plugin Android ("AdMobGodot"): o GDScript (plataforma/anuncios.gd) e um so.
void register_admobios_types() {
	admob_ios_singleton = memnew(AdMobIos);
	Engine::get_singleton()->add_singleton(Engine::Singleton("AdMobGodot", admob_ios_singleton));
}

void unregister_admobios_types() {
	if (admob_ios_singleton) {
		memdelete(admob_ios_singleton);
		admob_ios_singleton = nullptr;
	}
}
