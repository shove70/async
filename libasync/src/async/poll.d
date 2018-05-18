module async.poll;

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

    this()
    {
        _busyQueue = new Queue!TcpClient();
        _idleQueue = new Queue!TcpClient();
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
        TcpClient client;

        if (_idleQueue.empty())
        {
            client = create(selector, socket);
        }
        else
        {
            client = _idleQueue.pop();
            client.reset(socket);
        }

        client.state = State.BUSY;
        _busyQueue.push(client);

        return client;
    }

    void revert(TcpClient client)
    {
        client.state = State.IDLE;
        _idleQueue.push(client);
    }

    void removeAll()
    {
        while (!_idleQueue.empty())
        {
            TcpClient client = _idleQueue.pop();
            client.termTask();
        }

        _busyQueue.clear();
    }

private:

	__gshared ThreadPool _instance = null;

    Queue!TcpClient      _busyQueue;
    Queue!TcpClient      _idleQueue;

    TcpClient create(Selector selector, Socket socket)
    {
        return new TcpClient(selector, socket);
    }
}
