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

    Loop loop = new Loop(listener, &onConnected, &onDisConnected, &onReceive, &onSendCompleted, &onSocketError);

    return loop;
}

void main()
{
    LoopGroup group = new LoopGroup(&onCreateServer);
    group.start();

    //group.stop();
}

void onConnected(TcpClient client)
{
    writeln("New connection: ", client.remoteAddress().toString());
}

void onDisConnected(int fd, string remoteAddress)
{
    writefln("\033[7mClient socket close: %s\033[0m", remoteAddress);
}

void onReceive(TcpClient client, in ubyte[] data)
{
    writefln("Receive from %s: %d", client.remoteAddress().toString(), data.length);

    client.send(cast(ubyte[])data); // echo
}

void onSocketError(int fd, string remoteAddress, string msg)
{
    writeln("Client socket error: ", remoteAddress, " ", msg);
}

void onSendCompleted(int fd, string remoteAddress, in ubyte[] data, size_t sent_size)
{
    if (sent_size != data.length)
    {
        writefln("Send to %s Error. Original size: %d, sent: %d", remoteAddress, data.length, sent_size);
    }
    else
    {
        writefln("Sent to %s completed, Size: %d", remoteAddress, sent_size);
    }
}