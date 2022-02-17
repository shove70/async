module async.event.epoll;

debug import std.stdio;

version (linux):

import
	async.codec,
	async.event.selector,
	async.net.tcplistener,
	core.stdc.errno,
	core.sys.linux.epoll,
	core.sys.posix.netinet.in_,
	core.sys.posix.netinet.tcp,
	core.sys.posix.signal,
	core.sys.posix.time,
	std.socket;

alias LoopSelector = Epoll;

class Epoll : Selector
{
	this(TcpListener listener, OnConnected onConnected = null, OnDisconnected onDisconnected = null,
		OnReceive onReceive = null, OnSendCompleted onSendCompleted = null,
		OnSocketError onSocketError = null, Codec codec = null, uint workerThreadNum = 0)
	{
		super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError, codec, workerThreadNum);

		_eventHandle = epoll_create1(0);
		register(_listener.fd, EventType.ACCEPT);
	}

	private int reg(int fd, EventType et, int op)
	{
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
		if (et == EventType.WRITE || et == EventType.READWRITE)
		{
			ev.events |= EPOLLOUT;
		}
		return epoll_ctl(_eventHandle, op, fd, &ev);
	}

	override bool register(int fd, EventType et)
	{
		if (fd < 0)
		{
			return false;
		}

		if (reg(fd, et, EPOLL_CTL_ADD) != 0)
		{
			return errno == EEXIST;
		}

		return true;
	}

	override bool reregister(int fd, EventType et)
	{
		return fd >= 0 && reg(fd, et, EPOLL_CTL_MOD) == 0;
	}

	override bool unregister(int fd)
	{
		return fd >= 0 && epoll_ctl(_eventHandle, EPOLL_CTL_DEL, fd, null) == 0;
	}

	override protected void handleEvent()
	{
		epoll_event[64] events = void;
		const len = epoll_wait(_eventHandle, events.ptr, events.length, -1);

		foreach (i; 0 .. len)
		{
			int fd = events[i].data.fd;

			if (events[i].events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP))
			{
				if (fd == _listener.fd)
				{
					debug writeln("Listener event error.", fd);
				}
				else
				{
					int err;
					socklen_t errlen = err.sizeof;
					getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen);
					removeClient(fd, err);
				}

				continue;
			}

			if (fd == _listener.fd)
			{
				accept();
			}
			else if (events[i].events & EPOLLIN)
			{
				read(fd);
			}
			else if (events[i].events & EPOLLOUT)
			{
				write(fd);
			}
		}
	}
}