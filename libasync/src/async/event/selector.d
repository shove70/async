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
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        this._onConnected    = onConnected;
        this.onDisConnected  = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this.onSocketError   = onSocketError;

        _lock          = new Mutex;
        _clients       = new Map!(int, TcpClient);
        _listener      = listener;
    }

    ~this()
    {
        dispose();
    }

    bool register  (int fd, EventType et);
    bool reregister(int fd, EventType et);
    bool deregister(int fd);

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
            deregister(c.fd);

            if (c.isAlive)
            {
                c.close();
            }
        }
        _clients.unlock();

        _clients.clear();

        deregister(_listener.fd);
        _listener.close();

        version (Windows)
        {
        }
        else
        {
            core.sys.posix.unistd.close(_eventHandle);
        }
    }

    void removeClient(int fd)
    {
        deregister(fd);

        TcpClient client = _clients[fd];
        if (client !is null)
        {
            _clients.remove(fd);
            new Thread( { client.termTask(); }).start();
        }
    }

protected:

    bool                 _isDisposed = false;
    TcpListener          _listener;
    int                  _eventHandle;

    Map!(int, TcpClient) _clients;

    OnConnected          _onConnected;

    Mutex                _lock;

    void handleEvent();

public:

    bool            runing;

    OnDisConnected  onDisConnected;
    OnReceive       onReceive;
    OnSendCompleted onSendCompleted;
    OnSocketError   onSocketError;
}
