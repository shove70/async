module async.thread;

import std.parallelism : TaskPool, task, totalCPUs;

class ThreadPool
{
	this(uint size = 0)
	{
		_pool = new TaskPool(size ? size : totalCPUs * 2 + 2);
	}

	~this() { _pool.finish(true); }

	@property size_t size() @safe const pure nothrow { return _pool.size; }

	void run(alias fn, Args...)(Args args)
	{
		_pool.put(task!fn(args));
	}

	private TaskPool _pool;
}