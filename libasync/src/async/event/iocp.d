module async.event.iocp;

version (Windows):

import
	async.codec,
	async.event.selector,
	async.net.tcplistener,
	core.stdc.errno,
	core.sys.windows.mswsock,
	core.sys.windows.windows,
	core.sys.windows.winsock2,
	std.socket;

alias LoopSelector = Iocp;

class Iocp : Selector
{
	this(TcpListener listener, OnConnected onConnected = null, OnDisconnected onDisconnected = null,
		OnReceive onReceive = null, OnSendCompleted onSendCompleted = null,
		OnSocketError onSocketError = null, Codec codec = null, uint workerThreadNum = 0)
	{
		super(listener, onConnected, onDisconnected, onReceive, onSendCompleted, onSocketError, codec, workerThreadNum);

		_eventHandle = CreateIoCompletionPort(INVALID_HANDLE_VALUE, null, 0, cast(uint)workerPool.size);
	}

	override bool register(int fd, EventType et)
	{
		return fd >= 0 && CreateIoCompletionPort(cast(HANDLE) fd, _eventHandle, fd, 0) != null;
	}

	override bool reregister(int fd, EventType et)
	{
		return fd >= 0;
	}

	override bool unregister(int fd)
	{
		return fd >= 0;
	}

	static void handleEvent(Selector selector)
	{
		OVERLAPPED* overlapped;
		IocpContext* context = void;
		WSABUF buffSend;
		uint dwSendNumBytes;
		uint dwFlags;

		while (selector._running)
		{
			ULONG_PTR key = void;
			DWORD bytes;
			int ret = GetQueuedCompletionStatus(selector._eventHandle, &bytes, &key, &overlapped, INFINITE);
			context = cast(IocpContext*) overlapped;

			if (ret == 0)
			{
				const err = GetLastError();
				if (err != WAIT_TIMEOUT && context)
				{
					selector.removeClient(context.fd, err);
				}
				continue;
			}

			if (bytes == 0)
			{
				selector.removeClient(context.fd, 0);
				continue;
			}

			if (context.operation == IocpOperation.read) // A read operation complete.
			{
				selector.read(context.fd, cast(ubyte[]) context.wsabuf.buf[0..bytes]);

				// Read operation completed, so post Read operation for remainder (if exists).
				iocp_receive(selector, context.fd);
			}
			else if (context.operation == IocpOperation.write) // A write operation complete.
			{
				context.nSentBytes += bytes;
				dwFlags = 0;

				if (context.nSentBytes < context.nTotalBytes)
				{
					// A Write operation has not completed yet, so post another.
					// Write operation to post remaining data.
					context.operation = IocpOperation.write;
					buffSend.buf = context.buffer.ptr + context.nSentBytes;
					buffSend.len = context.nTotalBytes - context.nSentBytes;
					ret = WSASend(cast(SOCKET) context.fd, &buffSend, 1, &dwSendNumBytes, dwFlags, &(context.overlapped), null);

					if (ret == SOCKET_ERROR)
					{
						const err = WSAGetLastError();

						if (err != ERROR_IO_PENDING)
						{
							selector.removeClient(context.fd, err);
							continue;
						}
					}
				}
				else
				{
					// Write operation completed, so post Read operation.
					iocp_receive(selector, context.fd);
				}
			}
		}
	}

	static void iocp_receive(Selector selector, int fd) nothrow
	{
		auto context = new IocpContext;
		context.operation   = IocpOperation.read;
		context.nTotalBytes = 0;
		context.nSentBytes  = 0;
		context.wsabuf.buf  = context.buffer.ptr;
		context.wsabuf.len  = context.buffer.sizeof;
		context.fd          = fd;
		uint dwRecvNumBytes;
		uint dwFlags;
		int err = WSARecv(cast(HANDLE) fd, &context.wsabuf, 1, &dwRecvNumBytes, &dwFlags, &context.overlapped, null);

		if (err == SOCKET_ERROR)
		{
			err = WSAGetLastError();

			if (err != ERROR_IO_PENDING)
			{
				selector.removeClient(fd, err);
			}
		}
	}

	static void iocp_send(Selector selector, int fd, const scope void[] data) nothrow
	{
		for (size_t pos; pos < data.length;)
		{
			size_t len = data.length - pos;
			len = len > BUFFERSIZE ? BUFFERSIZE : len;

			auto context = new IocpContext;
			context.operation  = IocpOperation.write;
			context.buffer[0..len] = cast(char[]) data[pos..pos + len];
			context.nTotalBytes = cast(int) len;
			context.nSentBytes  = 0;
			context.wsabuf.buf  = context.buffer.ptr;
			context.wsabuf.len  = cast(int) len;
			context.fd          = fd;
			uint dwSendNumBytes = void;
			enum dwFlags = 0;
			int err = WSASend(cast(HANDLE) fd, &context.wsabuf, 1, &dwSendNumBytes, dwFlags, &context.overlapped, null);

			if (err == SOCKET_ERROR)
			{
				err = WSAGetLastError();

				if (err != ERROR_IO_PENDING)
				{
					selector.removeClient(fd, err);
					return;
				}
			}

			pos += len;
		}
	}
}

private:

enum IocpOperation
{
	accept,
	connect,
	read,
	write,
	event,
	close
}

enum BUFFERSIZE = 4096 * 2;

struct IocpContext
{
	OVERLAPPED       overlapped;
	char[BUFFERSIZE] buffer;
	WSABUF           wsabuf;
	int              nTotalBytes;
	int              nSentBytes;
	IocpOperation    operation;
	int              fd;
}

extern (Windows) nothrow @nogc:

alias POVERLAPPED_COMPLETION_ROUTINE = void function(DWORD, DWORD, OVERLAPPED*, DWORD);
int WSASend(SOCKET, WSABUF*, DWORD, LPDWORD, DWORD,   OVERLAPPED*, POVERLAPPED_COMPLETION_ROUTINE);
int WSARecv(SOCKET, WSABUF*, DWORD, LPDWORD, LPDWORD, OVERLAPPED*, POVERLAPPED_COMPLETION_ROUTINE);