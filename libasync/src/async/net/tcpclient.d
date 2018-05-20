module async.net.tcpclient;

debug import std.stdio;

import core.stdc.errno;
import core.stdc.string;
import core.thread;
import core.sync.mutex;

import std.socket;
import std.conv;
import std.string;

import async.event.selector;
import async.net.tcpstream;
import async.container.queue;
import async.thread;
import async.pool;

class TcpClient : TcpStream
{
    shared ThreadPool.State state;

    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector      = selector;
        _sendLock      = new Mutex;

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;

        _onRead        = new Task(&read,  this);
        _onWrite       = new Task(&write, this);
    }

    void reset(Selector selector, Socket socket)
    {
        _selector = selector;
        super.reset(socket);

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;
        _closing       = false;

        _writeQueue.clear();
        _writingData.length = 0;
        _lastWriteOffset    = 0;
    }

    @property Selector selector()
    {
        return _selector;
    }

    void termTask()
    {
        _closing = true;

        if (_onRead.state != Task.State.TERM)
        {
            while (_onRead.state != Task.State.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            _onRead.call(Task.State.TERM);

            while (_onRead.state != Task.State.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }

        if (_onWrite.state != Task.State.TERM)
        {
            while (_onWrite.state != Task.State.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            _onWrite.call(Task.State.TERM);

            while (_onWrite.state != Task.State.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }
    }

    private void waitTaskHold()
    {
        while ((_onRead.state != Task.State.TERM) && (_onRead.state != Task.State.HOLD))
        {
            Thread.sleep(50.msecs);
        }

        while ((_onWrite.state != Task.State.TERM) && (_onWrite.state != Task.State.HOLD))
        {
            Thread.sleep(50.msecs);
        }
    }

    void weakup(EventType et)
    {
        if (!_selector.runing || _closing)
        {
            return;
        }

        final switch (et)
        {
        case EventType.READ:
            _onRead.call(Task.State.PROCESSING);
            break;
        case EventType.WRITE:
            if (!_writeQueue.empty() || (_lastWriteOffset > 0))
            {
                _onWrite.call(Task.State.PROCESSING);
            }
            break;
        case EventType.ACCEPT:
        case EventType.READWRITE:
            break;
        }
    }

    private static void read(shared Task _task)
    {
        Task task        = cast(Task)_task;
        TcpClient client = task.client;

        while (task.yield(Task.State.HOLD) != Task.State.TERM)
        {
            ubyte[]     data;
            ubyte[4096] buffer;

            while (client._selector.runing && !client._closing && client.isAlive)
            {
                long len = client._socket.receive(buffer);

                if (len > 0)
                {
                    data ~= buffer[0 .. cast(uint)len];

                    continue;
                }
                else if (len == 0)
                {
                    version (linux)
                    {
                        client._selector.removeClient(client.fd);
                    }
                    data = null;

                    break;
                }
                else
                {
                    if (errno == EINTR)
                    {
                        continue;
                    }
                    else if (errno == EAGAIN || errno == EWOULDBLOCK)
                    {
                        break;
                    }
                    else
                    {
                        data = null;

                        break;
                    }
                }
            }

            if ((data.length > 0) && (client._selector.onReceive !is null))
            {
                client._selector.onReceive(client, data);
            }
        }
    }

    private static void write(shared Task _task)
    {
        Task task        = cast(Task)_task;
        TcpClient client = task.client;

        first: while (task.yield(Task.State.HOLD) != Task.State.TERM)
        {
            second: while (client._selector.runing && !client._closing && client.isAlive && (!client._writeQueue.empty() || (client._lastWriteOffset > 0)))
            {
                if (client._writingData.length == 0)
                {
                    synchronized(client._sendLock)
                    {
                        client._writingData     = client._writeQueue.pop();
                        client._lastWriteOffset = 0;
                    }
                }

                while (client._selector.runing && !client._closing && client.isAlive && (client._lastWriteOffset < client._writingData.length))
                {
                    long len = client._socket.send(client._writingData[cast(uint)client._lastWriteOffset .. $]);

                    if (len > 0)
                    {
                        client._lastWriteOffset += len;

                        continue;
                    }
                    else if (len == 0)
                    {
                        //client._selector.removeClient(fd);

                        if (client._lastWriteOffset < client._writingData.length)
                        {
                            if (client._selector.onSendCompleted !is null)
                            {
                                client._selector.onSendCompleted(client._fd, client._remoteAddress, client._writingData, cast(size_t)client._lastWriteOffset);
                            }

                            debug writefln("The sending is incomplete, the total length is %d, but actually sent only %d.", client._writingData.length, client._lastWriteOffset);
                        }

                        client._writingData.length = 0;
                        client._lastWriteOffset    = 0;

                        continue first; // sending is break and incomplete.
                    }
                    else
                    {
                        if (errno == EINTR)
                        {
                            continue;
                        }
                        else if (errno == EAGAIN || errno == EWOULDBLOCK)
                        {
                            continue first; // Wait eventloop notify to continue again;
                        }
                        else
                        {
                            client._writingData.length = 0;
                            client._lastWriteOffset    = 0;

                            continue first; // Some error.
                        }
                    }
                }

                if (client._lastWriteOffset == client._writingData.length)
                {
                    if (client._selector.onSendCompleted !is null)
                    {
                        client._selector.onSendCompleted(client._fd, client._remoteAddress, client._writingData, cast(size_t)client._lastWriteOffset);
                    }

                    client._writingData.length = 0;
                    client._lastWriteOffset    = 0;
                }
            }

            if (client._writeQueue.empty() && (client._writingData.length == 0))
            {
                client._selector.reregister(client.fd, EventType.READ);
            }
        }
    }

    int send(ubyte[] data)
    {
        if (data.length == 0)
        {
            return -1;
        }

        if (!isAlive())
        {
            return -2;
        }

        synchronized(_sendLock)
        {
            _writeQueue.push(data);
        }
        _selector.reregister(fd, EventType.READWRITE);

        return 0;
    }

    long send_withoutEventloop(in ubyte[] data)
    {
        if ((data.length == 0) || !_selector.runing || _closing || !_socket.isAlive())
        {
            return 0;
        }

        long sent = 0;

        while (_selector.runing && !_closing && isAlive && (sent < data.length))
        {
            long len = _socket.send(data[cast(uint)sent .. $]);

            if (len > 0)
            {
                sent += len;

                continue;
            }
            else if (len == 0)
            {
                break;
            }
            else
            {
                if (errno == EINTR)
                {
                    continue;
                }
                else if (errno == EAGAIN || errno == EWOULDBLOCK)
                {
                    Thread.sleep(50.msecs);

                    continue;
                }
                else
                {
                    break;
                }
            }
        }

        if (_selector.onSendCompleted !is null)
        {
            _selector.onSendCompleted(_fd, _remoteAddress, data, cast(size_t)sent);
        }

        if (sent != data.length)
        {
            debug writefln("The sending is incomplete, the total length is %d, but actually sent only %d.", data.length, sent);
        }

        return sent;
    }

    void close(int errno = 0)
    {
        _closing = true;

        if ((errno != 0) && (_selector.onSocketError !is null))
        {
            _selector.onSocketError(_fd, _remoteAddress, fromStringz(strerror(errno)).idup);
        }

        if (_selector.onDisConnected !is null)
        {
            _selector.onDisConnected(_fd, _remoteAddress);
        }

        waitTaskHold();

        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();

        _fd            = -1;
        _remoteAddress = string.init;
    }

private:

    Selector           _selector;
    Queue!(ubyte[])    _writeQueue;
    ubyte[]            _writingData;
    size_t             _lastWriteOffset;
    Mutex              _sendLock;

    Task               _onRead;
    Task               _onWrite;

    string             _remoteAddress;
    int                _fd;
    shared bool        _closing = false;
}
