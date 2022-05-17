module async.thread;

import std.parallelism : TaskPool, task, totalCPUs;

class ThreadPool
{
	private TaskPool pool;

	this(uint size = 0)
	{
		pool = new TaskPool(size ? size : totalCPUs * 2 + 2);
	}

	~this() { pool.finish(true); }

	@property size_t size() @safe const pure nothrow { return pool.size; }

	void run(alias fn, Args...)(Args args)
	{
		pool.put(task!fn(args));
	}
}