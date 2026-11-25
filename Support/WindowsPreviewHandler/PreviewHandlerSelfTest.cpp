#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shobjidl.h>
#include <propsys.h>
#include <iterator>
#include <stdio.h>
#include <string>
#include <cwchar>
#include <vector>

namespace {
const CLSID kPreviewHandlerClsid =
    {0x734a81c0, 0x607d, 0x4d0a, {0x9e, 0x9b, 0x67, 0xc7, 0xb0, 0x6e, 0x4b, 0x21}};
constexpr wchar_t kPreviewWindowClass[] = L"FourDPreviewHandlerWindow";
constexpr UINT_PTR kPollTimer = 1;
constexpr UINT_PTR kTimeoutTimer = 2;
constexpr UINT kPollMs = 100;
constexpr UINT kTimeoutMs = 30000;

HWND g_window = nullptr;
IPreviewHandler* g_handler = nullptr;
bool g_ready = false;
int g_result = 1;
wchar_t g_lastPreviewTitle[128]{};

BOOL CALLBACK CheckPreviewWindow(HWND window, LPARAM) {
    wchar_t className[128]{};
    wchar_t title[128]{};
    GetClassNameW(window, className, static_cast<int>(sizeof(className) / sizeof(className[0])));
    GetWindowTextW(window, title, static_cast<int>(sizeof(title) / sizeof(title[0])));
    if (wcscmp(className, kPreviewWindowClass) == 0) {
        wcscpy_s(g_lastPreviewTitle, title);
    }
    if (wcscmp(className, kPreviewWindowClass) == 0 && wcscmp(title, L"WebView2 ready") == 0) {
        g_ready = true;
        g_result = 0;
        PostQuitMessage(0);
        return FALSE;
    }
    return TRUE;
}

bool GetIntegrityRid(DWORD processId, DWORD* integrityRid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (!process) return false;
    HANDLE token = nullptr;
    const BOOL opened = OpenProcessToken(process, TOKEN_QUERY, &token);
    CloseHandle(process);
    if (!opened) return false;

    DWORD required = 0;
    GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &required);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || required == 0) {
        CloseHandle(token);
        return false;
    }
    std::vector<BYTE> storage(required);
    const BOOL read = GetTokenInformation(token, TokenIntegrityLevel, storage.data(),
                                          required, &required);
    CloseHandle(token);
    if (!read) return false;
    const auto* label = reinterpret_cast<const TOKEN_MANDATORY_LABEL*>(storage.data());
    const UCHAR count = *GetSidSubAuthorityCount(label->Label.Sid);
    if (count == 0) return false;
    *integrityRid = *GetSidSubAuthority(label->Label.Sid, count - 1);
    return true;
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_TIMER && wParam == kPollTimer) {
        EnumChildWindows(window, CheckPreviewWindow, 0);
        return 0;
    }
    if (message == WM_TIMER && wParam == kTimeoutTimer) {
        PostQuitMessage(1);
        return 0;
    }
    if (message == WM_DESTROY) {
        PostQuitMessage(g_result);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}
}

int wmain(int argc, wchar_t** argv) {
    const bool outOfProcess = argc == 4 && wcscmp(argv[1], L"--out-of-proc") == 0;
    const int firstPath = outOfProcess ? 2 : 1;
    if (argc != firstPath + 2) {
        fwprintf(stderr, L"Usage: PreviewHandlerSelfTest.exe [--out-of-proc] <handler.dll> <fixture>\n");
        return 2;
    }

    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(comResult)) {
        fwprintf(stderr, L"CoInitializeEx failed: 0x%08lx\n", comResult);
        return 1;
    }

    HMODULE module = nullptr;
    HRESULT result = E_FAIL;
    if (outOfProcess) {
        result = CoCreateInstance(kPreviewHandlerClsid, nullptr, CLSCTX_LOCAL_SERVER,
                                  IID_PPV_ARGS(&g_handler));
    } else {
        module = LoadLibraryW(argv[firstPath]);
        if (!module) {
            fwprintf(stderr, L"Cannot load preview handler: %lu\n", GetLastError());
            CoUninitialize();
            return 1;
        }
        using GetClassObjectFunction = HRESULT(__stdcall*)(REFCLSID, REFIID, void**);
        auto getClassObject = reinterpret_cast<GetClassObjectFunction>(
            GetProcAddress(module, "DllGetClassObject"));
        if (!getClassObject) {
            fwprintf(stderr, L"Preview handler does not export DllGetClassObject.\n");
            FreeLibrary(module);
            CoUninitialize();
            return 1;
        }

        IClassFactory* factory = nullptr;
        result = getClassObject(kPreviewHandlerClsid, IID_IClassFactory,
                                reinterpret_cast<void**>(&factory));
        if (SUCCEEDED(result)) {
            result = factory->CreateInstance(nullptr, IID_PPV_ARGS(&g_handler));
            factory->Release();
        }
    }
    if (FAILED(result)) {
        fwprintf(stderr, L"%ls activation failed: 0x%08lx\n",
                 outOfProcess ? L"Out-of-process COM" : L"In-process COM", result);
        if (module) FreeLibrary(module);
        CoUninitialize();
        return 1;
    }

    IInitializeWithFile* initialize = nullptr;
    result = g_handler->QueryInterface(IID_PPV_ARGS(&initialize));
    if (SUCCEEDED(result)) {
        const HRESULT writeResult = initialize->Initialize(argv[firstPath + 1], STGM_WRITE);
        if (writeResult != STG_E_ACCESSDENIED) {
            result = FAILED(writeResult) ? writeResult : E_UNEXPECTED;
        } else {
            result = initialize->Initialize(argv[firstPath + 1], STGM_READ);
        }
    }
    if (initialize) initialize->Release();
    if (FAILED(result)) {
        fwprintf(stderr, L"IInitializeWithFile::Initialize failed: 0x%08lx\n", result);
        g_handler->Release();
        if (module) FreeLibrary(module);
        CoUninitialize();
        return 1;
    }

    WNDCLASSW windowClass{};
    windowClass.lpfnWndProc = WindowProc;
    windowClass.hInstance = GetModuleHandleW(nullptr);
    windowClass.lpszClassName = L"FourDPreviewHandlerSelfTest";
    RegisterClassW(&windowClass);
    g_window = CreateWindowExW(0, windowClass.lpszClassName, L"Preview handler self-test",
                               WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
                               800, 600, nullptr, nullptr, windowClass.hInstance, nullptr);
    if (!g_window) {
        fwprintf(stderr, L"CreateWindowExW failed: %lu\n", GetLastError());
        g_handler->Release();
        if (module) FreeLibrary(module);
        CoUninitialize();
        return 1;
    }

    RECT bounds{0, 0, 800, 560};
    result = g_handler->SetWindow(g_window, &bounds);
    if (SUCCEEDED(result)) result = g_handler->DoPreview();
    if (FAILED(result)) {
        fwprintf(stderr, L"Preview handler failed to start: 0x%08lx\n", result);
        g_handler->Unload();
        g_handler->Release();
        DestroyWindow(g_window);
        if (module) FreeLibrary(module);
        CoUninitialize();
        return 1;
    }

    IOleWindow* oleWindow = nullptr;
    result = g_handler->QueryInterface(IID_PPV_ARGS(&oleWindow));
    HWND previewWindow = nullptr;
    if (SUCCEEDED(result)) result = oleWindow->GetWindow(&previewWindow);
    if (oleWindow) oleWindow->Release();
    if (FAILED(result) || !previewWindow) {
        fwprintf(stderr, L"IOleWindow::GetWindow failed: 0x%08lx\n", result);
        g_handler->Unload();
        g_handler->Release();
        DestroyWindow(g_window);
        if (module) FreeLibrary(module);
        CoUninitialize();
        return 1;
    }
    if (outOfProcess) {
        DWORD processId = 0;
        GetWindowThreadProcessId(previewWindow, &processId);
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
        wchar_t processPath[32768]{};
        DWORD processPathLength = static_cast<DWORD>(std::size(processPath));
        const bool gotPath = process && QueryFullProcessImageNameW(
            process, 0, processPath, &processPathLength);
        if (process) CloseHandle(process);
        const wchar_t* processName = gotPath ? wcsrchr(processPath, L'\\') : nullptr;
        DWORD integrityRid = 0;
        const bool gotIntegrity = GetIntegrityRid(processId, &integrityRid);
        if (!processName || _wcsicmp(processName + 1, L"prevhost.exe") != 0) {
            fwprintf(stderr, L"Expected prevhost.exe, got %ls\n",
                     gotPath ? processPath : L"an unknown process");
            g_handler->Unload();
            g_handler->Release();
            DestroyWindow(g_window);
            if (module) FreeLibrary(module);
            CoUninitialize();
            return 1;
        }
        if (!gotIntegrity) {
            fwprintf(stderr, L"Cannot query preview-host process integrity level.\n");
            g_handler->Unload();
            g_handler->Release();
            DestroyWindow(g_window);
            if (module) FreeLibrary(module);
            CoUninitialize();
            return 1;
        }
        const wchar_t* integrityName = integrityRid < SECURITY_MANDATORY_MEDIUM_RID ? L"low" :
            integrityRid < SECURITY_MANDATORY_HIGH_RID ? L"medium" : L"high";
        wprintf(L"Preview handler activated in %ls (PID %lu, %ls integrity).\n",
                processName + 1, processId, integrityName);
    }

    SetTimer(g_window, kPollTimer, kPollMs, nullptr);
    SetTimer(g_window, kTimeoutTimer, kTimeoutMs, nullptr);
    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    KillTimer(g_window, kPollTimer);
    KillTimer(g_window, kTimeoutTimer);

    g_handler->Unload();
    g_handler->Release();
    DestroyWindow(g_window);
    if (module) FreeLibrary(module);
    CoUninitialize();
    if (g_ready) {
        wprintf(L"IPreviewHandler initialized WebView2 and completed navigation.\n");
        return 0;
    }
    fwprintf(stderr, L"Preview handler did not complete navigation within %u ms (state: %ls).\n",
             kTimeoutMs, g_lastPreviewTitle);
    return 1;
}
