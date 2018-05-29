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
import core.sys.posix.time;

import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

alias LoopSelector = Kqueue;

class Kqueue : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError, int workerThreadNum)
    {
        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError, workerThreadNum);

        _eventHandle = kqueue();
        register(_listener.fd, EventType.ACCEPT);
    }

    override bool register(int fd, EventType et)
    {
        kevent_t[2] ev = void;
        short  filter;
        ushort flags;

        if (et == EventType.ACCEPT)
        {
            filter = EVFILT_READ;
            flags  = EV_ADD | EV_ENABLE;
            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);

            return (kevent(_eventHandle, &(ev[0]), 1, null, 0, null) >= 0);
        }
        else
        {
            filter = EVFILT_READ;
            flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
            EV_SET(&(ev[0]), fd, filter, flags, 0, 0, null);

            filter = EVFILT_WRITE;
            flags  = EV_ADD | EV_CLEAR;
            flags |= (et == EventType.READ) ? EV_DISABLE : EV_ENABLE;
            EV_SET(&(ev[1]), fd, filter, flags, 0, 0, null);

            return (kevent(_eventHandle, &(ev[0]), 2, null, 0, null) >= 0);
        }
    }

    override bool reregister(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        return register(fd, et);
    }

    override bool unregister(int fd)
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
            return (kevent(_eventHandle, &(ev[0]), 1, null, 0, null) >= 0);
        }
        else
        {
            return (kevent(_eventHandle, &(ev[0]), 2, null, 0, null) >= 0);
        }
    }

    override protected void handleEvent()
    {
        kevent_t[64] events;
        //auto tspec = timespec(1, 1000 * 10);
        auto len = kevent(_eventHandle, null, 0, events.ptr, events.length, null);//&tspec);

        foreach (i; 0 .. len)
        {
            auto fd = cast(int)events[i].ident;

            if ((events[i].flags & EV_EOF) || (events[i].flags & EV_ERROR))
            {
                if (fd == _listener.fd)
                {
                    debug writeln("Listener event error.", fd);
                }
                else
                {
                    removeClient(fd);
                    debug writeln("Close event: ", fd);
                }

                continue;
            }

            if (fd == _listener.fd)
            {
                accept();
            }
            else if (events[i].filter == EVFILT_READ)
            {
                read(fd);
            }
            else if (events[i].filter == EVFILT_WRITE)
            {
                write(fd);
            }
        }
    }
}

extern (D) void EV_SET(kevent_t* kevp, typeof(kevent_t.tupleof) args) @nogc nothrow
{
    *kevp = kevent_t(args);
}
