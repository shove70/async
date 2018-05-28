import std.stdio;
import std.conv;
import std.socket;
import std.concurrency;
import core.thread;
import core.stdc.errno;
import core.atomic;

int size = 10000;

void main(string[] argv)
{
    ubyte[] data = new ubyte[size];
    data[0] = 1;
    data[$ - 1] = 2;

    for (int i = 0; i < 10; i++)
    {
        new Thread(
            {
                go(data);
            }
        ).start();
    }
}

shared long total = 0;

private void go(ubyte[] data)
{
    for (int i = 0; i < 100000; i++)
    {
        TcpSocket socket = new TcpSocket();
        socket.blocking = true;
        socket.connect(new InternetAddress("127.0.0.1", 12290));

        long len;
        for (size_t off; off < data.length; off += len)
        {
            len = socket.send(data[off..$]);

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
                writefln("Socket error at send. Local socket: %s, error: %s", socket.localAddress().toString(), formatSocketError(errno));
                socket.close();

                return;
            }
        }

        ubyte[] buffer = new ubyte[size];

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
                writefln("Socket error at receive. Local socket: %s, error: %s", socket.localAddress().toString(), formatSocketError(errno));
                socket.close();

                return;
            }
        }

        core.atomic.atomicOp!"+="(total, 1);
        writeln(total.to!string, ": receive: ", "[0]: ", buffer[0], ", [$ - 1]: ", buffer[$ - 1]);

        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
    }
}
