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
import async.poll;

class TcpClient : TcpStream
{
    ThreadPool.State state;

    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector      = selector;
        _writeQueue    = new Queue!(ubyte[])();

        _onRead        = new Task(&read,  this);
        _onWrite       = new Task(&write, this);

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;
    }

    override void reset(Socket socket)
    {
        super.reset(socket);

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;
    }

    void termTask()
    {
        _terming = true;

        if (_onRead.state != Task.State.TERM)
        {
            if (_onRead.state == Task.State.RESET)
            {
                _onRead.call(Task.State.TERM);
            }
            else
            {
                while (_onRead.state != Task.State.HOLD)
                {
                    Thread.sleep(50.msecs);
                }

                _onRead.call(Task.State.TERM);
            }
            
            while (_onRead.state != Task.State.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }

        if (_onWrite.state != Task.State.TERM)
        {
            if (_onWrite.state == Task.State.RESET)
            {
                _onWrite.call(Task.State.TERM);
            }
            else
            {
                while (_onWrite.state != Task.State.HOLD)
                {
                    Thread.sleep(50.msecs);
                }

                _onWrite.call(Task.State.TERM);
            }

            while (_onWrite.state != Task.State.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }
    }

    void resetTask()
    {
        assert(_onRead.state  != Task.State.TERM, "Task _onRead is terminated.");
        assert(_onWrite.state != Task.State.TERM, "Task _onWrite is terminated.");

        _reseting = true;

        if (_onRead.state != Task.State.RESET)
        {
            while (_onRead.state != Task.State.HOLD)
            {
                Thread.sleep(50.msecs);
            }
writeln("AAAA");
            _onRead.call(Task.State.RESET, 1);
writeln("BBBB");
            while (_onRead.state != Task.State.RESET)
            {
                Thread.sleep(0.msecs);
            }writeln("CCCC");
        }

        if (_onWrite.state != Task.State.RESET)
        {
            while (_onWrite.state != Task.State.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            _onWrite.call(Task.State.RESET);

            while (_onWrite.state != Task.State.RESET)
            {
                Thread.sleep(0.msecs);
            }
        }

        _reseting = false;
    }

    void weakup(EventType et)
    {
        if (!_selector.runing || _terming)
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
        Task task = cast(Task)_task;

    reset:
writeln("reset");
        TcpClient client = task.client;

        if (task.yield(Task.State.RESET) == Task.State.TERM)
        {
            goto terminate;
        }
writeln("processing");
        while (client._selector.runing && !client._terming && !client._reseting && client.isAlive)
        {
            ubyte[]     data;
            ubyte[4096] buffer;

            while (client._selector.runing && !client._terming && !client._reseting && client.isAlive)
            {
                long len = client._socket.receive(buffer);
//writeln("read: ", len, ", total: ", data.length);
                if (len > 0)
                {
                    data ~= buffer[0 .. cast(uint)len];

                    continue;
                }
                else if (len == 0)
                {
                    client._selector.removeClient(client.fd);
                    client.close();
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

        yield:
writeln("hold", " ", client.isAlive());
            Task.State ctrl = task.yield(Task.State.HOLD);
writeln("hold continue");
            if (ctrl == Task.State.RESET)
            {
                goto reset;
            }
            else if (ctrl == Task.State.TERM)
            {
                goto terminate;
            }
            else if (ctrl == Task.State.PROCESSING)
            {
                continue;
            }
        }

        if (client._reseting)
        {
            goto reset;
        }
writeln("term");
    terminate:

        task.terminate();
    }

    private static void write(shared Task _task)
    {
        Task task        = cast(Task)_task;
        TcpClient client = task.client;

    reset:

        if (task.yield(Task.State.RESET) == Task.State.TERM)
        {
            goto terminate;
        }

        while (client._selector.runing && !client._terming && !client._reseting && client.isAlive)
        {
            while (client._selector.runing && !client._terming && !client._reseting && client.isAlive && (!client._writeQueue.empty() || (client._lastWriteOffset > 0)))
            {
                if (client._writingData.length == 0)
                {
                    client._writingData     = client._writeQueue.pop();
                    client._lastWriteOffset = 0;
                }

                while (client._selector.runing && !client._terming && !client._reseting && client.isAlive && (client._lastWriteOffset < client._writingData.length))
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
                        //client.close();

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

                        goto yield; // sending is break and incomplete.
                    }
                    else
                    {
                        if (errno == EINTR)
                        {
                            continue;
                        }
                        else if (errno == EAGAIN || errno == EWOULDBLOCK)
                        {
                            goto yield;	// Wait eventloop notify to continue again;
                        }
                        else
                        {
                            client._writingData.length = 0;
                            client._lastWriteOffset    = 0;

                            goto yield; // Some error.
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

        yield:

            Task.State ctrl = task.yield(Task.State.HOLD);

            if (ctrl == Task.State.RESET)
            {
                goto reset;
            }
            else if (ctrl == Task.State.TERM)
            {
                goto terminate;
            }
            else if (ctrl == Task.State.PROCESSING)
            {
                continue;
            }
        }

        if (client._reseting)
        {
            goto reset;
        }

    terminate:

        task.terminate();
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

        _writeQueue.push(data);
        _selector.reregister(fd, EventType.READWRITE);

        return 0;
    }

    long send_withoutEventloop(in ubyte[] data)
    {
        if ((data.length == 0) || !_selector.runing || _terming || !_socket.isAlive())
        {
            return 0;
        }

        long sent = 0;

        while (_selector.runing && !_terming && isAlive && (sent < data.length))
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
        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();

        if ((errno != 0) && (_selector.onSocketError !is null))
        {
            _selector.onSocketError(_fd, _remoteAddress, fromStringz(strerror(errno)).idup);
        }

        if (_selector.onDisConnected !is null)
        {
            _selector.onDisConnected(_fd, _remoteAddress);
        }
    }

private:

    Selector           _selector;
    Queue!(ubyte[])    _writeQueue;
    ubyte[]            _writingData;
    size_t             _lastWriteOffset;

    Task               _onRead;
    Task               _onWrite;

    string             _remoteAddress;
    int                _fd;
    shared bool        _terming  = false;
    shared bool        _reseting = false;
}
