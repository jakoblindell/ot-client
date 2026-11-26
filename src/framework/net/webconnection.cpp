/*
 * Copyright (c) 2024 OTArchive <https://otarchive.com>
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
#ifdef __EMSCRIPTEN__

#include "webconnection.h"

#include <framework/core/application.h>

#include <utility>
#include <asio/read.hpp>
#include <asio/read_until.hpp>
#include <framework/core/eventdispatcher.h>

#include <emscripten/threading.h>

std::list<std::shared_ptr<asio::streambuf>> WebConnection::m_outputStreams;
WebConnection::WebConnection()
{
}

WebConnection::~WebConnection()
{
#ifndef NDEBUG
    assert(!g_app.isTerminated());
#endif
    close();
}

void WebConnection::poll()
{
}

void WebConnection::terminate()
{
    emscripten_websocket_deinitialize();
}

void WebConnection::close()
{
    if (!m_connected && !m_connecting)
        return;

    m_connecting = false;
    m_connected = false;
    m_connectCallback = nullptr;
    m_errorCallback = nullptr;
    m_recvCallback = nullptr;

    // Only this socket: the login and game connections, and the HTTP
    // WebSockets, can be open at the same time. Deleting it also removes
    // its handlers, so none of them runs after this, and what they queued
    // before is dropped (receive()).
    if (m_websocket > 0) {
        emscripten_websocket_close(m_websocket, 1000, "");
        emscripten_websocket_delete(m_websocket);
    }
    m_websocket = 0;

    m_inputStream.consume(m_inputStream.size());
}

void WebConnection::reportClose()
{
    // As on desktop: the server closing after what it sent is a normal end
    // (eof); closing before sending anything is a failed connection
    std::error_code error = asio::error::timed_out;
    if (m_received)
        error = asio::error::eof;

    // The callback may release this connection: nothing here after it
    const ErrorCallback callback = m_errorCallback;
    close();
    if (callback)
        callback(error);
}

void WebConnection::connect(const std::string_view host, uint16_t port, const std::function<void()>& connectCallback, bool /*gameWorld*/)
{
    m_connected = false;
    m_connecting = true;
    m_remoteClosed = false;
    m_received = false;
    m_connectCallback = connectCallback;

    std::string ip = std::string(host);
    ip.length() == 0 ? ip = "localhost" : ip;

#ifdef NDEBUG
    const std::string prefix = "wss://";
#else
    const std::string prefix = "ws://";
#endif

    m_pthread = pthread_self();

    const std::string url = prefix + ip + ":" + std::to_string(port);
    EmscriptenWebSocketCreateAttributes attributes =
    {
        url.c_str(),
        "binary",
        EM_FALSE // if the webscocket should be created in the main thread. Currently not implemented by emscripten so this does nothing
    };

    m_websocket = emscripten_websocket_new(&attributes);

    if (m_websocket < 1) {
        if (m_errorCallback)
            m_errorCallback(asio::error::network_unreachable);

        close();
        return;
    }

    emscripten_websocket_set_onopen_callback(m_websocket, this, ([](int /*eventType*/, const EmscriptenWebSocketOpenEvent* event, void* userData) -> EM_BOOL {
        dispatch(reinterpret_cast<void*>(runOnOpen), userData, event->socket);
        return EM_TRUE;
    }));

    emscripten_websocket_set_onerror_callback(m_websocket, this, ([](int /*eventType*/, const EmscriptenWebSocketErrorEvent* event, void* userData) -> EM_BOOL {
        dispatch(reinterpret_cast<void*>(runOnSocketClosed), userData, event->socket);
        return EM_TRUE;
    }));

    emscripten_websocket_set_onclose_callback(m_websocket, this, ([](int /*eventType*/, const EmscriptenWebSocketCloseEvent* event, void* userData) -> EM_BOOL {
        // Not closed here: what the server sent right before closing (such
        // as why it ended the session) is still waiting to be read. read()
        // reports the close once the received data runs out.
        dispatch(reinterpret_cast<void*>(runOnSocketClosed), userData, event->socket);
        return EM_TRUE;
    }));

    emscripten_websocket_set_onmessage_callback(m_websocket, this, ([](int /*eventType*/, const EmscriptenWebSocketMessageEvent* event, void* userData) -> EM_BOOL {
        if (event->numBytes == 0 || event->isText)
            return EM_TRUE;

        // the browser frees the data when this returns
        dispatch(reinterpret_cast<void*>(runOnMessage), userData, event->socket, event->data, event->numBytes);
        return EM_TRUE;
    }));
}

bool WebConnection::sendPacket(uint8_t* buffer, uint16_t size)
{
    if (m_websocket < 1) {
        close();
        return false;
    }

    const EMSCRIPTEN_RESULT result = emscripten_websocket_send_binary(m_websocket, buffer, size);
    return (result == EMSCRIPTEN_RESULT_SUCCESS);
}

void WebConnection::write(uint8_t* buffer, size_t size)
{
    if (!m_connected)
        return;

    if (!m_outputStream) {
        if (!m_outputStreams.empty()) {
            m_outputStream = m_outputStreams.front();
            m_outputStreams.pop_front();
        } else
            m_outputStream = std::make_shared<asio::streambuf>();
    }

    std::ostream os(m_outputStream.get());
    os.write((const char*)buffer, size);
    os.flush();

    internal_write();
}

void WebConnection::internal_write()
{
    if (!m_connected)
        return;

    std::shared_ptr<asio::streambuf> outputStream = m_outputStream;
    m_outputStream = nullptr;

    const auto* data = asio::buffer_cast<const uint8_t*>(outputStream->data());
    bool write = sendPacket((uint8_t*)data, outputStream->size());
    if (write) {
        onWrite(outputStream);
    }
}

void WebConnection::read(const uint16_t size, const RecvCallback& callback, int tries)
{
    if (!m_connected)
        return;

    m_recvCallback = callback;

    if (tries > 1000) {
        onTimeout();
        return;
    }

    auto retry = [capture0 = asWebConnection(), size, callback, tries] { capture0->read(size, callback, tries + 1); };

    if (tries == 0) {
        g_dispatcher.addEvent(std::move(retry));
        return;
    }

    if (m_inputStream.size() < size) {
        if (m_remoteClosed) {
            reportClose();
            return;
        }
        emscripten_thread_sleep(10);
        g_dispatcher.addEvent(std::move(retry));
        return;
    }

    onRecv(size);
}

void WebConnection::dispatch(void* handler, void* userData, const EMSCRIPTEN_WEBSOCKET_T socket, const uint8_t* data, const uint32_t size)
{
    // Read the connection before allocating anything: waiting on the
    // allocator's lock can let this thread run close()'s socket delete, and the
    // connection may be released after that. Only locals from here on.
    auto* const webConnection = static_cast<WebConnection*>(userData);
    const pthread_t thread = webConnection->m_pthread;
    std::weak_ptr<LuaObject> connection = webConnection->weak_from_this();

    auto* const event = new SocketEvent{ std::move(connection), socket, std::vector<uint8_t>(data, data + size) };
    emscripten_dispatch_to_thread(thread, EM_FUNC_SIG_VI, handler, nullptr, event);
}

WebConnectionPtr WebConnection::receive(const SocketEvent& event)
{
    // close() clears the socket: what it sent before that is not for the
    // protocol any more
    auto webConnection = std::static_pointer_cast<WebConnection>(event.connection.lock());
    if (!webConnection || webConnection->m_websocket < 1 || webConnection->m_websocket != event.socket)
        return nullptr;
    return webConnection;
}

void WebConnection::runOnOpen(SocketEvent* event)
{
    const std::unique_ptr<SocketEvent> owned(event);
    const auto webConnection = receive(*owned);
    if (!webConnection || !webConnection->m_connecting)
        return;

    webConnection->m_connected = true;
    webConnection->m_connecting = false;

    // The callback may close or release this connection
    const std::function<void()> callback = webConnection->m_connectCallback;
    if (callback)
        callback();
}

void WebConnection::runOnMessage(SocketEvent* event)
{
    const std::unique_ptr<SocketEvent> owned(event);
    const auto webConnection = receive(*owned);
    if (!webConnection)
        return;

    std::ostream os(&webConnection->m_inputStream);
    os.write(reinterpret_cast<const char*>(owned->data.data()), owned->data.size());
    os.flush();
}

void WebConnection::runOnSocketClosed(SocketEvent* event)
{
    const std::unique_ptr<SocketEvent> owned(event);
    const auto webConnection = receive(*owned);
    // the browser reports a failure with an error and then a close event
    if (!webConnection || webConnection->m_remoteClosed)
        return;

    webConnection->m_remoteClosed = true;

    // Once open, read() reports it after the data received before it
    if (!webConnection->m_connected)
        webConnection->reportClose();
}

void WebConnection::onWrite(const std::shared_ptr<asio::streambuf>& outputStream)
{
    // free output stream and store for using it again later
    outputStream->consume(outputStream->size());
    m_outputStreams.emplace_back(outputStream);
}

void WebConnection::onRecv(const uint16_t recvSize)
{
    m_activityTimer.restart();
    m_received = true;

    if (m_connected) {
        if (m_recvCallback) {
            const auto* header = asio::buffer_cast<const char*>(m_inputStream.data());
            m_recvCallback((uint8_t*)header, recvSize);
        }
    }
    m_inputStream.consume(recvSize);
}

void WebConnection::onTimeout()
{
    if (m_errorCallback)
        m_errorCallback(asio::error::timed_out);

    if (m_connected || m_connecting)
        close();
}

int WebConnection::getIp()
{
    g_logger.error("Getting remote ip");
    return 0;
}

#endif