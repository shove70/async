module async.event.epoll;

debug import std.stdio;

version(linux):

import core.sys.linux.epoll;
import core.stdc.errno;
import core.sys.posix.signal;
import core.sys.posix.netinet.tcp;
import core.sys.posix.netinet.in_;
import core.sys.posix.time;
import core.sync.mutex;
import core.thread;

import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;
import async.container.map;
import async.pool;

alias LoopSelector = Epoll;

class Epoll : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError);

        _eventHandle = epoll_create1(0);
        register(_listener.fd, EventType.ACCEPT);
    }

    override bool register(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        epoll_event ev;
        ev.events  = EPOLLHUP | EPOLLERR;
        ev.data.fd = fd;

        if (et != EventType.ACCEPT)
        {
            ev.events |= EPOLLET;
        }
        if (et == EventType.ACCEPT || et == EventType.READ || et == EventType.READWRITE)
        {
            ev.events |= EPOLLIN;
        }
        if ((et == EventType.WRITE) || (et == EventType.READWRITE))
        {
            ev.events |= EPOLLOUT;
        }

        if (epoll_ctl(_eventHandle, EPOLL_CTL_ADD, fd, &ev) != 0)
        {
            if (errno != EEXIST)
            {
                return false;
            }
        }

        return true;
    }

    override bool reregister(int fd, EventType et)
    {
        if (fd < 0)
        {
            return false;
        }

        epoll_event ev;
        ev.events  = EPOLLHUP | EPOLLERR;
        ev.data.fd = fd;

        if (et != EventType.ACCEPT)
        {
            ev.events |= EPOLLET;
        }
        if (et == EventType.ACCEPT || et == EventType.READ || et == EventType.READWRITE)
        {
            ev.events |= EPOLLIN;
        }
        if ((et == EventType.WRITE) || (et == EventType.READWRITE))
        {
            ev.events |= EPOLLOUT;
        }

        return (epoll_ctl(_eventHandle, EPOLL_CTL_MOD, fd, &ev) == 0);
    }

    override bool unregister(int fd)
    {
        if (fd < 0)
        {
            return false;
        }

        return (epoll_ctl(_eventHandle, EPOLL_CTL_DEL, fd, null) == 0);
    }

    override protected void handleEvent()
    {
        epoll_event[64] events;
        const int len = epoll_wait(_eventHandle, events.ptr, events.length, -1);

        foreach (i; 0 .. len)
        {
            auto fd = events[i].data.fd;

            if ((events[i].events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP)) != 0)
            {
                if (fd == _listener.fd)
                {
                    debug writeln("Listener event error.", fd);
                }
                else
                {
                    if (errno == EINTR)
                    {
                        continue;
                    }

                    TcpClient client = _clients[fd];

                    if (client !is null)
                    {
                        removeClient(fd, errno);
                    }

                    debug writeln("Close event: ", fd);
                }

                continue;
            }

            if (fd == _listener.fd)
            {
                Socket socket;
                int temp_errno = errno; // temp, will be remove.

                try
                {
                    socket = _listener.accept();
                }
                catch (Exception e)
                {
                    // temp, will be remove.
                    if (temp_errno == EINTR)
                    {
                        import std.stdio;
                        writeln("Epoll accepting exception when EINTR: " ~ e.toString());
                    }
                    // temp end.

                    continue;
                }

                TcpClient client = ThreadPool.instance.take(this, socket);
                _clients[client.fd] = client;

                if (_onConnected !is null)
                {
                    _onConnected(client);
                }

                register(client.fd, EventType.READ);
            }
            else if (events[i].events & EPOLLIN)
            {
                TcpClient client = _clients[fd];

                if (client !is null)
                {
                    client.weakup(EventType.READ);
                }
            }
            else if (events[i].events & EPOLLOUT)
            {
                TcpClient client = _clients[fd];

                if (client !is null)
                {
                    client.weakup(EventType.WRITE);
                }
            }
        }
    }
}
