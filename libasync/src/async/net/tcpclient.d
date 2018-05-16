module async.net.tcpclient;

debug import std.stdio;

import core.stdc.errno;
import core.stdc.string;
import core.thread;
import core.sync.mutex;

import std.socket;
import std.conv;
import std.string;
import std.concurrency;

import async.event.selector;
import async.net.tcpstream;
import async.container.queue;

class TcpClient : TcpStream
{
    debug
    {
        __gshared int thread_read_counter  = 0;
        __gshared int thread_write_counter = 0;
        __gshared int client_count         = 0;
        __gshared int socket_counter       = 0;
    }

    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector      = selector;
        _writeQueue    = new Queue!(ubyte[])();

        _onRead        = spawn(&read,  cast(shared TcpClient)this);
        _onWrite       = spawn(&write, cast(shared TcpClient)this);
        _readLock      = new Mutex;
        _writeLock     = new Mutex;

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;

        debug
        {
            thread_read_counter++;
            thread_write_counter++;
            client_count++;
            socket_counter++;
        }
    }

    ~this()
    {
        while (_readState != ThreadState.TERM)
        {
            Thread.sleep(0.msecs);
        }
        while (_writeState != ThreadState.TERM)
        {
            Thread.sleep(0.msecs);
        }

        debug
        {
            writeln("Client dispose end.");
        }
    }

    void termTask()
    {
        _terming = true;

        if (_readState != ThreadState.TERM)
        {
            while (_readState != ThreadState.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            call!"read"();

            while (_readState != ThreadState.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }

        if (_writeState != ThreadState.TERM)
        {
            while (_writeState != ThreadState.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            call!"write"();

            while (_writeState != ThreadState.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }

        debug
        {
            client_count--;
            writeln("TermTask dispose end.");
        }
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
            call!"read"();
            break;
        case EventType.WRITE:
            if (!_writeQueue.empty() || (_lastWriteOffset > 0))
            {
                call!"write"();
            }
            break;
        case EventType.ACCEPT:
        case EventType.READWRITE:
            break;
        }
    }

    private static void read(shared TcpClient _client)
    {
        TcpClient client = cast(TcpClient)_client;

        client._readState = ThreadState.HOLD;
        receiveOnly!int();
        client._readState = ThreadState.RUNNING;

        while (client._selector.runing && !client._terming && client.isAlive)
        {
            ubyte[]     data;
            ubyte[4096] buffer;

            while (client._selector.runing && !client._terming && client.isAlive)
            {
                long len = client._socket.receive(buffer);

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

            client._readState = ThreadState.HOLD;
            receiveOnly!int();
            client._readState = ThreadState.RUNNING;
        }

        debug
        {
            client.thread_read_counter--;
        }

        client._readState = ThreadState.TERM;
    }

    private static void write(shared TcpClient _client)
    {
        TcpClient client = cast(TcpClient)_client;

        client._writeState = ThreadState.HOLD;
        receiveOnly!int();
        client._writeState = ThreadState.RUNNING;

        while (client._selector.runing && !client._terming && client.isAlive)
        {
            while (client._selector.runing && !client._terming && client.isAlive && (!client._writeQueue.empty() || (client._lastWriteOffset > 0)))
            {
                if (client._writingData.length == 0)
                {
                    client._writingData     = client._writeQueue.pop();
                    client._lastWriteOffset = 0;
                }

                while (client._selector.runing && !client._terming && client.isAlive && (client._lastWriteOffset < client._writingData.length))
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
            client._writeState = ThreadState.HOLD;
            receiveOnly!int();
            client._writeState = ThreadState.RUNNING;
        }

        debug
        {
            client.thread_write_counter--;
        }

        client._writeState = ThreadState.TERM;
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

        debug
        {
            socket_counter--;
        }

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

    Tid                _onRead;
    Tid                _onWrite;
     ThreadState _readState  = ThreadState.HOLD;
     ThreadState _writeState = ThreadState.HOLD;
    Mutex              _readLock;
    Mutex              _writeLock;

    string             _remoteAddress;
    int                _fd;
    bool               _terming = false;

    void call(string T)()
    {
        Mutex       lock;
        Tid         tid;
        ThreadState state;

        static if (T == "read")
        {
            lock  = _readLock;
            tid   = _onRead;
            state = _readState;
        }
        else
        {
            lock  = _writeLock;
            tid   = _onWrite;
            state = _writeState;
        }

        if (state == ThreadState.HOLD)
        synchronized (lock)
        {
            if (state == ThreadState.HOLD)
            {
                tid.send(1);
            }
        }
    }
}

enum ThreadState
{
    HOLD, RUNNING, TERM
}
