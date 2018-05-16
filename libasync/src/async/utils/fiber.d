module async.utils.fiber;

import core.thread;
import core.sync.mutex;
import std.parallelism;

class SyncFiber : Fiber
{
    this(void function() fn) nothrow
    {
        super(fn);

        _lock = new Mutex;
    }

    this(void delegate() dg) nothrow
    {
        super(dg);

        _lock = new Mutex;
    }

    void call()
    {
        synchronized (_lock)
        {
            if (state != Fiber.State.TERM)
            {
                super.call();
                //new Thread( { super.call(); } ).start();
            }
        }
    }

private:

    Mutex _lock;
}