module async.loop;

import std.socket;
import std.stdio;

import async.event.selector;
import async.net.tcplistener;

version(linux)
{
    import async.event.epoll;
}
else version (OSX)
{
    import async.event.kqueue;
}
else version (iOS)
{
    import async.event.kqueue;
}
else version (TVOS)
{
    import async.event.kqueue;
}
else version (WatchOS)
{
    import async.event.kqueue;
}
else version (FreeBSD)
{
    import async.event.kqueue;
}
else version (OpenBSD)
{
    import async.event.kqueue;
}
else version (DragonFlyBSD)
{
    import async.event.kqueue;
}
else version (windows)
{
    import async.event.iocp;
}
else
{
    static assert(false, "Unsupported platform.");
}

class Loop : LoopSelector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        super(listener, onConnected, onDisConnected, onReceive, onSocketError);
    }
    
    void run()
    {
        writefln("Thread starts listening to %s...", _listener.localAddress().toString());

        startLoop();
    }
}