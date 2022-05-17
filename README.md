[![Build Status](https://travis-ci.org/shove70/async.svg?branch=master)](https://travis-ci.org/shove70/async)
[![GitHub tag](https://img.shields.io/github/tag/shove70/async.svg?maxAge=86400)](https://github.com/shove70/async/releases)
[![Dub downloads](https://img.shields.io/dub/dt/async.svg)](http://code.dlang.org/packages/async)

# A cross-platform event loop library of asynchroneous network sockets.

This is a simple wrapper of network library, D language implementation. Its encapsulation is simple and clear, and is very suitable for reading and reference. Though very small, its performance is pretty good, It's a real full duplex mode.

### Support platform:

* Platforms
* FreeBSD
* Windows
* OSX
* Linux
* NetBSD
* OpenBSD

### Support for kernel loop (while supporting IN and OUT event listener):

* Epoll
* Kqueue
* IOCP

### Quick Start:

```d

// Echo server:

import async;
import std.stdio;
import std.socket;
import std.exception;

void main()
{
    auto listener = new TcpListener();
    listener.bind(new InternetAddress(12290));
    listener.listen(10);

    auto loop = new EventLoop(listener, null, null, &onReceive, null, null);
    loop.run();
}

void onReceive(TcpClient client, const scope ubyte[] data) nothrow @trusted
{
    collectException({
        writefln("Receive from %s: %d", client.remoteAddress, data.length);
        client.send(cast(ubyte[])data);
    }());
}


// Echo client:

import std.stdio;
import std.socket;

void main(string[] argv)
{
    auto socket = new TcpSocket();
    socket.connect(new InternetAddress("127.0.0.1", 12290));

    auto data = "hello, server.";
    writeln("Client say: ", data);
    socket.send(data);

    ubyte[1024] buffer = void;
    size_t len = socket.receive(buffer[]);
    writeln("Server reply: ", cast(string)buffer[0..len]);

    socket.shutdown(SocketShutdown.BOTH);
    socket.close();
}

```

### Todo:

You can add, repair and submit after fork, and improve it together. Thank you.
