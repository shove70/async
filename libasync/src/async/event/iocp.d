module async.event.iocp;

debug import std.stdio;

version (Windows):

import core.sys.windows.windows;
import core.sync.mutex;
import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

alias LoopSelector = Iocp;

enum IocpOperation
{
    accept,
    connect,
    read,
    write,
    event,
    close
}

struct IocpContext
{
    OVERLAPPED    overlapped;
    IocpOperation operation;
    int           fd;
}

class Iocp : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        this._onConnected   = onConnected;
        this.onDisConnected = onDisConnected;
        this.onReceive      = onReceive;
        this.onSocketError  = onSocketError;

        _lock          = new Mutex;
        _handle        = CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0);
        _listener      = listener;
    }

    ~this()
    {
        dispose();
    }

    private bool register(int fd)
    {
        CreateIoCompletionPort(cast(HANDLE)fd, _handle, 0, 0);
        return true;
    }

    private bool reregister(int fd)
    {
       return true;
    }

    private bool deregister(int fd)
    {
        return true;
    }

    override void startLoop()
    {
        runing = true;

        while (runing)
        {
            handleEvent();
        }
    }

    private void handleEvent()
    {
        auto timeout  = 0;
        OVERLAPPED*   overlapped;
        ULONG_PTR key = 0;
        DWORD bytes   = 0;

        const int ret = GetQueuedCompletionStatus(_handle, &bytes, &key, &overlapped, timeout);

        if (ret == 0)
        {
            const auto error = GetLastError();
            if (error == WAIT_TIMEOUT) // || error == ERROR_OPERATION_ABORTED
            {
                return;
            }
        }

        if (overlapped is null)
        {
            debug writeln("ev is null.");

            return;
        }

        auto ev = cast(IocpContext*) overlapped;

        switch (ev.operation)
        {
        case IocpOperation.accept:
            TcpClient client = new TcpClient(this, _listener.accept());
            register(client.fd);

            synchronized (_lock) _clients[client.fd] = client;
            _onConnected(client);
            break;
        case IocpOperation.connect:
            _clients[ev.fd].weakup();
            break;
        case IocpOperation.read:
            _clients[ev.fd].weakup();
            break;
        case IocpOperation.write:
            
            break;
        case IocpOperation.event:
            
            break;
        case IocpOperation.close:
            debug writeln("close.");
            break;
        default:
            debug writefln("unsupported operation type: ", ev.operation);
            break;
        }
    }

    override void stop()
    {
        runing = false;
    }

    override void dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;
        foreach (c; _clients)
        {
            deregister(c.fd);
        }

        deregister(_listener.fd);
        _listener.close();

        //core.sys.posix.unistd.close(_fd);
    }

    override void removeClient(int fd)
    {
        deregister(fd);
        _clients.remove(fd);
    }

private:

    HANDLE _handle;
}
