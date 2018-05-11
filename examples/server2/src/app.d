import std.stdio;
import std.conv;
import std.socket;
import core.thread;

import async;

Loop onCreateServer()
{
    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress("127.0.0.1", 12290));
    listener.listen(10);

    Loop loop = new Loop(listener, &onConnected, &onDisConnected, &onReceive, &onSocketError);

    return loop;
}

void main()
{
    LoopGroup group = new LoopGroup(&onCreateServer);
    group.start();

    //group.stop();
}

void onConnected(string remoteAddress)
{
    writeln("New connection: ", remoteAddress);
}

void onDisConnected(TcpClient client)
{
    writeln("Client socket close: ", client.remoteAddress().toString());
}

void onReceive(TcpClient client, in ubyte[] data)
{
    writefln("Receive from %s: %d", client.remoteAddress().toString(), data.length);

    long sent = client.write(data); // echo

    if (sent != data.length)
    {
        writefln("Send to %s Error. sent: %d", client.remoteAddress().toString(), sent);
    }
    else
    {
        writefln("Sent to %s: %d", client.remoteAddress().toString(), sent);
    }
}

void onSocketError(string remoteAddress, string msg)
{
    writeln("Client socket error: ", remoteAddress, " ", msg);
}
