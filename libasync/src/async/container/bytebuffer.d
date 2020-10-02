module async.container.bytebuffer;

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

    ref typeof(this) opBinary(string op, Stuff)(auto ref Stuff rhs)
    if ((is(Stuff: const ubyte[])) && op == "~")
    {
        if (rhs is null)
        {
            return this;
        }

        _queue.insertBack(cast(ubyte[])rhs);
        _size += rhs.length;

        return this;
    }

    void opOpAssign(string op, Stuff)(auto ref Stuff rhs)
    if ((is(Stuff: const ubyte[])) && op == "~")
    {
        if (rhs is null)
        {
            return;
        }

        _queue.insertBack(cast(ubyte[])rhs);
        _size += rhs.length;
    }

    ubyte[] opSlice(const size_t low, const size_t high) @trusted
    in
    {
        assert((low <= high) && (high <= _size), "ByteBuffer.opSlice: Invalid arguments low, high");
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

    ref ubyte opIndex(const size_t index) @trusted
    in
    {
        assert((index < _size), "ByteBuffer.opIndex: Invalid arguments index");
    }
    body
    {
        size_t size, start;
        foreach (a; _queue)
        {
            start = size;
            size += a.length;

            if (index < size)
            {
                return a[index - start];
            }
        }

        assert(0);
    }

    @property ref inout(ubyte[]) front() inout
    {
        assert(!_queue.empty, "ByteBuffer.front: Queue is empty");

        return _queue.front;
    }

    void popFront()
    {
        assert(!_queue.empty, "ByteBuffer.popFront: Queue is empty");

        _size -= _queue.front.length;
        _queue.removeFront();
    }

    void popFront(const size_t size)
    {
        assert(size >= 0 && size <= _size, "ByteBuffer.popFront: Invalid arguments size");

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
            count += currline_len;

            if (count > size)
            {
                break;
            }
        }

        if (line > 1)
        {
            removed = count - currline_len;
            lack = size  - removed;
            _queue.removeFront(line - 1);
        }

        if (lack > 0)
        {
            _queue.front = _queue.front[lack .. $];
        }

        _size -= size;
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

    auto opCast(T)()
    {
        static if (isSomeString!T)
        {
            return toString();
        }
        else static if (is(T: const ubyte[]))
        {
            return this[0 .. $];
        }
        else
        {
            static assert(0, "ByteBuffer.opCast: Not support type.");
        }
    }

private:

    DList!(ubyte[]) _queue;
    size_t          _size;
}
