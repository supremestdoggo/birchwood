module birchwood.client.events;

import eventy : EventyEvent = Event;
import birchwood.protocol.messages : Message;

public final enum IRCEventType : ulong
{
    GENERIC_EVENT = 1,
    PONG_EVENT
}


/* TODO: Move to an events.d class */
public final class IRCEvent : EventyEvent
{   
    private Message msg;

    this(Message msg)
    {
        super(IRCEventType.GENERIC_EVENT);

        this.msg = msg;
    }

    public Message getMessage()
    {
        return msg;
    }

    public override string toString()
    {
        return msg.toString();
    }
}

/* TODO: make PongEvent (id 2 buit-in) */
public final class PongEvent : EventyEvent
{
    private string pingID;

    this(string pingID)
    {
        super(IRCEventType.PONG_EVENT);
        this.pingID = pingID;
    }

    public string getID()
    {
        return pingID;
    }
}