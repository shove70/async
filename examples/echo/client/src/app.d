import std.stdio;
import std.socket;

void main()
{
    auto socket = new TcpSocket;
    socket.connect(new InternetAddress("127.0.0.1", 12290));

    auto data = "hello, server.";
    writeln("Client say: ", data);
    socket.send(data);

    ubyte[1024] buffer = void;
    size_t len = socket.receive(buffer[]);
    if (len != Socket.ERROR)
        writeln("Server reply: ", cast(string)buffer[0..len]);

    socket.shutdown(SocketShutdown.BOTH);
    socket.close();
}
