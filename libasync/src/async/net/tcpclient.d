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
    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector   = selector;
        _writeQueue = new Queue!(ubyte[])();

        _onRead     = new Fiber(&_read);
        _onWrite    = new Fiber(&_write);

        _remoteAddress = remoteAddress.toString();
        _fd            = fd;
    }

    void weakup(EventType et)
    {
        final switch (et)
        {
            case EventType.READ:
                _onRead.call();
                break;
            case EventType.WRITE:
                _onWrite.call();
                break;
            case EventType.ACCEPT:
                break;
        }
    }

    void termTask()
    {
        _terming = true;
        
        new Thread(
        {
            if (_onRead.state != Fiber.State.TERM)
            {
                while (_onRead.state != Fiber.State.HOLD)
                {
                    Thread.sleep(50.msecs);
                }
        
                weakup(EventType.READ);
                
                while (_onRead.state != Fiber.State.TERM)
                {
                    Thread.sleep(0.msecs);
                }
            }
        }).start();
        
        new Thread(
        {
            if (_onWrite.state != Fiber.State.TERM)
            {
                while (_onWrite.state != Fiber.State.HOLD)
                {
                    Thread.sleep(50.msecs);
                }
        
                weakup(EventType.WRITE);
                
                while (_onWrite.state != Fiber.State.TERM)
                {
                    Thread.sleep(0.msecs);
                }
            }
        }).start();
    }

    private void _read()
    {
        while (true)
        {
            ubyte[]     data;
            ubyte[4096] buffer;

            while (true)
            {
                long len = _socket.receive(buffer);

                if (len > 0)
                {
                    data ~= buffer[0 .. cast(uint)len];

                    continue;
                }
                else if (len == 0)
                {
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

            if (data.length > 0)
            {
                _selector.onReceive(this, data);
            }

            Fiber.yield();

            if (!_selector.runing || _terming)
            {
                break;
            }
        }
    }

    private void _write()
    {
//        if (!_socket.isAlive())
//        {
//            return;
//        }
//
//        long sent = 0;
//
//        while (sent < data.length)
//        {
//            long len = _socket.send(data[cast(uint)sent .. $]);
//
//            if (len > 0)
//            {
//                sent += len;
//                continue;
//            }
//            else if (len == 0)
//            {
//                _selector.removeClient(fd);
//                close();
//                break;
//            }
//            else
//            {
//                if (errno == EINTR)
//                {
//                    continue;
//                }
//                else if (errno == EAGAIN || errno == EWOULDBLOCK)
//                {
//                    //Thread.sleep(500.msecs);
//                    continue;
//                }
//                else
//                {
//                    _selector.removeClient(fd);
//                    close(errno);
//                    break;
//                }
//            }
//        }
//
//        if (sent < data.length)
//        {
//            debug writefln("The sending is incomplete, the total length is %d, but actually sent only %d.", data.length, sent);
//        }

        //return sent;
    }

    long write(in ubyte[] data)
    {
//        if (!_socket.isAlive())
//        {
//            return -1;
//        }
//
//        _writeQueue.push(cast(ubyte[])data);
//
//        return 0;

        if (!_socket.isAlive())
        {
            return 0;
        }

        long sent = 0;

        while (sent < data.length)
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
                    Thread.sleep(0.msecs);
                    continue;
                }
                else
                {
                    break;
                }
            }
        }

        if (sent < data.length)
        {
            debug writefln("The sending is incomplete, the total length is %d, but actually sent only %d.", data.length, sent);
        }

        return sent;
    }

    void close(int errno = 0)
    {
        termTask();

        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();

        if (errno != 0)
        {
            _selector.onSocketError(_fd, _remoteAddress, fromStringz(strerror(errno)).idup);
        }

        _selector.onDisConnected(_fd, _remoteAddress);
    }

private:

    Selector        _selector;
    Queue!(ubyte[]) _writeQueue;

    Fiber           _onRead;
    Fiber           _onWrite;

    string          _remoteAddress;
    int             _fd;
    bool            _terming = false;
}