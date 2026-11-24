/*
 * Copyright (c) 2010-2022 OTClient <https://github.com/edubart/otclient>
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

#ifdef __EMSCRIPTEN__

#include <atomic>
#include "declarations.h"
#include <framework/luaengine/luaobject.h>
#include <emscripten/websocket.h>

class WebConnection : public LuaObject
{
    using ErrorCallback = std::function<void(const std::error_code&)>;
    using RecvCallback = std::function<void(uint8_t*, uint16_t)>;

    enum
    {
        READ_TIMEOUT = 30,
        WRITE_TIMEOUT = 30,
        SEND_BUFFER_SIZE = 65536,
        RECV_BUFFER_SIZE = 65536
    };

public:
    WebConnection();
    ~WebConnection() override;

    static void poll();
    static void terminate();

    void connect(const std::string_view host, uint16_t port, const std::function<void()>& connectCallback, bool gameWorld);
    void close();

    void write(uint8_t* buffer, size_t size);
    void read(const uint16_t size, const RecvCallback& callback, int tries = 0);

    void setErrorCallback(const ErrorCallback& errorCallback) { m_errorCallback = errorCallback; }

    int getIp();
    bool isConnecting() const { return m_connecting; }
    bool isConnected() const { return m_connected; }
    ticks_t getElapsedTicksSinceLastRead() const { return m_connected ? m_activityTimer.elapsed_millis() : -1; }

    WebConnectionPtr asWebConnection() { return static_self_cast<WebConnection>(); }

protected:
    bool sendPacket(uint8_t* buffer, uint16_t size);

    void internal_write();
    void onWrite(const std::shared_ptr<asio::streambuf>&
                 outputStream);
    void onRecv(const uint16_t recvSize);
    void onTimeout();
    // Client thread: tells the protocol the connection ended and closes it
    void reportClose();
    // Browser thread: the socket failed or the server closed it
    void onSocketClosed();

    // Take ownership of what was queued for the client thread: the member
    // callbacks may be cleared by close(), and the connection released,
    // before the dispatched call runs there.
    static void runOnConnectCallback(std::function<void()>* callback);
    static void runOnSocketClosed(std::weak_ptr<LuaObject>* connection);

    std::function<void()> m_connectCallback;
    ErrorCallback m_errorCallback;
    RecvCallback m_recvCallback;

    EMSCRIPTEN_WEBSOCKET_T m_websocket = 0;
    pthread_t m_pthread;

    static std::list<std::shared_ptr<asio::streambuf>> m_outputStreams;
    std::shared_ptr<asio::streambuf> m_outputStream;
    bool m_connected{ false };
    bool m_connecting{ false };
    // The server closed the socket, or it failed; set on the browser's
    // thread, the close is reported once the data received before it has
    // been read
    std::atomic<bool> m_remoteClosed{ false };
    // Data came from the server (client thread)
    bool m_received{ false };
    stdext::timer m_activityTimer;

    asio::streambuf m_inputStream;
};
#endif
