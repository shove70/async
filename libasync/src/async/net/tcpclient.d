module async.net.tcpclient;

debug import std.stdio;

import core.thread;
import core.stdc.errno;
import std.socket;
import std.conv;

import async.event.selector;
import async.net.tcpstream;

class TcpClient : TcpStream
{
    this(Selector selector, Socket socket)
    {
        super(socket);
        _selector  = selector;

        _readTask = new Fiber(&onRead);
    }

    ~this()
    {
        _readTask.call();
    }

    void weakup()
    {
        _readTask.call();
    }

    private void onRead()
    {
        while (true)
        {
            ubyte[] data;

            while (true)
            {
                ubyte[8192] buffer;
                long len = _socket.receive(buffer);

                if (len > 0)
                {
                    data ~= buffer[0 .. len];

                    continue;
                }
                else if (len == 0)
                {
                    close();
                    _selector.onDisConnected(this);
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
                        close();
                        _selector.onSocketError(this, "errno: " ~ errno.to!string);
        	            break;
        	        }
                }
            }

            if (data.length > 0)
            {
                _selector.onReceive(this, data);
            }

            Fiber.yield();

            if (!_selector.runing)
            {
                break;
            }
        }
    }

    long write(in ubyte[] data)
    {
        long off = 0, sent = 0;

        while (sent < data.length)
        {
            long len = _socket.send(data[off .. $]);

            if (len > 0)
            {
                sent += len;
                continue;
            }
            else if (len == 0)
            {
                close();
                _selector.onDisConnected(this);
                break;
            }
            else
            {
                if (errno == EINTR)
                {
                    continue;
                }
                else if (errno == EAGAIN && errno == EWOULDBLOCK)
                {
                    Thread.sleep(50.msecs);
                    continue;
                }
                else
                {
                    close();
                    _selector.onSocketError(this, "errno: " ~ errno.to!string);
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

    void close()
    {
        _selector.removeClient(fd);
        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();
    }

private:

    Selector  _selector;
    Fiber     _readTask;
}