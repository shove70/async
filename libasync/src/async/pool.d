module async.pool;

import std.socket;

import async.event.selector;
import async.net.tcpclient;
import async.container.queue;

class ThreadPool
{
    enum State
    {
        BUSY, IDLE
    }

	static ThreadPool instance()
    {
        if (_instance is null)
        {
            synchronized(ThreadPool.classinfo)
            {
                if (_instance is null)
                {
                    _instance = new ThreadPool();
                }
            }
        }

        return _instance;
    }

    void init(Selector selector)
    {
        if (selector !in _idleQueue)
        {
            synchronized (selector.classinfo)
            {
                if (selector !in _idleQueue)
                {
                    _idleQueue[selector] = Queue!TcpClient();
                }
            }
        }
    }

    TcpClient take(Selector selector, Socket socket)
    {
        assert (selector in _idleQueue, "No initialization queue for selector.");

        TcpClient client = null;

        if (!_idleQueue[selector].empty())
        {
            synchronized (selector.classinfo)
            {
                if (!_idleQueue[selector].empty())
                {
                    client = _idleQueue[selector].pop();
                }
            }
        }

        if (client is null)
        {
            client = create(selector, socket);
        }
        else
        {
            client.reset(socket);
        }

        client.state = State.BUSY;

        return client;
    }

    void revert(TcpClient client)
    {
        assert (client.selector in _idleQueue, "No initialization queue for selector.");

        client.state = State.IDLE;

        synchronized (client.selector.classinfo)
        {
            _idleQueue[client.selector].push(client);
        }
    }

    void removeAll()
    {
        synchronized (this.classinfo)
        {
            foreach (queue; _idleQueue)
            {
                while (!queue.empty())
                {
                    queue.pop().termTask();
                }
            }
        }
    }

private:

	__gshared ThreadPool      _instance = null;
    Queue!TcpClient[Selector] _idleQueue;

    TcpClient create(Selector selector, Socket socket)
    {
        return new TcpClient(selector, socket);
    }
}
