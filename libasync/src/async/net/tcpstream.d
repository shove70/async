module async.net.tcpstream;

import std.socket;
import std.datetime;

abstract class TcpStream
{
    this(Socket socket)
    {
        _socket          = socket;
        _socket.blocking = false;
    }

    @property bool reusePort()
    {
        return _reusePort;
    }

    @property bool reusePort(bool enabled)
    {
        _reusePort = enabled;

        _socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, _reusePort);

        version (Posix)
        {
            import core.sys.posix.sys.socket;
            _socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_REUSEPORT, _reusePort);
        }

        version (Windows)
        {
            if (!_reusePort)
            {
                import core.sys.windows.winsock2;
                _socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_EXCLUSIVEADDRUSE, true);
            }
        }

        return _reusePort;
    }

    @property bool blocking()
    {
        return _blocking;
    }

    @property bool blocking(bool enabled)
    {
        _blocking        = enabled;
        _socket.blocking = _blocking;

        return _blocking;
    }

    @property int fd()
    {
        return _socket.handle();
    }

    @property Address remoteAddress()
    {
        return _socket.remoteAddress();
    }

    @property Address localAddress()
    {
        return _socket.localAddress();
    }

    @property bool isAlive()
    {
        return _socket.isAlive();
    }

    int getOption(SocketOptionLevel level, SocketOption option, void[] result) @trusted
    {
        return _socket.getOption(level, option, result);
    }

    int getOption(SocketOptionLevel level, SocketOption option, out int result) @trusted
    {
        return _socket.getOption(level, option, result);
    }

    int getOption(SocketOptionLevel level, SocketOption option, out Linger result) @trusted
    {
        return _socket.getOption(level, option, result);
    }

    void getOption(SocketOptionLevel level, SocketOption option, out Duration result) @trusted
    {
        return _socket.getOption(level, option, result);
    }

    void setOption(SocketOptionLevel level, SocketOption option, void[] value) @trusted
    {
        _socket.setOption(level, option, value);
    }

    void setOption(SocketOptionLevel level, SocketOption option, int value) @trusted
    {
        _socket.setOption(level, option, value);
    }

    void setOption(SocketOptionLevel level, SocketOption option, Linger value) @trusted
    {
        _socket.setOption(level, option, value);
    }

    void setOption(SocketOptionLevel level, SocketOption option, Duration value) @trusted
    {
        _socket.setOption(level, option, value);
    }

protected:

    Socket _socket;

    bool _reusePort = false;
    bool _blocking  = false;
}