// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE in the project root.
#pragma once

#include <windows.h>
#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>

namespace PowerToysPortable
{
    namespace detail
    {
        inline void RequirePlainDirectory(const std::filesystem::path& path)
        {
            const DWORD attributes = GetFileAttributesW(path.c_str());
            if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) || (attributes & FILE_ATTRIBUTE_REPARSE_POINT))
            {
                throw std::runtime_error("Portable data requires plain executable-adjacent directories.");
            }
        }

        inline std::wstring ResolveDataRoot()
        {
            std::wstring executable(32768, L'\0');
            const DWORD length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
            if (!length || length >= executable.size())
            {
                throw std::runtime_error("Cannot determine the executable directory for portable storage.");
            }
            executable.resize(length);
            const std::filesystem::path directory = std::filesystem::path(executable).parent_path();
            const auto marker = directory / L"portable-mode";
            const DWORD markerAttributes = GetFileAttributesW(marker.c_str());
            if (markerAttributes == INVALID_FILE_ATTRIBUTES)
            {
                const DWORD error = GetLastError();
                if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND)
                {
                    return {};
                }
                throw std::runtime_error("Cannot inspect the portable-mode marker.");
            }
            if (markerAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))
            {
                throw std::runtime_error("The portable-mode marker must be a regular file.");
            }
            RequirePlainDirectory(directory);
            auto root = directory;
            for (const auto* segment : { L"Data", L"Microsoft", L"PowerToys" })
            {
                root /= segment;
                if (GetFileAttributesW(root.c_str()) != INVALID_FILE_ATTRIBUTES)
                {
                    RequirePlainDirectory(root);
                }
                else
                {
                    std::filesystem::create_directory(root);
                    RequirePlainDirectory(root);
                }
            }
            const auto probe = root / (L".portable-write-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()) + L".tmp");
            HANDLE file = CreateFileW(probe.c_str(), GENERIC_READ | GENERIC_WRITE | DELETE, 0, nullptr, CREATE_NEW,
                                      FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
            if (file == INVALID_HANDLE_VALUE)
            {
                throw std::runtime_error("Portable data is not writable; installed-profile fallback is disabled.");
            }
            const BYTE byte = 0;
            DWORD written = 0;
            const bool writable = WriteFile(file, &byte, 1, &written, nullptr) && written == 1 && FlushFileBuffers(file);
            CloseHandle(file);
            if (!writable)
            {
                throw std::runtime_error("Portable data write validation failed.");
            }
            return root.native();
        }
    }

    inline const std::wstring& DataRoot()
    {
        static const std::wstring root = detail::ResolveDataRoot();
        return root;
    }

    inline bool IsEnabled()
    {
        return !DataRoot().empty();
    }

    inline std::wstring ScopedName(std::wstring_view name)
    {
        if (!IsEnabled())
        {
            return std::wstring(name);
        }
        std::wstring normalized = DataRoot();
        if (!LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, DataRoot().data(), static_cast<int>(DataRoot().size()),
                           normalized.data(), static_cast<int>(normalized.size()), nullptr, nullptr, 0))
        {
            throw std::runtime_error("Cannot scope the portable instance name.");
        }
        uint64_t hash = 14695981039346656037ULL;
        for (const wchar_t character : normalized)
        {
            hash ^= static_cast<uint16_t>(character);
            hash *= 1099511628211ULL;
        }
        return std::wstring(name) + L"-portable-" + std::to_wstring(hash);
    }
}
