module async.eventloop;

import std.stdio;
import std.socket;
import std.parallelism;

import async.event.selector;
import async.net.tcplistener;

version (Posix)
{
    import core.sys.posix.signal;
}

version (linux)
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
else version (Windows)
{
    import async.event.iocp;
}
else
{
    static assert(false, "Unsupported platform.");
}

class EventLoop : LoopSelector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError, int acceptThreadNum = totalCPUs, int workerThreadNum = totalCPUs * 2)
    {
        version (Posix)
        {
            sigset_t mask1;
            sigemptyset(&mask1);
            sigaddset(&mask1, SIGPIPE);
            sigaddset(&mask1, SIGILL);
            sigprocmask(SIG_BLOCK, &mask1, null);
        }

        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError, acceptThreadNum, workerThreadNum);
    }

    void run()
    {
        writefln("Start listening to %s...", _listener.localAddress().toString());

        startLoop();
    }
}