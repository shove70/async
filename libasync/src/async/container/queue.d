module async.container.queue;

import std.container.dlist;

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
        _data.insertBack(value);
        _size++;
    }

    T pop()
    {
        assert(!_data.empty(), "Queue is empty.");

        T value = _data.front();
        _data.removeFront();
        _size--;

        return value;
    }

    void clear()
    {
        _data.clear();
        _size = 0;
    }

    @property ref auto range()
    {
        return _data[];
    }

private:

    DList!T _data;
    size_t  _size = 0;
}
