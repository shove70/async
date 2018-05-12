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

class TcpClient : TcpStream
{
    this(Selector selector, Socket socket)
    {
        super(socket);

        _selector = selector;
        _readTask = new Fiber(&onRead);

        _remoteAddress = socket.remoteAddress().toString();
    }

    void weakup()
    {
        try
        {
            _readTask.call();
        }
        catch (Exception e) { }
    }

    void termTask()
    {
        _terming = true;
        while (_readTask.state != Fiber.State.HOLD) { Thread.sleep(0.msecs); }
        while (_readTask.state != Fiber.State.TERM)
        {
            weakup();
            Thread.sleep(0.msecs);writeln("Term.............OK");
        }
    }

    private void onRead()
    {
        while (true)
        {
            ubyte[] data;

            while (true)
            {
                ubyte[4096] buffer;
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
        	            _selector.removeClient(fd);
                        close();
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

    long write(in ubyte[] data)
    {
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
                _selector.removeClient(fd);
                close();
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
                    _selector.removeClient(fd);
                    close();
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
        new Thread( { Thread.sleep(0.seconds); termTask(); } ).start();

        _socket.shutdown(SocketShutdown.BOTH);
        _socket.close();

        _selector.onSocketError(_remoteAddress, fromStringz(strerror(errno)).idup);
    }

public:
    string    _remoteAddress;

private:

    Selector  _selector;
    Fiber     _readTask;

    bool      _terming = false;
}