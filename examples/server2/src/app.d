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

    Loop loop = new Loop(listener,
        ((client)                  => onConnected   (client)      ),
        ((client)                  => onDisConnected(client)      ),
        ((client, in ubyte[] data) => onReceive     (client, data)),
        ((client, msg)             => onSocketError (client, msg) ),
    );

    return loop;
}

void main()
{
    LoopGroup group = new LoopGroup(() => onCreateServer());
    group.start();

    //group.stop();
}

void onConnected(TcpClient client)
{
    writeln("New connection: ", client.remoteAddress().toString());
}

void onDisConnected(TcpClient client)
{
    writeln("Client socket close: ", client.remoteAddress().toString());
}

void onReceive(TcpClient client, in ubyte[] data)
{
    writeln("Receive: ", data.length);

    long sent = client.write(data); // echo

    if (sent != data.length)
    {
        writeln("Send Error.");
    }
}

void onSocketError(TcpClient client, string msg)
{
    writeln("Client socket error: ", msg);
}
