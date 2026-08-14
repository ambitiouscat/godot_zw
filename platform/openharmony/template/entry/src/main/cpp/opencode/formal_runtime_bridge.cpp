#include "formal_runtime_contract.h"

#include <AbilityKit/native_child_process.h>
#include <hilog/log.h>
#include <napi/native_api.h>

#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <mutex>
#include <string>
#include <vector>

#include <dirent.h>
#include <signal.h>
#include <unistd.h>

namespace {
constexpr unsigned int FORMAL_LOG_DOMAIN = 0xFF00;
constexpr const char *FORMAL_LOG_TAG = "OpenCodeFormalRuntime";
constexpr int32_t FORMAL_RUNTIME_INACTIVE = -7001;
constexpr int32_t FORMAL_RUNTIME_GENERATION_STALE = -7002;

enum class LifecyclePhase : int32_t {
    IDLE = 0,
    STARTING = 1,
    READY = 2,
    STOPPING = 3,
    STOPPED = 4,
    FAILED = 5,
};

std::atomic<int32_t> gActivePid {-1};
std::atomic<int64_t> gActiveGeneration {0};
std::atomic<int64_t> gHighestGeneration {0};
std::atomic<int32_t> gLastExitPid {-1};
std::atomic<int32_t> gLastExitSignal {-1};
std::atomic<int64_t> gLastExitGeneration {0};
std::atomic<bool> gExitObserved {false};
std::atomic<bool> gExitCallbackRegistered {false};
std::atomic<LifecyclePhase> gPhase {LifecyclePhase::IDLE};
std::mutex gRegistrationMutex;
std::mutex gEventPathMutex;
std::string gHostEventPath;
std::atomic<uint64_t> gNextHostEventSequence {1};

std::string CurrentHostEventPath()
{
    std::lock_guard<std::mutex> lock(gEventPathMutex);
    if (gHostEventPath.empty()) return "";
    return gHostEventPath + "." +
        std::to_string(gNextHostEventSequence.load(std::memory_order_acquire));
}

std::string ReadCurrentHostEvent()
{
    const std::string eventPath = CurrentHostEventPath();
    std::string payload;
    if (!eventPath.empty()) {
        std::ifstream input(eventPath, std::ios::binary);
        if (input) {
            payload.assign(
                std::istreambuf_iterator<char>(input),
                std::istreambuf_iterator<char>());
            if (payload.size() > 65536) payload.resize(65536);
        }
    }
    return payload;
}

void RefreshPhaseFromHostEventPayload(const std::string& payload)
{
    const int64_t generation =
        gActiveGeneration.load(std::memory_order_acquire);
    if (generation <= 0) return;
    if (payload.empty()) return;
    const std::string generationMarker =
        "\"generation\":" + std::to_string(generation) + ",";
    if (payload.find(generationMarker) == std::string::npos) return;
    if (payload.find("\"kind\":\"runtime.ready\"") != std::string::npos) {
        LifecyclePhase expected = LifecyclePhase::STARTING;
        gPhase.compare_exchange_strong(
            expected, LifecyclePhase::READY, std::memory_order_acq_rel);
    } else if (
        payload.find("\"kind\":\"runtime.fatal\"") != std::string::npos) {
        gPhase.store(LifecyclePhase::FAILED, std::memory_order_release);
    } else if (
        payload.find("\"kind\":\"runtime.stopped\"") != std::string::npos) {
        gPhase.store(LifecyclePhase::STOPPING, std::memory_order_release);
    }
}

void RefreshPhaseFromHostEvent()
{
    RefreshPhaseFromHostEventPayload(ReadCurrentHostEvent());
}

void ConsumeCurrentHostEvent()
{
    const std::string eventPath = CurrentHostEventPath();
    if (eventPath.empty()) return;
    if (std::remove(eventPath.c_str()) == 0) {
        gNextHostEventSequence.fetch_add(1, std::memory_order_acq_rel);
    }
}

void RemoveHostEventQueue(const std::string& eventPath)
{
    std::remove(eventPath.c_str());
    std::remove((eventPath + ".tmp").c_str());
    const size_t separator = eventPath.find_last_of('/');
    const std::string directory =
        separator == std::string::npos ? "." : eventPath.substr(0, separator);
    const std::string base =
        separator == std::string::npos ? eventPath : eventPath.substr(separator + 1);
    const std::string prefix = base + ".";
    DIR *stream = opendir(directory.c_str());
    if (stream == nullptr) return;
    while (dirent *entry = readdir(stream)) {
        const std::string name = entry->d_name;
        if (name.rfind(prefix, 0) != 0) continue;
        std::remove((directory + "/" + name).c_str());
    }
    closedir(stream);
}

const char *PhaseName(LifecyclePhase phase)
{
    switch (phase) {
        case LifecyclePhase::IDLE:
            return "idle";
        case LifecyclePhase::STARTING:
            return "starting";
        case LifecyclePhase::READY:
            return "ready";
        case LifecyclePhase::STOPPING:
            return "stopping";
        case LifecyclePhase::STOPPED:
            return "stopped";
        case LifecyclePhase::FAILED:
            return "failed";
        default:
            return "invalid";
    }
}

void OnNativeChildProcessExit(int32_t pid, int32_t signal)
{
    int32_t expectedPid = pid;
    if (!gActivePid.compare_exchange_strong(expectedPid, -1, std::memory_order_acq_rel)) {
        OH_LOG_Print(LOG_APP, LOG_WARN, FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
            "FORMAL_NCP_STALE_EXIT pid=%{public}d signal=%{public}d", pid, signal);
        return;
    }
    const int64_t generation = gActiveGeneration.exchange(0, std::memory_order_acq_rel);
    gLastExitPid.store(pid, std::memory_order_release);
    gLastExitSignal.store(signal, std::memory_order_release);
    gLastExitGeneration.store(generation, std::memory_order_release);
    gExitObserved.store(true, std::memory_order_release);
    gPhase.store(signal == 0 ? LifecyclePhase::STOPPED : LifecyclePhase::FAILED,
        std::memory_order_release);
    OH_LOG_Print(LOG_APP, LOG_INFO, FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
        "FORMAL_NCP_EXIT generation=%{public}lld pid=%{public}d signal=%{public}d",
        static_cast<long long>(generation), pid, signal);
}

int32_t EnsureExitCallbackRegistered()
{
    if (gExitCallbackRegistered.load(std::memory_order_acquire)) return NCP_NO_ERROR;
    std::lock_guard<std::mutex> lock(gRegistrationMutex);
    if (gExitCallbackRegistered.load(std::memory_order_relaxed)) return NCP_NO_ERROR;
    const int32_t code =
        OH_Ability_RegisterNativeChildProcessExitCallback(OnNativeChildProcessExit);
    if (code == NCP_NO_ERROR) {
        gExitCallbackRegistered.store(true, std::memory_order_release);
    }
    OH_LOG_Print(LOG_APP, code == NCP_NO_ERROR ? LOG_INFO : LOG_ERROR,
        FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
        "FORMAL_NCP_EXIT_CALLBACK code=%{public}d", code);
    return code;
}

void SetNamedInt32(napi_env env, napi_value object, const char *name, int32_t value)
{
    napi_value property = nullptr;
    napi_create_int32(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetNamedInt64(napi_env env, napi_value object, const char *name, int64_t value)
{
    napi_value property = nullptr;
    napi_create_int64(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetNamedBoolean(napi_env env, napi_value object, const char *name, bool value)
{
    napi_value property = nullptr;
    napi_get_boolean(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetNamedString(napi_env env, napi_value object, const char *name, const std::string& value)
{
    napi_value property = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &property);
    napi_set_named_property(env, object, name, property);
}

bool ReadSingleObject(napi_env env, napi_callback_info info, napi_value *object)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok ||
        argc != 1) {
        napi_throw_type_error(env, nullptr, "Expected exactly one bootstrap object");
        return false;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_object) {
        napi_throw_type_error(env, nullptr, "Bootstrap input must be an object");
        return false;
    }
    *object = argv[0];
    return true;
}

bool ReadNamedString(napi_env env, napi_value object, const char *name,
    size_t maximumBytes, std::string *output)
{
    napi_value property = nullptr;
    if (napi_get_named_property(env, object, name, &property) != napi_ok) {
        napi_throw_type_error(env, nullptr, name);
        return false;
    }
    size_t length = 0;
    if (napi_get_value_string_utf8(env, property, nullptr, 0, &length) != napi_ok ||
        length == 0 || length > maximumBytes) {
        napi_throw_type_error(env, nullptr, name);
        return false;
    }
    std::vector<char> buffer(length + 1, '\0');
    if (napi_get_value_string_utf8(
            env, property, buffer.data(), buffer.size(), &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, name);
        return false;
    }
    output->assign(buffer.data(), length);
    return true;
}

bool ReadNamedInt32(napi_env env, napi_value object, const char *name, int32_t *output)
{
    napi_value property = nullptr;
    if (napi_get_named_property(env, object, name, &property) != napi_ok ||
        napi_get_value_int32(env, property, output) != napi_ok) {
        napi_throw_type_error(env, nullptr, name);
        return false;
    }
    return true;
}

bool ReadBootstrapInput(napi_env env, napi_callback_info info,
    opencode::formal::BootstrapInput *input)
{
    napi_value object = nullptr;
    if (!ReadSingleObject(env, info, &object)) return false;
    if (!ReadNamedString(env, object, "filesDirectory",
            opencode::formal::MAX_PATH_BYTES, &input->filesDirectory) ||
        !ReadNamedString(env, object, "cacheDirectory",
            opencode::formal::MAX_PATH_BYTES, &input->cacheDirectory) ||
        !ReadNamedString(env, object, "temporaryDirectory",
            opencode::formal::MAX_PATH_BYTES, &input->temporaryDirectory) ||
        !ReadNamedString(env, object, "projectRoot",
            opencode::formal::MAX_PATH_BYTES, &input->projectRoot) ||
        !ReadNamedString(env, object, "entryPath",
            opencode::formal::MAX_PATH_BYTES, &input->entryPath) ||
        !ReadNamedString(env, object, "credential",
            opencode::formal::MAX_CREDENTIAL_BYTES, &input->credential) ||
        !ReadNamedString(env, object, "allowedOrigin",
            opencode::formal::MAX_ORIGIN_BYTES, &input->allowedOrigin) ||
        !ReadNamedString(env, object, "capabilityProfile",
            opencode::formal::MAX_CAPABILITY_PROFILE_BYTES, &input->capabilityProfile) ||
        !ReadNamedString(env, object, "deviceForm",
            opencode::formal::MAX_DEVICE_FORM_BYTES, &input->deviceForm) ||
        !ReadNamedInt32(env, object, "requestedPort", &input->requestedPort)) {
        return false;
    }
    return true;
}

napi_value StartFormalRuntime(napi_env env, napi_callback_info info)
{
    opencode::formal::BootstrapInput input;
    if (!ReadBootstrapInput(env, info, &input)) return nullptr;
    if (gActivePid.load(std::memory_order_acquire) >= 0) {
        napi_throw_error(env, nullptr, "A formal runtime generation is already active");
        return nullptr;
    }

    input.generation = gHighestGeneration.fetch_add(1, std::memory_order_acq_rel) + 1;
    if (!opencode::formal::ValidateBootstrapInput(input)) {
        napi_throw_type_error(env, nullptr, "Formal runtime bootstrap input rejected");
        return nullptr;
    }

    const std::string hostEventPath =
        input.filesDirectory + "/" + opencode::formal::HOST_EVENT_FILE_NAME;
    RemoveHostEventQueue(hostEventPath);
    gNextHostEventSequence.store(1, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(gEventPathMutex);
        gHostEventPath = hostEventPath;
    }

    const int32_t callbackCode = EnsureExitCallbackRegistered();
    int32_t code = callbackCode;
    int32_t pid = -1;
    if (code == NCP_NO_ERROR) {
        const std::string serialized = opencode::formal::SerializeBootstrapInput(input);
        NativeChildProcess_Args arguments {};
        arguments.entryParams = static_cast<char *>(std::malloc(serialized.size() + 1));
        if (arguments.entryParams == nullptr) {
            napi_throw_error(env, nullptr, "Failed to allocate formal runtime arguments");
            return nullptr;
        }
        std::strcpy(arguments.entryParams, serialized.c_str());
        arguments.fdList.head = nullptr;

        gExitObserved.store(false, std::memory_order_release);
        gLastExitPid.store(-1, std::memory_order_release);
        gLastExitSignal.store(-1, std::memory_order_release);
        gLastExitGeneration.store(0, std::memory_order_release);
        gPhase.store(LifecyclePhase::STARTING, std::memory_order_release);

        NativeChildProcess_Options options {};
        options.isolationMode = NCP_ISOLATION_MODE_NORMAL;
        code = OH_Ability_StartNativeChildProcess(
            opencode::formal::CHILD_ENTRY, arguments, options, &pid);
        std::free(arguments.entryParams);
        if (code == NCP_NO_ERROR) {
            gActiveGeneration.store(input.generation, std::memory_order_release);
            gActivePid.store(pid, std::memory_order_release);
        } else {
            gPhase.store(LifecyclePhase::FAILED, std::memory_order_release);
        }
    } else {
        gPhase.store(LifecyclePhase::FAILED, std::memory_order_release);
    }

    OH_LOG_Print(LOG_APP, code == NCP_NO_ERROR ? LOG_INFO : LOG_ERROR,
        FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
        "FORMAL_NCP_START code=%{public}d generation=%{public}lld pid=%{public}d",
        code, static_cast<long long>(input.generation), pid);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamedInt32(env, result, "code", code);
    SetNamedInt32(env, result, "pid", pid);
    SetNamedInt32(env, result, "callbackCode", callbackCode);
    SetNamedInt64(env, result, "generation", input.generation);
    SetNamedString(env, result, "phase",
        PhaseName(gPhase.load(std::memory_order_acquire)));
    SetNamedString(env, result, "hostEventPath", hostEventPath);
    return result;
}

napi_value StopFormalRuntime(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    int64_t generation = 0;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok ||
        argc != 1 || napi_get_value_int64(env, argv[0], &generation) != napi_ok ||
        generation <= 0) {
        napi_throw_type_error(env, nullptr, "Expected one positive runtime generation");
        return nullptr;
    }

    const int32_t pid = gActivePid.load(std::memory_order_acquire);
    const int64_t activeGeneration =
        gActiveGeneration.load(std::memory_order_acquire);
    int32_t code = 0;
    bool accepted = false;
    if (pid < 0 || activeGeneration == 0) {
        code = FORMAL_RUNTIME_INACTIVE;
    } else if (generation != activeGeneration) {
        code = FORMAL_RUNTIME_GENERATION_STALE;
    } else {
        const LifecyclePhase previous =
            gPhase.exchange(LifecyclePhase::STOPPING, std::memory_order_acq_rel);
        errno = 0;
        if (kill(pid, SIGTERM) == 0) {
            accepted = true;
        } else {
            code = errno == 0 ? EIO : errno;
            gPhase.store(previous, std::memory_order_release);
        }
    }

    OH_LOG_Print(LOG_APP, accepted ? LOG_INFO : LOG_WARN,
        FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
        "FORMAL_NCP_STOP code=%{public}d generation=%{public}lld pid=%{public}d",
        code, static_cast<long long>(generation), pid);

    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamedInt32(env, result, "code", code);
    SetNamedInt32(env, result, "pid", pid);
    SetNamedInt64(env, result, "generation", generation);
    SetNamedBoolean(env, result, "accepted", accepted);
    SetNamedString(env, result, "phase",
        PhaseName(gPhase.load(std::memory_order_acquire)));
    return result;
}

napi_value GetFormalRuntimeState(napi_env env, napi_callback_info info)
{
    (void)info;
    RefreshPhaseFromHostEvent();
    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamedInt32(env, result, "contractVersion", opencode::formal::CONTRACT_VERSION);
    SetNamedInt32(env, result, "activePid",
        gActivePid.load(std::memory_order_acquire));
    SetNamedInt64(env, result, "activeGeneration",
        gActiveGeneration.load(std::memory_order_acquire));
    SetNamedInt64(env, result, "highestGeneration",
        gHighestGeneration.load(std::memory_order_acquire));
    SetNamedInt32(env, result, "lastExitPid",
        gLastExitPid.load(std::memory_order_acquire));
    SetNamedInt32(env, result, "lastExitSignal",
        gLastExitSignal.load(std::memory_order_acquire));
    SetNamedInt64(env, result, "lastExitGeneration",
        gLastExitGeneration.load(std::memory_order_acquire));
    SetNamedBoolean(env, result, "exitObserved",
        gExitObserved.load(std::memory_order_acquire));
    SetNamedBoolean(env, result, "callbackRegistered",
        gExitCallbackRegistered.load(std::memory_order_acquire));
    SetNamedString(env, result, "phase",
        PhaseName(gPhase.load(std::memory_order_acquire)));
    return result;
}

napi_value ReadFormalHostEvent(napi_env env, napi_callback_info info)
{
    (void)info;
    const std::string payload = ReadCurrentHostEvent();
    RefreshPhaseFromHostEventPayload(payload);
    if (!payload.empty()) ConsumeCurrentHostEvent();
    napi_value result = nullptr;
    napi_create_string_utf8(env, payload.c_str(), payload.size(), &result);
    return result;
}

napi_value GetFormalRuntimeContract(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_create_object(env, &result);
    SetNamedInt32(env, result, "version", opencode::formal::CONTRACT_VERSION);
    SetNamedString(env, result, "capabilityProfile",
        opencode::formal::CAPABILITY_PROFILE);
    SetNamedString(env, result, "entryExport", opencode::formal::ENTRY_EXPORT);

    napi_value callbacks = nullptr;
    napi_create_array_with_length(
        env, opencode::formal::APPROVED_HOST_CALLBACKS.size(), &callbacks);
    uint32_t index = 0;
    for (const char *callback : opencode::formal::APPROVED_HOST_CALLBACKS) {
        napi_value value = nullptr;
        napi_create_string_utf8(env, callback, NAPI_AUTO_LENGTH, &value);
        napi_set_element(env, callbacks, index++, value);
    }
    napi_set_named_property(env, result, "approvedHostCallbacks", callbacks);
    return result;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"startFormalRuntime", nullptr, StartFormalRuntime,
            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopFormalRuntime", nullptr, StopFormalRuntime,
            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getFormalRuntimeState", nullptr, GetFormalRuntimeState,
            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"readFormalHostEvent", nullptr, ReadFormalHostEvent,
            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getFormalRuntimeContract", nullptr, GetFormalRuntimeContract,
            nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(
        env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
} // namespace

static napi_module formalRuntimeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "opencode_formal_runtime",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterOpenCodeFormalRuntimeModule(void)
{
    napi_module_register(&formalRuntimeModule);
}
