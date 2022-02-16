module async.container.map;

import core.sync.mutex;
import std.exception;

class Map(TKey, TValue)
{
    this() { _lock = new Mutex; }

    pure nothrow @safe {
        bool exists(TKey key) const { return (key in _data) !is null; }

        @nogc:
            bool empty() const { return _data.length == 0; }

            size_t length() const { return _data.length; }
    }

    alias opDollar = length;

    ref auto opIndex(TKey key) @safe
    {
        import std.traits : isArray;

        synchronized (_lock)
        {
            if (key !in _data)
            {
                static if (isArray!TValue)
                {
                    _data[key] = [];
                }
                else
                {
                    return null;
                }
            }

            return _data[key];
        }
    }

    void opIndexAssign(TValue value, TKey key) @safe
    {
        synchronized (_lock)
        {
            _data[key] = value;
        }
    }

    @property pure nothrow @safe {
        ref auto front() inout
        {
            if (!_data.length)
            {
                return null;
            }

            return _data[_data.keys[0]];
        }

        ref auto back() inout
        {
            if (!_data.length)
            {
                return null;
            }

            return _data[_data.keys[$ - 1]];
        }

        TKey[] keys() { return _data.keys; }

        TValue[] values() { return _data.values; }
    }

    int opApply(scope int delegate(ref TValue) dg)
    {
        int result;

        foreach (d; _data)
        {
            result = dg(d);

            if (result)
            {
                break;
            }
        }

        return result;
    }

    int opApply(scope int delegate(TKey, ref TValue) dg)
    {
        int result;

        foreach (k, d; _data)
        {
            result = dg(k, d);

            if (result)
            {
                break;
            }
        }

        return result;
    }

    void remove(TKey key)
    {
        synchronized (_lock)
        {
            _data.remove(key);
        }
    }

    void clear()
    {
        synchronized (_lock)
        {
            _data.clear();
        }
    }

    void lock() @safe { _lock.lock(); }

    void unlock() @safe { _lock.unlock(); }

private:
    TValue[TKey] _data;
    Mutex        _lock;
}