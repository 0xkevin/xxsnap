#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <array>
#include <optional>
#include <string>

namespace xxsnap::win {

struct PreferencesSettings {
    std::wstring filenameTemplate;
    bool checksForUpdatesAtLaunch = true;
    int updateCheckIntervalHours = 24;
    bool disablesTextRecognitionSound = false;
    bool disablesTextRecognitionSuccessNotification = false;
    bool showsShortcutFeedback = true;
    bool showsSystemShortcutFeedback = true;

    static PreferencesSettings defaults();
};

bool operator==(
    const PreferencesSettings& lhs, const PreferencesSettings& rhs) noexcept;
bool operator!=(
    const PreferencesSettings& lhs, const PreferencesSettings& rhs) noexcept;

inline constexpr std::array<int, 6> allowedUpdateIntervals{
    1, 6, 12, 24, 48, 72};

class PreferencesRegistry {
public:
    virtual ~PreferencesRegistry() = default;
    virtual std::optional<std::wstring> readString(
        const wchar_t* name) const noexcept = 0;
    virtual std::optional<DWORD> readDword(
        const wchar_t* name) const noexcept = 0;
    virtual bool writeString(
        const wchar_t* name, const std::wstring& value) noexcept = 0;
    virtual bool writeDword(const wchar_t* name, DWORD value) noexcept = 0;
};

class SystemPreferencesRegistry final : public PreferencesRegistry {
public:
    std::optional<std::wstring> readString(
        const wchar_t* name) const noexcept override;
    std::optional<DWORD> readDword(
        const wchar_t* name) const noexcept override;
    bool writeString(
        const wchar_t* name, const std::wstring& value) noexcept override;
    bool writeDword(const wchar_t* name, DWORD value) noexcept override;
};

class PreferencesSettingsStore final {
public:
    explicit PreferencesSettingsStore(PreferencesRegistry& registry) noexcept;

    PreferencesSettings load() const;
    bool save(const PreferencesSettings& settings) noexcept;

private:
    PreferencesRegistry& registry_;
};

enum class FilenameTemplateError {
    empty,
    pathCharacter,
    unknownVariable,
};

struct FilenameRenderResult {
    std::wstring filename;
    std::optional<FilenameTemplateError> error;
    std::wstring invalidVariable;
};

FilenameRenderResult renderCaptureFilename(
    const std::wstring& filenameTemplate, const SYSTEMTIME& localTime);

class CaptureFilenameProvider final {
public:
    explicit CaptureFilenameProvider(
        const PreferencesSettingsStore& settingsStore) noexcept;

    std::wstring suggestedFilename(const SYSTEMTIME& localTime) const;
    std::wstring suggestedFilename() const;

private:
    const PreferencesSettingsStore& settingsStore_;
};

std::wstring suggestedCaptureFilename();

} // namespace xxsnap::win
