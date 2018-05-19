module async.container.queue;

import core.sync.mutex;
import core.atomic;

import std.container.slist;

struct Queue(T)
{
    @property bool empty() const
    {
        return _data.empty();
    }

    @property ref T front()
    {
        return _data.front();
    }

    @property size_t length()
    {
        return _size;
    }

    void push(T value)
    {
        _data.insertAfter(_data[], value);
        core.atomic.atomicOp!"+="(this._size, 1);
    }

    T pop()
    {
        assert(!_data.empty(), "Queue is empty.");

        T value = _data.front();
        _data.removeFront();
        core.atomic.atomicOp!"-="(this._size, 1);

        return value;
    }

    void clear()
    {
        _data.clear();
        _size = 0;
    }

    void reverse()
    {
        _data.reverse();
    }

private:

    SList!T        _data;
    shared size_t  _size = 0;
}
