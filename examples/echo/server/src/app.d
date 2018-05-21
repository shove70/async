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
