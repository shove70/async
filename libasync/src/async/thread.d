module async.thread;

import std.parallelism;

class ThreadPool
{
    this(int size)
    {
        if (size <= 0)
        {
            size = totalCPUs;
        }

        _pool = new TaskPool(size);
    }

    ~this()
    {
        _pool.finish(true);
    }

    void run(alias fn, Args...)(Args args)
    {
        _pool.put(task!fn(args));
    }

private:

    TaskPool _pool;
}
