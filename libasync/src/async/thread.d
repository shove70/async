module async.thread;

import core.sync.mutex;

import std.concurrency;

import async.net.tcpclient;
import std.stdio;
class Task
{
    enum State
    {
        RESET, START, HOLD, PROCESSING, TERM
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

    State yield(State toState)
    {synchronized(_lock){
        _state     = toState;
        State ctrl = receiveOnly!State;
        _state     = State.PROCESSING;

        return ctrl;}
    }

    void call(State toState, int a = 0)
    {
        writeln("call: ", toState, " --  ", a);
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

    void terminate()
    {
        _state = State.TERM;
    }

private:

    Tid          _tid;
    shared State _state = State.PROCESSING;
    Mutex        _lock;

    TcpClient    _client;
}
