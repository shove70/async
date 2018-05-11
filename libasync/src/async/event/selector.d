module async.event.selector;

import async.net.tcplistener;
import async.net.tcpclient;

alias OnConnected    = void function(TcpClient);
alias OnDisConnected = void function(string);
alias OnReceive      = void function(TcpClient, in ubyte[]);
alias OnSocketError  = void function(string, string);

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
