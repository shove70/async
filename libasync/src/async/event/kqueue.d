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

import
	async.codec,
	async.event.selector,
	async.net.tcplistener,
	core.stdc.errno,
	core.sys.posix.netinet.in_,
	core.sys.posix.netinet.tcp,
	core.sys.posix.signal,
	core.sys.posix.time,
	std.socket;

alias LoopSelector = Kqueue;

class Kqueue : Selector
{
	this(TcpListener listener, OnConnected onConnected = null, OnDisconnected onDisconnected = null,
		OnReceive onReceive = null, OnSendCompleted onSendCompleted = null,
		OnSocketError onSocketError = null, Codec codec = null, uint workerThreadNum = 0)
	{
		super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError, codec, workerThreadNum);

		_eventHandle = kqueue();
		reg(_listener.fd, EventType.ACCEPT);
	}

	private auto reg(int fd, EventType et)
	{
		kevent_t[2] ev = void;
		short filter = void;
		ushort flags = void;

		if (et == EventType.ACCEPT)
		{
			filter = EVFILT_READ;
			flags  = EV_ADD | EV_ENABLE;
			EV_SET(&ev[0], fd, filter, flags, 0, 0, null);

			return kevent(_eventHandle, &ev[0], 1, null, 0, null) >= 0;
		}
		else
		{
			filter = EVFILT_READ;
			flags  = EV_ADD | EV_ENABLE | EV_CLEAR;
			EV_SET(&ev[0], fd, filter, flags, 0, 0, null);

			filter = EVFILT_WRITE;
			flags  = EV_ADD | EV_CLEAR;
			flags |= (et == EventType.READ) ? EV_DISABLE : EV_ENABLE;
			EV_SET(&ev[1], fd, filter, flags, 0, 0, null);

			return kevent(_eventHandle, &ev[0], 2, null, 0, null) >= 0;
		}
	}

	override bool register(int fd, EventType et)
	{
		return reg(fd, et);
	}

	override bool reregister(int fd, EventType et)
	{
		return fd >= 0 && reg(fd, et);
	}

	override bool unregister(int fd)
	{
		if (fd < 0)
		{
			return false;
		}

		kevent_t[2] ev = void;
		EV_SET(&ev[0], fd, EVFILT_READ,  EV_DELETE, 0, 0, null);
		EV_SET(&ev[1], fd, EVFILT_WRITE, EV_DELETE, 0, 0, null);

		return kevent(_eventHandle, &ev[0], fd == _listener.fd ? 1 : 2, null, 0, null) >= 0;
	}

	override protected void handleEvent()
	{
		kevent_t[64] events = void;
		//auto tspec = timespec(1, 1000 * 10);
		const len = kevent(_eventHandle, null, 0, events.ptr, events.length, null);//&tspec);

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
					if (events[i].flags & EV_ERROR)
					{
						int err = void;
						socklen_t errlen = err.sizeof;
						getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen);
						removeClient(fd, err);
					}
					else
					{
						removeClient(fd);
					}
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