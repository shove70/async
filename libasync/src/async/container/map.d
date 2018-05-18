module async.container.map;

import core.sync.mutex;

import std.exception;
import std.typecons;
import std.traits : isArray;

class Map(TKey, TValue)
{
    this()
    {
        _lock = new Mutex;
    }

    @property bool empty() const
    {
        return (_data.length == 0);
    }

    @property size_t length() const
    {
        return _data.length;
    }

    @property size_t opDollar() const
    {
        return _data.length;
    }

    ref auto opIndex(TKey key)
    {
        synchronized(_lock)
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

    void opIndexAssign(TValue value, TKey key)
    {
        synchronized(_lock)
        {
            _data[key] = value;
        }
    }

    @property ref auto front() inout
    {
        if (_data.length == 0)
        {
            return null;
        }

        return _data[_data.keys[0]];
    }

    @property ref auto back() inout
    {
        if (_data.length == 0)
        {
            return null;
        }

        return _data[_data.keys[$ - 1]];
    }

    int opApply(scope int delegate(ref TValue) dg)
    {
        int result = 0;

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
        int result = 0;

        for (size_t i = 0; i < _data.keys.length; i++)
        {
            result = dg(_data.keys[i], _data[_data.keys[i]]);

            if (result)
            {
                break;
            }
        }

        return result;
    }

    @property TKey[] keys()
    {
        return _data.keys;
    }

    @property TValue[] values()
    {
        return _data.values;
    }

    bool exists(TKey key)
    {
        if (key in _data)
        {
            return true;
        }
        return false;
    }

    void remove(TKey key)
    {
        synchronized(_lock)
        {
            _data.remove(key);
        }
    }

    void clear()
    {
        synchronized(_lock)
        {
            _data.clear();
        }
    }

    void lock()
    {
        _lock.lock();
    }

    void unlock()
    {
        _lock.unlock();
    }

private:

    TValue[TKey] _data;
    Mutex        _lock;
}
