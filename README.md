# A cross-platform event loop library of asynchroneous objects.

This is a simple wrapper of network library, D language implementation. Its encapsulation is simple and clear, and is very suitable for reading and reference. Though very small, its performance is pretty good.

### Support platform:

Platforms
FreeBSD
Windows
OSX
Linux
NetBSD
OpenBSD

### Support for kernel loop (while supporting IN and OUT event listener):

Epoll
Kqueue
IOCP

### todo:

You can add, repair and submit after fork, and improve it together. Thank you.

Note:

IOCP has not been completed and submitted.


### Quick Start:

```

// Echo server:

import std.stdio;
import std.conv;
import std.socket;
import std.exception;

import async;

void main()
{
    EventLoopGroup group = new EventLoopGroup(&createEventLoop);
    group.run();

    group.stop();
}

EventLoop createEventLoop()
{
    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress("0.0.0.0", 12290));
    listener.listen(10);

    return new EventLoop(listener, null, null, &onReceive, null, null);
}

void onReceive(TcpClient client, in ubyte[] data) nothrow @trusted
{
    collectException({
        writefln("Receive from %s: %d", client.remoteAddress().toString(), data.length);
        client.send(cast(ubyte[])data);
    }());
}


// Echo client:

import std.stdio;
import std.conv;
import std.socket;

void main(string[] argv)
{
    TcpSocket socket = new TcpSocket();
    socket.blocking = true;
    socket.connect(new InternetAddress("127.0.0.1", 12290));

    string data = "hello, server.";
    writeln("client say: ", data);
    socket.send(data);

    ubyte[] buffer = new ubyte[1024];
    size_t len = socket.receive(buffer);
    writeln("Server reply: ", cast(string)buffer[0..len]);

    socket.shutdown(SocketShutdown.BOTH);
    socket.close();
}

```