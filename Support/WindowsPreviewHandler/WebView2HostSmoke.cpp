#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wrl.h>
#include <atomic>
#include <cstdio>
#include <string>
#include "WebView2.h"

using Microsoft::WRL::Callback;

namespace {
constexpr UINT kNavigationComplete = WM_APP + 1;
constexpr UINT_PTR kTimeoutTimer = 1;
constexpr UINT kTimeoutMs = 15000;

HWND g_window = nullptr;
ICoreWebView2Controller* g_controller = nullptr;
ICoreWebView2* g_webView = nullptr;
std::atomic<bool> g_navigated = false;
HRESULT g_result = E_PENDING;

void SetBounds() {
    if (!g_controller || !g_window) return;
    RECT bounds{};
    GetClientRect(g_window, &bounds);
    g_controller->put_Bounds(bounds);
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_SIZE) {
        SetBounds();
        return 0;
    }
    if (message == kNavigationComplete) {
        PostQuitMessage(0);
        return 0;
    }
    if (message == WM_TIMER && wParam == kTimeoutTimer) {
        g_result = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
        PostQuitMessage(1);
        return 0;
    }
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}
}

int wmain() {
    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(comResult)) {
        std::fwprintf(stderr, L"CoInitializeEx failed: 0x%08lx\n", comResult);
        return 1;
    }

    WNDCLASSW windowClass{};
    windowClass.lpfnWndProc = WindowProc;
    windowClass.hInstance = GetModuleHandleW(nullptr);
    windowClass.lpszClassName = L"FourDWebView2HostSmoke";
    RegisterClassW(&windowClass);

    g_window = CreateWindowExW(0, windowClass.lpszClassName, L"WebView2 native host smoke",
                               WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
                               800, 600, nullptr, nullptr, windowClass.hInstance, nullptr);
    if (!g_window) {
        std::fwprintf(stderr, L"CreateWindowExW failed: %lu\n", GetLastError());
        CoUninitialize();
        return 1;
    }

    wchar_t localAppData[MAX_PATH]{};
    const DWORD localAppDataLength = GetEnvironmentVariableW(
        L"LOCALAPPDATA", localAppData, static_cast<DWORD>(std::size(localAppData)));
    if (localAppDataLength == 0 || localAppDataLength >= std::size(localAppData)) {
        std::fwprintf(stderr, L"LOCALAPPDATA is unavailable.\n");
        DestroyWindow(g_window);
        CoUninitialize();
        return 1;
    }
    std::wstring userDataFolder(localAppData);
    userDataFolder += L"\\4DQuickLook\\WebView2";

    const HRESULT createResult = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, userDataFolder.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [](HRESULT result, ICoreWebView2Environment* environment) -> HRESULT {
                if (FAILED(result) || !environment) {
                    g_result = FAILED(result) ? result : E_FAIL;
                    PostMessageW(g_window, kNavigationComplete, 0, 0);
                    return S_OK;
                }
                return environment->CreateCoreWebView2Controller(
                    g_window,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [](HRESULT controllerResult, ICoreWebView2Controller* controller) -> HRESULT {
                            if (FAILED(controllerResult) || !controller) {
                                g_result = FAILED(controllerResult) ? controllerResult : E_FAIL;
                                PostMessageW(g_window, kNavigationComplete, 0, 0);
                                return S_OK;
                            }
                            g_controller = controller;
                            g_controller->AddRef();
                            SetBounds();
                            HRESULT result = g_controller->get_CoreWebView2(&g_webView);
                            if (FAILED(result)) {
                                g_result = result;
                                PostMessageW(g_window, kNavigationComplete, 0, 0);
                                return S_OK;
                            }

                            ICoreWebView2Settings* settings = nullptr;
                            result = g_webView->get_Settings(&settings);
                            if (SUCCEEDED(result) && settings) {
                                settings->put_IsScriptEnabled(FALSE);
                                settings->put_AreDefaultContextMenusEnabled(FALSE);
                                settings->Release();
                            }
                            result = g_webView->add_NavigationCompleted(
                                Callback<ICoreWebView2NavigationCompletedEventHandler>(
                                    [](ICoreWebView2*,
                                       ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                                        BOOL succeeded = FALSE;
                                        HRESULT result = args->get_IsSuccess(&succeeded);
                                        g_result = SUCCEEDED(result) && succeeded ? S_OK : E_FAIL;
                                        PostMessageW(g_window, kNavigationComplete, 0, 0);
                                        return S_OK;
                                    }).Get(), nullptr);
                            if (FAILED(result)) {
                                g_result = result;
                                PostMessageW(g_window, kNavigationComplete, 0, 0);
                                return S_OK;
                            }
                            return g_webView->NavigateToString(
                                L"<!doctype html><meta charset=utf-8><title>WebView2 ready</title>"
                                L"<body><h1>Native WebView2 host is working</h1></body>");
                        }).Get());
            }).Get());
    if (FAILED(createResult)) {
        g_result = createResult;
        std::fwprintf(stderr, L"CreateCoreWebView2EnvironmentWithOptions failed: 0x%08lx\n", createResult);
        DestroyWindow(g_window);
        CoUninitialize();
        return 1;
    }

    SetTimer(g_window, kTimeoutTimer, kTimeoutMs, nullptr);
    MSG message{};
    int messageResult = 0;
    while ((messageResult = GetMessageW(&message, nullptr, 0, 0)) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    KillTimer(g_window, kTimeoutTimer);

    if (g_webView) g_webView->Release();
    if (g_controller) {
        g_controller->Close();
        g_controller->Release();
    }
    DestroyWindow(g_window);
    CoUninitialize();

    if (FAILED(g_result)) {
        std::fwprintf(stderr, L"WebView2 navigation failed: 0x%08lx\n", g_result);
        return 1;
    }
    std::wprintf(L"WebView2 initialized and completed navigation in a native child window.\n");
    return 0;
}
