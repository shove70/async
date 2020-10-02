module async.event.iocp;

debug import std.stdio;

version (Windows):

import core.stdc.errno;

import core.sys.windows.windows;
import core.sys.windows.winsock2;
import core.sys.windows.mswsock;

import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;
import async.codec;

alias LoopSelector = Iocp;

class Iocp : Selector
{
    this(TcpListener listener,
        OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted,
        OnSocketError onSocketError, Codec codec, const int workerThreadNum)
    {
        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError, codec, workerThreadNum);

        _eventHandle = CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, _workerThreadNum);
    }

    override bool register(const int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        return (CreateIoCompletionPort(cast(HANDLE)fd, _eventHandle, cast(size_t)(cast(void*) fd), 0) != null);
    }

    override bool reregister(const int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        return true;
    }

    override bool unregister(const int fd)
    {
        if (fd < 0)
        {
            return false;
        }

        return true;
    }

    static void handleEvent(Selector selector)
    {
        OVERLAPPED* overlapped;
        IocpContext* context;
        WSABUF buffSend;
        uint dwSendNumBytes;
        uint dwFlags;
        DWORD bytes;
        int ret;

        while (selector._runing)
        {
            ULONG_PTR key;
            bytes = 0;
            ret = GetQueuedCompletionStatus(selector._eventHandle, &bytes, &key, &overlapped, INFINITE);
            context = cast(IocpContext*) overlapped;

            if (ret == 0)
            {
                immutable err = GetLastError();
                if (err == WAIT_TIMEOUT)
                    continue;

                if (context !is null)
                {
                    selector.removeClient(context.fd, err);
                    debug writeln("Close event: ", context.fd);
                }

                continue;
            }

            if (bytes == 0)
            {
                selector.removeClient(context.fd, 0);
                debug writeln("Close event: ", context.fd);

                continue;
            }

            if (context.operation == IocpOperation.read) // A read operation complete.
            {
                selector.read(context.fd, cast(ubyte[]) context.wsabuf.buf[0..bytes]);

                // Read operation completed, so post Read operation for remainder (if exists).
                selector.iocp_receive(context.fd);
            }
            else if (context.operation == IocpOperation.write) // A write operation complete.
            {
                context.nSentBytes += bytes;
                dwFlags = 0;

                if (context.nSentBytes < context.nTotalBytes)
                {
                    // A Write operation has not completed yet, so post another.
                    // Write operation to post remaining data.
                    context.operation = IocpOperation.write;
                    buffSend.buf = context.buffer.ptr + context.nSentBytes;
                    buffSend.len = context.nTotalBytes - context.nSentBytes;
                    ret = WSASend(cast(SOCKET) context.fd, &buffSend, 1, &dwSendNumBytes, dwFlags, &(context.overlapped), null);

                    if (ret == SOCKET_ERROR)
                    {
                        immutable err = WSAGetLastError();

                        if (err != ERROR_IO_PENDING)
                        {
                            selector.removeClient(context.fd, err);
                            debug writeln("Close event: ", context.fd);

                            continue;
                        }
                    }
                }
                else
                {
                    // Write operation completed, so post Read operation.
                    selector.iocp_receive(context.fd);
                }
            }
        }
    }

    override void iocp_receive(const int fd)
    {
        IocpContext* context = new IocpContext();
        context.operation   = IocpOperation.read;
        context.nTotalBytes = 0;
        context.nSentBytes  = 0;
        context.wsabuf.buf  = context.buffer.ptr;
        context.wsabuf.len  = context.buffer.sizeof;
        context.fd          = fd;
        uint dwRecvNumBytes = 0;
        uint dwFlags = 0;
        int ret = WSARecv(cast(HANDLE) fd, &context.wsabuf, 1, &dwRecvNumBytes, &dwFlags, &context.overlapped, null);

        if (ret == SOCKET_ERROR)
        {
            immutable err = WSAGetLastError();

            if (err != ERROR_IO_PENDING)
            {
                removeClient(fd, err);
                debug writeln("Close event: ", fd);
            }
        }
    }

    override void iocp_send(const int fd, const scope ubyte[] data)
    {
        size_t pos;
        while (pos < data.length)
        {
            size_t len = data.length - pos;
            len = ((len > BUFFERSIZE) ? BUFFERSIZE : len);

            IocpContext* context = new IocpContext();
            context.operation  = IocpOperation.write;
            context.buffer[0..len] = cast(char[]) data[pos..pos + len];
            context.nTotalBytes = cast(int) len;
            context.nSentBytes  = 0;
            context.wsabuf.buf  = context.buffer.ptr;
            context.wsabuf.len  = cast(int) len;
            context.fd          = fd;
            uint dwSendNumBytes = 0;
            immutable uint dwFlags = 0;
            int ret = WSASend(cast(HANDLE) fd, &context.wsabuf, 1, &dwSendNumBytes, dwFlags, &context.overlapped, null);

            if (ret == SOCKET_ERROR)
            {
                immutable err = WSAGetLastError();

                if (err != ERROR_IO_PENDING)
                {
                    removeClient(fd, err);
                    debug writeln("Close event: ", fd);

                    return;
                }
            }

            pos += len;
        }
    }
}

private:

enum IocpOperation
{
    accept,
    connect,
    read,
    write,
    event,
    close
}

immutable BUFFERSIZE = 4096 * 2;

struct IocpContext
{
    OVERLAPPED       overlapped;
    char[BUFFERSIZE] buffer;
    WSABUF           wsabuf;
    int              nTotalBytes;
    int              nSentBytes;
    IocpOperation    operation;
    int              fd;
}


extern (Windows):

alias POVERLAPPED_COMPLETION_ROUTINE = void function(DWORD, DWORD, OVERLAPPED*, DWORD);
int WSASend(SOCKET, WSABUF*, DWORD, LPDWORD, DWORD,   OVERLAPPED*, POVERLAPPED_COMPLETION_ROUTINE);
int WSARecv(SOCKET, WSABUF*, DWORD, LPDWORD, LPDWORD, OVERLAPPED*, POVERLAPPED_COMPLETION_ROUTINE);
