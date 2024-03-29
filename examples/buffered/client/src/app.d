import std.stdio;
import std.conv;
import std.socket;
import std.concurrency;
import core.thread;
import core.stdc.errno;
import core.atomic;
import std.bitmanip;
import std.datetime;

import buffer.message;
import crypto.rsa;

mixin(LoadBufferFile!"account.buffer");

__gshared RSAKeyInfo publicKey;

void main()
{
    publicKey = RSA.decodeKey("AAAAIH4RaeCOInmS/CcWOrurajxk3dZ4XGEZ9MsqT3LnFqP3/uk=");
    Message.settings(615, publicKey, true);

    foreach (i; 0..200)
    {
        new Thread( { go(); } ).start();
    }
}

shared long total;

private void go()
{
    for (int i; i < 100000; i++)
    {
        i++;
        auto req = new LoginRequest;
        req.idOrMobile = "userId";
        req.password   = "******";
        req.UDID       = Clock.currTime().toUnixTime().to!string;
        ubyte[] buf = req.serialize("login");

        auto socket = new TcpSocket;

        try
        {
            socket.connect(new InternetAddress("127.0.0.1", 12290));
        }
        catch(Exception e)
        {
            writeln(e);
            continue;
        }

        long len;
        for (size_t off; off < buf.length; off += len)
        {
            len = socket.send(buf[off..$]);

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

        ubyte[] buffer;

        buf = new ubyte[ushort.sizeof];
        len = socket.receive(buf);

        if (len != ushort.sizeof)
        {
            writefln("Socket error at receive1. Local socket: %s, error: %s", socket.localAddress, formatSocketError(errno));
            socket.close();

            return;
        }

        if (buf.peek!ushort(0) != 615)
        {
            writefln("Head isn't 407. Local socket: %s", socket.localAddress);
            socket.close();

            return;
        }

        buffer ~= buf;

        buf = new ubyte[int.sizeof];
        len = socket.receive(buf);

        if (len != int.sizeof)
        {
            writefln("Socket error at receive2. Local socket: %s, error: %s", socket.localAddress, formatSocketError(errno));
            socket.close();

            return;
        }

        size_t size = buf.peek!int(0);
        buffer ~= buf;

        buf = new ubyte[size];
        len = 0;
        for (size_t off; off < buf.length; off += len)
        {
            len = socket.receive(buf[off..$]);

            if (len > 0)
            {
                continue;
            }
            else if (len == 0)
            {
                writefln("Server socket close at receive. Local socket: %s", socket.localAddress);
                socket.close();

                return;
            }
            else
            {
                if (errno == EINTR || errno == EAGAIN/* || errno == EWOULDBLOCK*/)
                {
                    len = 0;
                    continue;
                }

                writeln("Socket error at receive3. Local socket: %s, error: %s", socket.localAddress, formatSocketError(errno));
                socket.close();

                return;
            }
        }

        buffer ~= buf;

        core.atomic.atomicOp!"+="(total, 1);
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();

        LoginResponse res = Message.deserialize!LoginResponse(buffer);
        writefln("result: %d, description: %s, userId: %d, token: %s, name: %s, mobile: %s", res.result, res.description, res.userId, res.token, res.name, (Clock.currTime() - SysTime.fromUnixTime(res.mobile.to!long)).total!"seconds");
        Thread.sleep(50.msecs);
    }
}