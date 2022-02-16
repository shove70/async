module async.event.selector;

import
	async.codec,
	async.container.map,
	async.net.tcpclient,
	async.net.tcplistener,
	async.thread,
	core.sync.mutex,
	core.thread,
	std.socket;

alias
	OnConnected     = void function(TcpClient)                                    nothrow @trusted,
	OnDisconnected  = void function(TcpClient)                                    nothrow @trusted,
	OnReceive       = void function(TcpClient, const scope ubyte[])               nothrow @trusted,
	OnSendCompleted = void function(TcpClient, const scope ubyte[], const size_t) nothrow @trusted,
	OnSocketError   = void function(TcpClient, string)                            nothrow @trusted;

enum EventType
{
	ACCEPT, READ, WRITE, READWRITE
}

abstract class Selector
{
	this(TcpListener listener, OnConnected onConnected = null, OnDisconnected onDisconnected = null,
		OnReceive onReceive = null, OnSendCompleted onSendCompleted = null,
		OnSocketError onSocketError = null, Codec codec = null, uint workerThreadNum = 0)
	{
		import std.parallelism : totalCPUs;

		this.onConnected    = onConnected;
		this.onDisconnected = onDisconnected;
		this.onReceive       = onReceive;
		this.onSendCompleted = onSendCompleted;
		this.onSocketError  = onSocketError;
		_codec          = codec;
		_clients  = new Map!(int, TcpClient);
		_listener = listener;

		version (Windows) { } else _acceptPool = new ThreadPool(1);
		workerPool = new ThreadPool(workerThreadNum ? workerThreadNum : totalCPUs * 2 + 2);
	}

	~this() { dispose(); }

	bool register  (int fd, EventType et);
	bool reregister(int fd, EventType et);
	bool unregister(int fd);

	void initialize()
	{
		version (Windows)
		{
			foreach (i; 0 .. workerPool.size)
				workerPool.run!handleEvent(this);
		}
	}

	void runLoop()
	{
		version (Windows)
		{
			beginAccept(this);
		}
		else
		{
			handleEvent();
		}
	}

	void startLoop()
	{
		_runing = true;

		version (Windows)
		{
			foreach (i; 0 .. workerPool.size)
				workerPool.run!handleEvent(this);
		}

		while (_runing)
		{
			version (Windows)
			{
				beginAccept(this);
			}
			else
			{
				handleEvent();
			}
		}
	}

	void stop() { _runing = false; }

	void dispose()
	{
		if (_clients is null)
		{
			return;
		}

		_clients.lock();
		foreach (ref c; _clients)
		{
			unregister(c.fd);

			if (c.isAlive)
			{
				c.close();
			}
		}
		_clients.unlock();

		_clients.clear();
		_clients = null;

		unregister(_listener.fd);
		_listener.close();

		version (Posix)
		{
			static import core.sys.posix.unistd;
			core.sys.posix.unistd.close(_eventHandle);
		}
	}

	void removeClient(int fd, int err = 0)
	{
		debug import std.stdio;
		debug writeln("Close event: ", fd);
		if (!unregister(fd))
			return;

		if (auto client = _clients[fd])
		{
			if (err > 0 && onSocketError)
			{
				onSocketError(client, formatSocketError(err));
			}

			if (onDisconnected)
			{
				onDisconnected(client);
			}

			client.close();
		}

		_clients.remove(fd);
		//debug if (!err)
			//stderr.writeln(err);
	}

	version (Windows)
	{
		void iocp_send(int fd, const scope void[] data);
		void iocp_receive(int fd);
	}

	@property Codec codec() nothrow @nogc @safe { return _codec; }

	@property auto clients() { return _clients; }

protected:

	version (Windows) { } else void accept()
	{
		_acceptPool.run!beginAccept(this);
	}

	static void beginAccept(Selector selector)
	{
		Socket socket = void;

		try
		{
			socket = selector._listener.accept();
		}
		catch (Exception)
		{
			return;
		}

		auto client = new TcpClient(selector, socket);

		try
			client.setKeepAlive(600, 10);
		catch (Exception) { }

		selector._clients[client.fd] = client;

		if (selector.onConnected)
		{
			selector.onConnected(client);
		}

		selector.register(client.fd, EventType.READ);

		version (Windows) selector.iocp_receive(client.fd);
	}

	version (Windows)
	{
		void read(int fd, const scope ubyte[] data)
		{
			auto client = _clients[fd];

			if (client && onReceive)
			{
				onReceive(client, data);
			}
		}
	}
	else
	{
		void read(int fd)
		{
			if (auto client = _clients[fd])
			{
				client.weakup(EventType.READ);
			}
		}

		void write(int fd)
		{
			if (auto client = _clients[fd])
			{
				client.weakup(EventType.WRITE);
			}
		}
	}

	Map!(int, TcpClient) _clients;
	TcpListener          _listener;
	bool                 _runing;

	version (Windows)
	{
		import core.sys.windows.basetsd : HANDLE;
		HANDLE _eventHandle;

		static void handleEvent(Selector selector)
		{
			import async.event.iocp : Iocp;
			Iocp.handleEvent(selector);
		}
	}
	else
	{
		int _eventHandle;

		void handleEvent();
	}

private:
	ThreadPool           _acceptPool;
	Codec                _codec;

public:
	ThreadPool           workerPool;

	OnReceive            onReceive;
	OnSendCompleted      onSendCompleted;
	OnConnected          onConnected;
	OnDisconnected       onDisconnected;
	OnSocketError        onSocketError;
}