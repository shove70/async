module async.event.selector;

import core.sync.mutex;
import core.thread;

import std.socket;
import std.parallelism : totalCPUs;

import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;
import async.thread;
import async.codec;

alias OnConnected     = void function(TcpClient)                                            nothrow @trusted;
alias OnDisConnected  = void function(const int, string)                                    nothrow @trusted;
alias OnReceive       = void function(TcpClient, const scope ubyte[])                       nothrow @trusted;
alias OnSendCompleted = void function(const int, string, const scope ubyte[], const size_t) nothrow @trusted;
alias OnSocketError   = void function(const int, string, string)                            nothrow @trusted;

enum EventType
{
    ACCEPT, READ, WRITE, READWRITE
}

abstract class Selector
{
    this(TcpListener listener,
        OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted,
        OnSocketError onSocketError, Codec codec, const int workerThreadNum)
    {
        this._onConnected    = onConnected;
        this._onDisConnected = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this._onSocketError  = onSocketError;
        this._codec          = codec;

        _clients  = new Map!(int, TcpClient);
        _listener = listener;
        _workerThreadNum = (workerThreadNum <= 0) ? totalCPUs * 2 + 2 : workerThreadNum;

        version (Windows) { } else _acceptPool = new ThreadPool(1);
        workerPool = new ThreadPool(_workerThreadNum);
    }

    ~this()
    {
        dispose();
    }

    bool register  (const int fd, EventType et);
    bool reregister(const int fd, EventType et);
    bool unregister(const int fd);

    void initialize()
    {
        version (Windows)
        {
            foreach (i; 0 .. _workerThreadNum)
                workerPool.run!handleEvent(this);
        }
    }
    
    void runLoop()
    {
        version (Windows)
        {
            beginAccept(this);
        }
        else
        {
            handleEvent();
        }
    }
    
    void startLoop()
    {
        _runing = true;

        version (Windows)
        {
            foreach (i; 0 .. _workerThreadNum)
                workerPool.run!handleEvent(this);
        }

        while (_runing)
        {
            version (Windows)
            {
                beginAccept(this);
            }
            else
            {
                handleEvent();
            }
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

        version (Windows) { } else
        {
            static import core.sys.posix.unistd;
            core.sys.posix.unistd.close(_eventHandle);
        }
    }

    void removeClient(const int fd, const int err = 0)
    {
        unregister(fd);

        TcpClient client = _clients[fd];

        if (client !is null)
        {
            if ((err > 0) && (_onSocketError !is null))
            {
                _onSocketError(fd, client._remoteAddress, formatSocketError(err));
            }

            if (_onDisConnected !is null)
            {
                _onDisConnected(fd, client._remoteAddress);
            }

            client.close();
        }

        _clients.remove(fd);
    }

    version (Windows)
    {
        void iocp_send(const int fd, const scope ubyte[] data);
        void iocp_receive(const int fd);
    }

    @property Codec codec()
    {
        return this._codec;
    }

protected:

    version (Windows) { } else void accept()
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

        try
        {
            client.setKeepAlive(600, 10);
        }
        catch (Exception e)
        {
        }

        selector._clients[client.fd] = client;

        if (selector._onConnected !is null)
        {
            selector._onConnected(client);
        }

        selector.register(client.fd, EventType.READ);

        version (Windows) selector.iocp_receive(client.fd);
    }

    version (Windows)
    {
        void read(const int fd, const scope ubyte[] data)
        {
            TcpClient client = _clients[fd];

            if ((client !is null) && (onReceive !is null))
            {
                onReceive(client, data);
            }
        }
    }
    else
    {
        void read(const int fd)
        {
            TcpClient client = _clients[fd];

            if (client !is null)
            {
                client.weakup(EventType.READ);
            }
        }
    }

    version (Windows) { } else void write(const int fd)
    {
        TcpClient client = _clients[fd];

        if (client !is null)
        {
            client.weakup(EventType.WRITE);
        }
    }

    bool                 _isDisposed = false;
    TcpListener          _listener;
    bool                 _runing;
    int                  _workerThreadNum;

    version (Windows)
    {
        import core.sys.windows.basetsd : HANDLE;
        HANDLE _eventHandle;

        static void handleEvent(Selector selector)
        {
            import async.event.iocp : Iocp;
            Iocp.handleEvent(selector);
        }
    }
    else
    {
        int _eventHandle;

        void handleEvent();
    }

private:

    ThreadPool           _acceptPool;
    Map!(int, TcpClient) _clients;

    OnConnected          _onConnected;
    OnDisConnected       _onDisConnected;
    OnSocketError        _onSocketError;

    Codec                _codec;

public:

    ThreadPool           workerPool;

    OnReceive            onReceive;
    OnSendCompleted      onSendCompleted;
}
