module async.event.epoll;

debug import std.stdio;

version(linux):

import core.sys.linux.epoll;
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

alias LoopSelector = Epoll;

class Epoll : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        this._onConnected   = onConnected;
        this.onDisConnected = onDisConnected;
        this.onReceive      = onReceive;
        this.onSocketError  = onSocketError;

        _lock          = new Mutex;

        _epollFd       = epoll_create1(0);
        _listener      = listener;

        epoll_event ev;
        ev.events  = EPOLLIN | EPOLLHUP | EPOLLERR;
        ev.data.fd = listener.fd;
        register(_listener.fd, ev);
    }

    ~this()
    {
        dispose();
    }

    private bool register(int fd, ref epoll_event ev)
    {
        if (epoll_ctl(_epollFd, EPOLL_CTL_ADD, fd, &ev) != 0)
        {
            if (errno != EEXIST)
            {
                return false;
            }
        }

        return true;
    }

    private int reregister(int fd, ref epoll_event ev)
    {
       return (epoll_ctl(_epollFd, EPOLL_CTL_MOD, fd, &ev) == 0);
    }

    private int deregister(int fd)
    {
        return (epoll_ctl(_epollFd, EPOLL_CTL_DEL, fd, null) == 0);
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
        epoll_event[64] events;
        const int len = epoll_wait(_epollFd, events.ptr, events.length, 10);

        foreach (i; 0 .. len)
        {
            auto fd = events[i].data.fd;

            if ((events[i].events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP)) != 0)
            {
                if (fd == _listener.fd)
                {
                    debug writeln("listener event error.", fd);
                }
                else
                {
                    _clients[fd].close();
                    debug writeln("close event: ", fd);
                }
                continue;
            }

            if (fd == _listener.fd)
            {
                TcpClient client = new TcpClient(this, _listener.accept());

                epoll_event ev;
                ev.events  = EPOLLIN | EPOLLHUP | EPOLLERR | EPOLLET;
                ev.data.fd = client.fd;
                register(client.fd, ev);

                synchronized (_lock) _clients[client.fd] = client;
                _onConnected(client);
            }
            else if (events[i].events & EPOLLIN)
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
        }

        deregister(_listener.fd);
        _listener.close();

        core.sys.posix.unistd.close(_epollFd);
    }

    override void removeClient(int fd)
    {
        deregister(fd);
        synchronized (_lock) _clients.remove(fd);
    }

private:

    int _epollFd;
}
