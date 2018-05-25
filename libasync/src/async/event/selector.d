module async.event.selector;

import core.sync.mutex;
import core.thread;
version (Windows)
{
}
else
{
    import core.sys.posix.unistd;
}

import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;

alias OnConnected     = void function(TcpClient);                       nothrow @trusted
alias OnDisConnected  = void function(int, string);                     nothrow @trusted
alias OnReceive       = void function(TcpClient, in ubyte[]);           nothrow @trusted
alias OnSendCompleted = void function(int, string, in ubyte[], size_t); nothrow @trusted
alias OnSocketError   = void function(int, string, string);             nothrow @trusted

enum EventType
{
    ACCEPT, READ, WRITE, READWRITE
}

abstract class Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        this._onConnected    = onConnected;
        this.onDisConnected  = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this.onSocketError   = onSocketError;

        _clients  = new Map!(int, TcpClient);
        _listener = listener;
    }

    ~this()
    {
        dispose();
    }

    bool register  (int fd, EventType et);
    bool reregister(int fd, EventType et);
    bool unregister(int fd);

    void startLoop()
    {
        runing = true;

        while (runing)
        {
            handleEvent();
        }
    }

    void stop()
    {
        runing = false;
    }

    void dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;

        _clients.lock();
        foreach (ref c; _clients)
        {
            unregister(c.fd);

            if (c.isAlive)
            {
                c.close();
            }
        }
        _clients.unlock();

        _clients.clear();

        unregister(_listener.fd);
        _listener.close();

        version (Windows)
        {
        }
        else
        {
            core.sys.posix.unistd.close(_eventHandle);
        }
    }

    void removeClient(TcpClient client, int errno = 0)
    {
        unregister(client.fd);
        _clients.remove(client.fd);
        client.close(errno);
    }

protected:

    bool                 _isDisposed = false;
    TcpListener          _listener;
    int                  _eventHandle;

    Map!(int, TcpClient) _clients;

    OnConnected          _onConnected;

    void handleEvent();

public:

    bool                 runing;

    OnDisConnected       onDisConnected;
    OnReceive            onReceive;
    OnSendCompleted      onSendCompleted;
    OnSocketError        onSocketError;
}
