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
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        this._onConnected    = onConnected;
        this.onDisConnected  = onDisConnected;
        this.onReceive       = onReceive;
        this.onSendCompleted = onSendCompleted;
        this.onSocketError   = onSocketError;

        _lock          = new Mutex;
        _clients       = new Map!(int, TcpClient);

        _kqueueFd      = kqueue();
        _listener      = listener;

        register(_listener.fd, EventType.ACCEPT);
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

        int error = -1;
        kevent_t[2] ev = void;
        short  readFilter  = EV_ADD | EV_ENABLE;
        short  writeFilter = EV_ADD | EV_ENABLE;

        if (et != EventType.ACCEPT)
        {
            readFilter  |= EV_CLEAR;
            writeFilter |= EV_CLEAR;
        }

        EV_SET(&(ev[0]), fd, EVFILT_READ,  readFilter,  0, 0, null);
        EV_SET(&(ev[1]), fd, EVFILT_WRITE, writeFilter, 0, 0, null);

        if (et == EventType.READWRITE)
        {
            error = kevent(_kqueueFd, &(ev[0]), 2, null, 0, null);
        }
        else if ((et == EventType.ACCEPT) || (et == EventType.READ))
        {
            error = kevent(_kqueueFd, &(ev[0]), 1, null, 0, null);
        }
        else if (et == EventType.WRITE)
        {
            error = kevent(_kqueueFd, &(ev[1]), 1, null, 0, null);
        }

        return (error >= 0);
    }

//    override bool register(int fd, EventType et)
//    {
//        kevent_t[2] ev = void;
//        short  filter;
//        ushort flags;
//
//        if (et == EventType.ACCEPT)
//        {
//            filter = EVFILT_READ;
//            flags  = EV_ADD | EV_ENABLE;
//            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);
//
//            return (kevent(_kqueueFd, &(ev[0]), 1, null, 0, null) >= 0);
//        }
//        else
//        {
//            filter = EVFILT_READ;
//            flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
//            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);
//
//            filter = EVFILT_WRITE;
//            flags  = EV_ADD | EV_CLEAR;
//            flags |= (et == EventType.READ) ? EV_DISABLE : EV_ENABLE;
//            EV_SET(&(ev[1]), fd, filter, flags, 0, 0, null);
//
//            return (kevent(_kqueueFd, &(ev[0]), 2, null, 0, null) >= 0);
//        }
//    }

//    override bool register(int fd, EventType et)
//    {
//        kevent_t[2] ev = void;
//        short  filter;
//        ushort flags;
//
//        if (et == EventType.ACCEPT)
//        {
//            filter = EVFILT_READ;
//            flags  = EV_ADD | EV_ENABLE;
//            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);
//
//            return (kevent(_kqueueFd, &(ev[0]), 1, null, 0, null) >= 0);
//        }
//        else if (et == EventType.READ)
//        {
//            filter = EVFILT_READ;
//            flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
//            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);
//
//            return (kevent(_kqueueFd, &(ev[0]), 1, null, 0, null) >= 0);
//        }
//        else if (et == EventType.WRITE)
//        {
//            filter = EVFILT_WRITE;
//            flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
//            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);
//
//            return (kevent(_kqueueFd, &(ev[0]), 1, null, 0, null) >= 0);
//        }
//        else
//        {
//            filter = EVFILT_READ;
//            flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
//            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);
//
//            filter = EVFILT_WRITE;
//            flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
//            EV_SET(&(ev[1]), fd, filter, flags, 0, 0, null);
//
//            return (kevent(_kqueueFd, &(ev[0]), 2, null, 0, null) >= 0);
//        }
//    }

    override bool reregister(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }
deregister(fd);
return register(fd, et);
        //return true;//register(fd, et);
    }

    override bool deregister(int fd)
    {
        if (fd < 0)
        {
            return false;
        }

        kevent_t[2] ev = void;
        EV_SET(&(ev[0]), fd, EVFILT_READ,  EV_DELETE, 0, 0, null);
        EV_SET(&(ev[1]), fd, EVFILT_WRITE, EV_DELETE, 0, 0, null);

        if (fd == _listener.fd)
        {
            return (kevent(_kqueueFd, &(ev[0]), 1, null, 0, null) >= 0);
        }
        else
        {
            return (kevent(_kqueueFd, &(ev[0]), 2, null, 0, null) >= 0);
        }
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
writeln(fd, ", ", events[i].flags, ", ", events[i].filter);
            if ((events[i].flags & EV_EOF) || (events[i].flags & EV_ERROR))
            {
                if (fd == _listener.fd)
                {
                    debug writeln("listener event error.", fd);
                }
                else
                {
                    TcpClient client = _clients[fd];
                    if (client !is null)
                    {
                        removeClient(fd);
                        client.close();
                    }
                    debug writeln("close event: ", fd);
                }
                continue;
            }

            if (fd == _listener.fd)
            {
                TcpClient client = new TcpClient(this, _listener.accept());
                _clients[client.fd] = client;
                register(client.fd, EventType.READ);

                if (_onConnected !is null)
                {
                    _onConnected(client);
                }
            }
            else if (events[i].filter & EVFILT_READ)
            {
                TcpClient client = _clients[fd];

                if (client !is null)
                {
                    client.weakup(EventType.READ);
                }
            }
            else if (events[i].filter & EVFILT_WRITE)
            {writeln(fd, "------------------22--Pre Write");
                TcpClient client = _clients[fd];

                if (client !is null)
                {
                    client.weakup(EventType.WRITE);
                }
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
