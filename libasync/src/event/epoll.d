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
import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

class Epoll : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        _fd            = epoll_create1(0);
        _listener      = listener;
        _event.events  = EPOLLIN | EPOLLHUP | EPOLLERR | EPOLLET;
        _event.data.fd = listener.fd;
        register(_listener.fd, _event);
        
        this.onConnected    = onConnected;
        this.onDisConnected = onDisConnected;
        this.onReceive      = onReceive;
        this.onSocketError  = onSocketError;
    }

    ~this()
    {
        dispose();
    }

    bool register(int fd, ref epoll_event ev)
    {
        if (epoll_ctl(_fd, EPOLL_CTL_ADD, fd, &ev) != 0)
        {
            if (errno != EEXIST)
            {
                return false;
            }
        }

        return true;
    }

    int reregister(int fd, ref epoll_event ev)
    {
       return (epoll_ctl(_fd, EPOLL_CTL_MOD, fd, &ev) == 0);
    }

    int deregister(int fd)
    {
        return (epoll_ctl(_fd, EPOLL_CTL_DEL, fd, null) == 0);
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
        epoll_event[64] events;
        const int len = epoll_wait(_fd, events.ptr, events.length, 10);

        foreach (i; 0 .. len)
        {
            if (events[i].data.ptr is null)
            {
                debug writeln("event is null.");
                continue;
            }

            auto fd = events[i].data.fd;

            if ((events[i].events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP)) != 0)
            {
                if (fd == _listener.fd)
                {
                    debug writeln("listen event error.");
                }
                else
                {
                    removeClient(fd);
                    debug writeln("close event: ", events[i].data.fd);
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

                _clients[client.fd] = client;
                onConnected(client);
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
        core.sys.posix.unistd.close(_fd);
    }

    override void removeClient(int fd)
    {
        deregister(fd);
        _clients.remove(fd);
    }

private:

    int         _fd;
    epoll_event _event;
}
