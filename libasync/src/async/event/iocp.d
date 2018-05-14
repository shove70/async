module async.event.iocp;

debug import std.stdio;

version (Windows):

import core.sys.windows.windows;
import core.sync.mutex;
import core.memory;
import core.thread;

import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;

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
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        this._onConnected    = onConnected;
        this.onDisConnected  = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this.onSocketError   = onSocketError;

        _lock          = new Mutex;
        _clients       = new Map!(int, TcpClient);

        _handle        = CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0);
        _listener      = listener;
    }

    ~this()
    {
        dispose();
    }

    override bool register(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        CreateIoCompletionPort(cast(HANDLE)fd, _handle, 0, 0);
        return true;
    }

    override bool reregister(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        return true;
    }

    override bool deregister(int fd)
    {
        if (fd < 0)
        {
            return false;
        }

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
            register(client.fd, EventType.READ);
            _clients[client.fd] = client;

            if (_onConnected !is null)
            {
                _onConnected(client);
            }
            break;
        case IocpOperation.connect:
            TcpClient client = _clients[ev.fd];

            if (client !is null)
            {
                client.weakup(EventType.READ);
            }
            break;
        case IocpOperation.read:
            TcpClient client = _clients[ev.fd];

            if (client !is null)
            {
                client.weakup(EventType.READ);
            }
            break;
        case IocpOperation.write:

            break;
        case IocpOperation.event:

            break;
        case IocpOperation.close:
            TcpClient client = _clients[ev.fd];

            if (client !is null)
            {
                removeClient(ev.fd);
                client.close();
            }

            debug writeln("close event: ", ev.fd);
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
    }

    override void removeClient(int fd)
    {
        deregister(fd);

        TcpClient client = _clients[fd];
        if (client !is null)
        {
            _clients.remove(fd);
            new Thread( { client.termTask(); GC.free(&client); }).start();
        }
    }

private:

    HANDLE _handle;
}
