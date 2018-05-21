import std.stdio;
import std.conv;
import std.socket;

void main(string[] argv)
{
    TcpSocket socket = new TcpSocket();
    socket.blocking = true;
    socket.connect(new InternetAddress("127.0.0.1", 12290));

    string data = "hello, server.";
    writeln("Client say: ", data);
    socket.send(data);

    ubyte[] buffer = new ubyte[1024];
    size_t len = socket.receive(buffer);
    writeln("Server reply: ", cast(string)buffer[0..len]);

    socket.shutdown(SocketShutdown.BOTH);
    socket.close();
}
