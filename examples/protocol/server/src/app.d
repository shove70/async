import std.stdio;
import std.conv;
import std.socket;
import std.exception;
import std.bitmanip;

import async;

void main()
{
    TcpListener listener = new TcpListener();
    listener.bind(new InternetAddress(12290));
    listener.listen(10);

    Codec codec = new Codec(CodecType.SizeGuide);
    EventLoop loop = new EventLoop(listener, &onConnected, &onDisConnected, &onReceive, &onSendCompleted, &onSocketError, codec);
    loop.run();

    //loop.stop();
}

void onConnected(TcpClient client) nothrow @trusted
{
    collectException({
        writefln("New connection: %s, fd: %d", client.remoteAddress().toString(), client.fd);
    }());
}

void onDisConnected(const int fd, string remoteAddress) nothrow @trusted
{
    collectException({
        writefln("\033[7mClient socket close: %s, fd: %d\033[0m", remoteAddress, fd);
    }());
}

void onReceive(TcpClient client, const scope ubyte[] data) nothrow @trusted
{
    collectException({
        writefln("Receive from %s: %d, fd: %d", client.remoteAddress().toString(), data.length, client.fd);
        client.send(data); // echo
    }());
}

void onSocketError(const int fd, string remoteAddress, string msg) nothrow @trusted
{
    collectException({
        writeln("Client socket error: ", remoteAddress, " ", msg);
    }());
}

void onSendCompleted(const int fd, string remoteAddress, const scope ubyte[] data, const size_t sent_size) nothrow @trusted
{
    collectException({
        if (sent_size != data.length)
        {
            writefln("Send to %s Error. Original size: %d, sent: %d, fd: %d", remoteAddress, data.length, sent_size, fd);
        }
        else
        {
            writefln("Sent to %s completed, Size: %d, fd: %d", remoteAddress, sent_size, fd);
        }
    }());
}
