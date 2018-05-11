module async.event.iocp;

debug import std.stdio;

version (Windows):

import core.sys.windows.windows;
import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

class Iocp : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        this.onConnected    = onConnected;
        this.onDisConnected = onDisConnected;
        this.onReceive      = onReceive;
        this.onSocketError  = onSocketError;
    }

    ~this()
    {
        dispose();
    }

    bool register(int fd)
    {
        return true;
    }

    bool reRegister(int fd)
    {
       return true;
    }

    bool deRegister(int fd)
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

    override void handleEvent()
    {
        
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
