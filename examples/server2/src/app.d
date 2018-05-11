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

void onConnected(TcpClient client)
{
    writeln("New connection: ", client.remoteAddress().toString());
}

void onDisConnected(string remoteAddress)
{
    writefln("\033[7mClient socket close: %s\033[0m", remoteAddress);
}

void onReceive(TcpClient client, in ubyte[] data)
{
    writefln("Receive from %s: %d", client.remoteAddress().toString(), data.length);

    new Thread({
        long sent = client.write(data); // echo
    
        if (sent != data.length)
        {
            writefln("Send to %s Error. sent: %d", client.remoteAddress().toString(), sent);
        }
        else
        {
            writefln("Sent to %s: %d", client.remoteAddress().toString(), sent);
        }
    }).start();
}

void onSocketError(string remoteAddress, string msg)
{
    writeln("Client socket error: ", remoteAddress, " ", msg);
}
