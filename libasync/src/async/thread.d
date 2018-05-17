module async.thread;

import core.sync.mutex;

import std.concurrency;

class Task
{
    enum State
    {
        HOLD, PROCESSING, TERM
    }

    this(T...)(void function(T args) fn, T args)
    {
        _tid  = spawn(fn, args);
        _lock = new Mutex;
    }

    this(T...)(void delegate(T args) dg, T args)
    {
        _tid  = spawn(fn, args);
        _lock = new Mutex;
    }

    @property State state() const
    {
        return _state;
    }

    @property void state(State value)
    {
        _state = value;
    }

    int yield()
    {
        _state = State.HOLD;
        int received = receiveOnly!int();
        _state = State.PROCESSING;

        return received;
    }

    void call(int iden = 1)
    {
        if (_state == State.HOLD)
        {
            synchronized (_lock)
            {
                if (_state == State.HOLD)
                {
                    _tid.send(iden);
                }
            }
        }
    }

    void terminate()
    {
        _state = State.TERM;
    }

private:

    Tid          _tid;
    shared State _state = State.PROCESSING;
    Mutex        _lock;
}
