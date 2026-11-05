#pragma once

#include "pch.h"

#include <mmsystem.h> // sound
#include <common/utils/portable_mode.h>

class Sound
{
public:
    enum class Type
    {
        On,
        Off,
        IncreaseOpacity,
        DecreaseOpacity,
    };
    
    void Play(Type type)
    {
        BOOL success = false;
        if (PowerToysPortable::IsEnabled())
        {
            wchar_t windowsDirectory[MAX_PATH]{};
            if (!GetWindowsDirectoryW(windowsDirectory, ARRAYSIZE(windowsDirectory)))
            {
                return;
            }
            const wchar_t* file = type == Type::On ? L"Speech On.wav" :
                type == Type::Off ? L"Speech Sleep.wav" :
                type == Type::IncreaseOpacity ? L"Windows Hardware Insert.wav" : L"Windows Hardware Remove.wav";
            const auto path = std::filesystem::path(windowsDirectory) / L"Media" / file;
            PlaySoundW(path.c_str(), nullptr, SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
            return;
        }
        switch (type)
        {
        case Type::On:
            success = PlaySound(TEXT("Media\\Speech On.wav"), NULL, SND_FILENAME | SND_ASYNC);
            break;
        case Type::Off:
            success = PlaySound(TEXT("Media\\Speech Sleep.wav"), NULL, SND_FILENAME | SND_ASYNC);
            break;
        case Type::IncreaseOpacity:
            success = PlaySound(TEXT("Media\\Windows Hardware Insert.wav"), NULL, SND_FILENAME | SND_ASYNC);
            break;
        case Type::DecreaseOpacity:
            success = PlaySound(TEXT("Media\\Windows Hardware Remove.wav"), NULL, SND_FILENAME | SND_ASYNC);
            break;
        default:
            break;
        }

        if (!success)
        {
            Logger::error(L"Sound playing error");
        }
    }
};
