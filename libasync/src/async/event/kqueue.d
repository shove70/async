module async.event.kqueue;

debug import std.stdio;

version (Posix)
{
	import core.sys.darwin.sys.event;
}
else version (FreeBSD)
{
	import core.sys.freebsd.sys.event;
}
else version (DragonFlyBSD)
{
	import core.sys.dragonflybsd.sys.event;
}

version (OSX)
{
    version = KQUEUE;
}
else version (iOS)
{
    version = KQUEUE;
}
else version (TVOS)
{
    version = KQUEUE;
}
else version (WatchOS)
{
    version = KQUEUE;
}
else version (FreeBSD)
{
    version = KQUEUE;
}
else version (OpenBSD)
{
    version = KQUEUE;
}
else version (DragonFlyBSD)
{
    version = KQUEUE;
}

version (KQUEUE):

import core.stdc.errno;
import core.sys.posix.signal;
import core.sys.posix.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.unistd;
import core.sys.posix.time;
import core.sync.mutex;
import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;

alias LoopSelector = Kqueue;

extern (D) void EV_SET(kevent_t* kevp, typeof(kevent_t.tupleof) args) @nogc nothrow
{
    *kevp = kevent_t(args);
}

class Kqueue : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        this._onConnected   = onConnected;
        this.onDisConnected = onDisConnected;
        this.onReceive      = onReceive;
        this.onSocketError  = onSocketError;

        _lock          = new Mutex;
        _clients       = new Map!(int, TcpClient);

        _kqueueFd      = kqueue();
        _listener      = listener;

        register(_listener.fd);
    }

    ~this()
    {
        dispose();
    }

    private bool registerTimer(int fd)
    {
        kevent_t ev;
        size_t time = 20;
        EV_SET(&ev, fd, EVFILT_TIMER, EV_ADD | EV_ENABLE | EV_CLEAR, 0, time, null);

        return (kevent(_kqueueFd, &ev, 1, null, 0, null) >= 0);
    }

    private bool register(int fd, bool isETMode = false)
    {
        kevent_t ev;
        short read  = EV_ADD | EV_ENABLE;
        if (isETMode)
        {
            read |= EV_CLEAR;
        }

        EV_SET(&ev, fd, EVFILT_READ, read, 0, 0, null);

        return (kevent(_kqueueFd, &ev, 1, null, 0, null) >= 0);
    }

    private bool deregisterTimer(int fd)
    {
        kevent_t ev;
        EV_SET(&ev, fd, EVFILT_TIMER, EV_DELETE, 0, 0, null); 

        return (kevent(_kqueueFd, &ev, 1, null, 0, null) >= 0);
    }

    private bool deregister(int fd)
    {
        kevent_t ev;
        EV_SET(&ev, fd, EVFILT_READ, EV_DELETE, 0, 0, null);

        return (kevent(_kqueueFd, &ev, 1, null, 0, null) >= 0);
    }

    override void startLoop()
    {
        runing = true;

        auto tspec = timespec(1, 1000 * 10);
        while (runing)
        {
            handleEvent(tspec);
        }
    }

    private void handleEvent(ref timespec tspec)
    {
        kevent_t[64] events;
        auto len = kevent(_kqueueFd, null, 0, events.ptr, events.length, &tspec);

        foreach (i; 0 .. len)
        {
            auto fd = cast(int)events[i].ident;

            if ((events[i].flags & EV_EOF) || (events[i].flags & EV_ERROR))
            {
                if (fd == _listener.fd)
                {
                    debug writeln("listener event error.", fd);
                }
                else
                {
                    TcpClient client = _clients[fd];
                    removeClient(fd);
                    client.close();
                    debug writeln("close event: ", fd);
                }
                continue;
            }

            if (fd == _listener.fd)
            {
                TcpClient client = new TcpClient(this, _listener.accept());

                register(client.fd, true);

                _clients[client.fd] = client;
                _onConnected(client);
            }
            else if ((events[i].filter & EVFILT_READ) || (events[i].filter & EVFILT_TIMER))
            {
                _clients[fd].weakup();
            }
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
            c.close();
        }

        _clients.clear();

        deregister(_listener.fd);
        _listener.close();

        core.sys.posix.unistd.close(_kqueueFd);
    }

    override void removeClient(int fd)
    {
        deregister(fd);
        _clients.remove(fd);
    }

private:

    int _kqueueFd;
}
