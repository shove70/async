import std.stdio;
import std.conv;
import std.socket;
import core.thread;

import async;

void main()
{
    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress("127.0.0.1", 12290));
    listener.listen(10);

    Loop loop = new Loop(listener, &onConnected, &onDisConnected, &onReceive, &onSocketError);
    loop.run();
}

void onConnected(TcpClient client)
{
    writeln("New connection: ", client.remoteAddress().toString());
}

void onDisConnected(int fd, string remoteAddress)
{
    queue.remove(fd);
    writefln("\033[7mClient socket close: %s\033[0m", remoteAddress);
}

void onReceive(TcpClient client, in ubyte[] data)
{
//    writefln("Receive from %s: %d", client.remoteAddress().toString(), data.length);

    queue[client.fd] ~= data;

    size_t len = findCompleteMessage(queue[client.fd]);

    if (len == 0)
    {
        return;
    }

    ubyte[] buffer   = queue[client.fd][0 .. len];
    queue[client.fd] = queue[client.fd][len .. $];

    new Thread({
        long sent = client.write(buffer); // echo
    
        if (sent != buffer.length)
        {
            writefln("Send to %s Error. sent: %d", client.remoteAddress().toString(), sent);
        }
        else
        {
            writefln("Sent to %s: %d", client.remoteAddress().toString(), sent);
        }
    }).start();
}

void onSocketError(int fd, string remoteAddress, string msg)
{
    writeln("Client socket error: ", remoteAddress, " ", msg);
}

__gshared int size = 10000000;
__gshared ubyte[][int] queue;

private size_t findCompleteMessage(in ubyte[] data)
{
    if (data.length < size)
    {
        return 0;
    }

    return size;
}