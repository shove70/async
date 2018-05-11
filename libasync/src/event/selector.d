module async.event.selector;

import async.net.tcplistener;
import async.net.tcpclient;

alias OnConnected    = void delegate(TcpClient);
alias OnDisConnected = void delegate(TcpClient);
alias OnReceive      = void delegate(TcpClient, in ubyte[]);
alias OnSocketError  = void delegate(TcpClient, string);

abstract class Selector
{
    void startLoop();

    void handleEvent();

    void stop();

    void dispose();

    void removeClient(int fd);

protected:

    bool           _isDisposed = false;
    TcpListener    _listener;

    TcpClient[int] _clients;

    OnConnected    onConnected;

public:

    bool           runing;

    OnDisConnected onDisConnected;
    OnReceive      onReceive;
    OnSocketError  onSocketError;
}
