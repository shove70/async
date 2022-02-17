module async.net.tcplistener;

import std.socket;

class TcpListener
{
	this()
	{
		this(new TcpSocket());
		socket.reusePort = true;

		Linger optLinger;
		optLinger.on   = 1;
		optLinger.time = 0;
		setOption(SocketOptionLevel.SOCKET, SocketOption.LINGER, optLinger);
	}

	void close() @trusted nothrow @nogc
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}

	this(Socket socket)
	{
		import std.datetime;

		this.socket = socket;
		version (Windows) { } else socket.blocking = false;

		setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, 60.seconds);
		setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, 60.seconds);
	}

	@property final int fd() pure nothrow @nogc { return cast(int)handle; }

	Socket socket;
	alias socket this;
}

@property bool reusePort(Socket socket)
{
	int result = void;
	socket.getOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, result);
	return result != 0;
}

@property bool reusePort(Socket socket, bool enabled)
{
	socket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, enabled);

	version (Posix)
	{
		import core.sys.posix.sys.socket;
		socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_REUSEPORT, enabled);
	}

	version (Windows)
	{
		if (!enabled)
		{
			import core.sys.windows.winsock2;
			socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption)SO_EXCLUSIVEADDRUSE, true);
		}
	}

	return enabled;
}