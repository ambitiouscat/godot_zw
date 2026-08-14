#ifndef OPENCODE_FORMAL_RUNTIME_CONTRACT_H
#define OPENCODE_FORMAL_RUNTIME_CONTRACT_H

#include <array>
#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>

namespace opencode::formal {

constexpr int32_t CONTRACT_VERSION = 1;
constexpr size_t MAX_PATH_BYTES = 4096;
constexpr size_t MAX_CREDENTIAL_BYTES = 128;
constexpr size_t MAX_ORIGIN_BYTES = 256;
constexpr size_t MAX_CAPABILITY_PROFILE_BYTES = 64;
constexpr size_t MAX_DEVICE_FORM_BYTES = 32;
constexpr size_t MAX_HOST_EVENT_BYTES = 4096;
constexpr uint64_t MAX_HOST_EVENT_QUEUE_DEPTH = 4096;
constexpr const char *CAPABILITY_PROFILE = "harmony-tier-a";
constexpr const char *ENTRY_EXPORT = "startHarmonyNativeChildRuntime";
constexpr const char *CHILD_ENTRY = "libopencode_formal_runtime.so:OpenCodeFormalRuntimeMain";
constexpr const char *HOST_EVENT_FILE_NAME = "opencode-formal-host-event.json";

constexpr std::array<const char *, 4> APPROVED_HOST_CALLBACKS = {
    "runtime.ready",
    "runtime.fatal",
    "runtime.stopped",
    "workspace.changed",
};

struct BootstrapInput {
    std::string filesDirectory;
    std::string cacheDirectory;
    std::string temporaryDirectory;
    std::string projectRoot;
    std::string entryPath;
    std::string credential;
    std::string allowedOrigin;
    std::string capabilityProfile;
    // Optional device form token from deviceInfo.deviceType (e.g. "2in1");
    // empty when the host did not supply one. Gates form-factor-bound
    // runtime capabilities such as the shell tool.
    std::string deviceForm;
    int64_t generation = 0;
    int32_t requestedPort = 0;
};

inline bool ParseInt32(const std::string& value, int32_t *result);

inline bool HasUnsupportedText(const std::string& value)
{
    return value.find('\0') != std::string::npos ||
        value.find('\n') != std::string::npos ||
        value.find('\r') != std::string::npos;
}

inline bool IsAbsoluteHarmonyPath(const std::string& value)
{
    return !value.empty() && value.front() == '/' &&
        value.find("/../") == std::string::npos &&
        value.find("/./") == std::string::npos &&
        !value.ends_with("/..") &&
        !value.ends_with("/.");
}

inline bool IsPathInside(const std::string& root, const std::string& candidate)
{
    if (candidate == root) return true;
    if (!candidate.starts_with(root)) return false;
    return root.ends_with("/") ||
        (candidate.size() > root.size() && candidate[root.size()] == '/');
}

inline bool IsBase64UrlCredential(const std::string& value)
{
    if (value.size() < 43 || value.size() > MAX_CREDENTIAL_BYTES) return false;
    for (const char character : value) {
        const bool accepted =
            (character >= 'a' && character <= 'z') ||
            (character >= 'A' && character <= 'Z') ||
            (character >= '0' && character <= '9') ||
            character == '-' || character == '_';
        if (!accepted) return false;
    }
    return true;
}

inline bool IsLoopbackOrigin(const std::string& value)
{
    if (value == "http://127.0.0.1" ||
        value == "https://127.0.0.1") {
        return true;
    }
    const std::array<std::string, 2> prefixes = {
        "http://127.0.0.1:",
        "https://127.0.0.1:",
    };
    for (const std::string& prefix : prefixes) {
        if (!value.starts_with(prefix)) continue;
        const std::string port = value.substr(prefix.size());
        int32_t parsedPort = 0;
        return ParseInt32(port, &parsedPort) &&
            parsedPort > 0 && parsedPort <= 65535;
    }
    return false;
}

inline bool ValidateBootstrapInput(const BootstrapInput& input)
{
    const std::array<const std::string *, 5> paths = {
        &input.filesDirectory,
        &input.cacheDirectory,
        &input.temporaryDirectory,
        &input.projectRoot,
        &input.entryPath,
    };
    for (const std::string *path : paths) {
        if (path->size() > MAX_PATH_BYTES || HasUnsupportedText(*path) ||
            !IsAbsoluteHarmonyPath(*path)) {
            return false;
        }
    }
    return IsPathInside(input.filesDirectory, input.entryPath) &&
        IsBase64UrlCredential(input.credential) &&
        input.allowedOrigin.size() <= MAX_ORIGIN_BYTES &&
        !HasUnsupportedText(input.allowedOrigin) &&
        IsLoopbackOrigin(input.allowedOrigin) &&
        input.capabilityProfile == CAPABILITY_PROFILE &&
        input.capabilityProfile.size() <= MAX_CAPABILITY_PROFILE_BYTES &&
        input.deviceForm.size() <= MAX_DEVICE_FORM_BYTES &&
        !HasUnsupportedText(input.deviceForm) &&
        input.generation > 0 &&
        input.requestedPort >= 0 &&
        input.requestedPort <= 65535;
}

inline std::string SerializeBootstrapInput(const BootstrapInput& input)
{
    std::ostringstream output;
    output << CONTRACT_VERSION << '\n'
        << input.generation << '\n'
        << input.requestedPort << '\n'
        << input.filesDirectory << '\n'
        << input.cacheDirectory << '\n'
        << input.temporaryDirectory << '\n'
        << input.projectRoot << '\n'
        << input.entryPath << '\n'
        << input.credential << '\n'
        << input.allowedOrigin << '\n'
        << input.capabilityProfile << '\n'
        << input.deviceForm;
    return output.str();
}

inline bool ParseInt32(const std::string& value, int32_t *result)
{
    if (result == nullptr || value.empty()) return false;
    errno = 0;
    char *end = nullptr;
    const long parsed = std::strtol(value.c_str(), &end, 10);
    if (errno == ERANGE || end == value.c_str() || *end != '\0' ||
        parsed < 0 || parsed > INT32_MAX) {
        return false;
    }
    *result = static_cast<int32_t>(parsed);
    return true;
}

inline bool ParseInt64(const std::string& value, int64_t *result)
{
    if (result == nullptr || value.empty()) return false;
    errno = 0;
    char *end = nullptr;
    const long long parsed = std::strtoll(value.c_str(), &end, 10);
    if (errno == ERANGE || end == value.c_str() || *end != '\0' ||
        parsed <= 0) {
        return false;
    }
    *result = static_cast<int64_t>(parsed);
    return true;
}

inline bool ParseBootstrapInput(const char *serialized, BootstrapInput *input)
{
    if (serialized == nullptr || input == nullptr) return false;
    std::istringstream source(serialized);
    std::string version;
    std::string generation;
    std::string requestedPort;
    if (!std::getline(source, version) ||
        !std::getline(source, generation) ||
        !std::getline(source, requestedPort) ||
        !std::getline(source, input->filesDirectory) ||
        !std::getline(source, input->cacheDirectory) ||
        !std::getline(source, input->temporaryDirectory) ||
        !std::getline(source, input->projectRoot) ||
        !std::getline(source, input->entryPath) ||
        !std::getline(source, input->credential) ||
        !std::getline(source, input->allowedOrigin) ||
        !std::getline(source, input->capabilityProfile)) {
        return false;
    }
    // deviceForm is a trailing optional field; older serialized blobs end at
    // capabilityProfile and leave it empty.
    if (!std::getline(source, input->deviceForm)) {
        input->deviceForm.clear();
    }
    int32_t parsedVersion = 0;
    return ParseInt32(version, &parsedVersion) &&
        parsedVersion == CONTRACT_VERSION &&
        ParseInt64(generation, &input->generation) &&
        ParseInt32(requestedPort, &input->requestedPort) &&
        ValidateBootstrapInput(*input);
}

inline bool IsApprovedHostCallback(const std::string& name)
{
    for (const char *approved : APPROVED_HOST_CALLBACKS) {
        if (name == approved) return true;
    }
    return false;
}

} // namespace opencode::formal

#endif // OPENCODE_FORMAL_RUNTIME_CONTRACT_H
