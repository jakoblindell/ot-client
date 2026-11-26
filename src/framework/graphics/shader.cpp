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

#include "shader.h"

#include "graphics.h"
#include "framework/core/eventdispatcher.h"
#include "framework/core/graphicalapplication.h"
#include "framework/core/resourcemanager.h"

Shader::Shader(ShaderType shaderType) : m_shaderId(glCreateShader(static_cast<GLenum>(shaderType))), m_shaderType(shaderType),
    m_glGeneration(g_graphics.getContextGeneration())
{
    if (!m_shaderId)
        g_logger.fatal("Unable to create GL shader");
}

Shader::~Shader()
{
#ifndef NDEBUG
    assert(!g_app.isTerminated());
#endif
    if (g_graphics.ok()) {
        g_mainDispatcher.addEvent([id = m_shaderId] {
            glDeleteShader(id);
        });
    }
}

bool Shader::compileSourceCode(const std::string_view sourceCode)
{
#ifdef OPENGL_ES
    static constexpr std::string_view qualifierDefines =
        "#ifndef GL_FRAGMENT_PRECISION_HIGH\n"
        "#define highp mediump\n"
        "#endif\n"
        "precision highp float;\n";
#else
    static constexpr std::string_view qualifierDefines =
        "#define lowp\n"
        "#define mediump\n"
        "#define highp\n";
#endif

    m_source = std::string{ qualifierDefines };
    m_source.append(sourceCode);
    return compile();
}

bool Shader::compile()
{
    const char* c_source = m_source.data();
    glShaderSource(m_shaderId, 1, &c_source, nullptr);
    glCompileShader(m_shaderId);

    int res = GL_FALSE;
    glGetShaderiv(m_shaderId, GL_COMPILE_STATUS, &res);
    return (res == GL_TRUE);
}

void Shader::restore(const uint32_t generation)
{
    if (m_glGeneration >= generation)
        return;

    // (the old name means nothing in the new context)
    m_glGeneration = generation;
    m_shaderId = glCreateShader(static_cast<GLenum>(m_shaderType));
    if (!m_source.empty() && !compile())
        g_logger.error("Failed to compile shader again: {}", log());
}

bool Shader::compileSourceFile(const std::string_view sourceFile)
{
    try {
        const auto& sourceCode = g_resources.readFileContents(sourceFile.data());
        return compileSourceCode(sourceCode);
    } catch (const stdext::exception& e) {
        g_logger.error("Unable to load shader source form file '{}': {}", sourceFile, e.what());
    }
    return false;
}

std::string Shader::log() const
{
    std::string infoLog;
    int infoLogLength = 0;
    glGetShaderiv(m_shaderId, GL_INFO_LOG_LENGTH, &infoLogLength);
    if (infoLogLength > 1) {
        std::vector<char> buf(infoLogLength);
        glGetShaderInfoLog(m_shaderId, infoLogLength - 1, nullptr, &buf[0]);
        infoLog = &buf[0];
    }
    return infoLog;
}