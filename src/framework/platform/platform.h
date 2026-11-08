/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#pragma once

#include <framework/core/inputevent.h>
#include <framework/global.h>

#include "staticdata.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

class Platform
{
public:

    void init(std::vector<std::string>& args);
    void processArgs(std::vector<std::string>& args);
    bool spawnProcess(std::string process, const std::vector<std::string>& args);
    int getProcessId();
    bool isProcessRunning(std::string_view name);
    bool killProcess(std::string_view name);
    std::string getTempPath();
    std::string getCurrentDir();
    bool copyFile(std::string from, std::string to);
    bool fileExists(std::string file);
    bool removeFile(std::string file);
    ticks_t getFileModificationTime(std::string file);
#ifdef __EMSCRIPTEN__
    void reloadPage();
#endif
    bool openUrl(std::string url, bool now = false);
    bool openDir(std::string path, bool now = false);
    std::string getCPUName();
    double getTotalSystemMemory();
    double getMemoryUsage();
    std::string getOSName();
    Device getDevice() { return m_device; }
    void setDevice(const Device device) { m_device = device; }
    bool isDesktop() { return m_device.type == Desktop; }
    // Browser: the touch layout is used on phones and tablets, chosen from
    // the user agent and the device (a touch screen without a precise
    // pointer: iPadOS Safari calls itself a Mac). The player can force it
    // with setTouchMode. Decided once: changing it reloads the page.
    bool isMobile() {
#ifndef __EMSCRIPTEN__
        return m_device.type == Mobile;
#else
        static const bool mobile = MAIN_THREAD_EM_ASM_INT({
            var mode = null;
            try { mode = localStorage.getItem('otclient-touch-mode'); } catch (e) {}
            if (mode === 'touch') return 1;
            if (mode === 'desktop') return 0;
            if ((/iphone|ipod|ipad|android/i).test(navigator.userAgent)) return 1;
            var touchOnly = navigator.maxTouchPoints > 0 &&
                window.matchMedia('(pointer: coarse)').matches &&
                !window.matchMedia('(any-pointer: fine)').matches;
            return touchOnly ? 1 : 0;
        }) == 1;
        return mobile;
#endif
    }
    // 0 automatic, 1 touch, 2 desktop (browser only)
    int getTouchMode() {
#ifndef __EMSCRIPTEN__
        return 0;
#else
        return MAIN_THREAD_EM_ASM_INT({
            var mode = null;
            try { mode = localStorage.getItem('otclient-touch-mode'); } catch (e) {}
            return mode === 'touch' ? 1 : mode === 'desktop' ? 2 : 0;
        });
#endif
    }
    // Stores the choice on this device and reloads the client with it
    void setTouchMode(int mode) {
#ifdef __EMSCRIPTEN__
        MAIN_THREAD_ASYNC_EM_ASM({
            try {
                if ($0 === 1) localStorage.setItem('otclient-touch-mode', 'touch');
                else if ($0 === 2) localStorage.setItem('otclient-touch-mode', 'desktop');
                else localStorage.removeItem('otclient-touch-mode');
            } catch (e) {}
            location.reload();
        }, mode);
#else
        (void)mode;
#endif
    }
    // Browser only (always true elsewhere): navigator.onLine, and whether the
    // page is shown (not a background tab or a minimized window)
    bool isNetworkOnline() {
#ifndef __EMSCRIPTEN__
        return true;
#else
        return MAIN_THREAD_EM_ASM_INT({ return navigator.onLine ? 1 : 0; }) == 1;
#endif
    }
    bool isPageVisible() {
#ifndef __EMSCRIPTEN__
        return true;
#else
        return MAIN_THREAD_EM_ASM_INT({ return document.visibilityState === 'visible' ? 1 : 0; }) == 1;
#endif
    }
    // Installing the web client as an app (window.otclientApp, set by the
    // deployment's page, keeps the browser's install prompt):
    // 0 not possible, 1 the browser can install it (installApp shows its
    // prompt), 2 manual (iOS: Share > Add to Home Screen), 3 running as an
    // installed app
    int getAppInstallState() {
#ifndef __EMSCRIPTEN__
        return 0;
#else
        return MAIN_THREAD_EM_ASM_INT({
            if (window.matchMedia('(display-mode: standalone)').matches ||
                window.matchMedia('(display-mode: fullscreen)').matches || navigator.standalone)
                return 3;
            var app = window.otclientApp;
            if (!app) return 0;
            if (app.prompt) return 1;
            var ios = /iphone|ipad|ipod/i.test(navigator.userAgent) ||
                      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
            return ios ? 2 : 0;
        });
#endif
    }
    void installApp() {
#ifdef __EMSCRIPTEN__
        MAIN_THREAD_ASYNC_EM_ASM({
            var app = window.otclientApp;
            if (app && app.install) app.install();
        });
#endif
    }
    bool isBrowser() { return m_device.type == Browser; }
    bool isConsole() { return m_device.type == Console; }
    // A yes/no setting from the web page (window.otclientConfig[key], set by
    // the deployment): 1 yes, 0 no, -1 not set (and always -1 outside the browser)
    int getBrowserConfigFlag(const std::string& key) {
#ifndef __EMSCRIPTEN__
        (void)key;
        return -1;
#else
        return MAIN_THREAD_EM_ASM_INT({
            var config = window.otclientConfig;
            var value = config ? config[UTF8ToString($0)] : undefined;
            if (value === undefined || value === null) return -1;
            return (value === true || value === 1 || value === 'true' || value === 'on') ? 1 : 0;
        }, key.c_str());
#endif
    }
    // Browser: hands a file of the virtual file system (an absolute path, like
    // getWriteDir() .. "moments/1.png") to the browser as a download named
    // name (Moments' Save, ot-client#25). false outside the browser.
    bool downloadFile(const std::string& path, const std::string& name) {
#ifndef __EMSCRIPTEN__
        (void)path; (void)name;
        return false;
#else
        return MAIN_THREAD_EM_ASM_INT({
            try {
                var data = FS.readFile(UTF8ToString($0));
                var link = document.createElement('a');
                link.href = URL.createObjectURL(new Blob([data]));
                link.download = UTF8ToString($1);
                document.body.appendChild(link);
                link.click();
                setTimeout(function () { URL.revokeObjectURL(link.href); link.remove(); }, 1000);
                return 1;
            } catch (e) {
                return 0;
            }
        }, path.c_str(), name.c_str()) == 1;
#endif
    }

    // The browser and device, as JSON (bug reports, ot-client#67): user
    // agent, screen and window sizes, pixel ratio, orientation, language,
    // installed-app mode, CPU cores and memory when the browser says. "{}"
    // outside the browser.
    std::string getBrowserInfo() {
#ifndef __EMSCRIPTEN__
        return "{}";
#else
        char* value = (char*)MAIN_THREAD_EM_ASM_PTR({
            var info = {};
            try {
                // (no commas outside parentheses: they would split the macro)
                info.userAgent = navigator.userAgent;
                info.language = navigator.language;
                info.screen = screen.width + 'x' + screen.height;
                info.window = window.innerWidth + 'x' + window.innerHeight;
                info.pixelRatio = window.devicePixelRatio;
                info.orientation = (screen.orientation && screen.orientation.type) || '';
                info.touchPoints = navigator.maxTouchPoints || 0;
                info.standalone = !!(window.matchMedia('(display-mode: standalone)').matches || navigator.standalone);
                info.cores = navigator.hardwareConcurrency || 0;
                info.memoryGB = navigator.deviceMemory || 0;
                info.connection = (navigator.connection && navigator.connection.effectiveType) || '';
            } catch (e) {}
            return stringToNewUTF8(JSON.stringify(info));
        });
        if (!value) return "{}";
        std::string result(value);
        free(value);
        return result;
#endif
    }
    // A text setting from the web page (window.otclientConfig[key]); "" when
    // not set (and always "" outside the browser). For example the login
    // key's public half (rsaPublicKey, ot-server#17).
    std::string getBrowserConfigString(const std::string& key) {
#ifndef __EMSCRIPTEN__
        (void)key;
        return {};
#else
        char* value = (char*)MAIN_THREAD_EM_ASM_PTR({
            var config = window.otclientConfig;
            var value = config ? config[UTF8ToString($0)] : undefined;
            if (value === undefined || value === null) return 0;
            return stringToNewUTF8(String(value));
        }, key.c_str());
        if (!value) return {};
        std::string result(value);
        free(value);
        return result;
#endif
    }
    // The first connected game controller (browser Gamepad API, standard
    // mapping): the pressed buttons as bits (bit 0 is button 0), -1 when
    // there is none. Browsers report a controller only after one of its
    // buttons was pressed on the page.
    int getGamepadButtons() {
#ifndef __EMSCRIPTEN__
        return -1;
#else
        return MAIN_THREAD_EM_ASM_INT({
            var pads = navigator.getGamepads ? navigator.getGamepads() : [];
            for (var i = 0; i < pads.length; i++) {
                var pad = pads[i];
                if (!pad || !pad.connected) continue;
                var bits = 0;
                for (var b = 0; b < pad.buttons.length && b < 30; b++) {
                    var button = pad.buttons[b];
                    if (button.pressed || button.value > 0.5) bits |= (1 << b);
                }
                return bits;
            }
            return -1;
        });
#endif
    }
    // Its left stick: (x + 128) * 256 + (y + 128), each axis -127..127
    // (right and down positive); 128 * 256 + 128 when centred or absent
    int getGamepadStick() {
#ifndef __EMSCRIPTEN__
        return 128 * 256 + 128;
#else
        return MAIN_THREAD_EM_ASM_INT({
            var pads = navigator.getGamepads ? navigator.getGamepads() : [];
            for (var i = 0; i < pads.length; i++) {
                var pad = pads[i];
                if (!pad || !pad.connected || pad.axes.length < 2) continue;
                var x = Math.max(-127, Math.min(127, Math.round(pad.axes[0] * 127)));
                var y = Math.max(-127, Math.min(127, Math.round(pad.axes[1] * 127)));
                return (x + 128) * 256 + (y + 128);
            }
            return 128 * 256 + 128;
        });
#endif
    }
    std::string getDeviceShortName(DeviceType type = DeviceUnknown);
    std::string getOsShortName(OperatingSystem os = OsUnknown);
    std::string traceback(std::string_view where, int level = 1, int maxDepth = 32);
    void addKeyListener(std::function<void(const InputEvent&)> /*listener*/) {}

    static DeviceType getDeviceTypeByName(std::string shortName);
    static OperatingSystem getOsByName(std::string shortName);

private:
    Device m_device{ Device(Desktop, Windows) };

    static std::unordered_map<DeviceType, std::string> m_deviceShortNames;
    static std::unordered_map<OperatingSystem, std::string> m_osShortNames;
};

extern Platform g_platform;
