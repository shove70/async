module async.net.tcpclient;

debug import std.stdio;

import core.thread;
import core.stdc.errno;
import core.stdc.string;

import std.socket;
import std.conv;
import std.string;

import async.event.selector;
import async.net.tcpstream;
import async.container.queue;

class TcpClient : TcpStream
{
    debug
    {
        __gshared int fiber_read_counter = 0;
        __gshared int fiber_write_counter = 0;
        __gshared int socket_counter = 0;
    }

    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector   = selector;
        _writeQueue = new Queue!(ubyte[])();

        _onRead     = new Fiber(&read);
        _onWrite    = new Fiber(&write);

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;

        debug
        {
            fiber_read_counter++;
            fiber_write_counter++;
            socket_counter++;
        }
    }

    ~this()
    {
        while (_onRead.state != Fiber.State.TERM)
        {
            Thread.sleep(0.msecs);
        }
        while (_onWrite.state != Fiber.State.TERM)
        {
            Thread.sleep(0.msecs);
        }

        debug writeln("client dispose end.");
    }

    void termTask()
    {
        _terming = true;

        if (_onRead.state != Fiber.State.TERM)
        {
            while (_onRead.state != Fiber.State.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            _onRead.call();

            while (_onRead.state != Fiber.State.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }

        if (_onWrite.state != Fiber.State.TERM)
        {
            while (_onWrite.state != Fiber.State.HOLD)
            {
                Thread.sleep(50.msecs);
            }

            _onWrite.call();

            while (_onWrite.state != Fiber.State.TERM)
            {
                Thread.sleep(0.msecs);
            }
        }
        debug writeln("termTask dispose end.");
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
            _onRead.call();
            break;
        case EventType.WRITE:
            if (!_writeQueue.empty() || (_lastWriteOffset > 0))
            {
                _onWrite.call();
            }
            break;
        case EventType.ACCEPT:
        case EventType.READWRITE:
            break;
        }
    }

    private void read()
    {
        while (_selector.runing && !_terming && isAlive)
        {
            ubyte[]     data;
            ubyte[4096] buffer;

            while (_selector.runing && !_terming && isAlive)
            {
                long len = _socket.receive(buffer);

                if (len > 0)
                {
                    data ~= buffer[0 .. cast(uint)len];

                    continue;
                }
                else if (len == 0)
                {
                    _selector.removeClient(fd);
                    close();
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

            if ((data.length > 0) && (_selector.onReceive !is null))
            {
                _selector.onReceive(this, data);
            }

            Fiber.yield();
        }

        debug
        {
            fiber_read_counter--;
        }
    }

    private void write()
    {
        while (_selector.runing && !_terming && isAlive)
        {
            while (_selector.runing && !_terming && isAlive && (!_writeQueue.empty() || (_lastWriteOffset > 0)))
            {
                if (_writingData.length == 0)
                {
                    _writingData     = _writeQueue.pop();
                    _lastWriteOffset = 0;
                }

                while (_selector.runing && !_terming && isAlive && (_lastWriteOffset < _writingData.length))
                {
                    long len = _socket.send(_writingData[cast(uint)_lastWriteOffset .. $]);

                    if (len > 0)
                    {
                        _lastWriteOffset += len;

                        continue;
                    }
                    else if (len == 0)
                    {
                        //_selector.removeClient(fd);
                        //close();

                        if (_lastWriteOffset < _writingData.length)
                        {
                            if (_selector.onSendCompleted !is null)
                            {
                                _selector.onSendCompleted(_fd, _remoteAddress, _writingData, cast(size_t)_lastWriteOffset);
                            }

                            debug writefln("The sending is incomplete, the total length is %d, but actually sent only %d.", _writingData.length, _lastWriteOffset);
                        }

                        _writingData.length = 0;
                        _lastWriteOffset    = 0;

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
                            _writingData.length = 0;
                            _lastWriteOffset    = 0;

                            goto yield; // Some error.
                        }
                    }
                }

                if (_lastWriteOffset == _writingData.length)
                {
                    if (_selector.onSendCompleted !is null)
                    {
                        _selector.onSendCompleted(_fd, _remoteAddress, _writingData, cast(size_t)_lastWriteOffset);
                    }

                    _writingData.length = 0;
                    _lastWriteOffset    = 0;
                }
            }

            if (_writeQueue.empty() && (_writingData.length == 0))
            {
                _selector.reregister(fd, EventType.READ);
            }

        yield:
            Fiber.yield();
        }

        debug
        {
            fiber_write_counter--;
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

        _writeQueue.push(cast(ubyte[])data);
        _selector.reregister(fd, EventType.READWRITE);

        return 0;
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

    Selector        _selector;
    Queue!(ubyte[]) _writeQueue;
    ubyte[]         _writingData;
    size_t          _lastWriteOffset;

    Fiber           _onRead;
    Fiber           _onWrite;

    string          _remoteAddress;
    int             _fd;
    bool            _terming = false;
}