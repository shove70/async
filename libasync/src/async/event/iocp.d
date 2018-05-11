module async.event.iocp;

debug import std.stdio;

version (Windows):

import core.sys.windows.windows;
import core.sync.mutex;
import std.socket;

import async.event.selector;
import async.net.tcpstream;
import async.net.tcplistener;
import async.net.tcpclient;

alias LoopSelector = Iocp;

class Iocp : Selector
{
    this(TcpListener listener, OnConnected onConnected, OnDisConnected onDisConnected, OnReceive onReceive, OnSocketError onSocketError)
    {
        this._onConnected   = onConnected;
        this.onDisConnected = onDisConnected;
        this.onReceive      = onReceive;
        this.onSocketError  = onSocketError;

        _lock          = new Mutex;
    }

    ~this()
    {
        dispose();
    }

    private bool register(int fd)
    {
        return true;
    }

    private bool reRegister(int fd)
    {
       return true;
    }

    private bool deRegister(int fd)
    {
        return true;
    }

    override void startLoop()
    {
        runing = true;

        while (runing)
        {
            handleEvent();
        }
    }

    private void handleEvent()
    {

    }

    override void stop()
    {
        runing = false;
    }

    override void dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;
        foreach (c; _clients)
        {
            deregister(c.fd);
        }

        deregister(_listener.fd);
        _listener.close();

        //core.sys.posix.unistd.close(_fd);
    }

    override void removeClient(int fd)
    {
        deregister(fd);
        _clients.remove(fd);
    }

private:

    HANDLE _handle;
}
