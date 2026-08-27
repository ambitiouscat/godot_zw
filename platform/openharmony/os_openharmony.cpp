/**************************************************************************/
/*  os_openharmory.cpp                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "dir_access_openharmony.h"
#include "display_server_openharmony.h"
#include "file_access_openharmony.h"
#include "os_openharmony.h"
#include "bridge_openharmony.h"

#include "core/config/engine.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/version.h"
#include "drivers/unix/dir_access_unix.h"
#include "drivers/unix/file_access_unix.h"
#include "main/main.h"
#include "scene/main/scene_tree.h"

#include <dlfcn.h>
// Public directory access for editor's default project path.
// We use dlopen at runtime to avoid header conflicts (OHOS error_code.h
// defines ERR_INVALID_PARAMETER which clashes with Godot's Error enum).

#include <hilog/log.h>
#include <native_drawing/drawing_text_font_descriptor.h>
#include <native_drawing/drawing_text_typography.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "LIB_GODOT"

#if defined(__x86_64) || defined(__x86_64__) || defined(__amd64__) || defined(_M_X64)
const char *OS_OpenHarmony::EXEC_PATH = "/data/storage/el1/bundle/libs/x86_64/template";
#else
const char *OS_OpenHarmony::EXEC_PATH = "/data/storage/el1/bundle/libs/arm64/template";
#endif

const char *OS_OpenHarmony::BUNDLE_RESOURCE_DIR = "/data/storage/el1/bundle/resources/rawfile/";
const char *OS_OpenHarmony::USER_DATA_DIR = "/data/storage/el2/base/files/user_data/";

OS_OpenHarmony *OS_OpenHarmony::get_singleton() {
	return static_cast<OS_OpenHarmony *>(OS::get_singleton());
}

OS_OpenHarmony::OS_OpenHarmony() {
	Vector<Logger *> loggers;
	Logger_OpenHarmony *logger = memnew(Logger_OpenHarmony);
	loggers.push_back(logger);
	_set_logger(memnew(CompositeLogger(loggers)));

	AudioDriverManager::add_driver(&audio_driver);
	DisplayServerOpenHarmony::register_openharmony_driver();
}

String OS_OpenHarmony::get_name() const {
	return "OpenHarmony";
}

bool OS_OpenHarmony::is_sandboxed() const {
	// HarmonyOS apps run in a sandbox with restricted filesystem access.
	// This also enables the native file/directory picker flow in
	// EditorFileDialog::_should_use_native_popup().
	return true;
}

void OS_OpenHarmony::set_native_window(OHNativeWindow *p_native_window) {
	native_window = p_native_window;
}

OHNativeWindow *OS_OpenHarmony::get_native_window() const {
	return native_window;
}

void OS_OpenHarmony::set_window_id(int32_t p_window_id) {
	window_id = p_window_id;
}

int32_t OS_OpenHarmony::get_window_id() const {
	return window_id;
}

void OS_OpenHarmony::set_display_size(const Size2i &p_size) {
	display_size = p_size;
}

Size2i OS_OpenHarmony::get_display_size() const {
	return display_size;
}

void OS_OpenHarmony::set_allowed_permissions(const char *p_allowed_permissions) {
	String permissions = p_allowed_permissions;
	for (const String &permission : permissions.split(",")) {
		allowed_permissions.insert(permission);
	}
}

bool OS_OpenHarmony::request_permission(const String &p_name) {
	return allowed_permissions.has(p_name);
}

bool OS_OpenHarmony::request_permissions() {
	return false;
}

void OS_OpenHarmony::initialize() {
	OS_Unix::initialize_core();

	// Register FileAccess and DirAccess for all access types.
	// Without ACCESS_USERDATA, "user://" paths can't be opened because
	// FileAccess::create_for_path() and DirAccess::create_for_path()
	// use ACCESS_USERDATA for "user://" prefix.
	FileAccess::make_default<FileAccessOpenHarmony>(FileAccess::ACCESS_RESOURCES);
	FileAccess::make_default<FileAccessOpenHarmony>(FileAccess::ACCESS_FILESYSTEM);
	FileAccess::make_default<FileAccessOpenHarmony>(FileAccess::ACCESS_USERDATA);
	DirAccess::make_default<DirAccessOpenHarmony>(DirAccess::ACCESS_RESOURCES);
	DirAccess::make_default<DirAccessOpenHarmony>(DirAccess::ACCESS_FILESYSTEM);
	DirAccess::make_default<DirAccessOpenHarmony>(DirAccess::ACCESS_USERDATA);
}

void OS_OpenHarmony::initialize_joypads() {
}

void OS_OpenHarmony::set_main_loop(MainLoop *p_main_loop) {
	main_loop = p_main_loop;
}

MainLoop *OS_OpenHarmony::get_main_loop() const {
	return main_loop;
}

void OS_OpenHarmony::delete_main_loop() {
}

void OS_OpenHarmony::finalize() {
}

bool OS_OpenHarmony::_check_internal_feature_support(const String &p_feature) {
	if (p_feature == "system_fonts") {
		return true;
	}
	if (p_feature == "mobile") {
		return true;
	}
	return false;
}

String OS_OpenHarmony::get_user_data_dir(const String &p_user_dir) const {
	return OS_OpenHarmony::USER_DATA_DIR;
}

String OS_OpenHarmony::get_bundle_resource_dir() const {
	return OS_OpenHarmony::BUNDLE_RESOURCE_DIR;
}

String OS_OpenHarmony::get_executable_path() const {
	return OS_OpenHarmony::EXEC_PATH;
}

String OS_OpenHarmony::get_data_path() const {
	return String(OS_OpenHarmony::USER_DATA_DIR);
}

String OS_OpenHarmony::get_config_path() const {
	return String(OS_OpenHarmony::USER_DATA_DIR);
}

String OS_OpenHarmony::get_cache_path() const {
	return "/data/storage/el2/base/files/cache/";
}

String OS_OpenHarmony::get_temp_path() const {
	return "/data/storage/el2/base/files/temp/";
}

String OS_OpenHarmony::get_locale() const {
	if (!system_locale.is_empty()) {
		return system_locale;
	}
	String locale = OS_Unix::get_locale();
	// OS_Unix returns "" if env vars LANG/LC_ALL are not set.
	if (locale.is_empty()) {
		return "en-US";
	}
	return locale;
}

void OS_OpenHarmony::set_locale(const String &p_locale) {
	system_locale = p_locale;
}

String OS_OpenHarmony::get_system_dir(SystemDir p_dir, bool p_shared_storage) const {
	if (p_dir == SYSTEM_DIR_DOCUMENTS) {
		// First, check if a persistent project directory was set from ArkTS.
		// This takes priority as it was user-chosen and persists across sessions.
		const char *project_dir = godot_get_project_dir();
		if (project_dir && strlen(project_dir) > 0) {
			return String::utf8(project_dir);
		}
#ifdef TOOLS_ENABLED
		// Use public Document directory (via dlopen to avoid header conflicts with
		// OHOS error_code.h which defines ERR_INVALID_PARAMETER).
		void *handle = dlopen("libohenvironment.z.so", RTLD_LAZY | RTLD_LOCAL);
		if (handle) {
			typedef int (*GetDirFunc)(char **);
			GetDirFunc func = (GetDirFunc)dlsym(handle, "OH_Environment_GetUserDocumentDir");
			if (func) {
				char *path = nullptr;
				int err = func(&path);
				if (err == 0 && path) {
					String result = String::utf8(path);
					free(path);
					dlclose(handle);
					return result;
				}
			}
			dlclose(handle);
		}
#endif
		// Fallback to app data dir (always writable).
		return String(USER_DATA_DIR);
	}
	return OS_Unix::get_system_dir(p_dir, p_shared_storage);
}

String OS_OpenHarmony::get_model_name() const {
	return "OpenHarmony Device";
}

bool OS_OpenHarmony::has_environment(const String &p_var) const {
	// Hide HOME environment variable so EditorSettings falls through
	// to get_system_dir(SYSTEM_DIR_DOCUMENTS) which respects the
	// user-chosen persistent project directory from ArkTS.
	if (p_var == "HOME") {
		return false;
	}
	return OS_Unix::has_environment(p_var);
}

String OS_OpenHarmony::get_unique_id() const {
	// Fallback to MAC-based unique ID from OS base class.
	String uid = OS_Unix::get_unique_id();
	if (uid.is_empty()) {
		uid = OS::get_singleton()->get_executable_path().md5_text();
	}
	return uid;
}

void OS_OpenHarmony::_load_system_font_config() const {
	font_config_loaded = false;
	font_aliases.clear();
	fonts.clear();
	font_names.clear();

	OH_Drawing_FontConfigInfoErrorCode error_code;
	OH_Drawing_FontConfigInfo *font_config_info = OH_Drawing_GetSystemFontConfigInfo(&error_code);
	if (error_code != SUCCESS_FONT_CONFIG_INFO) {
		ERR_PRINT(vformat("Failed to load system font config: %d", error_code));
		return;
	}

	HashSet<String> generic_font_names;
	for (int i = 0; i < font_config_info->fontGenericInfoSize; i++) {
		OH_Drawing_FontGenericInfo &info = font_config_info->fontGenericInfoSet[i];
		String font_name = String(info.familyName).to_lower();
		for (size_t j = 0; j < info.aliasInfoSize; j++) {
			String alias_name = String(info.aliasInfoSet[j].familyName).to_lower();
			font_aliases[alias_name] = font_name;
			generic_font_names.insert(font_name);
			generic_font_names.insert(alias_name);
		}
	}

	HashMap<String, Vector<String>> font_languages;
	for (int i = 0; i < font_config_info->fallbackGroupSize; i++) {
		OH_Drawing_FontFallbackGroup &group = font_config_info->fallbackGroupSet[i];
		for (size_t j = 0; j < group.fallbackInfoSize; j++) {
			OH_Drawing_FontFallbackInfo &info = group.fallbackInfoSet[j];
			font_languages[String(info.familyName).to_lower()].push_back(info.language);
		}
	}
	OH_Drawing_DestroySystemFontConfigInfo(font_config_info);

	OH_Drawing_Array *names = OH_Drawing_GetSystemFontFullNamesByType(OH_Drawing_SystemFontType::GENERIC);
	for (size_t i = 0;; i++) {
		const OH_Drawing_String *name = OH_Drawing_GetSystemFontFullNameByIndex(names, i);
		if (!name) {
			break;
		}
		OH_Drawing_FontDescriptor *descriptor = OH_Drawing_GetFontDescriptorByFullName(name, OH_Drawing_SystemFontType::GENERIC);
		String font_name = String(descriptor->fontFamily).to_lower();
		FontInfo fi;
		if (!generic_font_names.has(font_name)) {
			fi.priority = 2;
		}
		if (font_name.ends_with("-condensed")) {
			font_name = font_name.trim_suffix("-condensed");
			fi.stretch = 75;
			fi.font_name = font_name;
		}
		fi.font_name = font_name;
		fi.weight = descriptor->weight;
		fi.italic = descriptor->italic;
		fi.path = String(descriptor->path);
		fi.descriptor = descriptor;
		Vector<String> lang_codes = font_languages[font_name];
		if (lang_codes.is_empty()) {
			lang_codes.push_back("en");
		}
		for (int i = 0; i < lang_codes.size(); i++) {
			Vector<String> lang_code_elements = lang_codes[i].split("-");
			if (lang_code_elements.size() >= 1 && lang_code_elements[0] != "und") {
				// Add missing script codes.
				if (lang_code_elements[0] == "ko") {
					fi.script.insert("Hani");
					fi.script.insert("Hang");
				}
				if (lang_code_elements[0] == "ja") {
					fi.script.insert("Hani");
					fi.script.insert("Kana");
					fi.script.insert("Hira");
				}
				if (!lang_code_elements[0].is_empty()) {
					fi.lang.insert(lang_code_elements[0]);
				}
			}
			if (lang_code_elements.size() >= 2) {
				// Add common codes for variants and remove variants not supported by HarfBuzz/ICU.
				if (lang_code_elements[1] == "Aran") {
					fi.script.insert("Arab");
				}
				if (lang_code_elements[1] == "Cyrs") {
					fi.script.insert("Cyrl");
				}
				if (lang_code_elements[1] == "Hanb") {
					fi.script.insert("Hani");
					fi.script.insert("Bopo");
				}
				if (lang_code_elements[1] == "Hans" || lang_code_elements[1] == "Hant") {
					fi.script.insert("Hani");
				}
				if (lang_code_elements[1] == "Syrj" || lang_code_elements[1] == "Syre" || lang_code_elements[1] == "Syrn") {
					fi.script.insert("Syrc");
				}
				if (!lang_code_elements[1].is_empty() && lang_code_elements[1] != "Zsym" && lang_code_elements[1] != "Zsye" && lang_code_elements[1] != "Zmth") {
					fi.script.insert(lang_code_elements[1]);
				}
			}
		}
		fonts.push_back(fi);
		font_names.insert(font_name);
	}
	OH_Drawing_DestroySystemFontFullNames(names);
	font_config_loaded = true;
}

Vector<String> OS_OpenHarmony::get_system_fonts() const {
	if (!font_config_loaded) {
		_load_system_font_config();
	}
	Vector<String> ret;
	for (const String &E : font_names) {
		ret.push_back(E);
	}
	return ret;
}

String OS_OpenHarmony::get_system_font_path(const String &p_font_name, int p_weight, int p_stretch, bool p_italic) const {
	if (!font_config_loaded) {
		_load_system_font_config();
	}
	String font_name = p_font_name.to_lower();
	if (font_aliases.has(font_name)) {
		font_name = font_aliases[font_name];
	}

	int best_score = 0;
	const List<FontInfo>::Element *best_match = nullptr;

	for (const List<FontInfo>::Element *E = fonts.front(); E; E = E->next()) {
		int score = 0;
		if (E->get().font_name == font_name) {
			score += (65 - E->get().priority);
		}
		score += (20 - Math::abs(E->get().weight - p_weight) / 50);
		score += (20 - Math::abs(E->get().stretch - p_stretch) / 10);
		if (E->get().italic == p_italic) {
			score += 30;
		}
		if (score >= 60 && score > best_score) {
			best_score = score;
			best_match = E;
		}
		if (score >= 140) {
			break; // Perfect match.
		}
	}
	if (best_match) {
		return best_match->get().path;
	}
	return String();
}

Vector<String> OS_OpenHarmony::get_system_font_path_for_text(const String &p_font_name, const String &p_text, const String &p_locale, const String &p_script, int p_weight, int p_stretch, bool p_italic) const {
	if (!font_config_loaded) {
		_load_system_font_config();
	}
	String font_name = p_font_name.to_lower();
	if (font_aliases.has(font_name)) {
		font_name = font_aliases[font_name];
	}
	String lang_prefix = p_locale.split("_")[0];
	Vector<String> ret;
	int best_score = 0;
	for (const List<FontInfo>::Element *E = fonts.front(); E; E = E->next()) {
		int score = 0;
		if (!E->get().script.is_empty() && !p_script.is_empty() && !E->get().script.has(p_script)) {
			continue;
		}
		float sim = E->get().font_name.similarity(font_name);
		if (sim > 0.0) {
			score += (60 * sim + 5 - E->get().priority);
		}
		if (E->get().lang.has(p_locale)) {
			score += 120;
		} else if (E->get().lang.has(lang_prefix)) {
			score += 115;
		}
		if (E->get().script.has(p_script)) {
			score += 240;
		}
		score += (20 - Math::abs(E->get().weight - p_weight) / 50);
		score += (20 - Math::abs(E->get().stretch - p_stretch) / 10);
		if (E->get().italic == p_italic) {
			score += 30;
		}
		if (score > best_score) {
			best_score = score;
			if (!ret.has(E->get().path)) {
				ret.insert(0, E->get().path);
			}
		} else if (score == best_score || E->get().script.is_empty()) {
			if (!ret.has(E->get().path)) {
				ret.push_back(E->get().path);
			}
		}
		if (score >= 490) {
			break; // Perfect match.
		}
	}

	return ret;
}

String OS_OpenHarmony::get_system_ca_certificates() {
	String certfile;
	Ref<DirAccess> da = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);

	if (da->file_exists("/etc/ssl/certs/cacert.pem")) {
		certfile = "/etc/ssl/certs/cacert.pem";
	}

	if (certfile.is_empty()) {
		return "";
	}

	Ref<FileAccess> f = FileAccess::open(certfile, FileAccess::READ);
	ERR_FAIL_COND_V_MSG(f.is_null(), "", vformat("Failed to open system CA certificates file: '%s'", certfile));

	String data = f->get_as_text();

	return data;
}

Error OS_OpenHarmony::shell_open(const String &p_uri) {
	// Request ArkTS layer to open the URI
	godot_request_shell_open(p_uri.utf8().get_data());

	// Return OK - the actual result will be handled asynchronously
	// This matches Android's behavior where the result is not tracked
	return OK;
}

Error OS_OpenHarmony::create_instance(const List<String> &p_arguments, ProcessID *r_child_id) {
	// Serialize arguments to newline-separated string for ArkTS layer
	String args_str;
	for (const String &arg : p_arguments) {
		if (!args_str.is_empty()) {
			args_str += "\n";
		}
		args_str += arg;
	}

	// The editor MCP lifecycle coordinator stores its per-run correlation
	// envelope in the process environment immediately before EditorRun starts
	// this instance.  Carry it through the existing native restart bridge as
	// private arguments; BridgeCallbacks consumes these flags before godot_init
	// receives the game command line.  This keeps session state out of
	// project.godot and avoids a cross-process global singleton.
	const String session_id = get_environment("GODOT_MCP_REAL_SESSION_ID");
	const String operation_id = get_environment("GODOT_MCP_REAL_OPERATION_ID");
	const String boot_nonce = get_environment("GODOT_MCP_REAL_BOOT_NONCE");
	unset_environment("GODOT_MCP_REAL_SESSION_ID");
	unset_environment("GODOT_MCP_REAL_OPERATION_ID");
	unset_environment("GODOT_MCP_REAL_BOOT_NONCE");
	const auto is_runtime_token = [](const String &p_value) {
		if (p_value.is_empty() || p_value.length() > 160) {
			return false;
		}
		for (int i = 0; i < p_value.length(); i++) {
			const char32_t c = p_value[i];
			const bool allowed = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
					(c >= '0' && c <= '9') || c == '.' || c == '_' || c == ':' || c == '-';
			if (!allowed) {
				return false;
			}
		}
		return true;
	};
	if (is_runtime_token(session_id) && is_runtime_token(operation_id) && is_runtime_token(boot_nonce)) {
		args_str += "\n--mcp-runtime-session-id\n" + session_id;
		args_str += "\n--mcp-runtime-operation-id\n" + operation_id;
		args_str += "\n--mcp-runtime-boot-nonce\n" + boot_nonce;
	} else if (!session_id.is_empty() || !operation_id.is_empty() || !boot_nonce.is_empty()) {
		WARN_PRINT("Discarded invalid or incomplete MCP runtime correlation envelope.");
	}

	// Request ArkTS to restart the app with new arguments
	godot_request_restart(args_str.utf8().get_data());

	// Set non-zero PID so EditorRun::run() adds it to pids,
	// which allows EditorRun::stop() to call kill() to terminate GameAbility.
	if (r_child_id) {
		*r_child_id = 1;
	}

	return OK;
}

Error OS_OpenHarmony::kill(const ProcessID &p_pid) {
	godot_request_process_kill();
	return OK;
}

void OS_OpenHarmony::vibrate_handheld(int p_duration_ms, float p_amplitude) {
	godot_request_vibrate(p_duration_ms);
}

void OS_OpenHarmony::_deploy_export_templates() {
	// Only deploy in editor mode — template builds don't need export templates.
	if (!Engine::get_singleton()->is_editor_hint()) {
		OH_LOG_INFO(LOG_APP, "_deploy_export_templates: not editor mode, skipping");
		return;
	}

	NativeResourceManager *res_mgr = FileAccessOpenHarmony::get_resource_manager();
	if (res_mgr == nullptr) {
		OH_LOG_INFO(LOG_APP, "_deploy_export_templates: resource_manager is null, skipping");
		return;
	}

	// Build the target directory: {data_dir}/export_templates/{version}/
	String data_dir = get_data_path().path_join("godot");
	String version_dir = data_dir.path_join("export_templates").path_join(GODOT_VERSION_FULL_CONFIG);
	OH_LOG_INFO(LOG_APP, "_deploy_export_templates: target dir = %{public}s", version_dir.utf8().get_data());

	const char *zip_names[] = {
		"openharmony_debug_arm64-v8a.zip",
		"openharmony_release_arm64-v8a.zip",
		nullptr
	};

	for (int i = 0; zip_names[i] != nullptr; i++) {
		String target_path = version_dir.path_join(zip_names[i]);

		// Always redeploy from HAP rawfile to ensure latest version.

		RawFile64 *rawfile = OH_ResourceManager_OpenRawFile64(res_mgr, zip_names[i]);
		if (rawfile == nullptr) {
			OH_LOG_INFO(LOG_APP, "_deploy_export_templates: NOT FOUND in rawfile: %{public}s", zip_names[i]);
			continue;
		}

		uint64_t length = OH_ResourceManager_GetRawFileSize64(rawfile);
		if (length == 0 || length > (uint64_t)INT_MAX) {
			OH_ResourceManager_CloseRawFile64(rawfile);
			continue;
		}

		Vector<uint8_t> buffer;
		buffer.resize((int)length);
		uint64_t read = OH_ResourceManager_ReadRawFile64(rawfile, buffer.ptrw(), length);
		OH_ResourceManager_CloseRawFile64(rawfile);

		if (read != length) {
			OH_LOG_INFO(LOG_APP, "_deploy_export_templates: read mismatch, expected %{public}d got %{public}d", (int)length, (int)read);
			continue;
		}

		// Ensure the target directory exists.
		Ref<DirAccess> da = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
		Error dir_err = da->make_dir_recursive(version_dir);
		if (dir_err != OK && dir_err != ERR_ALREADY_EXISTS) {
			continue;
		}

		Ref<FileAccess> f = FileAccess::open(target_path, FileAccess::WRITE);
		if (f.is_valid()) {
			f->store_buffer(buffer.ptr(), read);
			OH_LOG_INFO(LOG_APP, "_deploy_export_templates: DEPLOYED %{public}s (%{public}d KB)", zip_names[i], (int)(read / 1024));
		}
	}
}

void OS_OpenHarmony::main_loop_begin() {
	_deploy_export_templates();
	if (main_loop) {
		main_loop->initialize();
	}
}

bool OS_OpenHarmony::main_loop_iterate() {
	if (!main_loop) {
		return false;
	}
	DisplayServerOpenHarmony::get_singleton()->process_events();
	godot_process_engine_commands();
	return Main::iteration();
}

void OS_OpenHarmony::main_loop_end() {
	if (main_loop) {
		SceneTree *scene_tree = Object::cast_to<SceneTree>(main_loop);
		if (scene_tree) {
			scene_tree->quit();
		}
		main_loop->finalize();
	}

	// Request ArkTS to terminate the ability
	godot_request_terminate();
}

void OS_OpenHarmony::on_focus_out() {
	if (is_focused) {
		is_focused = false;

		if (DisplayServerOpenHarmony::get_singleton()) {
			DisplayServerOpenHarmony::get_singleton()->send_window_event(DisplayServerEnums::WINDOW_EVENT_FOCUS_OUT);
		}

		if (OS::get_singleton()->get_main_loop()) {
			OS::get_singleton()->get_main_loop()->notification(MainLoop::NOTIFICATION_APPLICATION_FOCUS_OUT);
		}

		audio_driver.set_pause(true);
	}
}

void OS_OpenHarmony::on_focus_in() {
	if (!is_focused) {
		is_focused = true;

		if (DisplayServerOpenHarmony::get_singleton()) {
			DisplayServerOpenHarmony::get_singleton()->send_window_event(DisplayServerEnums::WINDOW_EVENT_FOCUS_IN);
		}

		if (OS::get_singleton()->get_main_loop()) {
			OS::get_singleton()->get_main_loop()->notification(MainLoop::NOTIFICATION_APPLICATION_FOCUS_IN);
		}

		audio_driver.set_pause(false);
	}
}

void OS_OpenHarmony::on_enter_background() {
	if (OS::get_singleton()->get_main_loop()) {
		OS::get_singleton()->get_main_loop()->notification(MainLoop::NOTIFICATION_APPLICATION_PAUSED);
	}

	on_focus_out();
}

void OS_OpenHarmony::on_exit_background() {
	if (!is_focused) {
		on_focus_in();

		if (OS::get_singleton()->get_main_loop()) {
			OS::get_singleton()->get_main_loop()->notification(MainLoop::NOTIFICATION_APPLICATION_RESUMED);
		}
	}
}

void OS_OpenHarmony::alert(const String &p_alert, const String &p_title) {
	godot_request_alert(p_title.utf8().get_data(), p_alert.utf8().get_data());
}

void Logger_OpenHarmony::logv(const char *p_format, va_list p_list, bool p_err) {
	if (!should_log(p_err)) {
		return;
	}

	char buffer[4096];
	vsnprintf(&buffer[0], sizeof(buffer) - 1, p_format, p_list);

	if (p_err) {
		OH_LOG_ERROR(LOG_APP, "%{public}s", &buffer[0]);
	} else {
		OH_LOG_INFO(LOG_APP, "%{public}s", &buffer[0]);
	}
}
