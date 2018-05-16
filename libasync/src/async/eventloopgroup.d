module async.eventloopgroup;

import core.thread;

import std.parallelism;
import std.socket;

import async.event.selector;
import async.eventloop;
import async.net.tcplistener;

alias OnCreateEventLoop = EventLoop function();

class EventLoopGroup
{
    this(OnCreateEventLoop onCreateEventLoop, int size = totalCPUs)
    {
        assert(size >= 1, "The size of loop must be greater than or equal to 1.");
        assert(onCreateEventLoop !is null, "The delegate onCreateEventLoop must be provide.");

        _mainLoop = onCreateEventLoop();

        foreach (i; 0 .. size - 1)
        {
            EventLoop loop = onCreateEventLoop();
            _loops[loop]   = new Thread(&loop.run);
        }
    }

    void run()
    {
        if (_running)
        {
            return;
        }

        foreach (ref t; _loops.values)
        {
            t.start();
        }

        _mainLoop.run();

        _running = true;
    }

    void stop()
    {
        if (!_running)
        {
            return;
        }

        _mainLoop.stop();

        foreach (ref loop; _loops.keys)
        {
            loop.stop();
        }

        foreach (ref t; _loops.values)
        {
            t.join(false);
        }

        _running = false;
    }

private:

    EventLoop         _mainLoop;
    Thread[EventLoop] _loops;

    bool              _running;
}
