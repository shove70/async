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
import std.parallelism;

import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;
import async.thread;

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
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError, int workerThreadNum)
    {
        this._onConnected    = onConnected;
        this._onDisConnected = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this._onSocketError  = onSocketError;

        _clients  = new Map!(int, TcpClient);
        _listener = listener;

        if (workerThreadNum <= 0)
        {
            workerThreadNum = totalCPUs;
        }

        _acceptPool = new ThreadPool(1);
        workerPool  = new ThreadPool(workerThreadNum);
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
        _acceptPool.run!beginAccept(this);
    }

    static void beginAccept(Selector selector)
    {
        Socket socket;

        try
        {
            socket = selector._listener.accept();
        }
        catch (Exception e)
        {
            return;
        }

        TcpClient client = new TcpClient(selector, socket);
        selector._clients[client.fd] = client;

        if (selector._onConnected !is null)
        {
            selector._onConnected(client);
        }

        selector.register(client.fd, EventType.READ);
    }

    void read(int fd)
    {
        TcpClient client = _clients[fd];

        if (client !is null)
        {
            client.weakup(EventType.READ);
        }
    }

    void write(int fd)
    {
        TcpClient client = _clients[fd];

        if (client !is null)
        {
            client.weakup(EventType.WRITE);
        }
    }

protected:

    bool                 _isDisposed = false;
    TcpListener          _listener;
    int                  _eventHandle;

    void handleEvent();

private:

    ThreadPool           _acceptPool;
    bool                 _runing;
    Map!(int, TcpClient) _clients;

    OnConnected          _onConnected;
    OnDisConnected       _onDisConnected;
    OnSocketError        _onSocketError;

public:

    ThreadPool           workerPool;

    OnReceive            onReceive;
    OnSendCompleted      onSendCompleted;
}
