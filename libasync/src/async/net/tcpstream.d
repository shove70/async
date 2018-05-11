module async.net.tcpstream;

import std.socket;

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

protected:

    Socket _socket;

    bool _reusePort = false;
    bool _blocking  = false;
}