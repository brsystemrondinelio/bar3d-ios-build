#include "yodo1_ios_module.h"

#include "core/config/engine.h"

#include "yodo1_ios.h"

static Yodo1Ios *yodo1_ios_singleton = nullptr;

// O nome do singleton e o MESMO do plugin Android ("Yodo1Godot"): o GDScript (plataforma/anuncios.gd) e um so.
void register_yodo1ios_types() {
	yodo1_ios_singleton = memnew(Yodo1Ios);
	Engine::get_singleton()->add_singleton(Engine::Singleton("Yodo1Godot", yodo1_ios_singleton));
}

void unregister_yodo1ios_types() {
	if (yodo1_ios_singleton) {
		memdelete(yodo1_ios_singleton);
		yodo1_ios_singleton = nullptr;
	}
}
