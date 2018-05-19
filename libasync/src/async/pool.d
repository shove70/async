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

    TcpClient take(Selector selector, Socket socket)
    {
        TcpClient client = null;

        if (!_idleQueue.empty())
        {
            synchronized (this.classinfo)
            {
                if (!_idleQueue.empty())
                {
                    client = _idleQueue.pop();
                }
            }
        }

        if (client is null)
        {
            client = create(selector, socket);
        }
        else
        {
            client.reset(selector, socket);
        }

        client.state = State.BUSY;

        return client;
    }

    void revert(TcpClient client)
    {
        client.state = State.IDLE;

        synchronized (this.classinfo)
        {
            _idleQueue.push(client);
        }
    }

    void removeAll()
    {
        synchronized (this.classinfo)
        {
            while (!_idleQueue.empty())
            {
                _idleQueue.pop().termTask();
            }
        }
    }

private:

	__gshared ThreadPool _instance = null;
    Queue!TcpClient      _idleQueue;

    TcpClient create(Selector selector, Socket socket)
    {
        return new TcpClient(selector, socket);
    }
}
