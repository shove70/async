import std.stdio;
import std.conv;
import std.socket;
import std.exception;

import core.sync.mutex;

import async;
import async.container;

__gshared ByteBuffer[int] queue;
__gshared int size = 10000;
__gshared Mutex lock;

void main()
{
    lock = new Mutex();

    EventLoopGroup group = new EventLoopGroup(&createEventLoop);  // Use the thread group, thread num: totalCPUs
    group.run();

    group.stop();

//    Not use group:

//    EventLoop loop = createEventLoop();
//    loop.run();
//
//    loop.stop();
}

EventLoop createEventLoop()
{
    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress("0.0.0.0", 12290));
    listener.listen(10);

    return new EventLoop(listener, &onConnected, &onDisConnected, &onReceive, &onSendCompleted, &onSocketError);
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

            size_t len = findCompleteMessage(queue[client.fd]);
            if (len == 0)
            {
                return;
            }

            buffer = queue[client.fd][0 .. len];
            queue[client.fd].popFront(len);
        }

        writefln("Receive from %s: %d, fd: %d", client.remoteAddress().toString(), buffer.length, client.fd);
        client.send(buffer); // echo
    }());
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

private size_t findCompleteMessage(ref ByteBuffer data)
{
    if (data.length < size)
    {
        return 0;
    }

    return size;
}
