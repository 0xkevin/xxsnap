#include "app/PreferencesSettings.h"

#include <algorithm>
#include <climits>
#include <cwchar>
#include <cwctype>
#include <limits>
#include <utility>

namespace xxsnap::win {
namespace {

constexpr wchar_t preferencesKey[] = L"Software\\XxSnap\\Preferences";
constexpr wchar_t defaultFilenameTemplate[] =
    L"xxsnap_截图_{yyyyMMdd}_{HHmmss}";

constexpr wchar_t filenameTemplateName[] = L"FilenameTemplate";
constexpr wchar_t checksForUpdatesName[] = L"ChecksForUpdatesAtLaunch";
constexpr wchar_t updateIntervalName[] = L"UpdateCheckIntervalHours";
constexpr wchar_t disablesSoundName[] = L"DisablesTextRecognitionSound";
constexpr wchar_t disablesNotificationName[] =
    L"DisablesTextRecognitionSuccessNotification";
constexpr wchar_t showsShortcutFeedbackName[] = L"ShowsShortcutFeedback";
constexpr wchar_t showsSystemShortcutFeedbackName[] =
    L"ShowsSystemShortcutFeedback";

std::wstring trim(const std::wstring& value)
{
    const auto first = std::find_if_not(value.begin(), value.end(),
        [](wchar_t character) { return std::iswspace(character) != 0; });
    if (first == value.end()) return {};
    const auto last = std::find_if_not(value.rbegin(), value.rend(),
        [](wchar_t character) { return std::iswspace(character) != 0; }).base();
    return std::wstring(first, last);
}

bool containsInvalidPathCharacter(const std::wstring& value) noexcept
{
    constexpr wchar_t invalid[] = L"<>:\"/\\|?*";
    return std::any_of(value.begin(), value.end(), [&](wchar_t character) {
        return character < 32 || std::wcschr(invalid, character) != nullptr;
    });
}

bool endsWithPng(const std::wstring& value) noexcept
{
    if (value.size() < 4U) return false;
    constexpr wchar_t suffix[] = L".png";
    const auto offset = value.size() - 4U;
    for (std::size_t index = 0; index < 4U; ++index) {
        if (std::towlower(value[offset + index]) != suffix[index]) return false;
    }
    return true;
}

std::wstring fourDigits(WORD value)
{
    wchar_t buffer[5]{};
    swprintf_s(buffer, L"%04u", static_cast<unsigned int>(value));
    return buffer;
}

std::wstring twoDigits(WORD value)
{
    wchar_t buffer[3]{};
    swprintf_s(buffer, L"%02u", static_cast<unsigned int>(value));
    return buffer;
}

std::optional<bool> readBool(
    const PreferencesRegistry& registry, const wchar_t* name) noexcept
{
    const auto value = registry.readDword(name);
    if (!value.has_value() || *value > 1U) return std::nullopt;
    return *value != 0U;
}

bool validUpdateInterval(int value) noexcept
{
    return std::find(allowedUpdateIntervals.begin(),
               allowedUpdateIntervals.end(), value)
        != allowedUpdateIntervals.end();
}

class RegistryKey final {
public:
    explicit RegistryKey(REGSAM access) noexcept
    {
        if ((access & KEY_SET_VALUE) != 0U) {
            RegCreateKeyExW(HKEY_CURRENT_USER, preferencesKey, 0, nullptr,
                REG_OPTION_NON_VOLATILE, access, nullptr, &key_, nullptr);
        } else {
            RegOpenKeyExW(HKEY_CURRENT_USER, preferencesKey, 0, access, &key_);
        }
    }

    ~RegistryKey()
    {
        if (key_ != nullptr) RegCloseKey(key_);
    }

    RegistryKey(const RegistryKey&) = delete;
    RegistryKey& operator=(const RegistryKey&) = delete;

    HKEY get() const noexcept { return key_; }

private:
    HKEY key_ = nullptr;
};

} // namespace

PreferencesSettings PreferencesSettings::defaults()
{
    PreferencesSettings result;
    result.filenameTemplate = defaultFilenameTemplate;
    return result;
}

bool operator==(
    const PreferencesSettings& lhs, const PreferencesSettings& rhs) noexcept
{
    return lhs.filenameTemplate == rhs.filenameTemplate
        && lhs.checksForUpdatesAtLaunch == rhs.checksForUpdatesAtLaunch
        && lhs.updateCheckIntervalHours == rhs.updateCheckIntervalHours
        && lhs.disablesTextRecognitionSound
            == rhs.disablesTextRecognitionSound
        && lhs.disablesTextRecognitionSuccessNotification
            == rhs.disablesTextRecognitionSuccessNotification
        && lhs.showsShortcutFeedback == rhs.showsShortcutFeedback
        && lhs.showsSystemShortcutFeedback
            == rhs.showsSystemShortcutFeedback;
}

bool operator!=(
    const PreferencesSettings& lhs, const PreferencesSettings& rhs) noexcept
{
    return !(lhs == rhs);
}

std::optional<std::wstring> SystemPreferencesRegistry::readString(
    const wchar_t* name) const noexcept
{
    if (name == nullptr) return std::nullopt;
    RegistryKey key(KEY_QUERY_VALUE);
    if (key.get() == nullptr) return std::nullopt;
    DWORD type = 0;
    DWORD byteCount = 0;
    if (RegQueryValueExW(key.get(), name, nullptr, &type, nullptr, &byteCount)
            != ERROR_SUCCESS
        || (type != REG_SZ && type != REG_EXPAND_SZ)
        || byteCount < sizeof(wchar_t)
        || byteCount / sizeof(wchar_t)
            > static_cast<DWORD>(std::numeric_limits<int>::max())) {
        return std::nullopt;
    }
    try {
        std::wstring value(byteCount / sizeof(wchar_t), L'\0');
        if (RegQueryValueExW(key.get(), name, nullptr, &type,
                reinterpret_cast<BYTE*>(value.data()), &byteCount)
            != ERROR_SUCCESS) {
            return std::nullopt;
        }
        while (!value.empty() && value.back() == L'\0') value.pop_back();
        return value;
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<DWORD> SystemPreferencesRegistry::readDword(
    const wchar_t* name) const noexcept
{
    if (name == nullptr) return std::nullopt;
    RegistryKey key(KEY_QUERY_VALUE);
    if (key.get() == nullptr) return std::nullopt;
    DWORD value = 0;
    DWORD type = 0;
    DWORD byteCount = sizeof(value);
    if (RegQueryValueExW(key.get(), name, nullptr, &type,
            reinterpret_cast<BYTE*>(&value), &byteCount) != ERROR_SUCCESS
        || type != REG_DWORD || byteCount != sizeof(value)) {
        return std::nullopt;
    }
    return value;
}

bool SystemPreferencesRegistry::writeString(
    const wchar_t* name, const std::wstring& value) noexcept
{
    if (name == nullptr
        || value.size() > (std::numeric_limits<DWORD>::max() / sizeof(wchar_t))
                - 1U) {
        return false;
    }
    RegistryKey key(KEY_SET_VALUE);
    if (key.get() == nullptr) return false;
    const auto byteCount = static_cast<DWORD>(
        (value.size() + 1U) * sizeof(wchar_t));
    return RegSetValueExW(key.get(), name, 0, REG_SZ,
               reinterpret_cast<const BYTE*>(value.c_str()), byteCount)
        == ERROR_SUCCESS;
}

bool SystemPreferencesRegistry::writeDword(
    const wchar_t* name, DWORD value) noexcept
{
    if (name == nullptr) return false;
    RegistryKey key(KEY_SET_VALUE);
    if (key.get() == nullptr) return false;
    return RegSetValueExW(key.get(), name, 0, REG_DWORD,
               reinterpret_cast<const BYTE*>(&value), sizeof(value))
        == ERROR_SUCCESS;
}

PreferencesSettingsStore::PreferencesSettingsStore(
    PreferencesRegistry& registry) noexcept
    : registry_(registry)
{
}

PreferencesSettings PreferencesSettingsStore::load() const
{
    auto result = PreferencesSettings::defaults();
    if (const auto value = registry_.readString(filenameTemplateName)) {
        result.filenameTemplate = *value;
    }
    if (const auto value = readBool(registry_, checksForUpdatesName)) {
        result.checksForUpdatesAtLaunch = *value;
    }
    if (const auto value = registry_.readDword(updateIntervalName);
        value.has_value() && *value <= static_cast<DWORD>(INT_MAX)
        && validUpdateInterval(static_cast<int>(*value))) {
        result.updateCheckIntervalHours = static_cast<int>(*value);
    }
    if (const auto value = readBool(registry_, disablesSoundName)) {
        result.disablesTextRecognitionSound = *value;
    }
    if (const auto value = readBool(registry_, disablesNotificationName)) {
        result.disablesTextRecognitionSuccessNotification = *value;
    }
    if (const auto value = readBool(registry_, showsShortcutFeedbackName)) {
        result.showsShortcutFeedback = *value;
    }
    if (const auto value = readBool(
            registry_, showsSystemShortcutFeedbackName)) {
        result.showsSystemShortcutFeedback = *value;
    }
    return result;
}

bool PreferencesSettingsStore::save(
    const PreferencesSettings& settings) noexcept
{
    if (!validUpdateInterval(settings.updateCheckIntervalHours)) return false;
    bool succeeded = registry_.writeString(
        filenameTemplateName, settings.filenameTemplate);
    succeeded = registry_.writeDword(checksForUpdatesName,
                    settings.checksForUpdatesAtLaunch ? 1U : 0U)
        && succeeded;
    succeeded = registry_.writeDword(updateIntervalName,
                    static_cast<DWORD>(settings.updateCheckIntervalHours))
        && succeeded;
    succeeded = registry_.writeDword(disablesSoundName,
                    settings.disablesTextRecognitionSound ? 1U : 0U)
        && succeeded;
    succeeded = registry_.writeDword(disablesNotificationName,
                    settings.disablesTextRecognitionSuccessNotification
                        ? 1U : 0U)
        && succeeded;
    succeeded = registry_.writeDword(showsShortcutFeedbackName,
                    settings.showsShortcutFeedback ? 1U : 0U)
        && succeeded;
    succeeded = registry_.writeDword(showsSystemShortcutFeedbackName,
                    settings.showsSystemShortcutFeedback ? 1U : 0U)
        && succeeded;
    return succeeded;
}

FilenameRenderResult renderCaptureFilename(
    const std::wstring& filenameTemplate, const SYSTEMTIME& localTime)
{
    const auto value = trim(filenameTemplate);
    if (value.empty()) return {{}, FilenameTemplateError::empty, {}};
    if (containsInvalidPathCharacter(value)) {
        return {{}, FilenameTemplateError::pathCharacter, {}};
    }

    const auto date = fourDigits(localTime.wYear)
        + twoDigits(localTime.wMonth) + twoDigits(localTime.wDay);
    const auto time = twoDigits(localTime.wHour)
        + twoDigits(localTime.wMinute) + twoDigits(localTime.wSecond);
    std::wstring rendered;
    rendered.reserve(value.size() + 16U);
    for (std::size_t index = 0; index < value.size();) {
        if (value[index] == L'{') {
            const auto closing = value.find(L'}', index + 1U);
            if (closing == std::wstring::npos) {
                return {{}, FilenameTemplateError::unknownVariable,
                    value.substr(index)};
            }
            const auto variable = value.substr(
                index, closing - index + 1U);
            if (variable == L"{yyyyMMdd}") {
                rendered += date;
            } else if (variable == L"{HHmmss}") {
                rendered += time;
            } else {
                return {{}, FilenameTemplateError::unknownVariable,
                    variable};
            }
            index = closing + 1U;
        } else if (value[index] == L'}') {
            return {{}, FilenameTemplateError::unknownVariable, L"}"};
        } else {
            rendered.push_back(value[index]);
            ++index;
        }
    }
    if (!endsWithPng(rendered)) rendered += L".png";
    return {std::move(rendered), std::nullopt, {}};
}

CaptureFilenameProvider::CaptureFilenameProvider(
    const PreferencesSettingsStore& settingsStore) noexcept
    : settingsStore_(settingsStore)
{
}

std::wstring CaptureFilenameProvider::suggestedFilename(
    const SYSTEMTIME& localTime) const
{
    const auto configured = renderCaptureFilename(
        settingsStore_.load().filenameTemplate, localTime);
    if (!configured.error.has_value()) return configured.filename;
    const auto fallback = renderCaptureFilename(
        PreferencesSettings::defaults().filenameTemplate, localTime);
    return !fallback.error.has_value()
        ? fallback.filename : L"xxsnap_截图.png";
}

std::wstring CaptureFilenameProvider::suggestedFilename() const
{
    SYSTEMTIME localTime{};
    GetLocalTime(&localTime);
    return suggestedFilename(localTime);
}

std::wstring suggestedCaptureFilename()
{
    SystemPreferencesRegistry registry;
    PreferencesSettingsStore store(registry);
    return CaptureFilenameProvider(store).suggestedFilename();
}

} // namespace xxsnap::win
