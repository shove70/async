module async.container.map;

import std.exception;
import core.sync.mutex;

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
	    synchronized (_lock)
        {
            assert (key in _data);

            return _data[key];
        }
	}

    void opIndexAssign(TValue value, TKey key)
    {
        synchronized (_lock)
        {
            _data[key] = value;
        }
    }

    @property ref inout(TValue) front() inout
    {
        assert (_data.length > 0);

        return _data[_data.keys[0]];
    }

    @property ref inout(TValue) back() inout
    {
        assert (_data.length > 0);

        return _data[_data.keys[$ - 1]];
    }

    int opApply(scope int delegate(ref TValue) dg)
    {
        int result = 0;

        foreach (d; _data)
        {
            result = dg(d);
            if (result)
                break;
        }
        return result;
    }

    int opApply(scope int delegate(TKey, ref TValue) dg)
    {
        int result = 0;

        for (size_t i = 0; i < _data.keys.length; i++)
        {
            result = dg(_data.keys[i], _data[_data.keys[i]]);
            if (result) break;
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

private:

    TValue[TKey] _data;
    Mutex        _lock;
}
