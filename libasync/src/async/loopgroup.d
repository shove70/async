module async.loopgroup;

import core.thread;
import std.parallelism;
import std.socket;

import async.event.selector;
import async.loop;

alias OnCreateServer = Loop function();

class LoopGroup
{
    this(OnCreateServer onCreateServer, int size = totalCPUs - 1)
    {
        assert(size >= 0, "The size of loop must be greater than or equal to zero.");

        _mainLoop = onCreateServer();

        foreach (i; 0 .. size)
        {
            Loop loop    = onCreateServer();
            _loops[loop] = new Thread(&loop.run);
        }
    }

    void start()
    {
        if (_started)
        {
            return;
        }

        foreach (ref t; _loops.values)
        {
            t.start();
        }

        _mainLoop.run();

        _started = true;
    }

    void stop()
    {
        if (!_started)
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

        _started = false;
    }

    @property size_t length()
    {
        return _loops.length;
    }

private:

    Loop         _mainLoop;
    Thread[Loop] _loops;

    bool         _started;
}
