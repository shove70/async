module async.thread;

import core.sync.mutex;

import std.concurrency;

import async.net.tcpclient;
import std.stdio;
class Task
{
    enum State
    {
        HOLD, PROCESSING, TERM
    }

    this(void function(shared Task task) fn, TcpClient client)
    {
        _tid    = spawn(fn, cast(shared Task)this);
        _client = client;
        _lock   = new Mutex;
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

//        if ((_state == State.RESET) || (_state == State.HOLD))
//        {
//            synchronized(_lock)
//            {
//                if ((_state == State.RESET) || (_state == State.HOLD))
//                {writeln("call: ", toState);
//                    _tid.send(toState);
//                    _state = State.PROCESSING;
//                }
//            }
//        }
    }

private:

    Tid          _tid;
    shared State _state = State.HOLD;
    Mutex        _lock;

    TcpClient    _client;
}
