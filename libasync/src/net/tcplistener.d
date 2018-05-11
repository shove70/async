module async.net.tcplistener;

import std.socket;

import async.net.tcpstream;

class TcpListener : TcpStream
{
    this()
    {
        super(new TcpSocket());
        reusePort = true;
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
