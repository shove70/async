module async.container.queue;

import std.container.slist;
import std.exception;
import core.sync.mutex;

class Queue(T)
{
    this()
    {
        lock = new Mutex;
    }

    @property bool empty() const
    {
        return data.empty();
    }

    void push(T value)
    {
        synchronized (lock)
        {
            data.insertAfter(data[], value);
        }
    }

    T pop()
    {
        synchronized (lock)
        {
            enforce(!empty);

            T value = data.front();
            data.removeFront();

            return value;
        }
    }

    void clear()
    {
        synchronized (lock)
        {
            data.clear();
        }
    }

private:

    SList!T data;
    Mutex   lock;
}
