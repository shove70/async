module async.net.tcplistener;

import std.socket;

import async.net.tcpstream;

class TcpListener : TcpStream
{
    this()
    {
        super(new TcpSocket());
        reusePort = true;

        Linger optLinger;
        optLinger.on   = 1;
        optLinger.time = 0;
        setOption(SocketOptionLevel.SOCKET, SocketOption.LINGER, optLinger);
//        version (linux)
//        {
//            setOption(SocketOptionLevel.TCP, cast(SocketOption) 23, 1024);
//        }
    }

    void bind(string host, ushort port)
    {
        _socket.bind(new InternetAddress(host, port));
    }

    void bind(InternetAddress address)
    {
        _socket.bind(address);
    }

    void listen(int backlog = 10)
    {
        _socket.listen(backlog);
    }

    Socket accept()
    {
        return _socket.accept();
    }

    void close()
    {
        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();
    }
}
