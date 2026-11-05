// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE in the project root.
#pragma once

#include <windows.h>
#include <shellapi.h>
#include <shlobj_core.h>
#include <knownfolders.h>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace PowerToysPortable
{
    inline std::filesystem::path ExecutableDirectory()
    {
        std::wstring executable(32768, L'\0');
        const DWORD length = GetModuleFileNameW(nullptr, executable.data(), static_cast<DWORD>(executable.size()));
        if (!length || length >= executable.size())
        {
            throw std::runtime_error("Cannot determine the module executable directory.");
        }
        executable.resize(length);
        return std::filesystem::path(executable).parent_path();
    }

    namespace detail
    {
        inline void RequirePlainDirectory(const std::filesystem::path& path)
        {
            const DWORD attributes = GetFileAttributesW(path.c_str());
            if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) || (attributes & FILE_ATTRIBUTE_REPARSE_POINT))
            {
                throw std::runtime_error("Module data requires plain directories.");
            }
        }

        inline bool HasMarker(const std::filesystem::path& marker)
        {
            const DWORD attributes = GetFileAttributesW(marker.c_str());
            if (attributes == INVALID_FILE_ATTRIBUTES)
            {
                const DWORD error = GetLastError();
                if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND)
                {
                    return false;
                }
                throw std::runtime_error("Cannot inspect the module mode marker.");
            }
            if (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))
            {
                throw std::runtime_error("The module mode marker must be a regular file.");
            }
            return true;
        }

        inline std::filesystem::path StandaloneLocalRoot(const std::filesystem::path& marker)
        {
            if (std::filesystem::file_size(marker) > 64)
            {
                throw std::runtime_error("Standalone package identity is too large.");
            }
            std::ifstream input(marker, std::ios::binary);
            std::string module{ std::istreambuf_iterator<char>{ input }, std::istreambuf_iterator<char>{} };
            const auto first = module.find_first_not_of(" \t\r\n");
            const auto last = module.find_last_not_of(" \t\r\n");
            module = first == std::string::npos ? std::string{} : module.substr(first, last - first + 1);
            if (module != "FancyZones" && module != "ColorPicker" && module != "TextExtractor" && module != "ImageResizer" &&
                module != "PowerDisplay" && module != "AlwaysOnTop" && module != "FileLocksmith" && module != "Peek" &&
                module != "CropAndLock" && module != "AdvancedPaste")
            {
                throw std::runtime_error("Unknown standalone module.");
            }

            PWSTR localAppData = nullptr;
            const HRESULT result = SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &localAppData);
            if (FAILED(result) || !localAppData)
            {
                CoTaskMemFree(localAppData);
                throw std::runtime_error("Cannot resolve the user's local application data directory.");
            }
            const std::filesystem::path base{ localAppData };
            CoTaskMemFree(localAppData);
            RequirePlainDirectory(base);
            auto root = base;
            for (const std::wstring& segment : { std::wstring{ L"Naturian" }, std::wstring{ L"PowerToysModules" }, std::wstring{ module.begin(), module.end() } })
            {
                root /= segment;
                std::filesystem::create_directory(root);
                RequirePlainDirectory(root);
            }
            return root;
        }

        inline void SeedProfile(const std::filesystem::path& directory, const std::filesystem::path& root)
        {
            for (const auto* name : { L"language.json", L"settings.json" })
            {
                const auto destination = root / name;
                if (std::filesystem::exists(destination))
                {
                    continue;
                }
                GUID identifier{};
                wchar_t uniqueName[40]{};
                if (FAILED(CoCreateGuid(&identifier)) || !StringFromGUID2(identifier, uniqueName, ARRAYSIZE(uniqueName)))
                {
                    throw std::runtime_error("Cannot create a unique profile seed name.");
                }
                const auto temporary = root / (L".profile-seed-" + std::wstring{ uniqueName } + L".tmp");
                if (!CopyFileW((directory / L"Defaults" / name).c_str(), temporary.c_str(), TRUE))
                {
                    throw std::runtime_error("Cannot copy the standalone profile template.");
                }
                if (!MoveFileExW(temporary.c_str(), destination.c_str(), MOVEFILE_WRITE_THROUGH))
                {
                    const DWORD error = GetLastError();
                    DeleteFileW(temporary.c_str());
                    if (error != ERROR_ALREADY_EXISTS && error != ERROR_FILE_EXISTS)
                    {
                        throw std::runtime_error("Cannot seed the standalone profile.");
                    }
                }
            }
        }

        inline std::wstring ResolveDataRoot()
        {
            const auto directory = ExecutableDirectory();
            const bool portable = HasMarker(directory / L"portable-mode");
            const bool standalone = HasMarker(directory / L"standalone-mode");
            if (!portable && !standalone)
            {
                return {};
            }
            if (portable && standalone)
            {
                throw std::runtime_error("A package must select exactly one data-storage mode.");
            }
            RequirePlainDirectory(directory);
            auto root = standalone ? StandaloneLocalRoot(directory / L"standalone-mode") : directory / L"Data";
            std::filesystem::create_directory(root);
            RequirePlainDirectory(root);
            for (const auto* segment : { L"Microsoft", L"PowerToys" })
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
            if (standalone)
            {
                SeedProfile(directory, root);
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
