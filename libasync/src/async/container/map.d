module async.container.map;

import core.sync.mutex;

class Map(TKey, TValue)
{
nothrow:
    this() { mutex = new Mutex; }

    ref auto opIndex(TKey key)
    {
        import std.traits : isArray;

        lock();
        scope(exit) unlock();
        if (key !in data)
        {
            static if (isArray!TValue)
            {
                data[key] = [];
            }
            else
            {
                return null;
            }
        }

        return data[key];
    }

    void opIndexAssign(TValue value, TKey key)
    {
        lock();
        data[key] = value;
        unlock();
    }

    @property bool empty() const pure @nogc { return data.length == 0; }

    bool remove(TKey key)
    {
        lock();
        scope(exit) unlock();
        return data.remove(key);
    }

    void clear() @trusted
    {
        lock();
        data.clear();
        unlock();
    }

@safe:
    final void lock() { mutex.lock_nothrow(); }

    final void unlock() { mutex.unlock_nothrow(); }

    TValue[TKey] data;
    alias data this;
    protected Mutex mutex;
}