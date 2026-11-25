#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propsys.h>
#include <wrl.h>
#include <algorithm>
#include <atomic>
#include <iterator>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <system_error>
#include <thread>
#include <vector>
#include <shlwapi.h>
#include "WebView2.h"

using Microsoft::WRL::Callback;

namespace {
const CLSID kPreviewHandlerClsid =
    {0x734a81c0, 0x607d, 0x4d0a, {0x9e, 0x9b, 0x67, 0xc7, 0xb0, 0x6e, 0x4b, 0x21}};
constexpr wchar_t kPreviewWindowClass[] = L"FourDPreviewHandlerWindow";
constexpr UINT kHtmlReadyMessage = WM_APP + 10;
constexpr DWORD kPreviewTimeoutMs = 5000;
constexpr size_t kMaxPreviewBytes = 32 * 1024 * 1024;
constexpr char kHelperMissingHtml[] =
    "<!doctype html><meta charset=utf-8><title>4D preview unavailable</title>"
    "<p>The fourdql preview helper is missing.</p>";
constexpr char kTimeoutHtml[] =
    "<!doctype html><meta charset=utf-8><title>4D preview timed out</title>"
    "<p>Preview generation timed out.</p>";
constexpr char kOutputLimitHtml[] =
    "<!doctype html><meta charset=utf-8><title>4D preview unavailable</title>"
    "<p>The generated preview exceeded the size limit.</p>";
constexpr char kProcessErrorHtml[] =
    "<!doctype html><meta charset=utf-8><title>4D preview unavailable</title>"
    "<p>Preview generation failed.</p>";

std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};

struct CancellationState {
    CancellationState() : event(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
    ~CancellationState() {
        if (event) CloseHandle(event);
    }
    HANDLE event;
};

struct ProcessOutput {
    HRESULT status = E_FAIL;
    std::string html;
};

struct PendingHtmlState {
    std::mutex mutex;
    std::string html;
    bool ready = false;
};

std::wstring HelperPath() {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&g_objectCount), &module)) {
        return {};
    }
    wchar_t path[32768]{};
    const DWORD length = GetModuleFileNameW(module, path, static_cast<DWORD>(std::size(path)));
    if (length == 0 || length >= std::size(path)) return {};
    std::wstring result(path, length);
    const size_t separator = result.find_last_of(L"\\/");
    if (separator == std::wstring::npos) return {};
    result.resize(separator + 1);
    result += L"fourdql.exe";
    return result;
}

ProcessOutput RunHelper(const std::wstring& filePath, HANDLE cancellationEvent) {
    const std::wstring helper = HelperPath();
    if (helper.empty() || GetFileAttributesW(helper.c_str()) == INVALID_FILE_ATTRIBUTES) {
        return {HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND), kHelperMissingHtml};
    }

    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    HANDLE outputRead = nullptr;
    HANDLE outputWrite = nullptr;
    if (!CreatePipe(&outputRead, &outputWrite, &security, 0)) {
        return {HRESULT_FROM_WIN32(GetLastError()), kProcessErrorHtml};
    }
    SetHandleInformation(outputRead, HANDLE_FLAG_INHERIT, 0);
    HANDLE nullInput = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                   &security, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (nullInput == INVALID_HANDLE_VALUE) {
        const HRESULT result = HRESULT_FROM_WIN32(GetLastError());
        CloseHandle(outputRead);
        CloseHandle(outputWrite);
        return {result, kProcessErrorHtml};
    }

    SIZE_T attributeBytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attributeBytes);
    std::vector<BYTE> attributeStorage(attributeBytes);
    auto* attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attributeStorage.data());
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attributeBytes)) {
        const HRESULT result = HRESULT_FROM_WIN32(GetLastError());
        CloseHandle(nullInput);
        CloseHandle(outputRead);
        CloseHandle(outputWrite);
        return {result, kProcessErrorHtml};
    }
    HANDLE inheritedHandles[] = {outputWrite, nullInput};
    if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                   inheritedHandles, sizeof(inheritedHandles), nullptr, nullptr)) {
        const HRESULT result = HRESULT_FROM_WIN32(GetLastError());
        DeleteProcThreadAttributeList(attributes);
        CloseHandle(nullInput);
        CloseHandle(outputRead);
        CloseHandle(outputWrite);
        return {result, kProcessErrorHtml};
    }

    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = nullInput;
    startup.StartupInfo.hStdOutput = outputWrite;
    startup.StartupInfo.hStdError = outputWrite;
    startup.lpAttributeList = attributes;
    std::wstring command = L"\"" + helper + L"\" --html \"" + filePath + L"\"";
    std::vector<wchar_t> commandLine(command.begin(), command.end());
    commandLine.push_back(L'\0');

    PROCESS_INFORMATION processInfo{};
    const BOOL created = CreateProcessW(
        helper.c_str(), commandLine.data(), nullptr, nullptr, TRUE,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr,
        nullptr, &startup.StartupInfo, &processInfo);
    const DWORD createError = created ? ERROR_SUCCESS : GetLastError();
    DeleteProcThreadAttributeList(attributes);
    CloseHandle(nullInput);
    CloseHandle(outputWrite);
    if (!created) {
        CloseHandle(outputRead);
        return {HRESULT_FROM_WIN32(createError), kProcessErrorHtml};
    }

    HANDLE job = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
                                               JOB_OBJECT_LIMIT_PROCESS_MEMORY;
    limits.ProcessMemoryLimit = 512 * 1024 * 1024;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)) ||
        !AssignProcessToJobObject(job, processInfo.hProcess)) {
        const DWORD error = GetLastError();
        TerminateProcess(processInfo.hProcess, 1);
        WaitForSingleObject(processInfo.hProcess, 1000);
        if (job) CloseHandle(job);
        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        CloseHandle(outputRead);
        return {HRESULT_FROM_WIN32(error), kProcessErrorHtml};
    }
    if (ResumeThread(processInfo.hThread) == static_cast<DWORD>(-1)) {
        const DWORD error = GetLastError();
        TerminateJobObject(job, 1);
        CloseHandle(job);
        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        CloseHandle(outputRead);
        return {HRESULT_FROM_WIN32(error), kProcessErrorHtml};
    }
    CloseHandle(processInfo.hThread);

    std::string html;
    html.reserve(64 * 1024);
    const ULONGLONG start = GetTickCount64();
    HRESULT result = S_OK;
    bool processExited = false;
    for (;;) {
        processExited = WaitForSingleObject(processInfo.hProcess, 0) == WAIT_OBJECT_0;
        if (WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) {
            result = HRESULT_FROM_WIN32(ERROR_CANCELLED);
            break;
        }
        if (!processExited && GetTickCount64() - start > kPreviewTimeoutMs) {
            result = HRESULT_FROM_WIN32(ERROR_TIMEOUT);
            break;
        }

        DWORD available = 0;
        if (!PeekNamedPipe(outputRead, nullptr, 0, nullptr, &available, nullptr)) {
            const DWORD error = GetLastError();
            if (error == ERROR_BROKEN_PIPE) {
                processExited = WaitForSingleObject(processInfo.hProcess, 0) == WAIT_OBJECT_0;
                if (processExited) break;
                Sleep(10);
                continue;
            }
            result = HRESULT_FROM_WIN32(error);
            break;
        }
        if (available > 0) {
            char buffer[64 * 1024];
            const DWORD requested = std::min<DWORD>(available, static_cast<DWORD>(sizeof(buffer)));
            DWORD read = 0;
            if (!ReadFile(outputRead, buffer, requested, &read, nullptr)) {
                result = HRESULT_FROM_WIN32(GetLastError());
                break;
            }
            if (html.size() + read > kMaxPreviewBytes) {
                result = HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);
                break;
            }
            html.append(buffer, read);
        }
        processExited = WaitForSingleObject(processInfo.hProcess, 0) == WAIT_OBJECT_0;
        if (processExited && available == 0) break;
        if (!processExited && available == 0) Sleep(10);
    }

    if (FAILED(result)) TerminateJobObject(job, 1);
    WaitForSingleObject(processInfo.hProcess, 1000);
    DWORD exitCode = 1;
    GetExitCodeProcess(processInfo.hProcess, &exitCode);
    CloseHandle(outputRead);
    CloseHandle(processInfo.hProcess);
    CloseHandle(job);

    if (result == HRESULT_FROM_WIN32(ERROR_TIMEOUT)) return {result, kTimeoutHtml};
    if (result == HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE)) return {result, kOutputLimitHtml};
    if (FAILED(result)) return {result, kProcessErrorHtml};
    if (exitCode != 0 || html.empty()) return {E_FAIL, kProcessErrorHtml};
    return {S_OK, std::move(html)};
}

class PreviewHandler final : public IPreviewHandler,
                             public IInitializeWithFile,
                             public IObjectWithSite,
                             public IOleWindow,
                             public IPreviewHandlerVisuals {
public:
    PreviewHandler() { ++g_objectCount; }

    ~PreviewHandler() {
        Unload();
        --g_objectCount;
    }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (iid == IID_IUnknown || iid == __uuidof(IPreviewHandler)) {
            *result = static_cast<IPreviewHandler*>(this);
        } else if (iid == __uuidof(IInitializeWithFile)) {
            *result = static_cast<IInitializeWithFile*>(this);
        } else if (iid == __uuidof(IObjectWithSite)) {
            *result = static_cast<IObjectWithSite*>(this);
        } else if (iid == __uuidof(IOleWindow)) {
            *result = static_cast<IOleWindow*>(this);
        } else if (iid == __uuidof(IPreviewHandlerVisuals)) {
            *result = static_cast<IPreviewHandlerVisuals*>(this);
        } else {
            return E_NOINTERFACE;
        }
        AddRef();
        return S_OK;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --references_;
        if (remaining == 0) delete this;
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE Initialize(LPCWSTR path, DWORD mode) override {
        if (!path || !*path) return E_INVALIDARG;
        if ((mode & 3) != STGM_READ) return STG_E_ACCESSDENIED;
        if (!filePath_.empty()) return HRESULT_FROM_WIN32(ERROR_ALREADY_INITIALIZED);
        filePath_ = path;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE SetSite(IUnknown* site) override {
        if (site_) site_->Release();
        if (frame_) frame_->Release();
        site_ = site;
        frame_ = nullptr;
        if (site_) {
            site_->AddRef();
            site_->QueryInterface(IID_PPV_ARGS(&frame_));
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE GetSite(REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        return site_ ? site_->QueryInterface(iid, result) : E_FAIL;
    }

    HRESULT STDMETHODCALLTYPE GetWindow(HWND* window) override {
        if (!window) return E_POINTER;
        *window = previewWindow_;
        return previewWindow_ ? S_OK : E_FAIL;
    }

    HRESULT STDMETHODCALLTYPE ContextSensitiveHelp(BOOL) override { return E_NOTIMPL; }

    HRESULT STDMETHODCALLTYPE SetWindow(HWND parent, const RECT* bounds) override {
        if (!parent || !bounds) return E_INVALIDARG;
        parentWindow_ = parent;
        bounds_ = *bounds;
        if (previewWindow_) {
            SetParent(previewWindow_, parentWindow_);
            PositionWindow();
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE SetRect(const RECT* bounds) override {
        if (!bounds) return E_INVALIDARG;
        bounds_ = *bounds;
        PositionWindow();
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DoPreview() override {
        if (!parentWindow_) return E_UNEXPECTED;
        if (filePath_.empty()) return E_UNEXPECTED;
        if (previewWindow_ && controller_) return S_OK;
        if (!RegisterPreviewWindowClass()) return HRESULT_FROM_WIN32(GetLastError());

        previewWindow_ = CreateWindowExW(
            0, kPreviewWindowClass, L"4D preview", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
            bounds_.left, bounds_.top, bounds_.right - bounds_.left, bounds_.bottom - bounds_.top,
            parentWindow_, nullptr, GetModuleHandleW(nullptr), this);
        if (!previewWindow_) return HRESULT_FROM_WIN32(GetLastError());
        SetWindowTextW(previewWindow_, L"Starting preview");

        const HRESULT folderResult = UserDataFolder();
        if (FAILED(folderResult)) {
            DestroyWindow(previewWindow_);
            previewWindow_ = nullptr;
            return folderResult;
        }

        const ULONG generation = ++generation_;
        const HWND targetWindow = previewWindow_;
        std::shared_ptr<CancellationState> cancellation;
        std::shared_ptr<PendingHtmlState> pendingHtml;
        try {
            cancellation = std::make_shared<CancellationState>();
            pendingHtml = std::make_shared<PendingHtmlState>();
        } catch (const std::bad_alloc&) {
            DestroyWindow(previewWindow_);
            previewWindow_ = nullptr;
            return E_OUTOFMEMORY;
        }
        if (!cancellation->event) {
            const HRESULT result = HRESULT_FROM_WIN32(GetLastError());
            DestroyWindow(previewWindow_);
            previewWindow_ = nullptr;
            return result;
        }
        cancellation_ = cancellation;
        pendingHtml_ = pendingHtml;
        AddRef();
        try {
            std::thread([this, targetWindow, generation, cancellation, pendingHtml, filePath = filePath_]() {
                ProcessOutput output;
                try {
                    output = RunHelper(filePath, cancellation->event);
                } catch (const std::bad_alloc&) {
                    output = {E_OUTOFMEMORY, kProcessErrorHtml};
                }
                if (WaitForSingleObject(cancellation->event, 0) != WAIT_OBJECT_0) {
                    {
                        std::lock_guard<std::mutex> lock(pendingHtml->mutex);
                        pendingHtml->html = std::move(output.html);
                        pendingHtml->ready = true;
                    }
                    if (!PostMessageW(targetWindow, kHtmlReadyMessage, generation, 0)) {
                        std::lock_guard<std::mutex> lock(pendingHtml->mutex);
                        pendingHtml->html.clear();
                        pendingHtml->ready = false;
                    }
                }
                Release();
            }).detach();
        } catch (const std::system_error&) {
            Release();
            cancellation_.reset();
            pendingHtml_.reset();
            DestroyWindow(previewWindow_);
            previewWindow_ = nullptr;
            return E_FAIL;
        } catch (const std::bad_alloc&) {
            Release();
            cancellation_.reset();
            pendingHtml_.reset();
            DestroyWindow(previewWindow_);
            previewWindow_ = nullptr;
            return E_OUTOFMEMORY;
        }

        AddRef();
        const HRESULT result = CreateCoreWebView2EnvironmentWithOptions(
            nullptr, userDataFolder_.c_str(), nullptr,
            Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
                [this, generation](HRESULT status, ICoreWebView2Environment* environment) -> HRESULT {
                    if (generation == generation_ && SUCCEEDED(status) && environment) {
                        StartController(environment, generation);
                    } else if (generation == generation_) {
                        SetWindowTextW(previewWindow_, L"4D preview unavailable");
                    }
                    Release();
                    return S_OK;
                }).Get());
        if (FAILED(result)) {
            Release();
            Unload();
        }
        return result;
    }

    HRESULT STDMETHODCALLTYPE Unload() override {
        ++generation_;
        if (cancellation_) SetEvent(cancellation_->event);
        CloseWebView();
        if (!previewFilePath_.empty()) DeleteFileW(previewFilePath_.c_str());
        previewFilePath_.clear();
        previewFileUri_.clear();
        pendingHtml_.reset();
        cancellation_.reset();
        if (previewWindow_) {
            DestroyWindow(previewWindow_);
            previewWindow_ = nullptr;
        }
        parentWindow_ = nullptr;
        filePath_.clear();
        if (frame_) {
            frame_->Release();
            frame_ = nullptr;
        }
        if (site_) {
            site_->Release();
            site_ = nullptr;
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE SetFocus() override {
        if (previewWindow_) ::SetFocus(previewWindow_);
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE QueryFocus(HWND* window) override {
        if (!window) return E_POINTER;
        *window = ::GetFocus();
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE TranslateAccelerator(MSG* message) override {
        if (!message) return E_INVALIDARG;
        return frame_ ? frame_->TranslateAccelerator(message) : S_FALSE;
    }

    HRESULT STDMETHODCALLTYPE SetBackgroundColor(COLORREF color) override {
        backgroundColor_ = color;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE SetFont(const LOGFONTW* font) override {
        if (!font) return E_INVALIDARG;
        font_ = *font;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE SetTextColor(COLORREF color) override {
        textColor_ = color;
        return S_OK;
    }

private:
    static bool RegisterPreviewWindowClass() {
        static const ATOM atom = [] {
            WNDCLASSW cls{};
            cls.lpfnWndProc = PreviewWindowProc;
            cls.hInstance = GetModuleHandleW(nullptr);
            cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
            cls.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
            cls.lpszClassName = kPreviewWindowClass;
            const ATOM registered = RegisterClassW(&cls);
            return registered ? registered :
                (GetLastError() == ERROR_CLASS_ALREADY_EXISTS ? static_cast<ATOM>(1) : ATOM{});
        }();
        return atom != 0;
    }

    static LRESULT CALLBACK PreviewWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
        auto* handler = reinterpret_cast<PreviewHandler*>(GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            handler = static_cast<PreviewHandler*>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(handler));
        }
        if (handler && message == kHtmlReadyMessage) {
            if (handler->generation_ != static_cast<ULONG>(wParam)) return 0;
            handler->DisplayPendingHtml();
            return 0;
        }
        if (handler && message == WM_SIZE) handler->SetControllerBounds();
        return DefWindowProcW(window, message, wParam, lParam);
    }

    HRESULT UserDataFolder() {
        PWSTR localAppData = nullptr;
        const HRESULT result = SHGetKnownFolderPath(FOLDERID_LocalAppDataLow, KF_FLAG_DEFAULT, nullptr, &localAppData);
        if (FAILED(result)) return result;
        userDataFolder_ = localAppData;
        CoTaskMemFree(localAppData);
        userDataFolder_ += L"\\4DQuickLook\\WebView2";
        const int created = SHCreateDirectoryExW(nullptr, userDataFolder_.c_str(), nullptr);
        if (created != ERROR_SUCCESS && created != ERROR_ALREADY_EXISTS && created != ERROR_FILE_EXISTS) {
            return HRESULT_FROM_WIN32(created);
        }
        return S_OK;
    }

    HRESULT NavigateHtml(const std::string& html) {
        if (!webView_) return E_UNEXPECTED;
        const size_t separator = userDataFolder_.find_last_of(L"\\/");
        if (separator == std::wstring::npos) return E_UNEXPECTED;
        const std::wstring previewFolder = userDataFolder_.substr(0, separator) + L"\\Previews";
        const int folderResult = SHCreateDirectoryExW(nullptr, previewFolder.c_str(), nullptr);
        if (folderResult != ERROR_SUCCESS && folderResult != ERROR_ALREADY_EXISTS &&
            folderResult != ERROR_FILE_EXISTS) {
            return HRESULT_FROM_WIN32(folderResult);
        }

        GUID identifier{};
        HRESULT result = CoCreateGuid(&identifier);
        if (FAILED(result)) return result;
        wchar_t identifierText[40]{};
        if (StringFromGUID2(identifier, identifierText,
                            static_cast<int>(std::size(identifierText))) == 0) {
            return E_FAIL;
        }
        previewFilePath_ = previewFolder + L"\\" + identifierText + L".html";

        HANDLE file = CreateFileW(previewFilePath_.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                                  CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY, nullptr);
        if (file == INVALID_HANDLE_VALUE) {
            previewFilePath_.clear();
            return HRESULT_FROM_WIN32(GetLastError());
        }
        size_t written = 0;
        while (written < html.size()) {
            const DWORD chunk = static_cast<DWORD>(std::min<size_t>(html.size() - written, 1024 * 1024));
            DWORD count = 0;
            if (!WriteFile(file, html.data() + written, chunk, &count, nullptr) || count == 0) {
                result = HRESULT_FROM_WIN32(GetLastError());
                CloseHandle(file);
                DeleteFileW(previewFilePath_.c_str());
                previewFilePath_.clear();
                return result;
            }
            written += count;
        }
        CloseHandle(file);

        std::vector<wchar_t> url(32768);
        DWORD urlLength = static_cast<DWORD>(url.size());
        result = UrlCreateFromPathW(previewFilePath_.c_str(), url.data(), &urlLength, 0);
        if (FAILED(result)) {
            DeleteFileW(previewFilePath_.c_str());
            previewFilePath_.clear();
            return result;
        }
        previewFileUri_ = url.data();
        initialDocumentStarted_ = false;
        result = webView_->Navigate(previewFileUri_.c_str());
        if (FAILED(result)) {
            DeleteFileW(previewFilePath_.c_str());
            previewFilePath_.clear();
            previewFileUri_.clear();
        }
        return result;
    }

    void StartController(ICoreWebView2Environment* environment, ULONG generation) {
        AddRef();
        const HRESULT result = environment->CreateCoreWebView2Controller(
            previewWindow_,
            Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                [this, generation](HRESULT status, ICoreWebView2Controller* controller) -> HRESULT {
                    if (generation == generation_ && SUCCEEDED(status) && controller) {
                        controller_ = controller;
                        controller_->AddRef();
                        SetControllerBounds();
                        HRESULT result = controller_->get_CoreWebView2(&webView_);
                        if (SUCCEEDED(result)) {
                            result = ConfigureWebView();
                        }
                        if (FAILED(result)) SetWindowTextW(previewWindow_, L"4D preview unavailable");
                    } else if (generation == generation_) {
                        SetWindowTextW(previewWindow_, L"4D preview unavailable");
                    }
                    Release();
                    return S_OK;
                }).Get());
        if (FAILED(result)) {
            SetWindowTextW(previewWindow_, L"4D preview unavailable");
            Release();
        }
    }

    HRESULT ConfigureWebView() {
        if (!webView_) return E_POINTER;
        ICoreWebView2Settings* settings = nullptr;
        HRESULT result = webView_->get_Settings(&settings);
        if (FAILED(result) || !settings) return FAILED(result) ? result : E_FAIL;
        result = settings->put_IsScriptEnabled(FALSE);
        if (SUCCEEDED(result)) result = settings->put_AreDefaultContextMenusEnabled(FALSE);
        if (SUCCEEDED(result)) result = settings->put_AreDevToolsEnabled(FALSE);
        if (SUCCEEDED(result)) result = settings->put_IsStatusBarEnabled(FALSE);
        settings->Release();
        if (FAILED(result)) return result;

        const ULONG generation = generation_;
        AddRef();
        result = webView_->add_NavigationCompleted(
            Callback<ICoreWebView2NavigationCompletedEventHandler>(
                [this, generation](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                    BOOL succeeded = FALSE;
                    if (generation == generation_ && previewWindow_) {
                        if (SUCCEEDED(args->get_IsSuccess(&succeeded)) && succeeded) {
                            SetWindowTextW(previewWindow_, L"WebView2 ready");
                            if (!previewFilePath_.empty() &&
                                (DeleteFileW(previewFilePath_.c_str()) || GetLastError() == ERROR_FILE_NOT_FOUND)) {
                                previewFilePath_.clear();
                                previewFileUri_.clear();
                            }
                        } else {
                            SetWindowTextW(previewWindow_, L"4D preview unavailable");
                        }
                    }
                    return S_OK;
                }).Get(), &navigationCompletedToken_);
        if (FAILED(result)) {
            Release();
            return result;
        }
        navigationCompletedRegistered_ = true;
        AddRef();
        result = webView_->add_NavigationStarting(
            Callback<ICoreWebView2NavigationStartingEventHandler>(
                [this, generation](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                    LPWSTR uri = nullptr;
                    BOOL cancel = TRUE;
                    if (SUCCEEDED(args->get_Uri(&uri)) && uri) {
                        const bool aboutBlank = wcscmp(uri, L"about:blank") == 0;
                        const bool initialHtml = generation == generation_ && !initialDocumentStarted_ &&
                            !previewFileUri_.empty() &&
                            CompareStringOrdinal(uri, -1, previewFileUri_.c_str(), -1, TRUE) == CSTR_EQUAL;
                        if (initialHtml) initialDocumentStarted_ = true;
                        cancel = !aboutBlank && !initialHtml;
                        CoTaskMemFree(uri);
                    }
                    args->put_Cancel(cancel);
                    return S_OK;
                }).Get(), &navigationStartingToken_);
        if (FAILED(result)) {
            Release();
            return result;
        }
        navigationStartingRegistered_ = true;
        initialDocumentStarted_ = false;
        DisplayPendingHtml();
        return S_OK;
    }

    void DisplayPendingHtml() {
        if (!pendingHtml_ || !webView_) return;
        std::string html;
        {
            std::lock_guard<std::mutex> lock(pendingHtml_->mutex);
            if (!pendingHtml_->ready) return;
            html = std::move(pendingHtml_->html);
            pendingHtml_->ready = false;
        }
        if (FAILED(NavigateHtml(html))) {
            SetWindowTextW(previewWindow_, L"4D preview unavailable");
        }
    }

    void SetControllerBounds() {
        if (!controller_ || !previewWindow_) return;
        RECT client{};
        GetClientRect(previewWindow_, &client);
        controller_->put_Bounds(client);
    }

    void PositionWindow() {
        if (previewWindow_) {
            SetWindowPos(previewWindow_, nullptr, bounds_.left, bounds_.top,
                         bounds_.right - bounds_.left, bounds_.bottom - bounds_.top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
        }
    }

    void CloseWebView() {
        if (webView_) {
            if (navigationStartingRegistered_) {
                webView_->remove_NavigationStarting(navigationStartingToken_);
                navigationStartingRegistered_ = false;
                Release();
            }
            if (navigationCompletedRegistered_) {
                webView_->remove_NavigationCompleted(navigationCompletedToken_);
                navigationCompletedRegistered_ = false;
                Release();
            }
            webView_->Release();
            webView_ = nullptr;
        }
        if (controller_) {
            controller_->Close();
            controller_->Release();
            controller_ = nullptr;
        }
    }

    std::atomic<ULONG> references_{1};
    std::wstring filePath_;
    std::wstring userDataFolder_;
    HWND parentWindow_ = nullptr;
    HWND previewWindow_ = nullptr;
    RECT bounds_{};
    ULONG generation_ = 0;
    bool initialDocumentStarted_ = false;
    bool navigationCompletedRegistered_ = false;
    bool navigationStartingRegistered_ = false;
    EventRegistrationToken navigationCompletedToken_{};
    EventRegistrationToken navigationStartingToken_{};
    IUnknown* site_ = nullptr;
    IPreviewHandlerFrame* frame_ = nullptr;
    ICoreWebView2Controller* controller_ = nullptr;
    ICoreWebView2* webView_ = nullptr;
    COLORREF backgroundColor_ = RGB(255, 255, 255);
    COLORREF textColor_ = RGB(0, 0, 0);
    LOGFONTW font_{};
    std::shared_ptr<CancellationState> cancellation_;
    std::wstring previewFilePath_;
    std::wstring previewFileUri_;
    std::shared_ptr<PendingHtmlState> pendingHtml_;
};

class ClassFactory final : public IClassFactory {
public:
    ClassFactory() { ++g_objectCount; }
    ~ClassFactory() { --g_objectCount; }

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER;
        *result = nullptr;
        if (iid != IID_IUnknown && iid != IID_IClassFactory) return E_NOINTERFACE;
        *result = static_cast<IClassFactory*>(this);
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining = --references_;
        if (remaining == 0) delete this;
        return remaining;
    }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer, REFIID iid, void** result) override {
        if (outer) return CLASS_E_NOAGGREGATION;
        auto* handler = new (std::nothrow) PreviewHandler();
        if (!handler) return E_OUTOFMEMORY;
        const HRESULT status = handler->QueryInterface(iid, result);
        handler->Release();
        return status;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override {
        if (lock) ++g_serverLocks;
        else --g_serverLocks;
        return S_OK;
    }

private:
    std::atomic<ULONG> references_{1};
};
}

STDAPI FourDPreviewHandlerGetClassObject(REFCLSID clsid, REFIID iid, LPVOID FAR* result) {
    if (clsid != kPreviewHandlerClsid) return CLASS_E_CLASSNOTAVAILABLE;
    auto* factory = new (std::nothrow) ClassFactory();
    if (!factory) return E_OUTOFMEMORY;
    const HRESULT status = factory->QueryInterface(iid, result);
    factory->Release();
    return status;
}

STDAPI FourDPreviewHandlerCanUnloadNow() {
    return g_objectCount == 0 && g_serverLocks == 0 ? S_OK : S_FALSE;
}
