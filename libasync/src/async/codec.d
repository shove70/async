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

		auto buf = new ubyte[2];
		buf.write!ushort(magic, 0);
		this.magic = buf;
	}

	/// Returns:
	///   ptrdiff_t: spliter position
	///   size_t: spliter size
	Tuple!(ptrdiff_t, size_t) decode(ref ByteBuffer buffer)
	{
		if (magic.length)
		{
			if (buffer.length < magic.length)
			{
				return typeof(return)(-1, 0);
			}

			if (buffer[0 .. magic.length] != magic)
			{
				return typeof(return)(-2, 0);
			}
		}

		if (ct == CodecType.TextLine)
		{
			ptrdiff_t endPoint = -1;

			for (size_t i; i < buffer.length; i++)
			{
				const char ch = buffer[i];
				if (ch == '\r' || ch == '\n')
				{
					endPoint = i;
					break;
				}
			}

			if (endPoint == -1)
			{
				return typeof(return)(-1, 0);
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

			return typeof(return)(endPoint, spliterSize);
		}
		else if (ct == CodecType.SizeGuide)
		{
			if (buffer.length < magic.length + int.sizeof)
			{
				return typeof(return)(-1, 0);
			}

			ubyte[] header = buffer[0 .. magic.length + int.sizeof];
			size_t size = header[magic.length .. $].peek!int(0);
			if (buffer.length < magic.length + int.sizeof + size)
			{
				return typeof(return)(-1, 0);
			}

			return typeof(return)(magic.length + int.sizeof + size, 0);
		}

		assert(0);
	}
}