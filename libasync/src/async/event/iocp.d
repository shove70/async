module async.event.iocp;

debug import std.stdio;

version (Windows):

pragma(lib, "Ws2_32");

import core.stdc.errno;
import core.sys.windows.windows;
import core.sys.windows.winsock2;
import core.sys.windows.mswsock;
import core.sync.mutex;
import core.thread;

import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;
import async.pool;

alias LoopSelector = Iocp;

class Iocp : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError);

        _eventHandle = CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, 0);
        register(_listener.fd, EventType.ACCEPT);
    }

    override bool register(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        auto ret = CreateIoCompletionPort(cast(HANDLE)fd, _eventHandle, cast(ULONG_PTR)fd, 0);
        return !(!ret);
    }

    override bool reregister(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        return true;
    }

    override bool unregister(int fd)
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
//            Socket socket = _listener.accept();
//            TcpClient client = new TcpClient(this, socket);
//            register(client.fd, EventType.READ);
//            _clients[client.fd] = client;
            handleEvent();
        }
    }

    override protected void handleEvent()
    {
        DWORD bytes   = 0;
        ULONG_PTR key = 0;
        OVERLAPPED*   overlapped;
        auto timeout  = 1000;

        const int ret = GetQueuedCompletionStatus(_eventHandle, &bytes, &key, &overlapped, timeout);

        if (overlapped is null)
        {
            debug writeln("Event is null.");

            return;
        }

        if (ret == 0)
        {
            const auto error = GetLastError();
            if (error == WAIT_TIMEOUT) // || error == ERROR_OPERATION_ABORTED
            {
                return;
            }

            auto ev = cast(IocpContext*)overlapped;

            if (ev && ev.fd)
            {
                TcpClient client = _clients[ev.fd];

                if (client !is null)
                {
                    removeClient(ev.fd);
                }

                debug writeln("Close event: ", ev.fd);

                return;
            }
        }

        auto ev = cast(IocpContext*)overlapped;
        switch (ev.operation)
        {
        case IocpOperation.accept:
            Socket socket;

            try
            {
                socket = _listener.accept();
            }
            catch (Exception e)
            {
                break;
            }

            TcpClient client = ThreadPool.instance.take(this, socket);
            _clients[client.fd] = client;

            if (_onConnected !is null)
            {
                _onConnected(client);
            }

            register(client.fd, EventType.READ);

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
                removeClient(ev.fd, errno);
            }

            debug writeln("Close event: ", ev.fd);

            break;
        default:
            debug writefln("Unsupported operation type: ", ev.operation);

            break;
        }
    }

    shared static this()
    {
        WSADATA wsaData;
        int iResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
    
        SOCKET ListenSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        scope (exit)
            closesocket(ListenSocket);
        GUID guid;
//        mixin(GET_FUNC_POINTER("WSAID_ACCEPTEX", "AcceptEx"));
//        mixin(GET_FUNC_POINTER("WSAID_CONNECTEX", "ConnectEx"));
    }
    
    shared static ~this()
    {
        WSACleanup();
    }

private:

    HANDLE _eventHandle;
}

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
