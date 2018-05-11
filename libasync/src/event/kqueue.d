module async.event.kqueue;

debug import std.stdio;

version (OSX)
{
    version = MacBSD;
}
else version (iOS)
{
    version = MacBSD;
}
else version (TVOS)
{
    version = MacBSD;
}
else version (WatchOS)
{
    version = MacBSD;
}
else version (FreeBSD)
{
    version = MacBSD;
}
else version (OpenBSD)
{
    version = MacBSD;
}
else version (DragonFlyBSD)
{
    version = MacBSD;
}

version (MacBSD):

import core.stdc.errno;
import core.sys.posix.signal;
import core.sys.posix.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.unistd;
import core.sys.posix.time;
import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

class Kqueue : Selector
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

    bool reregister(int fd)
    {
       return true;
    }

    bool deregister(int fd)
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
        core.sys.posix.unistd.close(_fd);
    }

    override void removeClient(int fd)
    {
        deregister(fd);
        _clients.remove(fd);
    }

private:

    int _fd;
}
