module async.event.selector;

import core.sync.mutex;

import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;

alias OnConnected     = void function(TcpClient);
alias OnDisConnected  = void function(int, string);
alias OnReceive       = void function(TcpClient, in ubyte[]);
alias OnSendCompleted = void function(int, string, in ubyte[], size_t);
alias OnSocketError   = void function(int, string, string);

enum EventType
{
    ACCEPT, READ, WRITE, READWRITE
}

abstract class Selector
{
    void startLoop();

    void stop();

    void dispose();

    bool register  (int fd, EventType et);
    bool reregister(int fd, EventType et);
    bool deregister(int fd);

    void removeClient(int fd);

protected:

    bool                 _isDisposed = false;
    TcpListener          _listener;

    Map!(int, TcpClient) _clients;

    OnConnected          _onConnected;

    Mutex                _lock;

public:

    bool           runing;

    OnDisConnected  onDisConnected;
    OnReceive       onReceive;
    OnSendCompleted onSendCompleted;
    OnSocketError   onSocketError;
}
