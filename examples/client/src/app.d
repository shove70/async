import std.stdio;
import std.conv;
import std.socket;
import std.concurrency;
import core.thread;

int size = 10240;// * 1024 * 10;

void main(string[] argv)
{
    ubyte[] data = new ubyte[size];
    data[0] = 1;
    data[$ - 1] = 2;

    for (int i = 0; i < 1; i++)
    {
        new Thread(
            {
                go(data);
            }
        ).start();
    }
}

private void go(ubyte[] data)
{
    for (int i = 0; i < 1; i++)
    {
        TcpSocket socket = new TcpSocket();
        socket.blocking = true;
        socket.bind(new InternetAddress("127.0.0.1", 0));
        socket.connect(new InternetAddress("127.0.0.1", 12290));

        for (size_t off, len; off < data.length; off += len) {
			len = socket.send(data[off..$]);
		}

    	ubyte[] buffer = new ubyte[size];
    	
    	for (size_t off, len; off < buffer.length; off += len) {
    	    writeln(len);
			len = socket.receive(buffer[off..$]);
		}

    	writeln("receive: ", "[0]: ", buffer[0], ", [$ - 1]: ", buffer[$ - 1]);
    	socket.shutdown(SocketShutdown.BOTH);
    	socket.close();
    }
}
