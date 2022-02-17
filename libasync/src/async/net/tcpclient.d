module async.net.tcpclient;

debug import std.stdio;

import
	async.container.bytebuffer,
	async.event.selector,
	async.eventloop,
	async.net.tcplistener,
	core.stdc.errno,
	std.socket,
	std.string;
version (Windows) { } else
	import core.sync.rwmutex;

class TcpClient : TcpListener
{
	this(Selector selector, Socket socket)
	{
		super(socket);
		_selector = selector;
		_closing  = false;

		version (Windows) { } else
		{
			_sendLock         = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
			_currentEventType = EventType.READ;
			_lastWriteOffset  = 0;
		}
	}

	version (Windows) { } else
	{
		void weakup(EventType event)
		{
			final switch (event)
			{
				case EventType.READ:
					_hasReadEvent = true;
					beginRead();
					break;
				case EventType.WRITE:
					_hasWriteEvent = true;
					beginWrite();
					break;
				case EventType.ACCEPT:
				case EventType.READWRITE:
					break;
			}
		}

private:
		void beginRead()
		{
			_hasReadEvent = false;

			if (_reading)
			{
				return;
			}

			_reading = true;
			_selector.workerPool.run!read(this);
		}

		protected static void read(TcpClient client)
		{
			ubyte[] data;
			ubyte[4096] buffer = void;

			while (!client._closing && client.isAlive)
			{
				auto len = client.socket.receive(buffer);

				if (len > 0)
				{
					data ~= buffer[0 .. len];
					continue;
				}
				else if (len == 0)
				{
					client.readCallback(-1);
					return;
				}

				if (errno == EINTR)
					continue;
				if (errno == EAGAIN/* || errno == EWOULDBLOCK*/)
					break;
				client.readCallback(errno);
				return;
			}

			if (data.length && client._selector.onReceive)
			{
				if (client._selector.codec)
				{
					client._receiveBuffer ~= data;

					ptrdiff_t pos = void;
					for (;;)
					{
						const ret = client._selector.codec.decode(client._receiveBuffer);
						pos = ret[0];

						if (pos < 0)
							break;
						const ubyte[] message = client._receiveBuffer[0 .. pos];
						client._receiveBuffer.popFront(pos + ret[1]);
						client._selector.onReceive(client, message);
					}
					if (pos == -2) // The magic is error.
					{
						client.forceClose();
						return;
					}
				}
				else
				{
					client._selector.onReceive(client, data);
				}
			}
			client.readCallback(0);
		}

		void readCallback(const int err)  // err: 0: OK, -1: client disconnection, 1,2... errno
		{
			version (linux)
			{
				if (err == -1)
				{
					_selector.removeClient(fd, err);
				}
			}

			_reading = false;

			if (_hasReadEvent)
			{
				beginRead();
			}
		}

		void beginWrite()
		{
			_hasWriteEvent = false;

			if (_writing)
			{
				return;
			}

			_writing = true;
			_selector.workerPool.run!write(this);
		}

		protected static void write(TcpClient client)
		{
			while (!client._closing && client.isAlive && (!client._writeQueue.empty || client._lastWriteOffset))
			{
				if (client._writingData.length == 0)
				{
					synchronized (client._sendLock.writer)
					{
						client._writingData     = client._writeQueue.front;
						client._writeQueue.popFront();
						client._lastWriteOffset = 0;
					}
				}

				while (!client._closing && client.isAlive && client._lastWriteOffset < client._writingData.length)
				{
					long len = client.socket.send(client._writingData[client._lastWriteOffset .. $]);

					if (len > 0)
					{
						client._lastWriteOffset += len;
						continue;
					}
					if (len == 0)
					{
						//client._selector.removeClient(fd);

						if (client._lastWriteOffset < client._writingData.length)
						{
							if (client._selector.onSendCompleted)
							{
								client._selector.onSendCompleted(client, client._writingData, client._lastWriteOffset);
							}

							debug writefln("The sending is incomplete, the total length is %d, but actually sent only %d.",
								client._writingData.length, client._lastWriteOffset);
						}

						client._writingData.length = 0;
						client._lastWriteOffset    = 0;

						client.writeCallback(-1);  // sending is break and incomplete.
						return;
					}
					if (errno == EINTR)
					{
						continue;
					}
					if (errno == EAGAIN/* || errno == EWOULDBLOCK*/)
					{
						if (client._currentEventType != EventType.READWRITE)
						{
							client._selector.reregister(client.fd, EventType.READWRITE);
							client._currentEventType = EventType.READWRITE;
						}

						client.writeCallback(0);  // Wait eventloop notify to continue again;
						return;
					}
					client._writingData.length = 0;
					client._lastWriteOffset    = 0;

					client.writeCallback(errno);  // Some error.
					return;
				}

				if (client._lastWriteOffset == client._writingData.length)
				{
					if (client._selector.onSendCompleted)
					{
						client._selector.onSendCompleted(client, client._writingData, client._lastWriteOffset);
					}

					client._writingData.length = 0;
					client._lastWriteOffset    = 0;
				}
			}

			if (client._writeQueue.empty && client._writingData.length == 0 && client._currentEventType == EventType.READWRITE)
			{
				client._selector.reregister(client.fd, EventType.READ);
				client._currentEventType = EventType.READ;
			}

			client.writeCallback(0);
			return;
		}

		void writeCallback(int err)  // err: 0: OK, -1: client disconnection, 1,2... errno
		{
			_writing = false;

			if (_hasWriteEvent)
			{
				beginWrite();
			}
		}
	}

public:

	int send(const void[] data) nothrow @trusted
	{
		if (!data.length)
			return -1;
		try {
			if (!isAlive)
				return -2;
		} catch(Exception)
			return -2;

		version (Windows)
		{
			import async.event.iocp;

			Iocp.iocp_send(_selector, fd, data);
		}
		else
		{
			synchronized (_sendLock.writer)
			{
				_writeQueue ~= data;
			}

			weakup(EventType.WRITE);  // First write direct, and when it encounter EAGAIN, it will open the EVENT notification.
		}
		return 0;
	}

	override void close() @trusted nothrow @nogc
	{
		_closing = true;
		super.close();
	}

	/*
	Important:

	The method for emergency shutdown of the application layer is close the socket.
	When a message that does not meet the requirements is sent to the server,
	this method should be called to avoid the waste of resources.
	*/
	void forceClose()
	{
		if (isAlive)
		{
			_selector.removeClient(fd);
		}
	}

private:
	Selector         _selector;
	shared bool      _closing;

	version (Windows) { } else
	{
		shared bool     _hasReadEvent,
						_hasWriteEvent,
						_reading,
						_writing;

		ByteBuffer      _writeQueue;
		ubyte[]         _writingData;
		size_t          _lastWriteOffset;
		ReadWriteMutex  _sendLock;

		EventType        _currentEventType;
	}

	ByteBuffer       _receiveBuffer;
}