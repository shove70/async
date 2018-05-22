module async.container.bytebuffer;

import core.atomic;

import std.container.dlist;
import std.conv;

struct ByteBuffer
{
    @property bool empty()
    {
        return (_size == 0);
    }

    @property size_t length()
    {
        return _size;
    }

    typeof(this) opBinary(string op, Stuff)(auto ref Stuff rhs)
    if ((is(Stuff : const ubyte[])) && op == "~")
    {
        if (rhs is null)
        {
            return this;
        }

        _queue.insertBack(rhs);
        core.atomic.atomicOp!"+="(_size, rhs.length);

        return this;
    }

    void opOpAssign(string op, Stuff)(auto ref Stuff rhs)
    if ((is(Stuff : const ubyte[])) && op == "~")
    {
        if (rhs is null)
        {
            return;
        }

        _queue.insertBack(rhs);
        core.atomic.atomicOp!"+="(_size, rhs.length);
    }

    ubyte[] opSlice(in size_t low, in size_t high) @trusted
    in
    {
        assert ((low <= high) && (high <= _size));
    }
    body
    {
        ubyte[] ret;

        if (low == high)
        {
            return ret;
        }

        size_t count = 0, lack = high - low;
        foreach (a; _queue)
        {
            count += a.length;

            if (count < low)
            {
                continue;
            }

            size_t start = low + ret.length - (count - a.length);
            ret ~= a[start .. ($ - start) >= lack ? start + lack : $];
            lack = high - low - ret.length;

            if (lack == 0)
            {
                break;
            }
        }

        return ret;
    }

    size_t opDollar() nothrow const
    {
        return _size;
    }

    void popFront()
    {
        assert (!_queue.empty);

        core.atomic.atomicOp!"-="(_size, _queue.front.length);
        _queue.removeFront();
    }

    void popFront(size_t size)
    {
        assert (size >= 0 && size <= _size);

        if (size == 0)
        {
            return;
        }

        if (size == _size)
        {
            _queue.clear();
            _size = 0;

            return;
        }

        size_t removed = 0, lack = size;

        size_t line = 0, count = 0, currline_len = 0;
        foreach (a; _queue)
        {
            line++;
            currline_len = a.length;
            count       += currline_len;

            if (count > size)
            {
                break;
            }
        }

        if (line > 1)
        {
            removed = count - currline_len;
            lack    = size  - removed;
            _queue.removeFront(line - 1);
        }

        if (lack > 0)
        {
            _queue.front = _queue.front[lack .. $];
        }

        core.atomic.atomicOp!"-="(_size, size);
    }

    void clear()
    {
        _queue.clear();
        _size = 0;
    }

    string toString()
    {
        return this[0 .. $].to!string();
    }

private:

    DList!(ubyte[]) _queue;
    shared size_t   _size;
}
