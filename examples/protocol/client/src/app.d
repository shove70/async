import core.stdc.errno;
import core.atomic;
import core.thread;

import std.stdio;
import std.conv;
import std.socket;
import std.bitmanip;

void main(string[] argv)
{
    ubyte[] data = new ubyte[10000];
    data[0] = 1;
    data[$ - 1] = 2;

    for (int i = 0; i < 3; i++)
    {
        new Thread( { go(data); } ).start();
    }
}

shared long total = 0;

private void go(ubyte[] data)
{
    for (int i = 0; i < 100000; i++)
    {
        TcpSocket socket = new TcpSocket();
        socket.connect(new InternetAddress("127.0.0.1", 12290));

        ubyte[] buffer = new ubyte[4];
        buffer.write!int(cast(int)data.length, 0);
        buffer ~= data;

        long len;
        for (size_t off; off < buffer.length; off += len)
        {
            len = socket.send(buffer[off..$]);

            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                writefln("Server socket close at send. Local socket: %s", socket.localAddress().toString());
                socket.close();

                return;
            }
            else
            {
                if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)
                {
                    len = 0;
                    continue;
                }

                writefln("Socket error at send. Local socket: %s, error: %s", socket.localAddress().toString(), formatSocketError(errno));
                socket.close();

                return;
            }
        }

        len = 0;
        for (size_t off; off < buffer.length; off += len)
        {
            len = socket.receive(buffer[off..$]);

            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                writefln("Server socket close at receive. Local socket: %s", socket.localAddress().toString());
                socket.close();

                return;
            }
            else
            {
                if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)
                {
                    len = 0;
                    continue;
                }

                writefln("Socket error at receive. Local socket: %s, error: %s", socket.localAddress().toString(), formatSocketError(errno));
                socket.close();

                return;
            }
        }

        core.atomic.atomicOp!"+="(total, 1);
        writeln(total.to!string, ": receive: ", "[0]: ", buffer[4], ", [$ - 1]: ", buffer[$ - 1]);

        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
        Thread.sleep(50.msecs);
    }
}
