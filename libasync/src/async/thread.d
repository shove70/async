module async.thread;

import std.parallelism;

class ThreadPool
{
    this(int poolSize = totalCPUs * 2 + 2)
    {
        if (poolSize <= 0)
        {
            poolSize = totalCPUs * 2 + 2;
        }

        defaultPoolThreads(poolSize);
    }

    ~this()
    {
        taskPool.finish(true);
    }

    void doWork(alias fn, Args...)(Args args)
    {
        taskPool.put(task!fn(args));
    }
}
