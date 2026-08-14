#include "formal_runtime_contract.h"

#include <AbilityKit/native_child_process.h>
#include <cppgc/platform.h>
#include <hilog/log.h>
#include <node.h>
#include <v8.h>

#include <atomic>
#include <cstdio>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr unsigned int FORMAL_LOG_DOMAIN = 0xFF00;
constexpr const char *FORMAL_LOG_TAG = "OpenCodeFormalRuntime";

struct HostCallbackContext {
    std::string eventPath;
    int64_t generation = 0;
    std::atomic<uint64_t> sequence {0};
};

void LogNodeErrors(const std::vector<std::string>& errors)
{
    const size_t limit = errors.size() < 4 ? errors.size() : 4;
    for (size_t index = 0; index < limit; ++index) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
            "FORMAL_NODE_ERROR index=%{public}zu category=initialization",
            index);
    }
}

std::string JsonEscape(const std::string& value)
{
    std::string output;
    output.reserve(value.size() + 16);
    for (const unsigned char character : value) {
        switch (character) {
            case '"':
                output += "\\\"";
                break;
            case '\\':
                output += "\\\\";
                break;
            case '\b':
                output += "\\b";
                break;
            case '\f':
                output += "\\f";
                break;
            case '\n':
                output += "\\n";
                break;
            case '\r':
                output += "\\r";
                break;
            case '\t':
                output += "\\t";
                break;
            default:
                if (character < 0x20) {
                    static constexpr char HEX[] = "0123456789abcdef";
                    output += "\\u00";
                    output += HEX[(character >> 4) & 0x0F];
                    output += HEX[character & 0x0F];
                } else {
                    output += static_cast<char>(character);
                }
        }
    }
    return output;
}

bool WriteHostEvent(HostCallbackContext *host, const std::string& kind,
    const std::string& payload)
{
    if (host == nullptr || !opencode::formal::IsApprovedHostCallback(kind) ||
        payload.size() > opencode::formal::MAX_HOST_EVENT_BYTES) {
        return false;
    }
    const uint64_t sequence =
        host->sequence.load(std::memory_order_acquire) + 1;
    if (sequence > opencode::formal::MAX_HOST_EVENT_QUEUE_DEPTH) {
        const std::string oldestPendingPath =
            host->eventPath + "." + std::to_string(
                sequence - opencode::formal::MAX_HOST_EVENT_QUEUE_DEPTH);
        std::ifstream oldestPending(oldestPendingPath, std::ios::binary);
        if (oldestPending.good()) return false;
    }
    const std::string eventPath =
        host->eventPath + "." + std::to_string(sequence);
    const std::string temporaryPath = eventPath + ".tmp";
    std::ofstream output(temporaryPath, std::ios::binary | std::ios::trunc);
    if (!output) return false;
    output << "{\"version\":" << opencode::formal::CONTRACT_VERSION
        << ",\"generation\":" << host->generation
        << ",\"sequence\":" << sequence
        << ",\"kind\":\"" << JsonEscape(kind)
        << "\",\"payload\":\"" << JsonEscape(payload) << "\"}";
    output.flush();
    if (!output) return false;
    output.close();
    if (std::rename(temporaryPath.c_str(), eventPath.c_str()) != 0) {
        std::remove(temporaryPath.c_str());
        return false;
    }
    host->sequence.store(sequence, std::memory_order_release);
    return true;
}

void HostCallback(const v8::FunctionCallbackInfo<v8::Value>& arguments)
{
    bool accepted = false;
    if (arguments.Length() == 2 && arguments[0]->IsString() &&
        arguments[1]->IsString() && arguments.Data()->IsExternal()) {
        v8::Isolate *isolate = arguments.GetIsolate();
        v8::String::Utf8Value kind(isolate, arguments[0]);
        v8::String::Utf8Value payload(isolate, arguments[1]);
        if (*kind != nullptr && *payload != nullptr) {
            auto *host = static_cast<HostCallbackContext *>(
                arguments.Data().As<v8::External>()->Value());
            accepted = WriteHostEvent(
                host,
                std::string(*kind, kind.length()),
                std::string(*payload, payload.length()));
        }
    }
    arguments.GetReturnValue().Set(accepted);
}

void SetGlobalString(v8::Isolate *isolate, v8::Local<v8::Context> context,
    const char *name, const std::string& value)
{
    context->Global()
        ->Set(context,
            v8::String::NewFromUtf8(isolate, name).ToLocalChecked(),
            v8::String::NewFromUtf8(
                isolate, value.c_str(), v8::NewStringType::kNormal,
                static_cast<int>(value.size())).ToLocalChecked())
        .Check();
}

void SetGlobalInt32(v8::Isolate *isolate, v8::Local<v8::Context> context,
    const char *name, int32_t value)
{
    context->Global()
        ->Set(context,
            v8::String::NewFromUtf8(isolate, name).ToLocalChecked(),
            v8::Int32::New(isolate, value))
        .Check();
}

void SetGlobalInt64(v8::Isolate *isolate, v8::Local<v8::Context> context,
    const char *name, int64_t value)
{
    context->Global()
        ->Set(context,
            v8::String::NewFromUtf8(isolate, name).ToLocalChecked(),
            v8::Number::New(isolate, static_cast<double>(value)))
        .Check();
}

void SetHostCallback(v8::Isolate *isolate, v8::Local<v8::Context> context,
    HostCallbackContext *host)
{
    v8::Local<v8::External> data = v8::External::New(isolate, host);
    v8::Local<v8::Function> callback =
        v8::Function::New(context, HostCallback, data).ToLocalChecked();
    context->Global()
        ->Set(context,
            v8::String::NewFromUtf8Literal(
                isolate, "__opencodeHarmonyPublishHostEvent"),
            callback)
        .Check();
}

int RunEmbeddedNode(const opencode::formal::BootstrapInput& input)
{
    std::vector<std::string> arguments = {
        "opencode-formal-runtime",
        "--jitless",
    };
    std::shared_ptr<node::InitializationResult> initialization =
        node::InitializeOncePerProcess(arguments, {
            node::ProcessInitializationFlags::kNoInitializeV8,
            node::ProcessInitializationFlags::kNoInitializeNodeV8Platform,
            node::ProcessInitializationFlags::kDisableNodeOptionsEnv,
            node::ProcessInitializationFlags::kNoInitializeCppgc,
        });

    LogNodeErrors(initialization->errors());
    if (initialization->early_return() != 0) {
        const int exitCode = initialization->exit_code();
        node::TearDownOncePerProcess();
        return exitCode;
    }

    std::unique_ptr<node::MultiIsolatePlatform> platform =
        node::MultiIsolatePlatform::Create(2);
    v8::V8::InitializePlatform(platform.get());
    cppgc::InitializeProcess(platform->GetPageAllocator());
    v8::V8::Initialize();

    int exitCode = 1;
    std::vector<std::string> errors;
    std::unique_ptr<node::CommonEnvironmentSetup> setup =
        node::CommonEnvironmentSetup::Create(
            platform.get(), &errors, initialization->args(),
            initialization->exec_args());
    if (!setup) {
        LogNodeErrors(errors);
    } else {
        v8::Isolate *isolate = setup->isolate();
        node::Environment *environment = setup->env();
        HostCallbackContext host {
            .eventPath =
                input.filesDirectory + "/" +
                opencode::formal::HOST_EVENT_FILE_NAME,
            .generation = input.generation,
        };
        {
            v8::Locker locker(isolate);
            v8::Isolate::Scope isolateScope(isolate);
            v8::HandleScope handleScope(isolate);
            v8::Local<v8::Context> context = setup->context();
            v8::Context::Scope contextScope(context);

            SetGlobalInt32(isolate, context,
                "__opencodeHarmonyContractVersion",
                opencode::formal::CONTRACT_VERSION);
            SetGlobalInt64(isolate, context,
                "__opencodeHarmonyGeneration", input.generation);
            SetGlobalInt32(isolate, context,
                "__opencodeHarmonyRequestedPort", input.requestedPort);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyFilesDirectory", input.filesDirectory);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyCacheDirectory", input.cacheDirectory);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyTemporaryDirectory",
                input.temporaryDirectory);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyProjectRoot", input.projectRoot);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyEntryPath", input.entryPath);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyCredential", input.credential);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyAllowedOrigin", input.allowedOrigin);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyCapabilityProfile",
                input.capabilityProfile);
            SetGlobalString(isolate, context,
                "__opencodeHarmonyDeviceForm",
                input.deviceForm);
            SetHostCallback(isolate, context, &host);

            v8::MaybeLocal<v8::Value> loaded =
                node::LoadEnvironment(environment, R"JS(
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const bootstrap = Object.freeze({
  contractVersion: globalThis.__opencodeHarmonyContractVersion,
  generation: globalThis.__opencodeHarmonyGeneration,
  requestedPort: globalThis.__opencodeHarmonyRequestedPort,
  filesDirectory: globalThis.__opencodeHarmonyFilesDirectory,
  cacheDirectory: globalThis.__opencodeHarmonyCacheDirectory,
  temporaryDirectory: globalThis.__opencodeHarmonyTemporaryDirectory,
  projectRoot: globalThis.__opencodeHarmonyProjectRoot,
  entryPath: globalThis.__opencodeHarmonyEntryPath,
  credential: globalThis.__opencodeHarmonyCredential,
  allowedOrigin: globalThis.__opencodeHarmonyAllowedOrigin,
  capabilityProfile: globalThis.__opencodeHarmonyCapabilityProfile,
  deviceForm: globalThis.__opencodeHarmonyDeviceForm
});
const formalRoot = path.posix.join(
  bootstrap.filesDirectory,
  'opencode-formal',
  'v1'
);
const runtimeRoot = path.posix.dirname(bootstrap.entryPath);
const installRoot = path.posix.dirname(runtimeRoot);
Object.assign(process.env, {
  HOME: path.posix.join(formalRoot, 'home'),
  OPENCODE_HARMONY_HOME: path.posix.join(formalRoot, 'home'),
  OPENCODE_HARMONY_DATA: path.posix.join(formalRoot, 'data'),
  OPENCODE_HARMONY_CACHE: path.posix.join(
    bootstrap.cacheDirectory,
    'opencode-formal',
    'v1'
  ),
  OPENCODE_HARMONY_CONFIG: path.posix.join(formalRoot, 'config'),
  OPENCODE_HARMONY_STATE: path.posix.join(formalRoot, 'state'),
  OPENCODE_HARMONY_TMP: path.posix.join(
    bootstrap.temporaryDirectory,
    'opencode-formal',
    'v1'
  ),
  OPENCODE_HARMONY_BIN: path.posix.join(
    bootstrap.cacheDirectory,
    'opencode-formal',
    'v1',
    'bin'
  ),
  OPENCODE_HARMONY_LOG: path.posix.join(formalRoot, 'data', 'log'),
  OPENCODE_HARMONY_REPOS: path.posix.join(formalRoot, 'data', 'repos'),
  OPENCODE_HARMONY_PROJECT_ROOT: bootstrap.projectRoot,
  OPENCODE_HARMONY_CLIENT_ROOT: path.posix.join(installRoot, 'client'),
  OPENCODE_HARMONY_DEVICE_FORM: bootstrap.deviceForm,
  OPENCODE_CONFIG_DIR: path.posix.join(formalRoot, 'config'),
  OPENCODE_DB: path.posix.join(formalRoot, 'data', 'opencode.db'),
  OPENCODE_MODELS_PATH: path.posix.join(
    runtimeRoot,
    'assets',
    'models-dev-api.json'
  ),
  OPENCODE_SERVER_USERNAME: 'opencode',
  OPENCODE_SERVER_PASSWORD: bootstrap.credential,
  OPENCODE_CLIENT: 'harmony',
  OPENCODE_DISABLE_AUTOUPDATE: '1',
  OPENCODE_DISABLE_PRUNE: '1',
  OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER: '1'
});
process.chdir(bootstrap.projectRoot);
const nativePublish = globalThis.__opencodeHarmonyPublishHostEvent;
for (const name of [
  '__opencodeHarmonyContractVersion',
  '__opencodeHarmonyGeneration',
  '__opencodeHarmonyRequestedPort',
  '__opencodeHarmonyFilesDirectory',
  '__opencodeHarmonyCacheDirectory',
  '__opencodeHarmonyTemporaryDirectory',
  '__opencodeHarmonyProjectRoot',
  '__opencodeHarmonyEntryPath',
  '__opencodeHarmonyCredential',
  '__opencodeHarmonyAllowedOrigin',
  '__opencodeHarmonyCapabilityProfile',
  '__opencodeHarmonyDeviceForm',
  '__opencodeHarmonyPublishHostEvent'
]) {
  delete globalThis[name];
}

const publish = (kind, payload = {}) => {
  let encoded = '{}';
  try {
    encoded = JSON.stringify(payload);
  } catch {
    encoded = '{"code":"HOST_EVENT_SERIALIZATION_FAILED"}';
  }
  return nativePublish(kind, encoded);
};
const boundedCategory = (error) => {
  const candidate = error && typeof error.name === 'string' ? error.name : typeof error;
  return /^[A-Za-z0-9._-]{1,64}$/.test(candidate) ? candidate : 'UnknownError';
};
const host = Object.freeze({
  version: 1,
  approvedCallbacks: Object.freeze([
    'runtime.ready',
    'runtime.fatal',
    'runtime.stopped',
    'workspace.changed'
  ]),
  publish
});

let runtimeHandle;
let stopRequested = false;
let stopPromise;
const stop = () => {
  stopRequested = true;
  if (!runtimeHandle) return Promise.resolve();
  if (stopPromise) return stopPromise;
  stopPromise = (async () => {
    const dispose = typeof runtimeHandle.stop === 'function'
      ? runtimeHandle.stop.bind(runtimeHandle)
      : typeof runtimeHandle.dispose === 'function'
        ? runtimeHandle.dispose.bind(runtimeHandle)
        : undefined;
    if (!dispose) throw new TypeError('FORMAL_RUNTIME_STOP_EXPORT_INVALID');
    await dispose();
    publish('runtime.stopped', { generation: bootstrap.generation });
    process.exitCode = 0;
  })().catch((error) => {
    publish('runtime.fatal', {
      generation: bootstrap.generation,
      code: 'FORMAL_RUNTIME_STOP_FAILED',
      category: boundedCategory(error)
    });
    process.exitCode = 1;
  });
  return stopPromise;
};

process.once('SIGTERM', () => void stop());
process.once('SIGINT', () => void stop());

void (async () => {
  const entry = await import(pathToFileURL(bootstrap.entryPath).href);
  const start = entry.startHarmonyNativeChildRuntime;
  if (typeof start !== 'function') {
    throw new TypeError('FORMAL_RUNTIME_ENTRY_EXPORT_MISSING');
  }
  runtimeHandle = await start(bootstrap, host);
  if (!runtimeHandle || (
    typeof runtimeHandle.stop !== 'function' &&
    typeof runtimeHandle.dispose !== 'function'
  )) {
    throw new TypeError('FORMAL_RUNTIME_HANDLE_INVALID');
  }
  const ready = runtimeHandle.ready;
  if (!ready || ready.generation !== bootstrap.generation) {
    throw new TypeError('FORMAL_RUNTIME_READY_INVALID');
  }
  publish('runtime.ready', {
    generation: ready.generation,
    hostname: ready.hostname,
    port: ready.port
  });
  if (stopRequested) await stop();
})().catch((error) => {
  publish('runtime.fatal', {
    generation: bootstrap.generation,
    code: 'FORMAL_RUNTIME_START_FAILED',
    category: boundedCategory(error)
  });
  process.exitCode = 1;
});
)JS");

            if (loaded.IsEmpty()) {
                OH_LOG_Print(LOG_APP, LOG_ERROR,
                    FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
                    "FORMAL_NODE_LOAD_FAILED generation=%{public}lld",
                    static_cast<long long>(input.generation));
            } else {
                OH_LOG_Print(LOG_APP, LOG_INFO,
                    FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
                    "FORMAL_NODE_LOAD_OK generation=%{public}lld",
                    static_cast<long long>(input.generation));
                exitCode = node::SpinEventLoop(environment).FromMaybe(1);
            }
            node::Stop(environment);
        }
    }

    setup.reset();
    v8::V8::Dispose();
    cppgc::ShutdownProcess();
    v8::V8::DisposePlatform();
    platform.reset();
    node::TearDownOncePerProcess();
    return exitCode;
}
} // namespace

extern "C" __attribute__((visibility("default"))) void
OpenCodeFormalRuntimeMain(NativeChildProcess_Args arguments)
{
    opencode::formal::BootstrapInput input;
    if (!opencode::formal::ParseBootstrapInput(arguments.entryParams, &input)) {
        OH_LOG_Print(LOG_APP, LOG_ERROR,
            FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
            "FORMAL_NCP_BOOTSTRAP_REJECTED");
        return;
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
        "FORMAL_NCP_CHILD_ENTER generation=%{public}lld profile=%{public}s",
        static_cast<long long>(input.generation),
        input.capabilityProfile.c_str());
    const int exitCode = RunEmbeddedNode(input);
    OH_LOG_Print(LOG_APP, exitCode == 0 ? LOG_INFO : LOG_ERROR,
        FORMAL_LOG_DOMAIN, FORMAL_LOG_TAG,
        "FORMAL_NCP_CHILD_EXIT generation=%{public}lld code=%{public}d",
        static_cast<long long>(input.generation), exitCode);
}
