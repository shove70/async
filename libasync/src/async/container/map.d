module async.container.map;

import core.sync.mutex;
import std.exception;

class Map(TKey, TValue)
{
nothrow @safe:
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

    @property pure {
        bool empty() const pure @nogc { return data.length == 0; }

        ref auto front() inout
        {
            return data.length ? data[data.keys[0]] : null;
        }

        ref auto back() inout
        {
            return data.length ? data[data.keys[$ - 1]] : null;
        }
    }

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

    final void lock() { mutex.lock_nothrow(); }

    final void unlock() { mutex.unlock_nothrow(); }

    TValue[TKey] data;
    alias data this;
    protected Mutex mutex;
}