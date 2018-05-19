import std.stdio;
import std.conv;
import std.socket;
import std.concurrency;
import core.thread;
import core.stdc.errno;

int size = 10000000;

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

__gshared long total = 0;

private void go(ubyte[] data)
{
    for (int i = 0; i < 1000; i++)
    {
        TcpSocket socket = new TcpSocket();
        socket.blocking = true;
        socket.connect(new InternetAddress("127.0.0.1", 12290));

        long len;
        for (size_t off; off < data.length; off += len) {
            len = socket.send(data[off..$]);
            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                socket.close();
                writeln("Server socket close at send.");
                return;
            }
            else
            {
                len = 0;
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
                    socket.close();
                    writeln("Socket error at send.");
                    return;
                }
            }
        }

        ubyte[] buffer = new ubyte[size];

        len = 0;
        for (size_t off; off < buffer.length; off += len) {
            len = socket.receive(buffer[off..$]);
            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                socket.close();
                writeln("Server socket close at receive.");
                return;
            }
            else
            {
                len = 0;
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
                    socket.close();
                    writeln("Socket error at receive.");
                    return;
                }
            }
        }

        total++;
        writeln(total.to!string, ": receive: ", "[0]: ", buffer[0], ", [$ - 1]: ", buffer[$ - 1]);
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
    }
}
