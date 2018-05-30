import std.stdio;
import std.conv;
import std.socket;
import std.exception;
import std.bitmanip;

import core.sync.mutex;

import async;
import async.container;
import buffer;
import buffer.rpc.server;
import crypto.rsa;

import package_business;

__gshared Server!(Business) business;

__gshared ByteBuffer[int] queue;
__gshared Mutex lock;

__gshared ThreadPool businessPool;

void main()
{
    RSAKeyInfo privateKey = RSA.decodeKey("AAAAIH4RaeCOInmS/CcWOrurajxk3dZ4XGEZ9MsqT3LnFqP3HnO6WmZVW8rflcb5nHsl9Ga9U4NdPO7cDC2WQ8Y02LE=");
    Message.settings(615, privateKey, true);

    lock         = new Mutex();
    businessPool = new ThreadPool(32);
    business     = new Server!(Business)();

    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress("0.0.0.0", 12290));
    listener.listen(1024);

    EventLoop loop = new EventLoop(listener, &onConnected, &onDisConnected, &onReceive, &onSendCompleted, &onSocketError, 8);
    loop.run();

    //loop.stop();
}

void onConnected(TcpClient client) nothrow @trusted
{
    collectException({
        synchronized(lock) queue[client.fd] = ByteBuffer();
        writefln("New connection: %s, fd: %d", client.remoteAddress().toString(), client.fd);
    }());
}

void onDisConnected(int fd, string remoteAddress) nothrow @trusted
{
    collectException({
        synchronized(lock) queue.remove(fd);
        writefln("\033[7mClient socket close: %s, fd: %d\033[0m", remoteAddress, fd);
    }());
}

void onReceive(TcpClient client, in ubyte[] data) nothrow @trusted
{
    collectException({
        ubyte[] buffer;

        synchronized(lock)
        {
            if (client.fd !in queue)
            {
                writeln("onReceive error. ", client.fd);
                assert (0, "Error, fd: " ~ client.fd.to!string);
            }

            queue[client.fd] ~= data;

            size_t len = findCompleteMessage(client, queue[client.fd]);
            if (len == 0)
            {
                return;
            }

            buffer = queue[client.fd][0 .. len];
            queue[client.fd].popFront(len);
        }

        businessPool.run!businessHandle(client, buffer);
    }());
}

void businessHandle(TcpClient client, ubyte[] buffer)
{
    ubyte[] ret_data = business.Handler(buffer);
    client.send(ret_data);
}

void onSocketError(int fd, string remoteAddress, string msg) nothrow @trusted
{
    collectException({
        writeln("Client socket error: ", remoteAddress, " ", msg);
    }());
}

void onSendCompleted(int fd, string remoteAddress, in ubyte[] data, size_t sent_size) nothrow @trusted
{
    collectException({
        if (sent_size != data.length)
        {
            writefln("Send to %s Error. Original size: %d, sent: %d, fd: %d", remoteAddress, data.length, sent_size, fd);
        }
        else
        {
            writefln("Sent to %s completed, Size: %d, fd: %d", remoteAddress, sent_size, fd);
        }
    }());
}

size_t findCompleteMessage(TcpClient client, ref ByteBuffer data)
{
    if (data.length < (ushort.sizeof + int.sizeof))
    {
        return 0;
    }

    ubyte[] head = data[0 .. ushort.sizeof + int.sizeof];

    if (head.peek!ushort(0) != 615)
    {
        string remoteAddress = client.remoteAddress().toString();
        client.forceClose();
        writeln("Socket Error: " ~ remoteAddress ~ ", An unusual message data!");

        return 0;
    }

    size_t len = head.peek!int(ushort.sizeof);

    if (data.length < (len + (ushort.sizeof + int.sizeof)))
    {
        return 0;
    }

    return len + (ushort.sizeof + int.sizeof);
}