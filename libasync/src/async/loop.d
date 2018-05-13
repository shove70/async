module async.loop;

import std.stdio;
import std.socket;

import async.event.selector;
import async.net.tcplistener;

version (Posix)
{
	import core.sys.posix.signal;
}

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
else version (Windows)
{
    import async.event.iocp;
}
else
{
    static assert(false, "Unsupported platform.");
}

class Loop : LoopSelector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSendCompleted onSendCompleted, OnSocketError onSocketError)
    {
        version (Posix)
        {
            sigset_t mask1;
            sigemptyset(&mask1);
            sigaddset(&mask1, SIGPIPE);
            sigaddset(&mask1, SIGILL);
            sigprocmask(SIG_BLOCK, &mask1, null);
        }

        super(listener, onConnected, onDisConnected, onReceive, onSendCompleted, onSocketError);

        debug
        {
            import core.thread;
            new Thread(
            {
                while (1)
                {
                    writefln("clients: %d", _clients.length);
                    Thread.sleep(1.seconds);
                }
            }).start();
        }
    }

    void run()
    {
        writefln("Thread starts listening to %s...", _listener.localAddress().toString());

        startLoop();
    }
}