#include "pch.h"

#include <common/utils/logger_helper.h>
#include <common/utils/ProcessWaiter.h>
#include <common/utils/window.h>
#include <common/utils/UnhandledExceptionHandler.h>
#include <common/utils/gpo.h>
#include <common/utils/portable_mode.h>
#include <common/utils/EventWaiter.h>

#include <common/Telemetry/EtwTrace/EtwTrace.h>

#include <AlwaysOnTop.h>
#include <trace.h>

// Non-localizable
const std::wstring moduleName = L"AlwaysOnTop";
const std::wstring internalPath = L"";
const std::wstring instanceMutexName = L"Local\\PowerToys_AlwaysOnTop_InstanceMutex";

int WINAPI wWinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ PWSTR lpCmdLine, _In_ int nCmdShow)
{
    bool portable = false;
    std::wstring portableStopEventName;
    try
    {
        portable = PowerToysPortable::IsEnabled();
        if (portable)
        {
            const auto executableDirectory = std::filesystem::path(PowerToysPortable::DataRoot()).parent_path().parent_path().parent_path();
            if (!SetCurrentDirectoryW(executableDirectory.c_str()))
            {
                throw std::runtime_error("Cannot select the portable executable directory.");
            }
            portableStopEventName = PowerToysPortable::ScopedName(L"Local\\PowerToys_AlwaysOnTop_Portable_Stop");
            if (std::wstring_view(lpCmdLine) == L"--stop")
            {
                wil::unique_handle stopEvent(OpenEventW(EVENT_MODIFY_STATE, FALSE, portableStopEventName.c_str()));
                if (!stopEvent)
                {
                    return GetLastError() == ERROR_FILE_NOT_FOUND ? 0 : 1;
                }
                return SetEvent(stopEvent.get()) ? 0 : 1;
            }
        }
    }
    catch (const std::exception&)
    {
        MessageBoxW(nullptr, L"Der portable Programmordner oder Datenordner ist nicht zugänglich oder nicht beschreibbar.", L"Always On Top Portable", MB_OK | MB_ICONERROR);
        return 1;
    }

    Shared::Trace::ETWTrace trace;
    trace.UpdateState(true);

    winrt::init_apartment();
    LoggerHelpers::init_logger(moduleName, internalPath, LogSettings::alwaysOnTopLoggerName);

    if (powertoys_gpo::getConfiguredAlwaysOnTopEnabledValue() == powertoys_gpo::gpo_rule_configured_disabled)
    {
        Logger::warn(L"Tried to start with a GPO policy setting the utility to always be disabled. Please contact your systems administrator.");
        return 0;
    }

    InitUnhandledExceptionHandler();

    wil::unique_handle mutex(CreateMutex(nullptr, true, PowerToysPortable::ScopedName(instanceMutexName).c_str()));
    const DWORD mutexError = GetLastError();
    if (!mutex)
    {
        Logger::error(L"Failed to create mutex. {}", get_last_error_or_default(mutexError));
        return 1;
    }

    if (mutexError == ERROR_ALREADY_EXISTS)
    {
        return 0;
    }

    auto mainThreadId = GetCurrentThreadId();

    std::wstring pid = portable ? L"" : std::wstring(lpCmdLine);
    if (!pid.empty())
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

            Logger::trace(L"Exiting AlwaysOnTop");
            PostThreadMessage(mainThreadId, WM_QUIT, 0, 0);
        });
    }

    Trace::AlwaysOnTop::RegisterProvider();

    AlwaysOnTop app(!pid.empty(), mainThreadId);

    EventWaiter portableStopWaiter;
    if (portable)
    {
        // Ensure the main thread has a message queue before accepting stop requests.
        MSG message;
        PeekMessageW(&message, nullptr, 0, 0, PM_NOREMOVE);
        if (!portableStopWaiter.start(portableStopEventName, [mainThreadId](DWORD error) {
                if (error == ERROR_SUCCESS)
                {
                    PostThreadMessageW(mainThreadId, WM_QUIT, 0, 0);
                }
            }))
        {
            Logger::error(L"Failed to create the portable stop event.");
            Trace::AlwaysOnTop::UnregisterProvider();
            return 1;
        }
    }

    run_message_loop();

    portableStopWaiter.stop();

    Trace::AlwaysOnTop::UnregisterProvider();

    trace.Flush();

    return 0;
}
