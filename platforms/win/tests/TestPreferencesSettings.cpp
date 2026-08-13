#include "app/PreferencesSettings.h"
#include "app/HotKeySettings.h"

#include <iostream>
#include <map>
#include <optional>
#include <string>

using namespace xxsnap::win;

namespace {

int failureCount = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failureCount;                                                     \
        }                                                                       \
    } while (false)

class FakeRegistry final : public PreferencesRegistry {
public:
    std::optional<std::wstring> readString(
        const wchar_t* name) const noexcept override
    {
        const auto found = strings.find(name == nullptr ? L"" : name);
        return found == strings.end()
            ? std::nullopt : std::optional<std::wstring>{found->second};
    }

    std::optional<DWORD> readDword(
        const wchar_t* name) const noexcept override
    {
        const auto found = dwords.find(name == nullptr ? L"" : name);
        return found == dwords.end()
            ? std::nullopt : std::optional<DWORD>{found->second};
    }

    bool writeString(
        const wchar_t* name, const std::wstring& value) noexcept override
    {
        if (failWrites) return false;
        strings[name == nullptr ? L"" : name] = value;
        return true;
    }

    bool writeDword(const wchar_t* name, DWORD value) noexcept override
    {
        if (failWrites) return false;
        dwords[name == nullptr ? L"" : name] = value;
        return true;
    }

    std::map<std::wstring, std::wstring> strings;
    std::map<std::wstring, DWORD> dwords;
    bool failWrites = false;
};

void testDefaultsMatchMacContract()
{
    const auto settings = PreferencesSettings::defaults();
    CHECK(settings.filenameTemplate == L"xxsnap_截图_{yyyyMMdd}_{HHmmss}");
    CHECK(settings.checksForUpdatesAtLaunch);
    CHECK(settings.updateCheckIntervalHours == 24);
    CHECK(!settings.disablesTextRecognitionSound);
    CHECK(!settings.disablesTextRecognitionSuccessNotification);
    CHECK(settings.showsShortcutFeedback);
    CHECK(settings.showsSystemShortcutFeedback);
    CHECK(shouldPlayTextRecognitionSuccessSound(settings));
    CHECK(shouldShowTextRecognitionSuccessNotification(settings));
    auto muted = settings;
    muted.disablesTextRecognitionSound = true;
    muted.disablesTextRecognitionSuccessNotification = true;
    CHECK(!shouldPlayTextRecognitionSuccessSound(muted));
    CHECK(!shouldShowTextRecognitionSuccessNotification(muted));
}

void testStoreRecoversOnlyInvalidFields()
{
    FakeRegistry registry;
    registry.strings[L"FilenameTemplate"] = L"capture_{yyyyMMdd}";
    registry.dwords[L"ChecksForUpdatesAtLaunch"] = 0U;
    registry.dwords[L"UpdateCheckIntervalHours"] = 7U;
    registry.dwords[L"DisablesTextRecognitionSound"] = 1U;
    registry.dwords[L"DisablesTextRecognitionSuccessNotification"] = 0U;
    registry.dwords[L"ShowsShortcutFeedback"] = 0U;
    registry.dwords[L"ShowsSystemShortcutFeedback"] = 1U;

    PreferencesSettingsStore store(registry);
    const auto settings = store.load();
    CHECK(settings.filenameTemplate == L"capture_{yyyyMMdd}");
    CHECK(!settings.checksForUpdatesAtLaunch);
    CHECK(settings.updateCheckIntervalHours == 24);
    CHECK(settings.disablesTextRecognitionSound);
    CHECK(!settings.disablesTextRecognitionSuccessNotification);
    CHECK(!settings.showsShortcutFeedback);
    CHECK(settings.showsSystemShortcutFeedback);
}

void testStorePersistsAndReportsFailure()
{
    FakeRegistry registry;
    PreferencesSettingsStore store(registry);
    auto settings = PreferencesSettings::defaults();
    settings.filenameTemplate = L"shot_{HHmmss}";
    settings.updateCheckIntervalHours = 6;
    settings.disablesTextRecognitionSound = true;
    CHECK(store.save(settings));

    const auto loaded = store.load();
    CHECK(loaded == settings);

    registry.failWrites = true;
    settings.updateCheckIntervalHours = 12;
    CHECK(!store.save(settings));
}

void testFilenameTemplateRendering()
{
    SYSTEMTIME time{};
    time.wYear = 2026;
    time.wMonth = 8;
    time.wDay = 13;
    time.wHour = 7;
    time.wMinute = 5;
    time.wSecond = 9;

    const auto rendered = renderCaptureFilename(
        L" xxsnap_截图_{yyyyMMdd}_{HHmmss} ", time);
    CHECK(rendered.filename == L"xxsnap_截图_20260813_070509.png");
    CHECK(!rendered.error.has_value());

    const auto existingExtension = renderCaptureFilename(
        L"capture_{yyyyMMdd}.PNG", time);
    CHECK(existingExtension.filename == L"capture_20260813.PNG");
}

void testFilenameTemplateValidation()
{
    SYSTEMTIME time{};
    time.wYear = 2026;
    time.wMonth = 8;
    time.wDay = 13;

    CHECK(renderCaptureFilename(L"   ", time).error
        == FilenameTemplateError::empty);
    CHECK(renderCaptureFilename(L"folder\\capture", time).error
        == FilenameTemplateError::pathCharacter);
    CHECK(renderCaptureFilename(L"capture:name", time).error
        == FilenameTemplateError::pathCharacter);
    const auto unknown = renderCaptureFilename(L"capture_{date}", time);
    CHECK(unknown.error == FilenameTemplateError::unknownVariable);
    CHECK(unknown.invalidVariable == L"{date}");
    CHECK(renderCaptureFilename(L"capture_{yyyyMMdd", time).error
        == FilenameTemplateError::unknownVariable);
}

void testSuggestedFilenameFallsBackFromInvalidStoredTemplate()
{
    FakeRegistry registry;
    registry.strings[L"FilenameTemplate"] = L"bad/path";
    PreferencesSettingsStore store(registry);
    CaptureFilenameProvider provider(store);

    SYSTEMTIME time{};
    time.wYear = 2026;
    time.wMonth = 8;
    time.wDay = 13;
    time.wHour = 7;
    time.wMinute = 5;
    time.wSecond = 9;
    CHECK(provider.suggestedFilename(time)
        == L"xxsnap_截图_20260813_070509.png");
}

void testHotKeySettingsRecoverPersistAndReset()
{
    FakeRegistry registry;
    registry.dwords[L"HotKey.Ocr.Modifiers"] = MOD_CONTROL | MOD_ALT;
    registry.dwords[L"HotKey.Ocr.VirtualKey"] = 'O';
    registry.dwords[L"HotKey.TeachingPen.Modifiers"] = 0U;
    registry.dwords[L"HotKey.TeachingPen.VirtualKey"] = 'P';
    HotKeySettingsStore store(registry);
    const auto loaded = store.load();
    CHECK(loaded[2] == (HotKeyBinding{
        HotKeyCommand::ocr, MOD_CONTROL | MOD_ALT, 'O'}));
    CHECK(loaded[3] == defaultAppHotKeys()[3]);

    const HotKeyBinding replacement{
        HotKeyCommand::regionCapture, MOD_CONTROL | MOD_SHIFT, 'S'};
    CHECK(store.save(replacement));
    CHECK(registry.dwords[L"HotKey.Region.Binding"]
        == ((MOD_CONTROL | MOD_SHIFT) << 16U | 'S'));
    CHECK(store.load()[0] == replacement);
    const auto disabled = disabledHotKey(HotKeyCommand::ocr);
    CHECK(store.save(disabled));
    CHECK(registry.dwords[L"HotKey.Ocr.Binding"] == 0U);
    CHECK(store.load()[2] == disabled);
    CHECK(!store.save(HotKeyBinding{
        HotKeyCommand::ocr, MOD_CONTROL, 'O', false}));
    registry.failWrites = true;
    CHECK(!store.save(HotKeyBinding{
        HotKeyCommand::regionCapture, MOD_CONTROL | MOD_ALT, 'R'}));
    registry.failWrites = false;
    CHECK(store.load()[0] == replacement);
    CHECK(store.reset());
    CHECK(store.load() == defaultAppHotKeys());
}

} // namespace

int main()
{
    testDefaultsMatchMacContract();
    testStoreRecoversOnlyInvalidFields();
    testStorePersistsAndReportsFailure();
    testFilenameTemplateRendering();
    testFilenameTemplateValidation();
    testSuggestedFilenameFallsBackFromInvalidStoredTemplate();
    testHotKeySettingsRecoverPersistAndReset();
    return failureCount == 0 ? 0 : 1;
}
