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

void onDisConnected(string remoteAddress)
{
    writeln("Client socket close: ", remoteAddress);
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
