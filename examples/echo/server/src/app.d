import std.stdio;
import std.conv;
import std.socket;
import std.exception;

import async;

void main()
{
    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress("0.0.0.0", 12290));
    listener.listen(10);

    EventLoop loop = new EventLoop(listener, null, null, &onReceive, null, null);
    loop.run();

    //loop.stop();
}

void onReceive(TcpClient client, const scope ubyte[] data) nothrow @trusted
{
    collectException({
        writefln("Receive from %s: %d", client.remoteAddress().toString(), data.length);
        client.send(data); // echo
    }());
}
