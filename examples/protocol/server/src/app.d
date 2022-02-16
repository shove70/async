import
    async,
    std.stdio,
    std.socket,
    std.exception;

void main()
{
    auto listener = new TcpListener;
    listener.bind(new InternetAddress(12290));
    listener.listen(10);

    auto codec = new Codec(CodecType.SizeGuide);
    auto loop = new EventLoop(listener, &onConnected, &onDisconnected, &onReceive, &onSendCompleted, &onSocketError, codec);
    loop.run();

    //loop.stop();
}

void onConnected(TcpClient client) nothrow @trusted
{
    collectException({
        writefln("New connection: %s, fd: %d", client.remoteAddress, client.fd);
    }());
}

void onDisconnected(TcpClient client) nothrow @trusted
{
    collectException({
        writefln("\033[7mClient socket close: %s, fd: %d\033[0m", client.remoteAddress, client.fd);
    }());
}

void onReceive(TcpClient client, const scope ubyte[] data) nothrow @trusted
{
    collectException({
        writefln("Receive from %s: %d, fd: %d", client.remoteAddress, data.length, client.fd);
        client.send(data); // echo
    }());
}

void onSocketError(TcpClient client, string msg) nothrow @trusted
{
    collectException({
        writeln("Client socket error: ", client.remoteAddress, " ", msg);
    }());
}

void onSendCompleted(TcpClient client, const scope ubyte[] data, const size_t sent_size) nothrow @trusted
{
    collectException({
        if (sent_size != data.length)
        {
            writefln("Send to %s Error. Original size: %d, sent: %d, fd: %d",
                client.remoteAddress, data.length, sent_size, client.fd);
        }
        else
        {
            writefln("Sent to %s completed, Size: %d, fd: %d", client.remoteAddress, sent_size, client.fd);
        }
    }());
}