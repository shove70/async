import core.thread;

void main()
{
    auto data = new ubyte[10000];
    data[0] = 1;
    data[$ - 1] = 2;

    foreach (i; 0..3)
    {
        new Thread( { go(data); } ).start();
    }
}

shared long total;

private void go(ubyte[] data)
{
    import
        core.stdc.errno,
        core.atomic,
        std.outbuffer,
        std.stdio,
        std.socket;

    foreach (i; 0..100000)
    {
        auto socket = new TcpSocket;
        socket.connect(new InternetAddress("127.0.0.1", 12290));

        auto ob = new OutBuffer;
        ob.write(cast(int)data.length);
        ob.write(data);
        auto buffer = ob.toBytes();

        long len;
        for (size_t off; off < buffer.length; off += len)
        {
            len = socket.send(buffer[off..$]);

            if (len > 0)
            {
                continue;
            }
            if (len == 0)
            {
                writefln("Server socket close at send. Local socket: %s", socket.localAddress);
                socket.close();

                return;
            }
            if (errno == EINTR || errno == EAGAIN/* || errno == EWOULDBLOCK*/)
            {
                len = 0;
                continue;
            }

            writefln("Socket error at send. Local socket: %s, error: %s", socket.localAddress, formatSocketError(errno));
            socket.close();

            return;
        }

        for (size_t off; off < buffer.length; off += len)
        {
            len = socket.receive(buffer[off..$]);

            if (len > 0)
            {
                continue;
            }
            if (len == 0)
            {
                writefln("Server socket close at receive. Local socket: %s", socket.localAddress);
                socket.close();

                return;
            }
            if (errno == EINTR || errno == EAGAIN/* || errno == EWOULDBLOCK*/)
            {
                len = 0;
                continue;
            }

            writefln("Socket error at receive. Local socket: %s, error: %s", socket.localAddress, formatSocketError(errno));
            socket.close();

            return;
        }

        atomicOp!"+="(total, 1);
        writeln(total, ": receive: [0]: ", buffer[4], ", [$ - 1]: ", buffer[$ - 1]);

        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
        Thread.sleep(50.msecs);
    }
}
