import std.stdio;
import std.socket;
import std.exception;
import std.bitmanip;
import async;
import buffer;
import buffer.rpc.server;
import crypto.rsa;
import package_business;

__gshared Server!(Business) business;
__gshared ThreadPool businessPool;

void main()
{
    RSAKeyInfo privateKey = RSA.decodeKey("AAAAIH4RaeCOInmS/CcWOrurajxk3dZ4XGEZ9MsqT3LnFqP3HnO6WmZVW8rflcb5nHsl9Ga9U4NdPO7cDC2WQ8Y02LE=");
    Message.settings(615, privateKey, true);

    businessPool = new ThreadPool(32);
    business     = new Server!(Business)();

    auto listener = new TcpListener;
    listener.bind(new InternetAddress(12290));
    listener.listen(1024);

    Codec codec = new Codec(CodecType.SizeGuide, 615);
    EventLoop loop = new EventLoop(listener, &onConnected, &onDisConnected, &onReceive, &onSendCompleted, &onSocketError, codec, 8);
    loop.run();

    //loop.stop();
}

void onConnected(TcpClient client) nothrow @trusted
{
    collectException({
        writefln("New connection: %s, fd: %d", client.remoteAddress, client.fd);
    }());
}

void onDisConnected(TcpClient client) nothrow @trusted
{
    collectException({
        writefln("\033[7mClient socket close: %s, fd: %d\033[0m", client.remoteAddress, client.fd);
    }());
}

void onReceive(TcpClient client, const scope ubyte[] data) nothrow @trusted
{
    collectException({
        businessPool.run!businessHandle(client, data);
    }());
}

void businessHandle(TcpClient client, const scope ubyte[] buffer)
{
    ubyte[] ret_data = business.Handler(buffer);
    client.send(ret_data);
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
