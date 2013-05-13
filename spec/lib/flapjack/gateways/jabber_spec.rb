require 'spec_helper'
require 'flapjack/gateways/jabber'

describe Flapjack::Gateways::Jabber, :logger => true do

  let(:config) { {'queue'    => 'jabber_notifications',
                  'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:fiber) { mock(Fiber) }

  let(:stanza) { mock('stanza') }

  it "hooks up event handlers to the appropriate methods" do
    Socket.should_receive(:gethostname).and_return('thismachine')

    Flapjack::RedisPool.should_receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine.should_receive(:next_tick).exactly(5).times.and_yield

    fj.should_receive(:register_handler).with(:ready).and_yield(stanza)
    fj.should_receive(:on_ready).with(stanza)

    fj.should_receive(:register_handler).with(:message, :groupchat?, :body => /^flapjack:\s+/).and_yield(stanza)
    fj.should_receive(:on_groupchat).with(stanza)

    fj.should_receive(:register_handler).with(:message, :chat?).and_yield(stanza)
    fj.should_receive(:on_chat).with(stanza)

    fj.should_receive(:register_handler).with(:disconnected).and_yield(stanza)
    fj.should_receive(:on_disconnect).with(stanza).and_return(true)

    error = mock('error')
    fj.should_receive(:register_handler).with(:error).and_yield(error)
    Kernel.should_receive(:throw).with(:halt)

    fj.setup
  end

  it "joins a chat room after connecting" do
    Flapjack::RedisPool.should_receive(:new)

    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)
    fj.should_receive(:connected?).and_return(true)

    EventMachine.should_receive(:next_tick).and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Presence))
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_ready(stanza)
  end

  it "receives an acknowledgement message" do
    stanza.should_receive(:body).and_return('flapjack: ACKID 876 fixing now duration: 90m')
    from = mock('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    redis = mock('redis')
    redis.should_receive(:hget).with('unacknowledged_failures', '876').
      and_return('main-example.com:ping')

    entity_check = mock(Flapjack::Data::EntityCheck)
    entity_check.should_receive(:in_unscheduled_maintenance?)
    entity_check.should_receive(:create_acknowledgement).
      with('summary' => 'fixing now', 'acknowledgement_id' => '876', 'duration' => (90 * 60))
    entity_check.should_receive(:entity_name).and_return('main-example.com')
    entity_check.should_receive(:check).and_return('ping')

    Flapjack::Data::EntityCheck.should_receive(:for_event_id).
      with('main-example.com:ping', :redis => redis).
      and_return(entity_check)

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine.should_receive(:next_tick).and_yield
    fj.should_receive(:connected?).and_return(true)
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fj.on_groupchat(stanza)
  end

  it "receives a message it doesn't understand" do
    stanza.should_receive(:body).once.and_return('flapjack: hello!')
    from = mock('from')
    from.should_receive(:stripped).and_return('sender')
    stanza.should_receive(:from).and_return(from)

    Flapjack::RedisPool.should_receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    EventMachine.should_receive(:next_tick).and_yield
    fj.should_receive(:connected?).and_return(true)
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))

    fj.on_groupchat(stanza)
  end

  it "reconnects when disconnected (if not quitting)" do
    Flapjack::RedisPool.should_receive(:new)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    attempts = 0

    Kernel.should_receive(:sleep).with(5).exactly(1).times
    Kernel.should_receive(:sleep).with(2).exactly(3).times
    fj.should_receive(:connect).exactly(4).times.and_return {
      attempts +=1
      raise StandardError.new unless attempts > 3
    }

    ret = fj.on_disconnect(stanza)
    ret.should be_true
  end

  it "prompts the blocking redis connection to quit" do
    redis = mock('redis')
    redis.should_receive(:rpush).with('jabber_notifications', %q{{"notification_type":"shutdown"}})

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)

    fiber.should_receive(:resume)
    Fiber.should_receive(:new).and_yield.and_return(fiber)

    fj.stop
  end

  it "runs a blocking loop listening for notifications" do
    timer = mock('timer')
    timer.should_receive(:cancel)
    EventMachine.should_receive(:add_periodic_timer).with(60).and_return(timer)

    redis = mock('redis')

    Flapjack::RedisPool.should_receive(:new).and_return(redis)
    fj = Flapjack::Gateways::Jabber.new(:config => config, :logger => @logger)
    fj.should_receive(:clear_handlers).with(:error)
    fj.should_receive(:register_handler).exactly(5).times

    fj.should_receive(:connect)
    fj.should_receive(:connected?).exactly(3).times.and_return(true)

    blpop_count = 0

    fiber.should_receive(:resume).twice
    Fiber.should_receive(:new).twice.and_yield.and_return(fiber)

    redis.should_receive(:blpop).twice {
      blpop_count += 1
      if blpop_count == 1
        ["jabber_notifications", %q{{"notification_type":"problem","event_id":"main-example.com:ping","state":"critical","summary":"!!!"}}]
      else
        fj.instance_variable_set('@should_quit', true)
        ["jabber_notifications", %q{{"notification_type":"shutdown"}}]
      end
    }

    EventMachine.should_receive(:next_tick).twice.and_yield
    fj.should_receive(:write).with(an_instance_of(Blather::Stanza::Message))
    fj.should_receive(:close)

    fj.start
  end

end
