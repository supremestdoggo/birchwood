module birchwood.client.receiver;

import core.thread : Thread, dur;

import std.container.slist : SList;
import core.sync.mutex : Mutex;

import eventy : EventyEvent = Event;

// TODO: Examine the below import which seemingly fixes stuff for libsnooze
import libsnooze.clib;
import libsnooze;

import birchwood.client;
import birchwood.protocol.messages : Message, decodeMessage;
import std.string : indexOf;
import birchwood.client.events : PongEvent, IRCEvent;

public final class ReceiverThread : Thread
{
    /** 
     * The receive queue and its lock
     */
    private SList!(ubyte[]) recvQueue;
    private Mutex recvQueueLock;

    /** 
     * The libsnooze event to await on which
     * when we wake up signals a new message
     * to be processed and received
     */
    private Event receiveEvent;
    // private bool hasEnsured;

    /** 
     * The associated IRC client
     */
    private Client client;

    /** 
     * Constructs a new receiver thread with the associated
     * client
     *
     * Params:
     *   client = the Client to associate with
     */
    this(Client client)
    {
        super(&recvHandlerFunc);
        this.client = client;
        this.receiveEvent = new Event(); // TODO: Catch any libsnooze error here
        this.recvQueueLock = new Mutex();        
    }

    // TODO: Rename to `receiveQ`
    /** 
     * Enqueues the raw message into the receieve queue
     * for eventual processing
     *
     * Params:
     *   encodedMessage = the message to enqueue
     */
    public void rq(ubyte[] encodedMessage)
    {
        /* Lock queue */
        recvQueueLock.lock();

        /* Add to queue */
        recvQueue.insertAfter(recvQueue[], encodedMessage);

        /* Unlock queue */
        recvQueueLock.unlock();

        // TODO: Add a "register" function which can initialize pipes
        // ... without needing a wait, we'd need a ready flag though
        // ... for receiver's thread start

        /** 
         * Wake up all threads waiting on this event
         * (if any, and if so it would only be the receiver)
         */
        receiveEvent.notifyAll();
    }

    /** 
     * The receive queue worker function
     *
     * This has the job of dequeuing messages
     * in the receive queue, decoding them
     * into Message objects and then emitting
     * an event depending on the type of message
     *
     * Handles PINGs along with normal messages
     *
     * TODO: Our high load average is from here
     * ... it is getting lock a lot and spinning here
     * ... we should use libsnooze to avoid this
     */
    private void recvHandlerFunc()
    {
        while(client.running)
        {
            // TODO: We could look at libsnooze wait starvation or mutex racing (future thought)


            // // Do a once-off call to `ensure()` here which then only runs once and
            // // ... sets a `ready` flag for the Client to spin on. This ensures that
            // // ... when the first received messages will be able to cause a wait
            // // ... to immediately unblock rather than letting wait() register itself
            // // ... and then require another receiveQ call to wake it up and process
            // // ... the initial n messages + m new ones resulting in the second call
            // if(hasEnsured == false)
            // {
            //     receiveEvent.ensure();
            //     hasEnsured = true;
            // }

            // TODO: See above notes about libsnooze behaviour due
            // ... to usage in our context
            receiveEvent.wait(); // TODO: Catch any exceptions from libsnooze

            

            /* Lock the receieve queue */
            recvQueueLock.lock();

            /* Parsed messages */
            SList!(Message) currentMessageQueue;

            /** 
             * Parse all messages and save them
             * into the above array
             */
            foreach(ubyte[] message; recvQueue[])
            {
                /* Decode the message */
                string decodedMessage = decodeMessage(message);

                /* Parse the message */
                Message parsedMessage = Message.parseReceivedMessage(decodedMessage);

                /* Save it */
                currentMessageQueue.insertAfter(currentMessageQueue[], parsedMessage);
            }


            /** 
             * Search for any PING messages, then store it if so
             * and remove it so it isn't processed again later
             */
            Message pingMessage;
            foreach(Message curMsg; currentMessageQueue[])
            {
                import std.string : cmp;
                if(cmp(curMsg.getCommand(), "PING") == 0)
                {
                    currentMessageQueue.linearRemoveElement(curMsg);
                    pingMessage = curMsg;
                    break;
                }
            }

            /** 
             * If we have a PING then respond with a PONG
             */
            if(pingMessage !is null)
            {
                logger.log("Found a ping: "~pingMessage.toString());

                /* Extract the PING ID */
                string pingID = pingMessage.getParams();

                /* Spawn a PONG event */
                EventyEvent pongEvent = new PongEvent(pingID);
                client.engine.push(pongEvent);
            }




           


            /**
            * TODO: Plan of action
            *
            * 1. Firstly, we must run `parseReceivedMessage()` on the dequeued
            *    ping message (if any)
            * 2. Then (if there was a PING) trigger said PING handler
            * 3. Normal message handling; `parseReceivedMessage()` on one of the messages
            * (make the dequeue amount configurable possibly)
            * 4. Trigger generic handler
            * 5. We might need to also have a queue for commands ISSUED and command-replies
            *    RECEIVED and then match those first and do something with them (tasky-esque)
            * 6. We can just make a generic reply queue of these things - we have to maybe to this
            * - we can cache or remember stuff when we get 353
            */

            /** 
             * Process each message remaining in the queue now
             * till it is empty
             */
            while(!currentMessageQueue.empty())
            {
                /* Get the frontmost Message */
                Message curMsg = currentMessageQueue.front();

                // TODO: Remove the Eventy push and replace with a handler call (on second thought no)
                EventyEvent ircEvent = new IRCEvent(curMsg);
                client.engine.push(ircEvent);

                /* Remove the message from the queue */
                currentMessageQueue.linearRemoveElement(curMsg);
            }

            /* Clear the receive queue */
            recvQueue.clear();
        
            /* Unlock the receive queue */
            recvQueueLock.unlock();
        }
    }

    public void end()
    {
        // TODO: See above notes about libsnooze behaviour due
        // ... to usage in our context
        receiveEvent.notifyAll();
    }

    // public bool isReady()
    // {
    //     return hasEnsured;
    // }
}