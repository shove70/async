module async.codec;

import std.typecons : Tuple;
import std.bitmanip : peek, write;

import async.container.bytebuffer;

///
enum CodecType
{
    TextLine, SizeGuide
}

///
class Codec
{
    ///
    private CodecType ct;
    private const ubyte[] magic;

    ///
    this(const CodecType ct)
    {
        this.ct = ct;
        magic = null;
    }

    ///
    this(const CodecType ct, const ushort magic)
    {
        this.ct = ct;

        ubyte[] _magic = new ubyte[2];
        _magic.write!ushort(magic, 0);
        this.magic = _magic;
    }

    /// Returns:
    ///   long: spliter position
    ///   size_t: spliter size
    public Tuple!(long, size_t) decode(ref ByteBuffer buffer)
    {
        if (magic.length > 0)
        {
            if (buffer.length < magic.length)
            {
                return Tuple!(long, size_t)(-1, 0);
            }

            if (buffer[0 .. magic.length] != magic)
            {
                return Tuple!(long, size_t)(-2, 0);
            }
        }

        if (ct == CodecType.TextLine)
        {
            long endPoint = -1;

            for (size_t i = 0; i < buffer.length; i++)
            {
                const char ch = buffer[i];
                if ((ch == '\r') || (ch == '\n'))
                {
                    endPoint = i;
                    break;
                }
            }

            if (endPoint == -1)
            {
                return Tuple!(long, size_t)(-1, 0);
            }

            size_t spliterSize = 1;
            for (size_t i = endPoint + 1; i < buffer.length; i++)
            {
                const char ch = buffer[i];
                if ((ch != '\r') && (ch != '\n'))
                {
                    break;
                }

                spliterSize++;
            }

            return Tuple!(long, size_t)(endPoint, spliterSize);
        }
        else if (ct == CodecType.SizeGuide)
        {
            if (buffer.length < magic.length + int.sizeof)
            {
                return Tuple!(long, size_t)(-1, 0);
            }

            ubyte[] header = buffer[0 .. magic.length + int.sizeof];
            size_t size = header[magic.length .. $].peek!int(0);
            if (buffer.length < magic.length + int.sizeof + size)
            {
                return Tuple!(long, size_t)(-1, 0);
            }

            return Tuple!(long, size_t)(magic.length + int.sizeof + size, 0);
        }

        assert(0);
    }
}
