#include "pch.h"
#include "SettingsWindow.h"
#include "OverlayWindow.h"
#include "CropAndLockWindow.h"
#include "ScreenshotCropAndLockWindow.h"
#include "ThumbnailCropAndLockWindow.h"
#include "ReparentCropAndLockWindow.h"
#include "ModuleConstants.h"
#include "trace.h"

#include <common/interop/shared_constants.h>
#include <common/SettingsAPI/settings_helpers.h>
#include <common/SettingsAPI/settings_objects.h>

#include <common/utils/gpo.h>
#include <common/utils/logger_helper.h>
#include <common/utils/ProcessWaiter.h>
#include <common/utils/UnhandledExceptionHandler.h>
#include <common/utils/winapi_error.h>
#include <common/utils/portable_mode.h>

#include <array>
#include <atomic>
#include <filesystem>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <thread>

#include <common/Telemetry/EtwTrace/EtwTrace.h>

#include <common/Themes/theme_helpers.h>
#include <common/Themes/theme_listener.h>

#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

namespace winrt
{
    using namespace Windows::Foundation;
    using namespace Windows::Foundation::Numerics;
    using namespace Windows::UI;
    using namespace Windows::UI::Composition;
}

namespace util
{
    using namespace robmikh::common::desktop;
}

const std::wstring instanceMutexName = L"Local\\PowerToys_CropAndLock_InstanceMutex";
std::atomic_bool m_running{ true };

// Theming
ThemeListener theme_listener{};
// Keep a list of our cropped windows
std::vector<std::shared_ptr<CropAndLockWindow>> croppedWindows;

void handleTheme()
{
    auto theme = theme_listener.AppTheme;
    auto isDark = theme == Theme::Dark;
    Logger::info(L"Theme is now {}", isDark ? L"Dark" : L"Light");
    for (auto&& croppedWindow : croppedWindows)
    {
        ThemeHelpers::SetImmersiveDarkMode(croppedWindow->Handle(), isDark);
    }
}


int WINAPI wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ PWSTR lpCmdLine, _In_ int)
{
    bool portable = false;
    std::array<std::wstring, 4> eventNames;
    try
    {
        portable = PowerToysPortable::IsEnabled();
        eventNames = {
            PowerToysPortable::ScopedName(CommonSharedConstants::CROP_AND_LOCK_REPARENT_EVENT),
            PowerToysPortable::ScopedName(CommonSharedConstants::CROP_AND_LOCK_THUMBNAIL_EVENT),
            PowerToysPortable::ScopedName(CommonSharedConstants::CROP_AND_LOCK_SCREENSHOT_EVENT),
            PowerToysPortable::ScopedName(CommonSharedConstants::CROP_AND_LOCK_EXIT_EVENT)
        };
        if (portable)
        {
            const auto executableDirectory = PowerToysPortable::ExecutableDirectory();
            if (!SetCurrentDirectoryW(executableDirectory.c_str()))
            {
                throw std::runtime_error("Cannot select the portable executable directory.");
            }
            const std::wstring_view command(lpCmdLine);
            int eventIndex = -1;
            if (command == L"--reparent")
            {
                eventIndex = 0;
            }
            else if (command == L"--thumbnail")
            {
                eventIndex = 1;
            }
            else if (command == L"--screenshot")
            {
                eventIndex = 2;
            }
            else if (command == L"--stop")
            {
                eventIndex = 3;
            }
            if (eventIndex >= 0)
            {
                wil::unique_handle event(OpenEventW(EVENT_MODIFY_STATE, FALSE, eventNames[eventIndex].c_str()));
                if (!event)
                {
                    return eventIndex == 3 && GetLastError() == ERROR_FILE_NOT_FOUND ? 0 : 1;
                }
                return SetEvent(event.get()) ? 0 : 1;
            }
        }
    }
    catch (const std::exception&)
    {
        MessageBoxW(nullptr, L"Der portable Programmordner oder Datenordner ist nicht zugänglich oder nicht beschreibbar.", L"Crop And Lock Portable", MB_OK | MB_ICONERROR);
        return 1;
    }

    // Initialize COM
    winrt::init_apartment(winrt::apartment_type::single_threaded);

    Trace::CropAndLock::RegisterProvider();

    theme_listener.AddChangedHandler(handleTheme);

    Shared::Trace::ETWTrace trace;
    trace.UpdateState(true);

    // Initialize logger automatic logging of exceptions.
    LoggerHelpers::init_logger(NonLocalizable::ModuleKey, L"", LogSettings::cropAndLockLoggerName);
    InitUnhandledExceptionHandler();

    if (powertoys_gpo::getConfiguredCropAndLockEnabledValue() == powertoys_gpo::gpo_rule_configured_disabled)
    {
        Logger::warn(L"Tried to start with a GPO policy setting the utility to always be disabled. Please contact your systems administrator.");
        return 0;
    }

    // Before we do anything, check to see if we're already running. If we are,
    // the hotkey won't register and we'll fail. Instead, we should tell the user
    // to kill the other instance and exit this one.
    wil::unique_handle mutex(CreateMutex(nullptr, true, PowerToysPortable::ScopedName(instanceMutexName).c_str()));
    const DWORD mutexError = GetLastError();
    if (!mutex)
    {
        Logger::error(L"Failed to create mutex. {}", get_last_error_or_default(mutexError));
        return 1;
    }

    if (mutexError == ERROR_ALREADY_EXISTS)
    {
        // CropAndLock is already open.
        return portable ? 0 : 1;
    }

    std::wstring pid = portable ? L"" : std::wstring(lpCmdLine);
    if (!portable && pid.empty())
    {
        Logger::warn(L"Tried to run Crop And Lock as a standalone.");
        MessageBoxW(nullptr, L"CropAndLock can't run as a standalone. Start it from PowerToys.", L"CropAndLock", MB_ICONERROR);
        return 1;
    }

    auto mainThreadId = GetCurrentThreadId();
    if (!portable)
    {
        ProcessWaiter::OnProcessTerminate(pid, [mainThreadId](int err) {
            if (err != ERROR_SUCCESS)
            {
                Logger::error(L"Failed to wait for parent process exit. {}", get_last_error_or_default(err));
            }
            else
            {
                Logger::trace(L"PowerToys runner exited.");
            }

            Logger::trace(L"Exiting CropAndLock");
            PostThreadMessage(mainThreadId, WM_QUIT, 0, 0);
        });
    }

    // NOTE: reparenting a window with a different DPI context has consequences.
    //       See https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent#remarks
    //       for more info.
    winrt::check_bool(SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2));

    // Create the DispatcherQueue that the compositor needs to run
    auto controller = util::CreateDispatcherQueueControllerForCurrentThread();

    // Setup Composition
    auto compositor = winrt::Compositor();

    // Create our overlay window
    std::unique_ptr<OverlayWindow> overlayWindow;


    // Handles and thread for the events sent from runner
    wil::unique_handle reparentEvent;
    wil::unique_handle thumbnailEvent;
    wil::unique_handle screenshotEvent;
    wil::unique_handle exitEvent;
    std::thread m_event_triggers_thread;

    std::function<void(HWND)> removeWindowCallback = [&](HWND windowHandle) {
        if (!m_running)
        {
            // If we're not running, the reference to croppedWindows might no longer be valid and cause a crash at exit time, due to being called by destructors after wWinMain returns.
            return;
        }

        auto pos = std::find_if(croppedWindows.begin(), croppedWindows.end(), [windowHandle](auto window) { return window->Handle() == windowHandle; });
        if (pos != croppedWindows.end())
        {
            croppedWindows.erase(pos);
        }
    };

    std::function<void(CropAndLockType)> ProcessCommand = [&](CropAndLockType mode) {
        if (!m_running)
        {
            return;
        }
        std::function<void(HWND, RECT)> windowCroppedCallback = [&, mode](HWND targetWindow, RECT cropRect) {
            auto targetInfo = util::WindowInfo(targetWindow);
            // TODO: Fix WindowInfo.h to not contain the null char at the end.
            auto nullCharIndex = std::wstring::npos;
            do
            {
                nullCharIndex = targetInfo.Title.rfind(L'\0');
                if (nullCharIndex != std::wstring::npos)
                {
                    targetInfo.Title.erase(nullCharIndex);
                }
            } while (nullCharIndex != std::wstring::npos);

            std::wstringstream titleStream;
            titleStream << targetInfo.Title << (portable ? L" (Zugeschnitten)" : L" (Cropped)");
            auto title = titleStream.str();

            std::shared_ptr<CropAndLockWindow> croppedWindow;
            switch (mode)
            {
            case CropAndLockType::Reparent:
                croppedWindow = std::make_shared<ReparentCropAndLockWindow>(title, 800, 600);
                Logger::trace(L"Creating a reparent window");
                Trace::CropAndLock::CreateReparentWindow();
                break;
            case CropAndLockType::Thumbnail:
                croppedWindow = std::make_shared<ThumbnailCropAndLockWindow>(title, 800, 600);
                Logger::trace(L"Creating a thumbnail window");
                Trace::CropAndLock::CreateThumbnailWindow();
                break;
            case CropAndLockType::Screenshot:
                croppedWindow = std::make_shared<ScreenshotCropAndLockWindow>(title, 800, 600);
                Logger::trace(L"Creating a screenshot window");
                Trace::CropAndLock::CreateScreenshotWindow();
                break;
            default:
                return;
            }
            croppedWindow->CropAndLock(targetWindow, cropRect);
            croppedWindow->OnClosed(removeWindowCallback);
            croppedWindows.push_back(croppedWindow);
            handleTheme();
        };

        overlayWindow.reset();

        // Get the current window with focus
        auto foregroundWindow = GetForegroundWindow();
        if (foregroundWindow != nullptr)
        {
            bool match = false;
            for (auto&& croppedWindow : croppedWindows)
            {
                if (foregroundWindow == croppedWindow->Handle())
                {
                    match = true;
                    break;
                }
            }
            if (!match)
            {
                overlayWindow = std::make_unique<OverlayWindow>(compositor, foregroundWindow, windowCroppedCallback);
            }
        }
    };

    const std::array<const wchar_t*, 3> hotkeyNames{ L"reparent-hotkey", L"thumbnail-hotkey", L"screenshot-hotkey" };
    std::array<bool, 3> registeredHotkeys{};
    std::filesystem::path portableSettingsPath;
    std::filesystem::file_time_type portableSettingsTimestamp{};
    std::error_code portableSettingsError;
    bool portableSettingsLoaded = false;
    UINT_PTR settingsTimer = 0;
    auto reloadPortableHotkeys = [&]() {
        std::error_code error;
        const auto timestamp = std::filesystem::last_write_time(portableSettingsPath, error);
        if (portableSettingsLoaded && error == portableSettingsError && (error || timestamp == portableSettingsTimestamp))
        {
            return;
        }
        const bool hadSettings = portableSettingsLoaded;
        portableSettingsLoaded = true;
        portableSettingsTimestamp = timestamp;
        portableSettingsError = error;
        std::array<PowerToysSettings::HotkeyObject, 3> hotkeys{
            PowerToysSettings::HotkeyObject::from_settings(true, true, false, true, 'R'),
            PowerToysSettings::HotkeyObject::from_settings(true, true, false, true, 'T'),
            PowerToysSettings::HotkeyObject::from_settings(true, true, false, true, 'S')
        };
        try
        {
            if (!error)
            {
                const auto values = PowerToysSettings::PowerToyValues::load_from_settings_file(NonLocalizable::ModuleKey);
                for (size_t index = 0; index < hotkeys.size(); ++index)
                {
                    if (const auto value = values.get_json(hotkeyNames[index]))
                    {
                        const double code = value->GetNamedNumber(L"code");
                        if (!(code >= 0 && code <= 255) || code != static_cast<UINT>(code))
                        {
                            throw std::runtime_error("Invalid portable hotkey code.");
                        }
                        hotkeys[index] = PowerToysSettings::HotkeyObject::from_settings(
                            value->GetNamedBoolean(L"win"), value->GetNamedBoolean(L"ctrl"),
                            value->GetNamedBoolean(L"alt"), value->GetNamedBoolean(L"shift"), static_cast<UINT>(code));
                    }
                }
            }
        }
        catch (...)
        {
            Logger::error(L"Failed to read portable Crop And Lock shortcuts; keeping existing shortcuts.");
            if (hadSettings)
            {
                return;
            }
        }
        for (size_t index = 0; index < hotkeys.size(); ++index)
        {
            const int hotkeyId = static_cast<int>(index) + 1;
            if (registeredHotkeys[index])
            {
                UnregisterHotKey(nullptr, hotkeyId);
                registeredHotkeys[index] = false;
            }
        }
        for (size_t index = 0; index < hotkeys.size(); ++index)
        {
            if (hotkeys[index].get_code() == 0)
            {
                continue;
            }
            const int hotkeyId = static_cast<int>(index) + 1;
            registeredHotkeys[index] = RegisterHotKey(nullptr, hotkeyId, hotkeys[index].get_modifiers(), hotkeys[index].get_code()) != FALSE;
            if (!registeredHotkeys[index])
            {
                Logger::error(L"Failed to register portable shortcut {}. {}", hotkeyNames[index], get_last_error_or_default(GetLastError()));
            }
        }
    };
    auto unregisterPortableHotkeys = [&]() {
        if (settingsTimer)
        {
            KillTimer(nullptr, settingsTimer);
        }
        for (size_t index = 0; index < registeredHotkeys.size(); ++index)
        {
            if (registeredHotkeys[index])
            {
                UnregisterHotKey(nullptr, static_cast<int>(index) + 1);
            }
        }
    };
    if (portable)
    {
        portableSettingsPath = PTSettingsHelper::get_module_save_file_location(NonLocalizable::ModuleKey);
        reloadPortableHotkeys();
        settingsTimer = SetTimer(nullptr, 0, 1000, nullptr);
        if (!settingsTimer)
        {
            Logger::error(L"Failed to start portable settings reload timer. {}", get_last_error_or_default(GetLastError()));
            unregisterPortableHotkeys();
            return 1;
        }
    }

    // Start a thread to listen on the events.
    reparentEvent.reset(CreateEventW(nullptr, false, false, eventNames[0].c_str()));
    thumbnailEvent.reset(CreateEventW(nullptr, false, false, eventNames[1].c_str()));
    screenshotEvent.reset(CreateEventW(nullptr, false, false, eventNames[2].c_str()));
    exitEvent.reset(CreateEventW(nullptr, false, false, eventNames[3].c_str()));
    const HANDLE m_reparent_event_handle = reparentEvent.get();
    const HANDLE m_thumbnail_event_handle = thumbnailEvent.get();
    const HANDLE m_screenshot_event_handle = screenshotEvent.get();
    const HANDLE m_exit_event_handle = exitEvent.get();
    if (!m_reparent_event_handle || !m_thumbnail_event_handle || !m_screenshot_event_handle || !m_exit_event_handle)
    {
        Logger::warn(L"Failed to create events. {}", get_last_error_or_default(GetLastError()));
        unregisterPortableHotkeys();
        return 1;
    }

    MSG initialMessage;
    PeekMessageW(&initialMessage, nullptr, 0, 0, PM_NOREMOVE);
    m_event_triggers_thread = std::thread([&]() {
        MSG msg;
        HANDLE event_handles[4] = { m_reparent_event_handle, m_thumbnail_event_handle, m_screenshot_event_handle, m_exit_event_handle };
        while (m_running)
        {
            DWORD dwEvt = MsgWaitForMultipleObjects(4, event_handles, false, INFINITE, QS_ALLINPUT);
            if (!m_running)
            {
                break;
            }
            switch (dwEvt)
            {
            case WAIT_OBJECT_0:
            {
                // Reparent Event
                bool enqueueSucceeded = controller.DispatcherQueue().TryEnqueue([&]() {
                    ProcessCommand(CropAndLockType::Reparent);
                });
                if (!enqueueSucceeded)
                {
                    Logger::error("Couldn't enqueue message to reparent a window.");
                }
                break;
            }
            case WAIT_OBJECT_0 + 1:
            {
                // Thumbnail Event
                bool enqueueSucceeded = controller.DispatcherQueue().TryEnqueue([&]() {
                    ProcessCommand(CropAndLockType::Thumbnail);
                });
                if (!enqueueSucceeded)
                {
                    Logger::error("Couldn't enqueue message to thumbnail a window.");
                }
                break;
            }
            case WAIT_OBJECT_0 + 2:
            {
                // Screenshot Event
                bool enqueueSucceeded = controller.DispatcherQueue().TryEnqueue([&]() {
                    ProcessCommand(CropAndLockType::Screenshot);
                });
                if (!enqueueSucceeded)
                {
                    Logger::error("Couldn't enqueue message to screenshot a window.");
                }
                break;
            }
            case WAIT_OBJECT_0 + 3:
            {
                // Exit Event
                Logger::trace(L"Received an exit event.");
                PostThreadMessage(mainThreadId, WM_QUIT, 0, 0);
                break;
            }
            case WAIT_OBJECT_0 + 4:
                if (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
                break;
            default:
                break;
            }
        }
    });

    // Message pump
    MSG msg = {};
    BOOL messageResult;
    while ((messageResult = GetMessageW(&msg, nullptr, 0, 0)) > 0)
    {
        if (portable && msg.hwnd == nullptr && msg.message == WM_HOTKEY)
        {
            switch (msg.wParam)
            {
            case 1:
                ProcessCommand(CropAndLockType::Reparent);
                break;
            case 2:
                ProcessCommand(CropAndLockType::Thumbnail);
                break;
            case 3:
                ProcessCommand(CropAndLockType::Screenshot);
                break;
            }
            continue;
        }
        if (portable && msg.hwnd == nullptr && msg.message == WM_TIMER && msg.wParam == settingsTimer)
        {
            reloadPortableHotkeys();
            continue;
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    m_running = false;
    unregisterPortableHotkeys();
    // Needed to unblock MsgWaitForMultipleObjects one last time
    SetEvent(m_reparent_event_handle);
    m_event_triggers_thread.join();
    reparentEvent.reset();
    thumbnailEvent.reset();
    screenshotEvent.reset();
    exitEvent.reset();

    overlayWindow.reset();
    croppedWindows.clear();

    trace.Flush();
    Trace::CropAndLock::UnregisterProvider();

    return util::ShutdownDispatcherQueueControllerAndWait(controller, messageResult == -1 ? 1 : static_cast<int>(msg.wParam));
}
