module async.net.tcpclient;

debug import std.stdio;

import core.stdc.errno;
import core.stdc.string;
import core.thread;
import core.sync.rwmutex;

import std.socket;
import std.conv;
import std.string;

import async.event.selector;
import async.net.tcpstream;
import async.container.bytebuffer;

class TcpClient : TcpStream
{
    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector           = selector;
        _sendLock           = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        _remoteAddress      = remoteAddress.toString();
        _fd                 = fd;
        _currentEventType   = EventType.READ;
        _closing            = false;

        _lastWriteOffset    = 0;
    }

    long read()
    {
        ubyte[]     data;
        ubyte[4096] buffer;

        while (!_closing && isAlive)
        {
            long len = _socket.receive(buffer);

            if (len > 0)
            {
                data ~= buffer[0 .. cast(uint)len];

                continue;
            }
            else if (len == 0)
            {
                return -1;
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
                    return -2;
                }
            }
        }

        if ((data.length > 0) && (_selector.onReceive !is null))
        {
            _selector.onReceive(this, data);
        }

        return data.length;
    }

    int write()
    {
        while (!_closing && isAlive && (!_writeQueue.empty() || (_lastWriteOffset > 0)))
        {
            if (_writingData.length == 0)
            {
                synchronized (_sendLock.writer)
                {
                    _writingData     = _writeQueue.front;
                    _writeQueue.popFront();
                    _lastWriteOffset = 0;
                }
            }

            while (!_closing && isAlive && (_lastWriteOffset < _writingData.length))
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

                    return -1; // sending is break and incomplete.
                }
                else
                {
                    if (errno == EINTR)
                    {
                        continue;
                    }
                    else if (errno == EAGAIN || errno == EWOULDBLOCK)
                    {
                        if (_currentEventType != EventType.READWRITE)
                        {
                            _selector.reregister(fd, EventType.READWRITE);
                            _currentEventType = EventType.READWRITE;
                        }

                        return 0; // Wait eventloop notify to continue again;
                    }
                    else
                    {
                        _writingData.length = 0;
                        _lastWriteOffset    = 0;

                        return -2; // Some error.
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

        if (_writeQueue.empty() && (_writingData.length == 0) && (_currentEventType == EventType.READWRITE))
        {
            _selector.reregister(fd, EventType.READ);
            _currentEventType = EventType.READ;
        }

        return 0;
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

        synchronized (_sendLock.writer)
        {
            _writeQueue ~= data;
        }

        write();  // First write direct, and when it encounter EAGAIN, it will open the EVENT notification.

        return 0;
    }

    void close()
    {
        _closing = true;

        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();
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

public:

    string           _remoteAddress;
    int              _fd;

private:

    Selector         _selector;
    ByteBuffer       _writeQueue;
    ubyte[]          _writingData;
    size_t           _lastWriteOffset;
    ReadWriteMutex   _sendLock;

    EventType        _currentEventType;
    shared bool      _closing;
}
