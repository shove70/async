module async.thread;

import std.concurrency;

import async.net.tcpclient;

class Task
{
    enum State
    {
        HOLD, PROCESSING, TERM
    }

    this(void function(shared Task task) fn, TcpClient client)
    {
        _client = client;
        _tid    = spawn(fn, cast(shared Task)this);
    }

    @property TcpClient client()
    {
        return _client;
    }

    @property State state() const
    {
        return _state;
    }

    @property void state(State value)
    {
        _state = value;
    }

    State yield(State asState)
    {
        _state     = asState;
        State ctrl = receiveOnly!State;
        _state     = ctrl;

        return ctrl;
    }

    void call(State toState)
    {
        //writeln("call: ", toState);
        _tid.send(toState);
    }

private:

    Tid          _tid;
    shared State _state = State.HOLD;

    TcpClient    _client;
}
