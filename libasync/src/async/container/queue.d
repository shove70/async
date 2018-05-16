module async.container.queue;

import core.sync.mutex;

import std.container.slist;

class Queue(T)
{
    this()
    {
        _lock = new Mutex;
        _size = 0;
    }

    @property bool empty() const
    {
        return _data.empty();
    }

    @property ref T front()
    {
        synchronized (_lock)
        {
            return _data.front();
        }
    }

    @property size_t length()
    {
        return _size;
    }

    void push(T value)
    {
        synchronized (_lock)
        {
            _data.insertAfter(_data[], value);
            _size++;
        }
    }

    T pop()
    {
        synchronized (_lock)
        {
            T value = _data.front();
            _data.removeFront();
            _size--;

            return value;
        }
    }

    void clear()
    {
        synchronized (_lock)
        {
            _data.clear();
            _size = 0;
        }
    }

    void reverse()
    {
        synchronized (_lock)
        {
            _data.reverse();
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

    SList!T _data;
    Mutex   _lock;

    size_t  _size;
}
