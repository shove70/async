module async.net.tcpclient;

debug import std.stdio;

import core.stdc.errno;
import core.stdc.string;
import core.thread;
import core.sync.rwmutex;

import std.socket;
import std.conv;
import std.string;
import std.typecons : Tuple;

import async.event.selector;
import async.eventloop;
import async.net.tcplistener;
import async.container.bytebuffer;

class TcpClient : TcpListener
{
    this(Selector selector, Socket socket)
    {
        super(socket);
        _selector           = selector;
        _remoteAddress      = remoteAddress.toString();
        _fd                 = fd;
        _closing            = false;

        version (Windows) { } else
        {
            _hasReadEvent       = false;
            _hasWriteEvent      = false;
            _reading            = false;
            _writing            = false;
            _sendLock           = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
            _currentEventType   = EventType.READ;
            _lastWriteOffset    = 0;
        }
    }

    version (Windows) { } else void weakup(EventType event)
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
    version (Windows) { } else
    {
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
            ubyte[]     data;
			ubyte[4096] buffer = void;

            while (!client._closing && client.isAlive)
            {
                long len = client._socket.receive(buffer);

                if (len > 0)
                {
                    data ~= buffer[0 .. cast(uint)len];

                    continue;
                }
                else if (len == 0)
                {
                    client.readCallback(-1);
                    return;
                }
                else
                {
                    if (errno == EINTR)
                    {
                        continue;
                    }
                    else if (errno == EAGAIN/* || errno == EWOULDBLOCK*/)
                    {
                        break;
                    }
                    else
                    {
                        client.readCallback(errno);
                        return;
                    }
                }
            }

            if ((data.length > 0) && (client._selector.onReceive !is null))
            {
                if (client._selector.codec is null)
                {
                    client._selector.onReceive(client, data);
                }
                else
                {
                    client._receiveBuffer ~= data;

                    label_parseOne:
					const ret = client._selector.codec.decode(client._receiveBuffer);

                    if (ret[0] >= 0)
                    {
                        const ubyte[] message = client._receiveBuffer[0 .. ret[0]];
                        client._receiveBuffer.popFront(ret[0] + ret[1]);
                        client._selector.onReceive(client, message);
                        goto label_parseOne;
                    }
                    else if (ret[0] == -2) // The magic is error.
                    {
                        client.forceClose();
                        return;
                    }
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
            while (!client._closing && client.isAlive && (!client._writeQueue.empty() || (client._lastWriteOffset > 0)))
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

                while (!client._closing && client.isAlive && (client._lastWriteOffset < client._writingData.length))
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

                        client.writeCallback(-1);  // sending is break and incomplete.
                        return;
                    }
                    else
                    {
                        if (errno == EINTR)
                        {
                            continue;
                        }
                        else if (errno == EAGAIN/* || errno == EWOULDBLOCK*/)
                        {
                            if (client._currentEventType != EventType.READWRITE)
                            {
                                client._selector.reregister(client.fd, EventType.READWRITE);
                                client._currentEventType = EventType.READWRITE;
                            }

                            client.writeCallback(0);  // Wait eventloop notify to continue again;
                            return;
                        }
                        else
                        {
                            client._writingData.length = 0;
                            client._lastWriteOffset    = 0;

                            client.writeCallback(errno);  // Some error.
                            return;
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

            if (client._writeQueue.empty() && (client._writingData.length == 0) && (client._currentEventType == EventType.READWRITE))
            {
                client._selector.reregister(client.fd, EventType.READ);
                client._currentEventType = EventType.READ;
            }

            client.writeCallback(0);
            return;
        }

        void writeCallback(const int err)  // err: 0: OK, -1: client disconnection, 1,2... errno
        {
            _writing = false;

            if (_hasWriteEvent)
            {
                beginWrite();
            }
        }
    }

public:

    version (Windows)
    {
		int send(const(void)[] data) @trusted
        {
            if (data.length == 0)
            {
                return -1;
            }

            if (!isAlive())
            {
                return -2;
            }

            _selector.iocp_send(_fd, data);

            return 0;
        }
    }
    else
    {
        int send(const scope ubyte[] data)
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

            weakup(EventType.WRITE);  // First write direct, and when it encounter EAGAIN, it will open the EVENT notification.

            return 0;
        }
    }

    override void close()
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

    string           _remoteAddress;
    int              _fd;

private:

    Selector         _selector;
    shared bool      _closing;

    version (Windows) { } else
    {
        shared bool      _hasReadEvent;
        shared bool      _hasWriteEvent;
        shared bool      _reading;
        shared bool      _writing;

        ByteBuffer       _writeQueue;
        ubyte[]          _writingData;
        size_t           _lastWriteOffset;
        ReadWriteMutex   _sendLock;

        EventType        _currentEventType;
    }

    ByteBuffer       _receiveBuffer;
}
