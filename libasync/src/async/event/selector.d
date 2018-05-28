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

import std.socket;

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
        this._onDisConnected = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this._onSocketError  = onSocketError;

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
        _runing = true;

        while (_runing)
        {
            handleEvent();
        }
    }

    void stop()
    {
        _runing = false;
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

    void removeClient(int fd, int errno = 0)
    {
        unregister(fd);

        TcpClient client = _clients[fd];

        if (client !is null)
        {
            if ((errno != 0) && (_onSocketError !is null))
            {
                _onSocketError(fd, client._remoteAddress, formatSocketError(errno));
            }

            if (_onDisConnected !is null)
            {
                _onDisConnected(fd, client._remoteAddress);
            }

            client.close();
        }

        _clients.remove(fd);
    }

protected:

    void accept()
    {
        Socket socket;

        try
        {
            socket = _listener.accept();
        }
        catch (Exception e)
        {
            return;
        }

        TcpClient client = new TcpClient(this, socket);
        _clients[client.fd] = client;

        if (_onConnected !is null)
        {
            _onConnected(client);
        }

        register(client.fd, EventType.READ);
    }

    void read(int fd)
    {
        TcpClient client = _clients[fd];

        if (client !is null)
        {
            version (Linux)
            {
                if (client.read() == -1)
                {
                    removeClient(fd);
                }
            }
            else
            {
                client.read();
            }
        }
    }

    void write(int fd)
    {
        TcpClient client = _clients[fd];

        if (client !is null)
        {
            client.write();
        }
    }

protected:

    bool                 _isDisposed = false;
    TcpListener          _listener;
    int                  _eventHandle;

    void handleEvent();

private:

    bool                 _runing;
    Map!(int, TcpClient) _clients;

    OnConnected          _onConnected;
    OnDisConnected       _onDisConnected;
    OnSocketError        _onSocketError;

public:

    OnReceive            onReceive;
    OnSendCompleted      onSendCompleted;
}
