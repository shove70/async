module async.container.bytebuffer;

import std.container.dlist;
import std.conv : to;
import std.exception : enforce;

struct ByteBuffer
{
@safe:
    @property pure nothrow @nogc {
        bool empty() const { return _size == 0; }

        size_t length() const { return _size; }
    }

    ref typeof(this) opBinary(string op : "~", T: const void[])(auto ref T rhs) @trusted
    {
        if (rhs is null)
        {
            return this;
        }

        _queue.insertBack(cast(ubyte[])rhs);
        _size += rhs.length;

        return this;
    }

    void opOpAssign(string op : "~", T: const void[])(auto ref T rhs) @trusted
    {
        if (rhs is null)
        {
            return;
        }

        _queue.insertBack(cast(ubyte[])rhs);
        _size += rhs.length;
    }

    ubyte[] opSlice(size_t low, size_t high) @trusted
    {
        enforce(low <= high && high <= _size, "ByteBuffer.opSlice: Invalid arguments low, high");

        ubyte[] ret;

        if (low == high)
        {
            return ret;
        }

        size_t count, lack = high - low;
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

    alias opDollar = length;

    ref ubyte opIndex(size_t index) @trusted
    {
        enforce(index < _size, "ByteBuffer.opIndex: Invalid arguments index");

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

    @property ref inout(ubyte[]) front() inout nothrow @nogc
    in(!_queue.empty, "ByteBuffer.front: Queue is empty") {
        return _queue.front;
    }

    void popFront() in(!_queue.empty, "ByteBuffer.popFront: Queue is empty")
    {
        _size -= _queue.front.length;
        _queue.removeFront();
    }

    void popFront(size_t size)
    in(size >= 0 && size <= _size, "ByteBuffer.popFront: Invalid arguments size") {
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

        size_t removed, lack = size;

        size_t line, count, currline_len;
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

    void clear() nothrow
    {
        _queue.clear();
        _size = 0;
    }

    string toString()
    {
        return this[0 .. $].to!string;
    }

    auto opCast(T)() if (isSomeString!T || is(T: const ubyte[]))
    {
        static if (isSomeString!T)
        {
            return toString();
        }
        else
        {
            return this[0 .. $];
        }
    }

private:

    DList!(ubyte[]) _queue;
    size_t          _size;
}